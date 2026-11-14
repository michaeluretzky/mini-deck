// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import Observation

/// How often Mini Deck does background work in each situation.
/// The music apps announce play, pause and song changes instantly; polling only
/// fills in the playback position and catches apps opening or closing.
enum EnergyPolicy {
    struct Context: Equatable {
        var playing: Bool
        /// The player is on screen and not covered.
        var visible: Bool
        /// The displays are on and this user session is active.
        var awake: Bool
        var lowPower: Bool
        var appRunning: Bool
    }

    /// Seconds between playback checks.
    static func pollInterval(_ c: Context) -> Double {
        guard c.appRunning else { return c.awake ? 5 : 30 }
        if c.playing {
            // Keep checking while hidden so plays are still counted with the screen off.
            // Four seconds stays inside the five-second window that joins checks into one listen.
            if c.visible && c.awake { return c.lowPower ? 2 : 1 }
            return 4
        }
        return c.visible && c.awake ? 5 : 30
    }

    /// The longest gap between two checks that still counts as continuous listening.
    static func listenGap(forInterval interval: Double) -> Double { max(2, interval + 1) }

    /// Seconds between progress-bar redraws.
    static func progressStep(_ c: Context) -> Double {
        guard c.playing, c.visible, c.awake else { return 30 }
        return c.lowPower ? 0.5 : 0.25
    }

    /// Animations and live sound bars run only while someone can see them.
    static func animates(_ c: Context) -> Bool { c.visible && c.awake && !c.lowPower }

    /// The Spotify account summary refreshes only while the Mac is in use.
    static func refreshesAccount(_ c: Context) -> Bool { c.awake }
}

/// Watches display sleep, user switching, Low Power Mode and player visibility.
@MainActor @Observable
final class Energy {
    private(set) var awake = true
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Set by the stage when the player is shown, hidden, covered or uncovered.
    private(set) var visible = true

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var sessionActive = true
    @ObservationIgnored private var tokens: [NSObjectProtocol] = []

    func start() {
        guard tokens.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, @MainActor (Energy) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.screensAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.screensAsleep = false }),
            (NSWorkspace.sessionDidResignActiveNotification, { $0.sessionActive = false }),
            (NSWorkspace.sessionDidBecomeActiveNotification, { $0.sessionActive = true }),
            (NSWorkspace.didWakeNotification, { $0.screensAsleep = false }),
        ]
        for (name, apply) in pairs {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    apply(self)
                    self.update()
                }
            })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                                             object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
    }

    func setVisible(_ shown: Bool) {
        guard shown != visible else { return }
        visible = shown
        onChange?()
    }

    func context(playing: Bool, appRunning: Bool) -> EnergyPolicy.Context {
        EnergyPolicy.Context(playing: playing, visible: visible, awake: awake, lowPower: lowPower, appRunning: appRunning)
    }

    private func update() {
        let nextAwake = !screensAsleep && sessionActive
        let nextLow = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard nextAwake != awake || nextLow != lowPower else { return }
        awake = nextAwake
        lowPower = nextLow
        onChange?()
    }
}
