// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

enum Metrics {
    // Design settings
    static let card: CGFloat = 448        // card width
    static let cover: CGFloat = 132       // album art side
    static let corner: CGFloat = 16       // card corner radius
    static let inset: CGFloat = 12        // card padding
    static let glow: Double = 0.5         // glow opacity while playing
    static let soundBarsOn = true         // sound bars default

    static let halo: CGFloat = 20
    static let screenGap: CGFloat = 10
    static let pull: CGFloat = 20
    static var panelWidth: CGFloat { card + halo * 2 }
}

enum Corner: String, CaseIterable, Identifiable {
    case topLeading, top, topTrailing, bottomLeading, bottom, bottomTrailing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .top: "Top Middle"
        case .topTrailing: "Top Right"
        case .bottomLeading: "Bottom Left"
        case .bottom: "Bottom Middle"
        case .bottomTrailing: "Bottom Right"
        }
    }
}

final class DeckPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosts the SwiftUI card and reports the pointer even when the app isn't active.
final class DeckHostView<Content: View>: NSHostingView<Content> {
    var scrollHandler: ((NSEvent) -> Void)?
    var pointerHandler: ((CGPoint?) -> Void)?
    private var tracker: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracker { removeTrackingArea(tracker) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracker = area
    }

    private func publish(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        pointerHandler?(CGPoint(x: p.x, y: isFlipped ? p.y : bounds.height - p.y))
    }

    override func mouseMoved(with event: NSEvent) { super.mouseMoved(with: event); publish(event) }
    override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); publish(event) }
    override func mouseDragged(with event: NSEvent) { super.mouseDragged(with: event); publish(event) }
    override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); pointerHandler?(nil) }
    override func scrollWheel(with event: NSEvent) { scrollHandler?(event) }
}

/// The floating window: dragging, edge magnets, preset spots, and growing to fit its content.
@MainActor @Observable
final class Stage {
    private(set) var isShown = false
    @ObservationIgnored private var panel: DeckPanel?
    @ObservationIgnored private var grab: (mouse: NSPoint, origin: NSPoint)?
    @ObservationIgnored private var pendingFit: (height: CGFloat, growDown: Bool)?
    @ObservationIgnored private var fitScheduled = false
    @ObservationIgnored var onScaleChange: ((CGFloat) -> Void)?

    var scale: CGFloat { panel?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    func build<V: View>(_ root: V, scroll: @escaping (NSEvent) -> Void, pointer: @escaping (CGPoint?) -> Void) {
        let start = NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 164)
        let host = DeckHostView(rootView: root)
        host.sizingOptions = []
        host.frame = start
        host.scrollHandler = scroll
        host.pointerHandler = pointer

        let p = DeckPanel(contentRect: start, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.isMovableByWindowBackground = false
        panel = p
        restorePosition()

        let center = NotificationCenter.default
        for name in [NSWindow.didChangeBackingPropertiesNotification, NSWindow.didChangeScreenNotification] {
            center.addObserver(forName: name, object: p, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.onScaleChange?(self.scale)
                }
            }
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settle() }
        }
        show()
    }

    // MARK: Showing

    func show() {
        guard let panel else { return }
        panel.orderFrontRegardless()
        isShown = true
        settle()
    }

    func hide() {
        panel?.orderOut(nil)
        isShown = false
    }

    func toggle() { isShown ? hide() : show() }

    // MARK: Geometry

    private func screen(for frame: NSRect) -> NSScreen? {
        if grab != nil, let s = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) { return s }
        func overlap(_ s: NSScreen) -> CGFloat {
            let r = s.frame.intersection(frame)
            return r.isNull ? 0 : r.width * r.height
        }
        return NSScreen.screens.max { overlap($0) < overlap($1) } ?? NSScreen.main
    }

    /// Where the card may sit: the visible screen less a small gap. The glow is allowed to spill past it.
    private func playArea(for frame: NSRect) -> NSRect? {
        let d = Metrics.screenGap - Metrics.halo
        return screen(for: frame)?.visibleFrame.insetBy(dx: d, dy: d)
    }

    private func magnetize(_ f: NSRect, clamp: Bool) -> NSPoint {
        guard let a = playArea(for: f) else { return f.origin }
        func nearest(_ value: CGFloat, _ stops: [CGFloat]) -> CGFloat {
            guard let best = stops.min(by: { abs($0 - value) < abs($1 - value) }), abs(best - value) <= Metrics.pull else { return value }
            return best
        }
        var x = nearest(f.minX, [a.minX, a.midX - f.width / 2, a.maxX - f.width])
        var y = nearest(f.minY, [a.minY, a.maxY - f.height])
        if clamp {
            x = min(max(x, a.minX), max(a.minX, a.maxX - f.width))
            y = min(max(y, a.minY), max(a.minY, a.maxY - f.height))
        }
        return NSPoint(x: x.rounded(), y: y.rounded())
    }

    private func glide(to frame: NSRect) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: true)
        }
        remember(frame)
    }

    private func remember(_ frame: NSRect) {
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: PrefKey.anchor)
    }

    private func restorePosition() {
        guard let panel else { return }
        var f = panel.frame
        if let saved = UserDefaults.standard.string(forKey: PrefKey.anchor) {
            let topLeft = NSPointFromString(saved)
            f.origin = NSPoint(x: topLeft.x, y: topLeft.y - f.height)
        } else if let a = playArea(for: NSScreen.main?.frame ?? f) {
            f.origin = NSPoint(x: a.maxX - f.width, y: a.maxY - f.height)
        }
        panel.setFrame(f, display: false)
    }

    // MARK: Moving

    func dragMoved() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if grab == nil {
            grab = (mouse, panel.frame.origin)
            NSCursor.closedHand.push()
        }
        guard let g = grab else { return }
        var f = panel.frame
        f.origin = NSPoint(x: g.origin.x + mouse.x - g.mouse.x, y: g.origin.y + mouse.y - g.mouse.y)
        panel.setFrameOrigin(magnetize(f, clamp: false))
    }

    func dragEnded() {
        guard grab != nil else { return }
        grab = nil
        NSCursor.pop()
        settle()
    }

    /// Pulls the card fully back on screen after a drag, a display change, or a resize.
    func settle() {
        guard let panel else { return }
        var f = panel.frame
        f.origin = magnetize(f, clamp: true)
        if f.origin != panel.frame.origin { glide(to: f) } else { remember(f) }
    }

    func park(at corner: Corner) {
        if !isShown { show() }
        guard let panel, let a = playArea(for: panel.frame) else { return }
        var f = panel.frame
        let left = a.minX, middle = a.midX - f.width / 2, right = a.maxX - f.width
        let top = a.maxY - f.height, bottom = a.minY
        switch corner {
        case .topLeading: f.origin = NSPoint(x: left, y: top)
        case .top: f.origin = NSPoint(x: middle, y: top)
        case .topTrailing: f.origin = NSPoint(x: right, y: top)
        case .bottomLeading: f.origin = NSPoint(x: left, y: bottom)
        case .bottom: f.origin = NSPoint(x: middle, y: bottom)
        case .bottomTrailing: f.origin = NSPoint(x: right, y: bottom)
        }
        f.origin = NSPoint(x: f.origin.x.rounded(), y: f.origin.y.rounded())
        glide(to: f)
    }

    /// Grows or shrinks to the content. The top edge stays put unless the card sits on the bottom edge.
    /// Coalesce layout measurements rather than queueing stale window sizes.
    func scheduleFit(height: CGFloat, growDown: Bool) {
        pendingFit = (height, growDown)
        guard !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fitScheduled = false
            guard let next = self.pendingFit else { return }
            self.pendingFit = nil
            self.fit(height: next.height, growDown: next.growDown)
        }
    }

    func fit(height: CGFloat, growDown: Bool) {
        guard let panel, height > 30 else { return }
        let height = ceil(height * scale) / scale
        let f = panel.frame
        guard abs(f.height - height) > 0.5 || f.width != Metrics.panelWidth else { return }
        let onBottom = playArea(for: f).map { abs(f.minY - $0.minY) < 2 } ?? false
        var next = NSRect(x: f.minX, y: (onBottom && !growDown) ? f.minY : f.maxY - height,
                          width: Metrics.panelWidth, height: height)
        next.origin = magnetize(next, clamp: true)
        // Content expansion must not start an AppKit animation for every
        // SwiftUI size measurement. Keep gliding only for explicit moves.
        panel.setFrame(next, display: true, animate: false)
        if next.origin != f.origin { remember(next) }
    }
}

enum Space {
    static let deck = "minideck.deck"
}

extension View {
    /// Records this view's frame so pointer hover works without the window being active.
    func zone(_ id: String, _ pointer: Pointer) -> some View {
        background(GeometryReader { g in
            let rect = g.frame(in: .named(Space.deck))
            Color.clear.onChange(of: rect, initial: true) { _, new in pointer.register(id, new) }
        })
    }
}
