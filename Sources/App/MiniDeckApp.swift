// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import ServiceManagement
import SwiftUI

@main
struct MiniDeckApp: App {
    @NSApplicationDelegateAdaptor(Launcher.self) private var launcher

    var body: some Scene {
        MenuBarExtra {
            StatusMenu(hub: Hub.shared)
        } label: {
            Image(systemName: "opticaldisc")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class Launcher: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Hub.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Hub.shared.log.flush()
    }
}

/// Owns every long-lived object and wires them together.
@MainActor
final class Hub {
    static let shared = Hub()

    let prefs = Prefs()
    let deck = Deck()
    let pointer = Pointer()
    let spectrum = Spectrum()
    let stage = Stage()
    let log = ListeningLog()
    let account = SpotifyAccount()
    let library = MusicLibrary()
    private let historyWindow = HistoryWindow()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        log.enabled = prefs.countPlays
        deck.choice = prefs.choice
        deck.onTick = { [weak self] snap in self?.log.tick(snap) }
        deck.onNewTrack = { [weak self] snap in self?.trackChanged(snap) }
        account.onNotice = { [weak self] text in self?.deck.flash("person.crop.circle.badge.checkmark", text) }
        stage.onScaleChange = { [weak self] scale in self?.deck.pixelScale = scale }
        stage.build(DeckRoot(hub: self),
                    scroll: { [weak self] event in self?.scrolled(event) },
                    pointer: { [weak self] point in self?.pointer.location = point })
        deck.pixelScale = stage.scale
        deck.start()
        followPlayback()
    }

    private func trackChanged(_ snap: Snapshot) {
        switch snap.source {
        case .spotify: Task { await account.update(trackChanged: true) }
        case .music: library.scanIfStale()
        }
    }

    private func scrolled(_ event: NSEvent) {
        var dy = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { dy = -dy }
        guard dy != 0 else { return }
        deck.adjustVolume(by: event.hasPreciseScrollingDeltas ? Double(dy) * 0.4 : Double(dy) * 3)
    }

    /// Re-runs whenever the sound-bar setting, the play state or the followed app changes.
    private func followPlayback() {
        let wanted = withObservationTracking {
            (prefs.soundBars, deck.appOpen && deck.isPlaying, deck.source.bundle)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followPlayback() }
        }
        spectrum.want(wanted.0, playing: wanted.1, bundle: wanted.2)
    }

    // MARK: Menu actions

    func showHistory() {
        historyWindow.show(hub: self)
    }

    /// Fetches fresh history when the history window opens or changes source.
    func refreshHistory() {
        Task { await account.update(trackChanged: true) }
        library.scanIfStale()
    }

    func choose(_ choice: SourceChoice) {
        prefs.choice = choice
        deck.choice = choice
        deck.refresh()
    }

    func setCounting(_ on: Bool) {
        prefs.countPlays = on
        log.enabled = on
    }

    func confirmClearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear listening history?"
        alert.informativeText = "This deletes the play counts Mini Deck has kept on this Mac. Your Spotify account and Music library aren't changed."
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            log.clear()
            deck.flash("trash", "Listening history cleared")
        }
    }

    /// Asks for the Client ID of the user's own Spotify developer app, then opens Spotify's sign-in page.
    func askToConnectSpotify() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Connect your Spotify account"
        alert.informativeText = """
        Mini Deck reads your top artists, top songs and recent plays. It can't change your account or play anything.

        1. Open the Spotify Developer Dashboard and create an app with any name.
        2. Add this Redirect URI: \(SpotifyAccount.redirect)
        3. Select "Web API", save, and paste the app's Client ID below.

        Your sign-in is kept in your Mac's keychain. Mini Deck talks only to Spotify.
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "Client ID"
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           SpotifyAccount.looksLikeClientID(clip) {
            field.stringValue = clip
        }
        alert.accessoryView = field
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Open Dashboard")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        // A menu bar app has no Edit menu, so wire up the usual editing keys for the field.
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  let key = event.charactersIgnoringModifiers?.lowercased() else { return event }
            let action: Selector? = switch key {
            case "v": #selector(NSText.paste(_:))
            case "c": #selector(NSText.copy(_:))
            case "x": #selector(NSText.cut(_:))
            case "a": #selector(NSText.selectAll(_:))
            default: nil
            }
            guard let action else { return event }
            return NSApp.sendAction(action, to: nil, from: nil) ? nil : event
        }
        let answer = alert.runModal()
        if let keys { NSEvent.removeMonitor(keys) }

        switch answer {
        case .alertFirstButtonReturn:
            account.connect(clientID: field.stringValue)
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://developer.spotify.com/dashboard") { NSWorkspace.shared.open(url) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.askToConnectSpotify() }
        default:
            break
        }
    }
}

enum PrefKey {
    static let soundBars = "minideck.soundBars"
    static let loginSeeded = "minideck.loginSeeded"
    static let askedCapture = "minideck.askedCapture"
    static let anchor = "minideck.anchorTopLeft"
    static let choice = "minideck.source"
    static let countPlays = "minideck.countPlays"
    static let statsAdvanced = "minideck.statsAdvanced"
}

@MainActor @Observable
final class Prefs {
    var soundBars: Bool {
        didSet { UserDefaults.standard.set(soundBars, forKey: PrefKey.soundBars) }
    }
    var choice: SourceChoice {
        didSet { UserDefaults.standard.set(choice.rawValue, forKey: PrefKey.choice) }
    }
    var countPlays: Bool {
        didSet { UserDefaults.standard.set(countPlays, forKey: PrefKey.countPlays) }
    }
    var statsAdvanced: Bool {
        didSet { UserDefaults.standard.set(statsAdvanced, forKey: PrefKey.statsAdvanced) }
    }
    private(set) var openAtLogin: Bool

    init() {
        let store = UserDefaults.standard
        soundBars = store.object(forKey: PrefKey.soundBars) as? Bool ?? Metrics.soundBarsOn
        choice = store.string(forKey: PrefKey.choice).flatMap(SourceChoice.init(rawValue:)) ?? .automatic
        countPlays = store.object(forKey: PrefKey.countPlays) as? Bool ?? true
        statsAdvanced = store.bool(forKey: PrefKey.statsAdvanced)
        openAtLogin = SMAppService.mainApp.status == .enabled
        if !store.bool(forKey: PrefKey.loginSeeded) {
            store.set(true, forKey: PrefKey.loginSeeded)
            setOpenAtLogin(true)
        }
    }

    func setOpenAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        if on { try? service.register() } else { try? service.unregister() }
        openAtLogin = service.status == .enabled
    }
}

struct StatusMenu: View {
    let hub: Hub

    var body: some View {
        Button(hub.stage.isShown ? "Hide Player" : "Show Player") { hub.stage.toggle() }
        Button("Open \(hub.deck.source.appName)") { hub.deck.revealApp() }
        Menu("Follow") {
            ForEach(SourceChoice.allCases) { option in
                Toggle(option.title, isOn: Binding(get: { hub.prefs.choice == option },
                                                   set: { if $0 { hub.choose(option) } }))
            }
        }
        Menu("Move Player") {
            ForEach(Corner.allCases) { corner in
                Button(corner.title) { hub.stage.park(at: corner) }
            }
        }
        Divider()
        Button("Listening History…") { hub.showHistory() }
            .keyboardShortcut("y")
        Menu("Listening Stats") {
            switch hub.account.status {
            case .on:
                Text("Spotify account connected")
                Button("Disconnect Spotify") { hub.account.disconnect() }
            case .waiting:
                Text("Waiting for Spotify sign-in…")
                Button("Cancel Sign-In") { hub.account.cancelSignIn() }
            case .expired:
                Button("Reconnect Spotify Account…") { hub.askToConnectSpotify() }
            case .off, .failed:
                Button("Connect Spotify Account…") { hub.askToConnectSpotify() }
            }
            Divider()
            Toggle("Count Plays on This Mac", isOn: Binding(get: { hub.prefs.countPlays },
                                                            set: { hub.setCounting($0) }))
            Button("Clear Listening History…") { hub.confirmClearHistory() }
                .disabled(hub.log.isEmpty)
        }
        Toggle("Sound Bars", isOn: Binding(get: { hub.prefs.soundBars },
                                           set: { hub.prefs.soundBars = $0 }))
        Toggle("Open at Login", isOn: Binding(get: { hub.prefs.openAtLogin },
                                              set: { hub.prefs.setOpenAtLogin($0) }))
        Divider()
        Text("Scroll over the player to change the volume")
        Divider()
        Button("Quit Mini Deck") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
