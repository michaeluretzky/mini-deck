// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import SwiftUI

/// Persist geometry with the app, without requiring the newer SwiftUI State macro plugin.
@MainActor @Observable
final class CardSizing {
    var playerHeight: CGFloat = 132
    var drawerHeight: CGFloat = 1

    func reset(compact: Bool) {
        playerHeight = compact ? 60 : 132
        drawerHeight = 1
    }
}

/// Measure natural content once per change; only overflow becomes scrollable.
struct BoundedDrawer<Content: View>: View {
    let limit: CGFloat
    let sizing: CardSizing
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.height, initial: true) { _, value in
                        if abs(sizing.drawerHeight - value) > 0.5 { sizing.drawerHeight = value }
                    }
                })
        }
        .scrollDisabled(sizing.drawerHeight <= limit)
        .frame(height: min(sizing.drawerHeight, limit))
    }
}
