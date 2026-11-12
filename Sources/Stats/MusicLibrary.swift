// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Artist totals, most-played songs and recently played songs from the Music app's library.
@MainActor @Observable
final class MusicLibrary {
    struct Total: Equatable, Sendable {
        var plays = 0
        var songs = 0
    }

    struct Song: Equatable, Sendable {
        let title: String
        let artist: String
        var album = ""
        var albumArtist = ""
        let plays: Int
        let lastPlayed: Date?
    }

    struct ArtistTotal: Equatable, Sendable {
        let name: String
        let total: Total
    }

    struct AlbumTotal: Equatable, Sendable {
        let album: String
        let artist: String
        let plays: Int
    }

    struct Scan: Sendable {
        var totals: [String: Total] = [:]
        var names: [String: String] = [:]
        var mostPlayed: [Song] = []
        var recentlyPlayed: [Song] = []
        var all: [Song] = []
        var topAlbums: [AlbumTotal] = []
    }

    static let listLength = 50

    private(set) var totals: [String: Total] = [:]
    private(set) var ranks: [String: Int] = [:]
    /// History lists for the history window.
    private(set) var mostPlayed: [Song] = []
    private(set) var recentlyPlayed: [Song] = []
    private(set) var topArtists: [ArtistTotal] = []
    private(set) var topAlbums: [AlbumTotal] = []
    /// Every library song, for artist and album history.
    @ObservationIgnored private(set) var all: [Song] = []
    private(set) var scanned: Date?
    private(set) var scanning = false
    private(set) var failed = false

    func total(for artist: String) -> Total? { totals[TitleTidy.key(artist)] }
    func rank(for artist: String) -> Int? { ranks[TitleTidy.key(artist)] }

    /// Reads the library at most every 30 minutes, only while the Music app is open.
    func scanIfStale(force: Bool = false) {
        guard !scanning, Players.isRunning(.music) else { return }
        if !force, let scanned, Date().timeIntervalSince(scanned) < 30 * 60 { return }
        scanning = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.readLibrary() }.value
            guard let self else { return }
            self.scanning = false
            guard let result else { self.failed = true; return }
            self.failed = false
            self.totals = result.totals
            let ordered = result.totals.filter { $0.value.plays > 0 }.sorted {
                $0.value.plays != $1.value.plays ? $0.value.plays > $1.value.plays : $0.key < $1.key
            }
            var ranks: [String: Int] = [:]
            var place = 0
            var previous = Int.max
            for (i, entry) in ordered.enumerated() {
                if entry.value.plays < previous { place = i + 1; previous = entry.value.plays }
                ranks[entry.key] = place
            }
            self.ranks = ranks
            self.topArtists = ordered.prefix(Self.listLength).map { ArtistTotal(name: result.names[$0.key] ?? $0.key, total: $0.value) }
            self.mostPlayed = result.mostPlayed
            self.recentlyPlayed = result.recentlyPlayed
            self.all = result.all
            self.topAlbums = result.topAlbums
            self.scanned = Date()
        }
    }

    // MARK: Artist and album history

    func songs(byArtist name: String) -> [Song] {
        let key = TitleTidy.key(name)
        guard !key.isEmpty else { return [] }
        return all.filter { TitleTidy.key($0.artist) == key || TitleTidy.key($0.albumArtist) == key }
    }

    func songs(onAlbum album: String, artists: [String]) -> [Song] {
        let albumKey = TitleTidy.key(album)
        let keys = Set(artists.map(TitleTidy.key).filter { !$0.isEmpty })
        guard !albumKey.isEmpty else { return [] }
        return all.filter { song in
            guard TitleTidy.key(song.album) == albumKey else { return false }
            return keys.isEmpty || keys.contains(TitleTidy.key(song.artist)) || keys.contains(TitleTidy.key(song.albumArtist))
        }
    }

    private struct Columns: Decodable {
        let n: [String?]
        let a: [String?]
        let b: [String?]
        let c: [String?]
        let p: [Int?]
        let d: [Double?]
    }

    /// Runs off the main thread through osascript so large libraries never stall the card.
    /// JavaScript for Automation returns dates as numbers, which avoids locale-dependent date text.
    nonisolated private static func readLibrary() -> Scan? {
        let script = """
        const lib = Application('com.apple.Music').libraryPlaylists[0].tracks;
        const n = lib.name(), a = lib.artist(), b = lib.album(), c = lib.albumArtist();
        const p = lib.playedCount(), d = lib.playedDate();
        JSON.stringify({ n: n, a: a, b: b, c: c, p: p,
                         d: d.map(x => (x instanceof Date) ? x.getTime() / 1000 : null) });
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-l", "JavaScript", "-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog.cancel()
        guard task.terminationStatus == 0 else { return nil }
        return parse(data)
    }

    nonisolated static func parse(_ data: Data) -> Scan? {
        guard let cols = try? JSONDecoder().decode(Columns.self, from: data),
              Set([cols.n.count, cols.a.count, cols.b.count, cols.c.count, cols.p.count, cols.d.count]).count == 1
        else { return nil }
        var scan = Scan()
        var songs: [Song] = []
        songs.reserveCapacity(cols.n.count)
        for i in cols.n.indices {
            let artist = cols.a[i] ?? ""
            let plays = max(0, cols.p[i] ?? 0)
            let key = TitleTidy.key(artist)
            if !key.isEmpty {
                var t = scan.totals[key] ?? Total()
                t.songs += 1
                t.plays += plays
                scan.totals[key] = t
                if scan.names[key] == nil { scan.names[key] = artist }
            }
            let when = cols.d[i].flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
            songs.append(Song(title: cols.n[i] ?? "", artist: artist, album: cols.b[i] ?? "",
                              albumArtist: cols.c[i] ?? "", plays: plays, lastPlayed: when))
        }
        scan.mostPlayed = Array(songs.filter { $0.plays > 0 }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.title < $1.title }
            .prefix(listLength))
        scan.recentlyPlayed = Array(songs.filter { $0.lastPlayed != nil }
            .sorted { $0.lastPlayed! > $1.lastPlayed! }
            .prefix(listLength))
        scan.all = songs
        var albums: [String: (album: String, artist: String, plays: Int)] = [:]
        for song in songs where song.plays > 0 && !TitleTidy.key(song.album).isEmpty {
            let owner = song.albumArtist.isEmpty ? song.artist : song.albumArtist
            let key = TitleTidy.key(song.album) + "/" + TitleTidy.key(owner)
            var entry = albums[key] ?? (song.album, owner, 0)
            entry.plays += song.plays
            albums[key] = entry
        }
        scan.topAlbums = albums.values
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.album < $1.album }
            .prefix(listLength)
            .map { AlbumTotal(album: $0.album, artist: $0.artist, plays: $0.plays) }
        return scan
    }
}
