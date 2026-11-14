// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Counts what you listen to while Mini Deck runs. Stored only on this Mac, readable only by your user.
@MainActor @Observable
final class ListeningLog {
    struct Song: Codable, Equatable {
        var title: String
        var artist: String
        /// Added in 1.2; older saved songs have none until heard again.
        var album: String? = nil
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
    @ObservationIgnored private let persists: Bool

    init(persist: Bool = true) {
        persists = persist
        book = (persist ? Self.load() : nil) ?? Book(since: Date())
    }

    static func songKey(artist: String, title: String) -> String {
        TitleTidy.key(artist) + "/" + TitleTidy.key(title)
    }

    static func artistKey(_ name: String) -> String { TitleTidy.key(name) }

    // MARK: Counting

    /// `gap` is the longest pause between checks that still counts as listening.
    /// Checks slow down while the player is hidden, so the gap follows the check pace.
    func tick(_ snap: Snapshot, now: Date = Date(), gap: TimeInterval = 2) {
        guard enabled, snap.state == .playing, !snap.title.isEmpty else {
            lastTick = nil
            return
        }
        let songKey = Self.songKey(artist: snap.primaryArtist, title: snap.title)
        let artistKey = Self.artistKey(snap.primaryArtist)
        let restarted = counted && snap.position < 3 && lastPosition > snap.position + 3
        if songKey != listenKey || restarted {
            listenKey = songKey
            heard = 0
            counted = false
        }
        lastPosition = snap.position
        let delta = lastTick.map { min(max(0, now.timeIntervalSince($0)), max(2, gap)) } ?? 0
        lastTick = now
        guard delta > 0 || !counted else { return }

        heard += delta
        var song = book.songs[songKey] ?? Song(title: snap.title, artist: snap.primaryArtist, first: now, last: now)
        var artist = book.artists[artistKey] ?? Artist(name: snap.primaryArtist, first: now)
        song.seconds += delta
        song.last = now
        if !snap.album.isEmpty { song.album = snap.album }
        artist.seconds += delta
        if !counted {
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

    // MARK: Artist and album history

    func songs(byArtist name: String) -> [Song] {
        let key = Self.artistKey(name)
        guard !key.isEmpty else { return [] }
        return book.songs.values.filter { TitleTidy.key($0.artist) == key }
    }

    func songs(onAlbum album: String, artists: [String]) -> [Song] {
        let albumKey = TitleTidy.key(album)
        let keys = Set(artists.map(TitleTidy.key).filter { !$0.isEmpty })
        guard !albumKey.isEmpty else { return [] }
        return book.songs.values.filter { song in
            guard let a = song.album, TitleTidy.key(a) == albumKey else { return false }
            return keys.isEmpty || keys.contains(TitleTidy.key(song.artist))
        }
    }

    // MARK: History lists

    /// Songs by when you last heard them here, newest first. Only songs that reached a full play.
    func recentSongs(limit: Int = 50) -> [Song] {
        Array(book.songs.values.filter { $0.plays > 0 }.sorted { $0.last > $1.last }.prefix(limit))
    }

    /// Songs by plays, then listening time.
    func topSongs(limit: Int = 50) -> [Song] {
        Array(book.songs.values.filter { $0.plays > 0 }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.seconds > $1.seconds }
            .prefix(limit))
    }

    struct AlbumTotal: Equatable {
        let album: String
        let artist: String
        let plays: Int
        let seconds: Double
    }

    /// Albums by listening time, from songs heard since 1.2 (older entries have no album).
    func topAlbums(limit: Int = 50) -> [AlbumTotal] {
        var albums: [String: AlbumTotal] = [:]
        for song in book.songs.values {
            guard let album = song.album, !TitleTidy.key(album).isEmpty else { continue }
            let key = TitleTidy.key(album) + "/" + TitleTidy.key(song.artist)
            let old = albums[key]
            albums[key] = AlbumTotal(album: old?.album ?? album, artist: old?.artist ?? song.artist,
                                     plays: (old?.plays ?? 0) + song.plays, seconds: (old?.seconds ?? 0) + song.seconds)
        }
        return Array(albums.values.filter { $0.seconds >= 60 }.sorted { $0.seconds > $1.seconds }.prefix(limit))
    }

    /// Artists by listening time.
    func topArtists(limit: Int = 50) -> [Artist] {
        Array(book.artists.values.filter { $0.seconds >= 60 }.sorted { $0.seconds > $1.seconds }.prefix(limit))
    }

    // MARK: Storage

    func clear() {
        saveTask?.cancel()
        saveTask = nil
        book = Book(since: Date())
        listenKey = ""
        heard = 0
        counted = false
        lastTick = nil
        if persists { try? FileManager.default.removeItem(at: Self.fileURL) }
    }

    func flush() {
        saveTask?.cancel()
        saveTask = nil
        if persists { Self.save(book) }
    }

    private func scheduleSave() {
        guard persists, saveTask == nil else { return }
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
