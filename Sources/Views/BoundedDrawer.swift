// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import SwiftUI

/// Measure natural content once per change; only overflow becomes scrollable.
struct BoundedDrawer<Content: View>: View {
    let limit: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 1

    var body: some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.height, initial: true) { _, value in
                        if abs(contentHeight - value) > 0.5 { contentHeight = value }
                    }
                })
        }
        .scrollDisabled(contentHeight <= limit)
        .frame(height: min(contentHeight, limit))
    }
}
