// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

/// Shared timing for Mini Deck's shape changes, tuned to feel like the Dynamic Island:
/// the shape springs open with a small overshoot, and the content sharpens out of a soft blur
/// as it arrives. Closing is quicker and settles without a bounce.
enum Motion {
    static let openResponse = 0.36
    static let openDamping = NotchGeometry.openDamping
    static let closeResponse = 0.3
    static let closeDamping = 0.92

    /// Expanding: a quick start and a small overshoot before it settles.
    static let open = Animation.spring(response: openResponse, dampingFraction: openDamping)
    /// Collapsing: just as quick, no bounce.
    static let close = Animation.spring(response: closeResponse, dampingFraction: closeDamping)
    /// Content leaving before the shape finishes shrinking.
    static let fadeOut = Animation.easeOut(duration: 0.12)
    /// With Reduce Motion on, sizes change at once and content only cross-fades.
    static let reduced = Animation.easeOut(duration: 0.12)

    /// How long the old content takes to shrink away before a smaller layout takes its place.
    static let morphOut: TimeInterval = 0.13

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Blur, scale and fade used for content that appears or leaves while its shape changes.
struct BlurMorph: ViewModifier {
    /// 0 means fully shown, 1 means fully out.
    var amount: CGFloat
    var scale: CGFloat = 0.9
    var blur: CGFloat = 10
    var anchor: UnitPoint = .top

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - (1 - scale) * amount, anchor: anchor)
            .blur(radius: blur * amount)
            .opacity(Double(1 - amount))
    }
}

extension AnyTransition {
    /// Content arrives on the opening spring, sharpening and growing into place, and
    /// leaves quickly with a slight blur so the shrinking shape is never crowded.
    static func island(anchor: UnitPoint = .top, scale: CGFloat = 0.9) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurMorph(amount: 1, scale: scale, anchor: anchor),
                                 identity: BlurMorph(amount: 0, scale: scale, anchor: anchor))
                .animation(Motion.open.delay(0.03)),
            removal: .modifier(active: BlurMorph(amount: 1, scale: 0.96, blur: 6, anchor: anchor),
                               identity: BlurMorph(amount: 0, scale: 0.96, blur: 6, anchor: anchor))
                .animation(Motion.fadeOut))
    }
}
