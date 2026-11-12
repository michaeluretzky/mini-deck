// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// One song in the available history, not one listening event.
@MainActor
enum AccountHistory {
    struct Song: Equatable {
        let id: String
        var title: String
        var artist: String
        var album: String
        var years: [Int] = []
        var recent: Date?
        var imported: Date?
        var latest: Date? { [recent, imported].compactMap { $0 }.max() }
    }

    static func songs(recent: [SpotifyAccount.Play], historical: [WrappedLibrary.HistoricalSong],
                      imported: [String: SpotifyArchive.Total] = [:]) -> [Song] {
        var indexed: [String: Song] = [:]
        for item in historical {
            let id = "spotify:track:" + item.trackID
            indexed[id] = Song(id: id, title: item.title, artist: item.artist,
                               album: item.album, years: item.years)
        }
        for (id, item) in imported {
            var song = indexed[id] ?? Song(id: id, title: item.title, artist: item.artist, album: item.album)
            song.imported = item.last
            indexed[id] = song
        }
        for item in recent where !item.trackID.isEmpty {
            let id = item.trackID.hasPrefix("spotify:track:") ? item.trackID : "spotify:track:" + item.trackID
            var song = indexed[id] ?? Song(id: id, title: item.title, artist: item.artist, album: item.album)
            song.recent = max(song.recent ?? item.at, item.at)
            indexed[id] = song
        }
        return indexed.values.sorted {
            switch ($0.latest, $1.latest) {
            case let (a?, b?) where a != b: return a > b
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            let a = $0.years.max() ?? 0, b = $1.years.max() ?? 0
            if a != b { return a > b }
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.id < $1.id
        }
    }
}
