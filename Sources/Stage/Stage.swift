// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

enum Metrics {
    // Design settings
    static let card: CGFloat = 448        // card width
    static let compactCard: CGFloat = 300
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
    var scrollHandler: ((NSEvent) -> Bool)?
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
    override func scrollWheel(with event: NSEvent) {
        if scrollHandler?(event) != true { super.scrollWheel(with: event) }
    }
}

/// The floating window: dragging, edge magnets, preset spots, and growing to fit its content.
@MainActor @Observable
final class Stage {
    private(set) var isShown = false
    private(set) var maxPanelHeight: CGFloat = 800
    @ObservationIgnored private var panel: DeckPanel?
    @ObservationIgnored private var grab: (mouse: NSPoint, topLeft: NSPoint)?
    @ObservationIgnored private var pendingFit: (height: CGFloat, width: CGFloat, growDown: Bool)?
    @ObservationIgnored private var fitScheduled = false
    @ObservationIgnored private var restingFrame: NSRect?
    @ObservationIgnored private var restingArea: NSRect?
    @ObservationIgnored private var placement: WindowGeometry.Anchor?
    @ObservationIgnored private var homeScreenID: UInt32?
    @ObservationIgnored private var drawerExpanded = false
    @ObservationIgnored private var adjustingFrame = false
    @ObservationIgnored var onScaleChange: ((CGFloat) -> Void)?

    var scale: CGFloat { panel?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }

    func build<V: View>(_ root: V, scroll: @escaping (NSEvent) -> Bool, pointer: @escaping (CGPoint?) -> Void) {
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
                    if self.grab == nil && !self.adjustingFrame { self.settle() }
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
        let screens = NSScreen.screens
        if let homeScreenID, let home = screens.first(where: { screenID($0) == homeScreenID }) { return home }
        guard let index = WindowGeometry.screenIndex(for: frame, screens: screens.map(\.frame)) else { return NSScreen.main }
        return screens[index]
    }

    private func screenID(_ screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// Reserve the same clear margin around the entire window, including its glow.
    private func playArea(for frame: NSRect) -> NSRect? {
        screen(for: frame).map { WindowGeometry.playArea(visibleFrame: $0.visibleFrame, gap: Metrics.screenGap) }
    }

    private func magnetize(_ f: NSRect, clamp: Bool) -> NSPoint {
        guard let a = playArea(for: f) else { return f.origin }
        return WindowGeometry.origin(for: f, in: a, snap: Metrics.pull, clamp: clamp,
                                     scale: screen(for: f)?.backingScaleFactor ?? scale)
    }

    private func apply(_ frame: NSRect) {
        guard let panel else { return }
        adjustingFrame = true
        panel.setFrame(frame, display: true, animate: false)
        adjustingFrame = false
    }

    private func remember(_ frame: NSRect) {
        restingFrame = frame
        restingArea = playArea(for: frame)
        if let screen = screen(for: frame) { homeScreenID = screenID(screen) }
        if placement == nil, let area = restingArea { placement = WindowGeometry.anchor(for: frame, in: area) }
        UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: PrefKey.anchor)
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "minideck.restingFrame")
        if let restingArea { UserDefaults.standard.set(NSStringFromRect(restingArea), forKey: "minideck.restingArea") }
        UserDefaults.standard.set(homeScreenID.map { NSNumber(value: $0) }, forKey: "minideck.homeScreen")
        UserDefaults.standard.set(placement?.horizontal.rawValue, forKey: "minideck.horizontalAnchor")
        UserDefaults.standard.set(placement?.vertical.rawValue, forKey: "minideck.verticalAnchor")
    }

    private func restorePosition() {
        guard let panel else { return }
        var f = panel.frame
        let store = UserDefaults.standard
        if let saved = store.string(forKey: "minideck.restingFrame") {
            let stored = NSRectFromString(saved)
            if stored.width > 100 && stored.height > 30 { f = stored }
            if let area = store.string(forKey: "minideck.restingArea") { restingArea = NSRectFromString(area) }
            homeScreenID = (store.object(forKey: "minideck.homeScreen") as? NSNumber)?.uint32Value
            if let h = store.string(forKey: "minideck.horizontalAnchor").flatMap(WindowGeometry.Horizontal.init(rawValue:)),
               let v = store.string(forKey: "minideck.verticalAnchor").flatMap(WindowGeometry.Vertical.init(rawValue:)) {
                placement = WindowGeometry.Anchor(horizontal: h, vertical: v)
            }
        } else if let saved = store.string(forKey: PrefKey.anchor) {
            let topLeft = NSPointFromString(saved)
            f.origin = NSPoint(x: topLeft.x, y: topLeft.y - f.height)
        } else if let a = playArea(for: NSScreen.main?.frame ?? f) {
            f.origin = NSPoint(x: a.maxX - f.width, y: a.maxY - f.height)
        }
        restingFrame = f
        apply(f)
    }

    // MARK: Moving

    func dragMoved() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        if grab == nil {
            if drawerExpanded, let restingFrame {
                let f = panel.frame
                apply(NSRect(x: f.minX, y: f.maxY - restingFrame.height, width: f.width, height: restingFrame.height))
                drawerExpanded = false
            }
            restingFrame = nil
            grab = (mouse, NSPoint(x: panel.frame.minX, y: panel.frame.maxY))
            NSCursor.closedHand.push()
        }
        guard let g = grab else { return }
        var f = panel.frame
        f.origin = NSPoint(x: g.topLeft.x + mouse.x - g.mouse.x,
                           y: g.topLeft.y + mouse.y - g.mouse.y - f.height)
        f.origin = magnetize(f, clamp: false)
        apply(f)
    }

    func dragEnded() {
        guard grab != nil else { return }
        finishDrag()
    }

    /// Ends a drag that the card can no longer finish, such as when a size switch rebuilds it.
    func cancelDrag() {
        guard grab != nil else { return }
        finishDrag()
    }

    /// SwiftUI may cancel a drag without calling onEnded when the view is rebuilt.
    /// No pressed button means no drag is really in progress.
    private func dropStaleGrab() {
        guard grab != nil, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        finishDrag()
    }

    private func finishDrag() {
        if let panel, let target = screen(for: panel.frame) { homeScreenID = screenID(target) }
        grab = nil
        restingFrame = panel?.frame
        restingArea = restingFrame.flatMap { playArea(for: $0) }
        placement = nil
        NSCursor.pop()
        settle()
    }

    /// Pulls the card fully back on screen after a drag, a display change, or a resize.
    func settle() {
        dropStaleGrab()
        guard let panel, grab == nil, !adjustingFrame else { return }
        var base = restingFrame ?? panel.frame
        guard let area = playArea(for: base) else { return }
        let anchor = placement ?? WindowGeometry.anchor(for: base, in: restingArea ?? area)
        placement = anchor
        if let previous = restingArea, previous != area {
            base = WindowGeometry.relocated(base, from: previous, to: area, anchor: anchor)
        }
        if maxPanelHeight != area.height { maxPanelHeight = area.height }
        base.origin = WindowGeometry.origin(for: base, in: area, snap: Metrics.pull, clamp: true, scale: scale)
        remember(base)
        var shown = drawerExpanded
            ? WindowGeometry.resized(base, to: panel.frame.size, in: area, growDown: true, anchor: anchor) : base
        shown.origin = WindowGeometry.origin(for: shown, in: area, snap: 0, clamp: true, scale: scale)
        apply(shown)
    }

    func park(at corner: Corner) {
        if !isShown { show() }
        guard let panel, let a = playArea(for: panel.frame) else { return }
        var f = restingFrame ?? panel.frame
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
        f.origin = WindowGeometry.origin(for: f, in: a, snap: 0, clamp: true, scale: scale)
        placement = WindowGeometry.anchor(for: f, in: a)
        remember(f)
        settle()
    }

    /// Grows or shrinks to the content. The top edge stays put unless the card sits on the bottom edge.
    /// Coalesce layout measurements rather than queueing stale window sizes.
    func scheduleFit(height: CGFloat, width: CGFloat, growDown: Bool) {
        pendingFit = (height, width, growDown)
        guard !fitScheduled else { return }
        fitScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fitScheduled = false
            guard let next = self.pendingFit else { return }
            self.pendingFit = nil
            self.fit(height: next.height, width: next.width, growDown: next.growDown)
        }
    }

    func fit(height: CGFloat, width: CGFloat, growDown: Bool) {
        guard let panel, height > 30, width > 100 else { return }
        let height = ceil(height * scale) / scale
        let f = panel.frame
        drawerExpanded = growDown
        dropStaleGrab()
        guard abs(f.height - height) > 0.5 || f.width != width else { return }
        if grab != nil {
            // Even mid-drag, a size change must not push the card past a screen edge.
            var moving = NSRect(x: f.minX, y: f.maxY - height, width: width, height: height)
            if let area = playArea(for: moving) {
                moving.origin = WindowGeometry.origin(for: moving, in: area, snap: 0, clamp: true, scale: scale)
            }
            apply(moving)
            return
        }
        let base = restingFrame ?? f
        guard let area = playArea(for: base) else { return }
        var next = WindowGeometry.resized(base, to: CGSize(width: width, height: height),
                                          in: area, growDown: growDown, anchor: placement)
        // Stay on the same monitor when expanding; the larger frame must not select a neighbor.
        next.origin = WindowGeometry.origin(for: next, in: area, snap: 0, clamp: true, scale: scale)
        // Content expansion must not start an AppKit animation for every
        // SwiftUI size measurement or re-anchor a temporary expanded frame.
        apply(next)
        if !growDown { remember(next) }
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
