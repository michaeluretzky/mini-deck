// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import ImageIO
import SwiftUI

enum NotesState: Equatable {
    case idle, loading, found(AlbumNotes), empty
}

struct HUDMessage: Equatable {
    let symbol: String
    let text: String
    let stamp = UUID()
}

/// The live model of the player: track, transport, cover, colors and liner notes.
@MainActor @Observable
final class Deck {
    /// The app the card is following.
    private(set) var source: Source = .spotify
    /// Whether that app is running.
    private(set) var appOpen = false
    private(set) var track = Snapshot()
    private(set) var facts: LibraryFacts?
    private(set) var cover: NSImage?
    private(set) var swatch = Swatch.fallback
    private(set) var notes: NotesState = .idle
    private(set) var songNote: String?
    private(set) var hud: HUDMessage?
    private(set) var volume: Double = 50
    private(set) var anchorPosition: Double = 0
    private(set) var anchorDate = Date()

    @ObservationIgnored private var seekHold = Date.distantPast
    @ObservationIgnored private var volumeHold = Date.distantPast
    @ObservationIgnored private var lastVolumeSend = Date.distantPast
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    @ObservationIgnored private var hudTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var coverTask: Task<Void, Never>?
    @ObservationIgnored private var albumTask: Task<Void, Never>?
    @ObservationIgnored private var songTask: Task<Void, Never>?
    @ObservationIgnored private var albumKey = ""
    @ObservationIgnored private var songKey = ""
    @ObservationIgnored private var coverKey = ""
    @ObservationIgnored private var decoding = false
    @ObservationIgnored private var coverURL: URL?
    @ObservationIgnored private var factsKey = ""
    @ObservationIgnored var choice: SourceChoice = .automatic
    @ObservationIgnored var onTick: ((Snapshot) -> Void)?
    @ObservationIgnored var onNewTrack: ((Snapshot) -> Void)?
    @ObservationIgnored private var coverSource: CGImage?
    @ObservationIgnored var pixelScale: CGFloat = 2 {
        didSet { if pixelScale != oldValue { rerenderCover() } }
    }

    var isPlaying: Bool { track.state == .playing }
    var hasTrack: Bool { appOpen && track.state != .stopped && !track.title.isEmpty }

    var creditedArtist: String {
        let aa = track.albumArtist
        return aa.isEmpty || aa.caseInsensitiveCompare("Various Artists") == .orderedSame ? track.artist : aa
    }

    var shareURL: URL? {
        guard track.source == .spotify else { return nil }
        let parts = track.trackID.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return nil }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }

    func elapsed(at date: Date) -> Double {
        guard track.length > 0 else { return 0 }
        let running = isPlaying ? max(0, date.timeIntervalSince(anchorDate)) : 0
        return min(anchorPosition + running, track.length)
    }

    // MARK: Reading the music apps

    func start() {
        for app in Source.allCases {
            DistributedNotificationCenter.default().addObserver(forName: app.changed, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Follows the chosen app, or in Automatic mode whichever app is playing.
    private func pick() -> (Source, Snapshot?) {
        if let only = choice.fixed { return (only, Players.read(only)) }
        var reads: [Source: Snapshot] = [:]
        for app in Source.allCases { if let s = Players.read(app) { reads[app] = s } }
        if let s = reads[source], s.state == .playing { return (source, s) }
        if let other = reads.first(where: { $0.value.state == .playing }) { return (other.key, other.value) }
        if let s = reads[source], s.state != .stopped { return (source, s) }
        if let other = reads.first(where: { $0.value.state != .stopped }) { return (other.key, other.value) }
        if Players.isRunning(source) { return (source, reads[source]) }
        if let any = reads.first { return (any.key, any.value) }
        return (source, nil)
    }

    func refresh() {
        let (app, read) = pick()
        if app != source { source = app }
        let open = Players.isRunning(app)
        if open != appOpen { appOpen = open }
        guard open, let snap = read else {
            if track.state != .stopped { track = Snapshot(source: app) }
            return
        }
        let newTrack = snap.title != track.title || snap.artist != track.artist || snap.source != track.source
        if snap != track { track = snap }
        let now = Date()
        if now > seekHold {
            anchorPosition = snap.position
            anchorDate = now
        }
        if now > volumeHold, volume != Double(snap.volume) { volume = Double(snap.volume) }
        updateCover(snap)
        updateFacts(snap)
        lookUp(snap)
        onTick?(snap)
        if newTrack && !snap.title.isEmpty { onNewTrack?(snap) }
    }

    private func updateFacts(_ s: Snapshot) {
        guard s.source == .music else {
            if facts != nil { facts = nil }
            factsKey = ""
            return
        }
        let key = s.trackID + "|" + s.title
        guard key != factsKey else { return }
        factsKey = key
        facts = Players.musicFacts()
    }

    private func refreshSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.refresh()
        }
    }

    // MARK: Liner notes

    private func lookUp(_ s: Snapshot) {
        guard !s.title.isEmpty else { return }
        let credit = creditedArtist
        let aKey = credit + "\n" + s.album
        if aKey != albumKey, !s.album.isEmpty {
            albumKey = aKey
            notes = .loading
            albumTask?.cancel()
            let album = s.album
            albumTask = Task { [weak self] in
                let found = await LinerNotesService.shared.album(artist: credit, title: album)
                guard let self, !Task.isCancelled, self.albumKey == aKey else { return }
                self.notes = found.map { .found($0) } ?? .empty
                if self.track.source == .music, self.cover == nil, !self.decoding, let art = found?.artworkURL {
                    self.coverURL = art
                    self.loadCover(art)
                }
            }
        }
        let sKey = s.artist + "\n" + s.title
        if sKey != songKey {
            songKey = sKey
            songNote = nil
            songTask?.cancel()
            let (title, artist) = (s.title, s.artist)
            songTask = Task { [weak self] in
                let note = await LinerNotesService.shared.song(title: title, artist: artist)
                guard let self, !Task.isCancelled, self.songKey == sKey else { return }
                self.songNote = note
            }
        }
    }

    // MARK: Cover

    private func updateCover(_ s: Snapshot) {
        switch s.source {
        case .spotify:
            let key = "spotify|" + (s.artworkURL?.absoluteString ?? "")
            guard key != coverKey else { return }
            coverKey = key
            coverURL = s.artworkURL
            loadCover(s.artworkURL)
        case .music:
            let key = "music|" + s.albumArtist + "|" + s.artist + "|" + s.album
            guard key != coverKey else { return }
            coverKey = key
            coverURL = nil
            if let data = Players.musicArtwork() {
                showCover(data, tag: key)
            } else if case .found(let n) = notes, albumKey == creditedArtist + "\n" + s.album, let art = n.artworkURL {
                coverURL = art
                loadCover(art)
            } else {
                clearCover()
            }
        }
    }

    private func clearCover() {
        coverTask?.cancel()
        coverSource = nil
        cover = nil
        swatch = .fallback
    }

    private func loadCover(_ url: URL?) {
        coverTask?.cancel()
        guard let url else { clearCover(); return }
        let tag = coverKey
        coverTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            guard let self, !Task.isCancelled, self.coverURL == url else { return }
            self.showCover(data, tag: tag)
        }
    }

    private func showCover(_ data: Data, tag: String) {
        coverTask?.cancel()
        let scale = pixelScale
        decoding = true
        coverTask = Task { [weak self] in
            defer { self?.decoding = false }
            let made = await Task.detached(priority: .userInitiated) { () -> (CGImage, NSImage, Swatch)? in
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                return (image, CoverArt.render(image, side: Metrics.cover, scale: scale), Palette.swatch(for: image))
            }.value
            guard let self, !Task.isCancelled, self.coverKey == tag else { return }
            guard let made else {
                // Some covers come in formats ImageIO can't read; fall back to the store's artwork.
                self.clearCover()
                if case .found(let n) = self.notes, let art = n.artworkURL, self.track.source == .music {
                    self.coverURL = art
                    self.loadCover(art)
                }
                return
            }
            self.coverSource = made.0
            self.cover = made.1
            self.swatch = made.2
        }
    }

    private func rerenderCover() {
        guard let coverSource else { return }
        cover = CoverArt.render(coverSource, side: Metrics.cover, scale: pixelScale)
    }

    // MARK: Commands

    private func send(_ command: PlayerCommand) { Players.send(command, to: source) }

    func togglePlay() { send(.playPause); refreshSoon() }
    func skipForward() { send(.next); refreshSoon() }
    func skipBack() { send(.previous); refreshSoon() }

    func toggleShuffle() {
        let on = !track.shuffle
        track.shuffle = on
        send(.shuffle(on))
        flash("shuffle", on ? "Shuffle is on" : "Shuffle is off")
    }

    func toggleRepeat() {
        let on = !track.loop
        track.loop = on
        send(.loop(on))
        flash("repeat", on ? "Repeat is on" : "Repeat is off")
    }

    func seek(fraction: Double) {
        let target = min(max(fraction, 0), 1) * track.length
        anchorPosition = target
        anchorDate = Date()
        seekHold = Date().addingTimeInterval(1.5)
        send(.seek(target))
    }

    func adjustVolume(by delta: Double) {
        guard appOpen else { return }
        volume = min(100, max(0, volume + delta))
        volumeHold = Date().addingTimeInterval(1.5)
        let level = Int(volume.rounded())
        flash(Self.speaker(level), "Volume \(level)%")
        volumeTask?.cancel()
        let wait = max(0, 0.1 - Date().timeIntervalSince(lastVolumeSend))
        volumeTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard let self, !Task.isCancelled else { return }
            self.lastVolumeSend = Date()
            self.send(.volume(level))
        }
    }

    func revealApp() { Players.reveal(source) }

    func copyLink() {
        guard let url = shareURL else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(url.absoluteString, forType: .string)
        flash("link", "Track link copied")
    }

    func flash(_ symbol: String, _ text: String) {
        hud = HUDMessage(symbol: symbol, text: text)
        hudTask?.cancel()
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.3))
            guard let self, !Task.isCancelled else { return }
            self.hud = nil
        }
    }

    private static func speaker(_ level: Int) -> String {
        switch level {
        case 0: "speaker.slash.fill"
        case 1..<34: "speaker.wave.1.fill"
        case 34..<67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
