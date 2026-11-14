// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Pure display-coordinate math, including negative and vertically stacked screens.
enum WindowGeometry {
    enum Horizontal: String { case leading, center, trailing }
    enum Vertical: String { case top, bottom }
    struct Anchor: Equatable {
        var horizontal: Horizontal
        var vertical: Vertical
    }

    static func playArea(visibleFrame: CGRect, gap: CGFloat) -> CGRect {
        visibleFrame.insetBy(dx: max(0, gap), dy: max(0, gap))
    }

    /// Choose once when the user moves the player, not again at every content resize.
    static func anchor(for frame: CGRect, in area: CGRect) -> Anchor {
        let horizontal: Horizontal = abs(frame.midX - area.midX) <= 20 ? .center
            : (frame.midX < area.midX ? .leading : .trailing)
        return Anchor(horizontal: horizontal,
                      vertical: abs(frame.minY - area.minY) < abs(frame.maxY - area.maxY) ? .bottom : .top)
    }

    static func screenIndex(for frame: CGRect, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        let overlaps = screens.map { screen -> CGFloat in
            let intersection = screen.intersection(frame)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        if let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }), overlaps[best] > 0 {
            return best
        }
        // A removed monitor's saved frame belongs on the nearest remaining screen.
        return screens.indices.min { distance(frame, screens[$0]) < distance(frame, screens[$1]) }
    }

    private static func distance(_ frame: CGRect, _ screen: CGRect) -> CGFloat {
        let x = min(max(frame.midX, screen.minX), screen.maxX)
        let y = min(max(frame.midY, screen.minY), screen.maxY)
        return pow(frame.midX - x, 2) + pow(frame.midY - y, 2)
    }

    static func origin(for frame: CGRect, in area: CGRect, snap: CGFloat, clamp: Bool, scale: CGFloat) -> CGPoint {
        func nearest(_ value: CGFloat, _ stops: [CGFloat]) -> CGFloat {
            guard let best = stops.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(best - value) <= snap else { return value }
            return best
        }
        var x = nearest(frame.minX, [area.minX, area.midX - frame.width / 2, area.maxX - frame.width])
        var y = nearest(frame.minY, [area.minY, area.maxY - frame.height])
        if clamp {
            x = min(max(x, area.minX), max(area.minX, area.maxX - frame.width))
            // Keep the top readable even when the expanded panel exceeds screen height.
            y = frame.height > area.height ? area.maxY - frame.height
                : min(max(y, area.minY), area.maxY - frame.height)
        }
        let pixels = max(1, scale)
        return CGPoint(x: (x * pixels).rounded() / pixels, y: (y * pixels).rounded() / pixels)
    }

    static func resized(_ frame: CGRect, to size: CGSize, in area: CGRect, growDown: Bool,
                        anchor: Anchor? = nil) -> CGRect {
        let anchor = anchor ?? self.anchor(for: frame, in: area)
        let x: CGFloat
        switch anchor.horizontal {
        case .leading: x = frame.minX
        case .center: x = frame.midX - size.width / 2
        case .trailing: x = frame.maxX - size.width
        }
        let y = anchor.vertical == .bottom && !growDown ? frame.minY : frame.maxY - size.height
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// Preserve edge distances when a display's work area moves or changes size.
    static func relocated(_ frame: CGRect, from old: CGRect, to area: CGRect, anchor: Anchor) -> CGRect {
        var next = frame
        switch anchor.horizontal {
        case .leading: next.origin.x += area.minX - old.minX
        case .center: next.origin.x += area.midX - old.midX
        case .trailing: next.origin.x += area.maxX - old.maxX
        }
        switch anchor.vertical {
        case .top: next.origin.y += area.maxY - old.maxY
        case .bottom: next.origin.y += area.minY - old.minY
        }
        return next
    }
}
