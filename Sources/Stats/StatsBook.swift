// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

struct StatTile: Hashable, Identifiable {
    let value: String
    let caption: String
    var symbol: String?
    var id: String { caption + value }
}

struct StatGroup: Identifiable {
    let title: String
    let tiles: [StatTile]
    var id: String { title }
}

/// What the "Your listening" section can show right now.
struct ListeningReport {
    enum Prompt: Equatable { case none, connectSpotify, reconnectSpotify, waiting, loading, problem(String) }
    var groups: [StatGroup] = []
    var prompt: Prompt = .none
}

/// Turns account, library and on-device numbers into short tiles for the current track.
@MainActor
enum StatsBook {
    static func report(track: Snapshot, facts: LibraryFacts?, account: SpotifyAccount,
                       library: MusicLibrary, log: ListeningLog, counting: Bool) -> ListeningReport {
        var out = ListeningReport()
        let artist = track.primaryArtist

        switch track.source {
        case .spotify:
            switch account.status {
            case .on:
                let tiles = spotifyTiles(track: track, account: account)
                if !tiles.isEmpty {
                    out.groups.append(StatGroup(title: "From your Spotify account", tiles: tiles))
                } else if account.updated == nil {
                    out.prompt = .loading
                } else {
                    out.groups.append(StatGroup(title: "From your Spotify account", tiles: [
                        StatTile(value: "New", caption: "not in your top 50 or last 50 plays", symbol: "sparkles"),
                    ]))
                }
            case .off: out.prompt = .connectSpotify
            case .expired: out.prompt = .reconnectSpotify
            case .waiting: out.prompt = .waiting
            case .failed(let why): out.prompt = .problem(why)
            }
        case .music:
            let tiles = musicTiles(track: track, facts: facts, library: library)
            if !tiles.isEmpty {
                out.groups.append(StatGroup(title: "From your Music library", tiles: tiles))
            } else if library.scanning {
                out.prompt = .loading
            }
        }

        if counting {
            var mine: [StatTile] = []
            if let song = log.song(artist: artist, title: track.title), song.plays > 0 {
                mine.append(StatTile(value: "\(song.plays)", caption: song.plays == 1 ? "play of this song" : "plays of this song",
                                     symbol: "play.circle"))
            }
            if let a = log.artist(artist), a.seconds >= 60 {
                mine.append(StatTile(value: duration(a.seconds), caption: "with \(artist)", symbol: "clock"))
            }
            if let rank = log.artistRank(artist), log.book.artists.count >= 3 {
                mine.append(StatTile(value: "#\(rank)", caption: "of \(log.book.artists.count) artists here", symbol: "list.number"))
            }
            if !mine.isEmpty {
                out.groups.append(StatGroup(title: "Counted on this Mac since \(shortDate(log.book.since))", tiles: mine))
            }
        }
        return out
    }

    private static func spotifyTiles(track: Snapshot, account: SpotifyAccount) -> [StatTile] {
        var tiles: [StatTile] = []
        let artistKeys = Set([track.primaryArtist, track.albumArtist].map(TitleTidy.key).filter { !$0.isEmpty })
        let trackID = track.trackID.split(separator: ":").last.map(String.init) ?? ""

        func best(_ pick: (SpotifyAccount.Top) -> Int?) -> (rank: Int, span: SpotifyAccount.Span)? {
            var found: (Int, SpotifyAccount.Span)?
            for span in SpotifyAccount.Span.allCases {
                if let r = account.top[span].flatMap(pick), r < (found?.0 ?? .max) { found = (r, span) }
            }
            return found
        }

        if let a = best({ top in artistKeys.compactMap { top.artists[$0] }.min() }) {
            tiles.append(StatTile(value: "#\(a.rank)", caption: "top artist · \(a.span.label)", symbol: "person.fill"))
        }
        if !trackID.isEmpty, let t = best({ $0.tracks[trackID] }) {
            tiles.append(StatTile(value: "#\(t.rank)", caption: "top song · \(t.span.label)", symbol: "music.note"))
        }
        if !account.recent.isEmpty {
            let songPlays = account.recent.filter { $0.trackID == trackID }.count
            let artistPlays = account.recent.filter { !artistKeys.isDisjoint(with: $0.artistKeys) }.count
            if songPlays > 0 {
                tiles.append(StatTile(value: "\(songPlays)×", caption: "in your last \(account.recent.count) plays", symbol: "arrow.counterclockwise"))
            }
            if artistPlays > songPlays {
                tiles.append(StatTile(value: "\(artistPlays)", caption: "recent plays of this artist", symbol: "waveform"))
            }
        }
        return tiles
    }

    private static func musicTiles(track: Snapshot, facts: LibraryFacts?, library: MusicLibrary) -> [StatTile] {
        var tiles: [StatTile] = []
        if let facts {
            if let plays = facts.plays {
                tiles.append(StatTile(value: "\(plays)", caption: plays == 1 ? "play of this song" : "plays of this song", symbol: "play.circle"))
            }
            if let last = facts.lastPlayed {
                tiles.append(StatTile(value: relative(last), caption: "last played", symbol: "calendar"))
            }
            if facts.favorite {
                tiles.append(StatTile(value: "Favorite", caption: "marked in Music", symbol: "star.fill"))
            } else if let added = facts.added {
                tiles.append(StatTile(value: monthYear(added), caption: "added to library", symbol: "plus.circle"))
            }
        }
        let names = [track.primaryArtist, track.albumArtist].filter { !$0.isEmpty }
        if let name = names.first(where: { library.total(for: $0) != nil }), let total = library.total(for: name) {
            if total.plays > 0 {
                tiles.append(StatTile(value: "\(total.plays)", caption: "plays of \(name)", symbol: "person.fill"))
            }
            if let rank = library.rank(for: name) {
                tiles.append(StatTile(value: "#\(rank)", caption: "most played artist", symbol: "list.number"))
            }
            tiles.append(StatTile(value: "\(total.songs)", caption: total.songs == 1 ? "song in library" : "songs in library",
                                  symbol: "music.note.list"))
        }
        return Array(tiles.prefix(6))
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
