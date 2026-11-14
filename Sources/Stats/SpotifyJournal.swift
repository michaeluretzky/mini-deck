// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Private forward history. API timestamps do not imply a listened duration.
struct SpotifyJournal: Codable, Sendable {
    struct Record: Codable, Sendable {
        var id: String
        var kind: String
        var started: Date
        var ended: Date
        var title: String
        var artist: String
        var album: String
        var uri: String
        var milliseconds: Int64
        var position: Double
        var playing: Bool

        var event: SpotifyArchive.Event {
            .init(ended: ended, milliseconds: milliseconds, title: title,
                  artist: artist, album: album, uri: uri, durationKnown: kind != "api")
        }
    }

    var since = Date()
    var records: [Record] = []
    var activeID: String?
    var lastSync: Date?

    /// One observed start is one play, including brief listens. Pauses are not new plays.
    mutating func observe(_ snap: Snapshot, now: Date) -> Bool {
        let active = activeID.flatMap { id in records.lastIndex { $0.id == id } }
        guard snap.source == .spotify, snap.state == .playing, !snap.title.isEmpty else {
            if let active { records[active].playing = false }
            return false
        }
        if let active {
            var record = records[active]
            let same = !snap.trackID.isEmpty && !record.uri.isEmpty
                ? snap.trackID == record.uri
                : snap.title == record.title && snap.primaryArtist == record.artist
            let elapsed = now.timeIntervalSince(record.ended)
            let restarted = snap.position < 3 && record.position > snap.position + 3
            // Do not turn a long unobserved gap into continuous listening.
            let continuous = elapsed >= 0 && elapsed <= 15
            if same && !restarted && (continuous || !record.playing) {
                let delta = record.playing && elapsed <= 5 ? max(0, elapsed) : 0
                record.milliseconds += Int64(delta * 1000)
                record.ended = now
                record.position = snap.position
                record.playing = true
                records[active] = record
                return false
            }
        }
        let id = UUID().uuidString
        records.append(Record(id: id, kind: "mac", started: now, ended: now,
                              title: snap.title, artist: snap.primaryArtist, album: snap.album,
                              uri: snap.trackID, milliseconds: 0, position: snap.position, playing: true))
        activeID = id
        return true
    }

    mutating func ingest(_ plays: [SpotifyAccount.Play], now: Date) {
        var known = Set(records.filter { $0.kind == "api" }.map(\.id))
        for play in plays where !play.title.isEmpty {
            let id = "api|\(play.trackID)|\(play.at.timeIntervalSince1970)"
            guard known.insert(id).inserted else { continue }
            records.append(Record(id: id, kind: "api", started: play.at, ended: play.at,
                                  title: play.title, artist: play.artist, album: play.album,
                                  uri: "spotify:track:" + play.trackID, milliseconds: 0,
                                  position: 0, playing: false))
        }
        lastSync = now
    }

    /// Exports are authoritative through their cutoff. Match each API play to at
    /// most one observed session; repeated polls and local/API overlap count once.
    func additions(after cutoff: Date?) -> [SpotifyArchive.Event] {
        let eligible = records.filter { cutoff == nil || $0.started > cutoff! }
        let local = eligible.filter { $0.kind == "mac" }.sorted { $0.started < $1.started }
        let remote = eligible.filter { $0.kind == "api" }.sorted { $0.started < $1.started }
        var matched = Set<String>()
        var result = local.map(\.event)
        for play in remote {
            let match = local.filter { record in
                guard !matched.contains(record.id) else { return false }
                let same = !record.uri.isEmpty && !play.uri.isEmpty
                    ? record.uri == play.uri
                    : SpotifyArchive.nameKey(record.title) == SpotifyArchive.nameKey(play.title)
                        && SpotifyArchive.nameKey(record.artist) == SpotifyArchive.nameKey(play.artist)
                // Account timestamps can land at the start or end of a session.
                // Include the already-playing portion seen on first observation.
                let inferredStart = record.ended.addingTimeInterval(-max(0, record.position))
                return same && play.started >= min(record.started, inferredStart).addingTimeInterval(-5)
                    && play.started <= record.ended.addingTimeInterval(5)
            }.min { abs($0.ended.timeIntervalSince(play.started)) < abs($1.ended.timeIntervalSince(play.started)) }
            if let match { matched.insert(match.id) }
            else { result.append(play.event) }
        }
        return result.sorted { $0.ended < $1.ended }
    }
}
