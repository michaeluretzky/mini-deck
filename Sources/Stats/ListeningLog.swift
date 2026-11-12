// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Counts what you listen to while Mini Deck runs. Stored only on this Mac, readable only by your user.
@MainActor @Observable
final class ListeningLog {
    struct Song: Codable, Equatable {
        var title: String
        var artist: String
        var plays = 0
        var seconds: Double = 0
        var first: Date
        var last: Date
    }

    struct Artist: Codable, Equatable {
        var name: String
        var plays = 0
        var seconds: Double = 0
        var first: Date
    }

    struct Book: Codable, Equatable {
        var version = 1
        var since: Date
        var songs: [String: Song] = [:]
        var artists: [String: Artist] = [:]
    }

    /// A song counts as played after this much listening, the same bar most services use.
    static let playThreshold: Double = 30

    private(set) var book: Book
    var enabled = true {
        didSet { if !enabled { lastTick = nil } }
    }

    @ObservationIgnored private var listenKey = ""
    @ObservationIgnored private var heard: Double = 0
    @ObservationIgnored private var counted = false
    @ObservationIgnored private var lastTick: Date?
    @ObservationIgnored private var lastPosition: Double = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        book = Self.load() ?? Book(since: Date())
    }

    static func songKey(artist: String, title: String) -> String {
        TitleTidy.key(artist) + "/" + TitleTidy.key(title)
    }

    static func artistKey(_ name: String) -> String { TitleTidy.key(name) }

    // MARK: Counting

    func tick(_ snap: Snapshot, now: Date = Date()) {
        guard enabled, snap.state == .playing, !snap.title.isEmpty else {
            lastTick = nil
            return
        }
        let songKey = Self.songKey(artist: snap.primaryArtist, title: snap.title)
        let artistKey = Self.artistKey(snap.primaryArtist)
        let restarted = counted && snap.position < 5 && lastPosition > Self.playThreshold
        if songKey != listenKey || restarted {
            listenKey = songKey
            heard = 0
            counted = false
        }
        lastPosition = snap.position
        let delta = lastTick.map { min(max(0, now.timeIntervalSince($0)), 2) } ?? 0
        lastTick = now
        guard delta > 0 else { return }

        heard += delta
        var song = book.songs[songKey] ?? Song(title: snap.title, artist: snap.primaryArtist, first: now, last: now)
        var artist = book.artists[artistKey] ?? Artist(name: snap.primaryArtist, first: now)
        song.seconds += delta
        song.last = now
        artist.seconds += delta
        if !counted && heard >= Self.playThreshold {
            counted = true
            song.plays += 1
            artist.plays += 1
        }
        book.songs[songKey] = song
        book.artists[artistKey] = artist
        scheduleSave()
    }

    // MARK: Questions

    func song(artist: String, title: String) -> Song? {
        book.songs[Self.songKey(artist: artist, title: title)]
    }

    func artist(_ name: String) -> Artist? { book.artists[Self.artistKey(name)] }

    /// 1 = the artist you've spent the most time with here.
    func artistRank(_ name: String) -> Int? {
        let key = Self.artistKey(name)
        guard let mine = book.artists[key], mine.seconds > 0 else { return nil }
        return 1 + book.artists.values.filter { $0.seconds > mine.seconds }.count
    }

    var isEmpty: Bool { book.songs.isEmpty }

    // MARK: Storage

    func clear() {
        saveTask?.cancel()
        book = Book(since: Date())
        listenKey = ""
        heard = 0
        counted = false
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        Self.save(book)
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, !Task.isCancelled else { return }
            self.saveTask = nil
            Self.save(self.book)
        }
    }

    private static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mini Deck", isDirectory: true)
    }

    private static var fileURL: URL { folderURL.appendingPathComponent("listening.json") }

    private static func load() -> Book? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Book.self, from: data)
    }

    private static func save(_ book: Book) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folderURL, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(book)
            try data.write(to: fileURL, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // Counting is a nice-to-have; a failed save never interrupts playback.
        }
    }
}
