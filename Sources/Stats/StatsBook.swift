// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

struct StatTile: Hashable, Identifiable {
    let value: String
    let caption: String
    var symbol: String?
    var id: String { caption + value }
}

/// One line of a short song list, such as "your top songs by this artist".
struct HistoryLine: Hashable, Identifiable {
    let title: String
    let detail: String
    var id: String { title + "\u{1F}" + detail }
}

/// Stats for one subject: the song, its artist, or its album.
struct StatScope {
    static let maxTiles = 3
    static let maxLines = 3

    private(set) var tiles: [StatTile] = []
    private(set) var lines: [HistoryLine] = []
    private(set) var linesTitle = ""
    private(set) var sources: [String] = []
    private var tileSources: [String] = []
    private var lineSource = ""

    var isEmpty: Bool { tiles.isEmpty && lines.isEmpty }
    var caption: String { sources.joined(separator: " · ") }

    mutating func add(_ more: [StatTile], from source: String) {
        tiles += more
        tileSources += Array(repeating: source, count: more.count)
    }

    mutating func list(_ title: String, _ more: [HistoryLine], from source: String) {
        guard lines.isEmpty, !more.isEmpty else { return }
        linesTitle = title
        lines = Array(more.prefix(Self.maxLines))
        lineSource = source
    }

    /// Keeps one row of tiles and names only the sources still shown.
    mutating func trim() {
        tiles = Array(tiles.prefix(Self.maxTiles))
        tileSources = Array(tileSources.prefix(Self.maxTiles))
        var used: [String] = []
        for source in tileSources + (lines.isEmpty ? [] : [lineSource]) where !used.contains(source) { used.append(source) }
        sources = used
    }
}

/// What the "Your listening" section can show right now.
struct ListeningReport {
    enum Prompt: Equatable { case none, connectSpotify, reconnectSpotify, waiting, loading, problem(String) }
    var song = StatScope()
    var artist = StatScope()
    var album = StatScope()
    var prompt: Prompt = .none
    var isEmpty: Bool { song.isEmpty && artist.isEmpty && album.isEmpty }
}

/// Turns account, library and on-device numbers into short tiles for the current song, artist and album.
@MainActor
enum StatsBook {
    static let spotifyLabel = "Spotify account"
    static let musicLabel = "Music library"
    static func macLabel(_ log: ListeningLog) -> String { "this Mac since \(shortDate(log.book.since))" }

    static func report(track: Snapshot, facts: LibraryFacts?, account: SpotifyAccount,
                       library: MusicLibrary, log: ListeningLog, counting: Bool) -> ListeningReport {
        var out = ListeningReport()
        let artist = track.primaryArtist
        let artists = [track.primaryArtist, track.albumArtist].filter { !$0.isEmpty }

        switch track.source {
        case .spotify:
            switch account.status {
            case .on:
                if account.updated == nil {
                    out.prompt = .loading
                } else {
                    spotify(track: track, account: account, into: &out)
                    if out.isEmpty {
                        out.song.add([StatTile(value: "New", caption: "not in your top 50 or last 50 plays", symbol: "sparkles")],
                                     from: spotifyLabel)
                    }
                }
            case .off: out.prompt = .connectSpotify
            case .expired: out.prompt = .reconnectSpotify
            case .waiting: out.prompt = .waiting
            case .failed(let why): out.prompt = .problem(why)
            }
        case .music:
            music(track: track, facts: facts, library: library, into: &out)
            if out.isEmpty && library.scanning { out.prompt = .loading }
        }

        if counting {
            mac(track: track, artist: artist, artists: artists, log: log, into: &out)
        }
        out.song.trim()
        out.artist.trim()
        out.album.trim()
        return out
    }

    // MARK: Spotify account

    private static func spotify(track: Snapshot, account: SpotifyAccount, into out: inout ListeningReport) {
        let artistKeys = Set([track.primaryArtist, track.albumArtist].map(TitleTidy.key).filter { !$0.isEmpty })
        let albumKey = TitleTidy.key(track.album)
        let trackID = track.trackID.split(separator: ":").last.map(String.init) ?? ""
        let byArtist: (SpotifyAccount.Play) -> Bool = { !artistKeys.isDisjoint(with: $0.artistKeys) }
        let onAlbum: (SpotifyAccount.Play) -> Bool = { !albumKey.isEmpty && TitleTidy.key($0.album) == albumKey && byArtist($0) }
        let recentCount = account.recent.count

        func best(_ pick: (SpotifyAccount.Top) -> Int?) -> (rank: Int, span: SpotifyAccount.Span)? {
            var found: (Int, SpotifyAccount.Span)?
            for span in SpotifyAccount.Span.allCases {
                if let r = account.top[span].flatMap(pick), r < (found?.0 ?? .max) { found = (r, span) }
            }
            return found
        }

        // Best rank across 4 weeks, 6 months and 12 months for every top song that matches.
        func topSongs(_ keep: (SpotifyAccount.Ranked) -> Bool) -> [(song: SpotifyAccount.Ranked, rank: Int, span: SpotifyAccount.Span)] {
            var bestByID: [String: (SpotifyAccount.Ranked, Int, SpotifyAccount.Span)] = [:]
            for span in SpotifyAccount.Span.allCases {
                for (i, song) in (account.topSongs[span] ?? []).enumerated() where keep(song) {
                    let id = song.id.isEmpty ? song.title : song.id
                    if (bestByID[id]?.1 ?? .max) > i + 1 { bestByID[id] = (song, i + 1, span) }
                }
            }
            return bestByID.values.sorted { $0.1 < $1.1 }.map { ($0.0, $0.1, $0.2) }
        }

        // This song
        var song: [StatTile] = []
        if !trackID.isEmpty, let t = best({ $0.tracks[trackID] }) {
            song.append(StatTile(value: "#\(t.rank)", caption: "top song · \(t.span.label)", symbol: "music.note"))
        }
        let songPlays = account.recent.filter { $0.trackID == trackID }
        if !songPlays.isEmpty {
            song.append(StatTile(value: "\(songPlays.count)×", caption: "in your last \(recentCount) plays", symbol: "arrow.counterclockwise"))
            if let last = songPlays.map(\.at).max() {
                song.append(StatTile(value: ago(last), caption: "last played", symbol: "calendar"))
            }
        }
        out.song.add(song, from: spotifyLabel)

        // This artist
        var art: [StatTile] = []
        if let a = best({ top in artistKeys.compactMap { top.artists[$0] }.min() }) {
            art.append(StatTile(value: "#\(a.rank)", caption: "top artist · \(a.span.label)", symbol: "person.fill"))
        }
        let artistTop = topSongs { !artistKeys.isDisjoint(with: $0.artistKeys) }
        if !artistTop.isEmpty {
            art.append(StatTile(value: "\(artistTop.count)", caption: artistTop.count == 1 ? "song in your top lists" : "songs in your top lists",
                                symbol: "list.number"))
        }
        let artistPlays = account.recent.filter(byArtist)
        if !artistPlays.isEmpty {
            art.append(StatTile(value: "\(artistPlays.count)", caption: "of your last \(recentCount) plays", symbol: "waveform"))
            if let last = artistPlays.map(\.at).max() {
                art.append(StatTile(value: ago(last), caption: "last played", symbol: "calendar"))
            }
        }
        out.artist.add(art, from: spotifyLabel)
        out.artist.list("Your top songs by \(track.primaryArtist)",
                        artistTop.map { HistoryLine(title: $0.song.title, detail: "#\($0.rank) · \($0.span.label)") },
                        from: spotifyLabel)

        // This album
        var alb: [StatTile] = []
        let albumTop = topSongs { !albumKey.isEmpty && TitleTidy.key($0.album) == albumKey && !artistKeys.isDisjoint(with: $0.artistKeys) }
        let albumPlays = account.recent.filter(onAlbum)
        if !albumPlays.isEmpty {
            alb.append(StatTile(value: "\(albumPlays.count)", caption: "of your last \(recentCount) plays", symbol: "opticaldisc"))
        }
        if !albumTop.isEmpty {
            alb.append(StatTile(value: "\(albumTop.count)", caption: albumTop.count == 1 ? "song in your top lists" : "songs in your top lists",
                                symbol: "list.number"))
        }
        if let last = albumPlays.map(\.at).max() {
            alb.append(StatTile(value: ago(last), caption: "last played", symbol: "calendar"))
        }
        let distinct = Set(albumPlays.map(\.trackID)).count
        if distinct > 1 {
            alb.append(StatTile(value: "\(distinct)", caption: "songs played recently", symbol: "music.note.list"))
        }
        out.album.add(alb, from: spotifyLabel)
        out.album.list("Your top songs on this album",
                       albumTop.map { HistoryLine(title: $0.song.title, detail: "#\($0.rank) · \($0.span.label)") },
                       from: spotifyLabel)
    }

    // MARK: Music library

    private static func music(track: Snapshot, facts: LibraryFacts?, library: MusicLibrary, into out: inout ListeningReport) {
        var song: [StatTile] = []
        if let facts {
            if let plays = facts.plays {
                song.append(StatTile(value: "\(plays)", caption: plays == 1 ? "play of this song" : "plays of this song", symbol: "play.circle"))
            }
            if let last = facts.lastPlayed {
                song.append(StatTile(value: relative(last), caption: "last played", symbol: "calendar"))
            }
            if facts.favorite {
                song.append(StatTile(value: "Favorite", caption: "marked in Music", symbol: "star.fill"))
            }
            if let added = facts.added {
                song.append(StatTile(value: monthYear(added), caption: "added to library", symbol: "plus.circle"))
            }
            if let skips = facts.skips, skips > 0 {
                song.append(StatTile(value: "\(skips)", caption: skips == 1 ? "skip" : "skips", symbol: "forward.end"))
            }
        }
        out.song.add(song, from: musicLabel)

        // This artist
        let names = [track.primaryArtist, track.albumArtist].filter { !$0.isEmpty }
        var art: [StatTile] = []
        if let name = names.first(where: { library.total(for: $0) != nil }), let total = library.total(for: name) {
            if total.plays > 0 {
                art.append(StatTile(value: "\(total.plays)", caption: "plays of \(name)", symbol: "person.fill"))
            }
            if let rank = library.rank(for: name) {
                art.append(StatTile(value: "#\(rank)", caption: "most played artist", symbol: "list.number"))
            }
            let songs = library.songs(byArtist: name)
            let played = songs.filter { $0.plays > 0 }
            art.append(StatTile(value: songs.isEmpty ? "\(total.songs)" : "\(played.count)/\(songs.count)",
                                caption: songs.isEmpty ? (total.songs == 1 ? "song in library" : "songs in library")
                                                       : "songs played",
                                symbol: "music.note.list"))
            if let last = songs.compactMap(\.lastPlayed).max() {
                art.append(StatTile(value: relative(last), caption: "last played", symbol: "calendar"))
            }
            let albums = Set(songs.map { TitleTidy.key($0.album) }.filter { !$0.isEmpty }).count
            if albums > 1 {
                art.append(StatTile(value: "\(albums)", caption: "albums in library", symbol: "square.stack"))
            }
            out.artist.add(art, from: musicLabel)
            out.artist.list("Your most played by \(name)",
                            played.sorted { $0.plays > $1.plays }.map { HistoryLine(title: $0.title, detail: plays($0.plays)) },
                            from: musicLabel)
        }

        // This album
        let albumSongs = library.songs(onAlbum: track.album, artists: names)
        if !albumSongs.isEmpty {
            var alb: [StatTile] = []
            let total = albumSongs.reduce(0) { $0 + $1.plays }
            let played = albumSongs.filter { $0.plays > 0 }
            if total > 0 {
                alb.append(StatTile(value: "\(total)", caption: "plays of this album", symbol: "opticaldisc"))
            }
            alb.append(StatTile(value: "\(played.count)/\(albumSongs.count)", caption: "songs played", symbol: "music.note.list"))
            if let last = albumSongs.compactMap(\.lastPlayed).max() {
                alb.append(StatTile(value: relative(last), caption: "last played", symbol: "calendar"))
            }
            out.album.add(alb, from: musicLabel)
            out.album.list("Your most played on this album",
                           played.sorted { $0.plays > $1.plays }.map { HistoryLine(title: $0.title, detail: plays($0.plays)) },
                           from: musicLabel)
        }
    }

    // MARK: This Mac

    private static func mac(track: Snapshot, artist: String, artists: [String], log: ListeningLog, into out: inout ListeningReport) {
        let label = macLabel(log)
        var song: [StatTile] = []
        if let s = log.song(artist: artist, title: track.title) {
            if s.plays > 0 {
                song.append(StatTile(value: "\(s.plays)", caption: s.plays == 1 ? "play here" : "plays here", symbol: "play.circle"))
            }
            if s.seconds >= 60 {
                song.append(StatTile(value: duration(s.seconds), caption: "listened here", symbol: "clock"))
            }
        }
        out.song.add(song, from: label)

        var art: [StatTile] = []
        if let a = log.artist(artist), a.seconds >= 60 {
            art.append(StatTile(value: duration(a.seconds), caption: "with \(artist) here", symbol: "clock"))
            if a.plays > 0 {
                art.append(StatTile(value: "\(a.plays)", caption: a.plays == 1 ? "play here" : "plays here", symbol: "play.circle"))
            }
            art.append(StatTile(value: monthDay(a.first), caption: "first heard here", symbol: "sparkles"))
        }
        if let rank = log.artistRank(artist), log.book.artists.count >= 3 {
            art.append(StatTile(value: "#\(rank)", caption: "of \(log.book.artists.count) artists here", symbol: "list.number"))
        }
        out.artist.add(art, from: label)
        let artistSongs = log.songs(byArtist: artist).filter { $0.plays > 0 }
            .sorted { $0.plays != $1.plays ? $0.plays > $1.plays : $0.seconds > $1.seconds }
        out.artist.list("Your most played by \(artist)",
                        artistSongs.map { HistoryLine(title: $0.title, detail: plays($0.plays)) }, from: label)

        let albumSongs = log.songs(onAlbum: track.album, artists: artists)
        if !albumSongs.isEmpty {
            var alb: [StatTile] = []
            let total = albumSongs.reduce(0) { $0 + $1.plays }
            let seconds = albumSongs.reduce(0) { $0 + $1.seconds }
            if total > 0 {
                alb.append(StatTile(value: "\(total)", caption: total == 1 ? "play here" : "plays here", symbol: "opticaldisc"))
            }
            if seconds >= 60 {
                alb.append(StatTile(value: duration(seconds), caption: "listened here", symbol: "clock"))
            }
            alb.append(StatTile(value: "\(albumSongs.count)", caption: albumSongs.count == 1 ? "song heard here" : "songs heard here",
                                symbol: "music.note.list"))
            out.album.add(alb, from: label)
            out.album.list("Your most played on this album",
                           albumSongs.filter { $0.plays > 0 }.sorted { $0.plays > $1.plays }
                               .map { HistoryLine(title: $0.title, detail: plays($0.plays)) }, from: label)
        }
    }

    // MARK: Formatting

    static func duration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(1, minutes)) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) m"
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func plays(_ n: Int) -> String { n == 1 ? "1 play" : "\(n) plays" }

    static func monthDay(_ date: Date) -> String {
        Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.month(.abbreviated).year())
    }

    /// "5 min ago", "3 h ago", then the same wording as `relative`.
    static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 6 * 3600 { return "\(Int(seconds / 3600)) h ago" }
        return relative(date)
    }

    static func monthYear(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).year())
    }

    static func relative(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<7: return "\(days) days ago"
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
