// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Pure display-coordinate math, including negative and vertically stacked screens.
enum WindowGeometry {
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

    static func resized(_ frame: CGRect, to size: CGSize, in area: CGRect, growDown: Bool) -> CGRect {
        let right = abs(frame.maxX - area.maxX) < 2
        let centered = abs(frame.midX - area.midX) < 2
        let bottom = abs(frame.minY - area.minY) < 2
        let x = right ? frame.maxX - size.width : (centered ? area.midX - size.width / 2 : frame.minX)
        let y = bottom && !growDown ? frame.minY : frame.maxY - size.height
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
