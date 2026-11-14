// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

/// What the notch view needs to draw itself.
@MainActor @Observable
final class NotchState {
    var expanded = false
    /// Notch size in points.
    var notch = CGSize(width: NotchGeometry.virtualWidth, height: 32)
    /// True when the screen has a real camera notch.
    var hasNotch = true
    /// Open player size in points.
    var open = CGSize(width: NotchGeometry.expandedWidth, height: 144)
}

/// Shows the player in the camera notch at the top of the screen, like the Dynamic Island.
/// Closed, it shows the cover and sound bars beside the notch. Pointing at it opens the player.
@MainActor
final class NotchStage {
    let state = NotchState()
    private(set) var isShown = false
    var onVisibility: ((Bool) -> Void)?
    /// Whether a song is loaded, so the closed shape shows its side wings.
    var hasTrack: () -> Bool = { false }
    var onCollapse: (() -> Void)?

    private var panel: DeckPanel?
    private var monitors: [Any] = []
    private var notchRect = CGRect.zero
    private var openRect = CGRect.zero
    private var closer: Task<Void, Never>?

    func build<V: View>(_ root: V, scroll: @escaping (NSEvent) -> Bool, pointer: @escaping (CGPoint?) -> Void) {
        let start = NSRect(x: 0, y: 0, width: NotchGeometry.expandedWidth, height: 160)
        let host = DeckHostView(rootView: root)
        host.sizingOptions = []
        host.frame = start
        host.autoresizingMask = [.width, .height]
        host.scrollHandler = scroll
        host.pointerHandler = { [weak self] point in
            pointer(point)
            if point == nil { self?.pointerMoved() }
        }
        let p = DeckPanel(contentRect: start, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let container = NSView(frame: start)
        container.addSubview(host)
        p.contentView = container
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        // Above the menu bar so the shape can sit around the notch.
        p.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.acceptsMouseMovedEvents = true
        p.isMovableByWindowBackground = false
        // Closed, clicks pass through to the menu bar under the window.
        p.ignoresMouseEvents = true
        panel = p
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    func show() {
        guard let panel else { return }
        place()
        panel.orderFrontRegardless()
        isShown = true
        watchPointer()
        onVisibility?(true)
    }

    func hide() {
        setExpanded(false)
        panel?.orderOut(nil)
        isShown = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        onVisibility?(false)
    }

    /// The built-in screen has the notch. Without one, the main screen gets a virtual notch.
    private var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func place() {
        guard let panel, let screen = targetScreen else { return }
        let frame = screen.frame
        notchRect = NotchGeometry.notch(screen: frame, menuBarHeight: frame.maxY - screen.visibleFrame.maxY,
                                        safeTop: screen.safeAreaInsets.top,
                                        leftWidth: screen.auxiliaryTopLeftArea?.width,
                                        rightWidth: screen.auxiliaryTopRightArea?.width)
        openRect = NotchGeometry.expanded(notchRect, screen: frame)
        state.notch = notchRect.size
        state.hasNotch = screen.safeAreaInsets.top > 0
        state.open = openRect.size
        let window = NotchGeometry.window(notchRect, screen: frame)
        if panel.frame != window { panel.setFrame(window, display: true) }
    }

    /// Mouse-moved monitors need no extra permission. They run only while the notch player is shown.
    private func watchPointer() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { monitors.append(local) }
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        if state.expanded {
            if NotchGeometry.keepZone(openRect).contains(point) {
                closer?.cancel()
                closer = nil
            } else if closer == nil {
                closer = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(250))
                    guard let self, !Task.isCancelled else { return }
                    self.closer = nil
                    if !NotchGeometry.keepZone(self.openRect).contains(NSEvent.mouseLocation) { self.setExpanded(false) }
                }
            }
        } else if NotchGeometry.hoverZone(NotchGeometry.collapsed(notchRect, wings: hasTrack())).contains(point) {
            setExpanded(true)
        }
    }

    private func setExpanded(_ on: Bool) {
        closer?.cancel()
        closer = nil
        guard state.expanded != on else { return }
        state.expanded = on
        panel?.ignoresMouseEvents = !on
        if !on { onCollapse?() }
    }
}
