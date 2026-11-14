// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import CoreGraphics

/// Sizes for the notch player. All rects use screen coordinates with y growing upward.
enum NotchGeometry {
    /// Width added on each side of the notch for the cover and sound bars.
    static let wing: CGFloat = 40
    /// Small outward curve where the shape meets the top edge of the screen.
    static let flare: CGFloat = 6
    static let expandedWidth: CGFloat = 500
    /// Height of the open player below the notch.
    static let expandedBody: CGFloat = 128
    /// Size used on screens without a camera notch.
    static let virtualWidth: CGFloat = 180
    static let minimumHeight: CGFloat = 24

    /// The camera notch, or a virtual one centered at the top of screens without a notch.
    /// `leftWidth` and `rightWidth` are the widths of the usable areas beside the notch.
    static func notch(screen: CGRect, menuBarHeight: CGFloat, safeTop: CGFloat,
                      leftWidth: CGFloat?, rightWidth: CGFloat?) -> CGRect {
        if safeTop > 0, let l = leftWidth, let r = rightWidth {
            let width = screen.width - l - r
            if width > 40 && width < screen.width / 2 {
                return CGRect(x: screen.minX + l, y: screen.maxY - safeTop, width: width, height: safeTop)
            }
        }
        let height = max(minimumHeight, menuBarHeight)
        return CGRect(x: screen.midX - virtualWidth / 2, y: screen.maxY - height, width: virtualWidth, height: height)
    }

    /// The closed shape: the notch alone, or with a wing on each side while a song is loaded.
    static func collapsed(_ notch: CGRect, wings: Bool) -> CGRect {
        notch.insetBy(dx: wings ? -wing : 0, dy: 0)
    }

    /// The open player, centered under the notch and kept on screen.
    static func expanded(_ notch: CGRect, screen: CGRect) -> CGRect {
        let width = min(screen.width, max(expandedWidth, notch.width + 2 * wing))
        let height = notch.height + expandedBody
        let x = min(max(notch.midX - width / 2, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: screen.maxY - height, width: width, height: height)
    }

    /// The window holds the open player plus the curves at the top corners.
    static func window(_ notch: CGRect, screen: CGRect) -> CGRect {
        var open = expanded(notch, screen: screen).insetBy(dx: -flare, dy: 0)
        open.size.width = min(open.width, screen.width)
        let x = min(max(open.minX, screen.minX), screen.maxX - open.width)
        // Room below for the shadow of the open player.
        return CGRect(x: x, y: open.minY - 16, width: open.width, height: open.height + 16)
    }

    /// Where the pointer opens the player. It reaches the top edge so moving into the
    /// corner of the screen still counts.
    static func hoverZone(_ collapsed: CGRect) -> CGRect {
        CGRect(x: collapsed.minX - 4, y: collapsed.minY - 4, width: collapsed.width + 8, height: collapsed.height + 6)
    }

    /// Where the pointer keeps the open player open.
    static func keepZone(_ expanded: CGRect) -> CGRect {
        CGRect(x: expanded.minX - 10, y: expanded.minY - 10, width: expanded.width + 20, height: expanded.height + 12)
    }
}
