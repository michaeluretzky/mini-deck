// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

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
        Hub.shared.archive.flush()
    }
}

/// Owns every long-lived object and wires them together.
@MainActor
final class Hub {
    static let shared = Hub()

    let prefs = Prefs()
    let cardSizing = CardSizing()
    let deck = Deck()
    let pointer = Pointer()
    let spectrum = Spectrum()
    let stage = Stage()
    let log = ListeningLog()
    let account = SpotifyAccount()
    let library = MusicLibrary()
    let archive = SpotifyArchive()
    let wrapped = WrappedLibrary()
    private let historyWindow = HistoryWindow()
    private let setupWindow = SetupWindow()
    private var started = false
    private var accountRefreshTask: Task<Void, Never>?

    func start() {
        guard !started else { return }
        started = true
        log.enabled = prefs.countPlays
        deck.choice = prefs.choice
        deck.onTick = { [weak self] snap in
            guard let self else { return }
            self.log.tick(snap)
            if self.prefs.countPlays { self.archive.observe(snap) }
        }
        account.onRecent = { [weak self] plays, complete in self?.archive.ingestRecent(plays, complete: complete) }
        account.historyBoundary = { [weak self] in
            guard let self else { return nil }
            return self.archive.journal.lastSync?.addingTimeInterval(-600)
                ?? self.archive.exportCutoff ?? self.archive.journal.since
        }
        deck.onNewTrack = { [weak self] snap in self?.trackChanged(snap) }
        account.onNotice = { [weak self] text in self?.deck.flash("person.crop.circle.badge.checkmark", text) }
        stage.onScaleChange = { [weak self] scale in self?.deck.pixelScale = scale }
        stage.build(DeckRoot(hub: self),
                    scroll: { [weak self] event in self?.scrolled(event) ?? false },
                    pointer: { [weak self] point in self?.pointer.location = point })
        deck.pixelScale = stage.scale
        deck.start()
        followPlayback()
        accountRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.account.update(trackChanged: true)
                try? await Task.sleep(for: .seconds(120))
            }
        }
        if !UserDefaults.standard.bool(forKey: "minideck.setupShown") {
            UserDefaults.standard.set(true, forKey: "minideck.setupShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showSetup() }
        }
    }

    private func trackChanged(_ snap: Snapshot) {
        switch snap.source {
        case .spotify:
            Task {
                await account.update(trackChanged: true)
                let value = await account.audience(for: snap, creditedArtist: deck.creditedArtist)
                deck.applyAudience(value, for: snap)
            }
        case .music: library.scanIfStale()
        }
    }

    private func scrolled(_ event: NSEvent) -> Bool {
        // Let the bounded information panel scroll instead of changing volume.
        guard !pointer.over(Zone.drawer) else { return false }
        var dy = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { dy = -dy }
        guard dy != 0 else { return false }
        deck.adjustVolume(by: event.hasPreciseScrollingDeltas ? Double(dy) * 0.4 : Double(dy) * 3)
        return true
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

    func setCompact(_ compact: Bool) {
        guard prefs.compactView != compact else { return }
        pointer.resetLayout()
        cardSizing.reset(compact: compact)
        prefs.compactView = compact
    }

    func showHistory(source: HistorySource? = nil) {
        historyWindow.show(hub: self, preferredSource: source)
    }

    func importWrapped() {
        guard !wrapped.loading, !wrapped.busy else { return }
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Import historical song data"
        panel.message = "Choose a Mini Deck historical-song JSON snapshot. It stays private on this Mac and does not add to streaming-history totals."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await wrapped.importFile(url)
                showHistory(source: .spotify)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Historical song data was not imported"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    func clearWrapped() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Remove historical song data?"
        alert.informativeText = "Only Mini Deck's private historical-song copy is removed. Spotify, your full-history import and original files are unchanged."
        alert.addButton(withTitle: "Remove Snapshot")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try wrapped.clear() }
        catch { deck.flash("exclamationmark.triangle", "Couldn't remove historical song data") }
    }

    func showSetup(step: Int? = nil) { setupWindow.show(hub: self, step: step) }

    func chooseAutoImportFolder() {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Automatically import Spotify exports"
        panel.message = "Choose a dedicated folder for extracted Spotify history JSON files. Mini Deck will check only this selected folder every 30 seconds and deduplicate new imports. ZIP files must be extracted first."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try archive.watchFolder(url) }
        catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't watch this folder"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
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

    func importSpotifyHistory() {
        guard !archive.busy, !archive.loading else { return }
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.title = "Import Spotify Extended Streaming History"
        panel.message = "Unzip Spotify's export first. Select all Streaming_History_Audio JSON files (or their folder). Imported data stays on this Mac."
        panel.allowedContentTypes = [.json, .folder]
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            do {
                try await archive.importFiles(urls)
                deck.flash("checkmark.circle", "Spotify history imported")
                showHistory()
            } catch {
                let alert = NSAlert()
                alert.messageText = "Spotify history was not imported"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    func clearSpotifyImport() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Remove imported Spotify history?"
        alert.informativeText = "Only Mini Deck's sanitized import is deleted. Your original export, Spotify account, and Mac-only history are unchanged."
        alert.addButton(withTitle: "Remove Import")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { archive.stopWatching(); try archive.clear() }
        catch { deck.flash("exclamationmark.triangle", "Couldn't remove the import") }
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

    func clearOngoingSpotify() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Clear ongoing Spotify records?"
        alert.informativeText = "Removes Mini Deck's saved recent-account records and new Spotify playback sessions. Imported files, historical song data, and Spotify are unchanged. Recording resumes while enabled."
        alert.addButton(withTitle: "Clear Ongoing Records")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try archive.clearOngoing() }
        catch { deck.flash("exclamationmark.triangle", "Couldn't clear ongoing history") }
    }

    /// The guided flow reuses a bundled registration when available, with a
    /// complete manual fallback and no unsolicited clipboard reads.
    func askToConnectSpotify() {
        showSetup(step: 2)
    }
}

enum PrefKey {
    static let compactView = "minideck.compactView"
    static let soundBars = "minideck.soundBars"
    static let loginSeeded = "minideck.loginSeeded"
    static let askedCapture = "minideck.askedCapture"
    static let anchor = "minideck.anchorTopLeft"
    static let choice = "minideck.source"
    static let countPlays = "minideck.countPlays"
    static let statsAdvanced = "minideck.statsAdvanced"
    static let spotifySpan = "minideck.spotifySpan"
    static let exportRequested = "minideck.exportRequested"
}

@MainActor @Observable
final class Prefs {
    var compactView: Bool {
        didSet { UserDefaults.standard.set(compactView, forKey: PrefKey.compactView) }
    }
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
    var spotifySpan: SpotifyAccount.Span {
        didSet { UserDefaults.standard.set(spotifySpan.rawValue, forKey: PrefKey.spotifySpan) }
    }
    var exportRequested: Bool {
        didSet { UserDefaults.standard.set(exportRequested, forKey: PrefKey.exportRequested) }
    }
    private(set) var openAtLogin: Bool

    init() {
        let store = UserDefaults.standard
        compactView = store.bool(forKey: PrefKey.compactView)
        soundBars = store.object(forKey: PrefKey.soundBars) as? Bool ?? Metrics.soundBarsOn
        choice = store.string(forKey: PrefKey.choice).flatMap(SourceChoice.init(rawValue:)) ?? .automatic
        countPlays = store.object(forKey: PrefKey.countPlays) as? Bool ?? true
        statsAdvanced = store.bool(forKey: PrefKey.statsAdvanced)
        spotifySpan = store.string(forKey: PrefKey.spotifySpan).flatMap(SpotifyAccount.Span.init(rawValue:)) ?? .short
        exportRequested = store.bool(forKey: PrefKey.exportRequested)
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
        Button("Setup & Help…") { hub.showSetup() }
        Menu("Listening Stats") {
            Button(hub.archive.busy ? "Importing Spotify History…" : "Import Full Spotify History…") { hub.importSpotifyHistory() }
                .disabled(hub.archive.busy || hub.archive.loading)
            Button("Clear Ongoing Spotify Records…") { hub.clearOngoingSpotify() }
                .disabled(hub.archive.loading)
            Button("Request Spotify Extended History…") {
                NSWorkspace.shared.open(URL(string: "https://www.spotify.com/account/privacy/")!)
            }
            Button("Auto-import Spotify Export Folder…") { hub.chooseAutoImportFolder() }
            if hub.archive.watchedFolderName != nil {
                Button("Stop Automatic Imports") { hub.archive.stopWatching() }
            }
            if hub.archive.hasHistory || hub.archive.loadError != nil {
                Button("Remove Imported Spotify History…") { hub.clearSpotifyImport() }
                    .disabled(hub.archive.busy)
            }
            Button("Import Historical Song Data…") { hub.importWrapped() }
                .disabled(hub.wrapped.loading || hub.wrapped.busy)
            if !hub.wrapped.playlists.isEmpty || hub.wrapped.loadError {
                Button("Remove Historical Song Data…") { hub.clearWrapped() }
                    .disabled(hub.wrapped.loading || hub.wrapped.busy)
            }
            Divider()
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
        Toggle("Compact View", isOn: Binding(get: { hub.prefs.compactView },
                                             set: { hub.setCompact($0) }))
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
