// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation
import Observation

/// Publish only region crossings, not each mouse coordinate. Moving inside
/// the card should not rebuild its metadata, statistics and window geometry.
@MainActor @Observable
final class Pointer {
    @ObservationIgnored var location: CGPoint? {
        didSet { if location != oldValue { evaluate() } }
    }
    var frozen = false { didSet { evaluate() } }
    var scrub: Double?
    @ObservationIgnored private(set) var zones: [String: CGRect] = [:]
    private(set) var hovered: Set<String> = []
    private(set) var drawerOpen = false
    @ObservationIgnored private var opener: Task<Void, Never>?
    @ObservationIgnored private var closer: Task<Void, Never>?

    static let openDelay: Duration = .milliseconds(90)
    static let exitGrace: Duration = .milliseconds(120)

    func register(_ id: String, _ rect: CGRect) {
        guard zones[id] != rect else { return }
        zones[id] = rect
        evaluate()
    }

    func over(_ id: String) -> Bool { hovered.contains(id) }

    func remove(_ id: String) {
        zones.removeValue(forKey: id)
        evaluate()
    }

    /// Discard stale normal/compact hit regions and pending hover work on resize.
    func resetLayout() {
        opener?.cancel()
        closer?.cancel()
        opener = nil
        closer = nil
        zones.removeAll()
        hovered = []
        drawerOpen = false
        scrub = nil
        location = nil
    }

    private func evaluate() {
        let next: Set<String>
        if !frozen, let point = location {
            next = Set(zones.compactMap { $0.value.contains(point) ? $0.key : nil })
        } else {
            next = []
        }
        if hovered != next { hovered = next }
        let onCover = over(Zone.cover)
        if onCover && !drawerOpen && opener == nil {
            opener = Task { [weak self] in
                try? await Task.sleep(for: Self.openDelay)
                guard let self, !Task.isCancelled else { return }
                self.opener = nil
                if self.over(Zone.cover) { self.drawerOpen = true }
            }
        } else if !onCover {
            opener?.cancel()
            opener = nil
        }

        if frozen || over(Zone.transport) || over(Zone.scrubber) {
            closer?.cancel()
            closer = nil
            drawerOpen = false
        } else if onCover || over(Zone.card) || !drawerOpen {
            closer?.cancel()
            closer = nil
        } else if closer == nil {
            // Resizing replaces tracking areas and may emit a transient exit.
            // Allow a quick re-entry without collapsing/reopening the drawer.
            closer = Task { [weak self] in
                try? await Task.sleep(for: Self.exitGrace)
                guard let self, !Task.isCancelled else { return }
                self.closer = nil
                if !self.over(Zone.cover) && !self.over(Zone.card) { self.drawerOpen = false }
            }
        }
    }
}

enum Zone {
    static let drawer = "drawer"
    static let card = "card"
    static let cover = "cover"
    static let transport = "transport"
    static let scrubber = "scrubber"
}
