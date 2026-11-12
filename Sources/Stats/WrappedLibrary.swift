// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation
import Observation

/// A private, explicitly imported snapshot of saved Spotify Wrapped playlists.
/// Playlist positions are not play counts or annual listening-statistic ranks.
@MainActor @Observable
final class WrappedLibrary {
    struct Item: Codable, Equatable, Sendable {
        let position: Int
        let trackID: String
        let title: String
        let artist: String
        let album: String
    }
    struct Playlist: Codable, Equatable, Identifiable, Sendable {
        let year: Int
        let id: String
        let name: String
        let url: String
        var items: [Item]
    }
    struct Document: Codable, Sendable {
        var format = "minideck-wrapped-playlists"
        var version = 1
        let capturedAt: String
        var playlists: [Playlist]
    }
    struct HistoricalSong: Equatable, Sendable {
        let trackID: String
        let title: String
        let artist: String
        let album: String
        var years: [Int]
    }
    enum ImportError: LocalizedError {
        case invalid, tooLarge, damagedSave
        var errorDescription: String? {
            switch self {
            case .invalid:
                "Choose a valid Mini Deck historical-song snapshot. Raw account summaries, streaming-history exports and screenshots use different formats."
            case .tooLarge: "The historical-song snapshot exceeds the 4 MB limit."
            case .damagedSave:
                "The existing historical-song data is unreadable and was not overwritten. Remove its saved copy in Mini Deck before importing again."
            }
        }
    }

    private(set) var playlists: [Playlist] = []
    private(set) var songs: [HistoricalSong] = []
    private(set) var loading = false
    private(set) var busy = false
    private(set) var message = ""
    private(set) var loadError = false
    @ObservationIgnored private let storageURL: URL?
    nonisolated static let byteLimit = 4 * 1024 * 1024
    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Mini Deck/wrapped-playlists.json")
    }

    init(storageURL: URL? = WrappedLibrary.defaultURL) {
        self.storageURL = storageURL
        guard let storageURL else { return }
        loading = true
        Task {
            let result = await Task.detached { () -> (Document?, Bool) in
                guard FileManager.default.fileExists(atPath: storageURL.path) else { return (nil, false) }
                do {
                    let document = try Self.read(storageURL)
                    try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                          ofItemAtPath: storageURL.deletingLastPathComponent().path)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
                    return (document, false)
                } catch { return (nil, true) }
            }.value
            playlists = result.0?.playlists ?? []
            songs = Self.history(from: playlists)
            loadError = result.1
            if loadError { message = ImportError.damagedSave.localizedDescription }
            loading = false
        }
    }

    func playlist(year: Int) -> Playlist? {
        playlists.first { $0.year == year } ?? playlists.first
    }

    func yearsContaining(_ spotifyURI: String) -> [Int] {
        let prefix = "spotify:track:"
        guard spotifyURI.hasPrefix(prefix) else { return [] }
        let id = String(spotifyURI.dropFirst(prefix.count))
        return playlists.filter { $0.items.contains { $0.trackID == id } }.map(\.year)
    }

    /// Preserve year-level evidence, never manufacture play events or rankings.
    nonisolated static func history(from playlists: [Playlist]) -> [HistoricalSong] {
        var indexed: [String: HistoricalSong] = [:]
        for playlist in playlists.sorted(by: { $0.year > $1.year }) {
            for item in playlist.items {
                if var song = indexed[item.trackID] {
                    song.years = Array(Set(song.years + [playlist.year])).sorted(by: >)
                    indexed[item.trackID] = song
                } else {
                    indexed[item.trackID] = HistoricalSong(trackID: item.trackID, title: item.title,
                        artist: item.artist, album: item.album, years: [playlist.year])
                }
            }
        }
        return indexed.values.sorted {
            if $0.title != $1.title { return $0.title < $1.title }
            return $0.trackID < $1.trackID
        }
    }

    func importFile(_ url: URL) async throws {
        guard !loading, !busy else { return }
        guard !loadError else { throw ImportError.damagedSave }
        busy = true
        defer { busy = false }
        let existing = playlists
        let destination = storageURL
        let document = try await Task.detached {
            var incoming = try Self.read(url)
            var byYear = Dictionary(uniqueKeysWithValues: existing.map { ($0.year, $0) })
            for item in incoming.playlists { byYear[item.year] = item }
            incoming.playlists = byYear.values.sorted { $0.year > $1.year }
            let data = try JSONEncoder().encode(incoming)
            _ = try Self.parse(data)
            if let destination {
                let fm = FileManager.default
                let folder = destination.deletingLastPathComponent()
                try fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])
                try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
                try data.write(to: destination, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            return incoming
        }.value
        playlists = document.playlists
        songs = Self.history(from: playlists)
        message = "Historical song data imported locally. No play counts or listened minutes were inferred."
    }

    func clear() throws {
        guard !loading, !busy else { return }
        if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            try FileManager.default.removeItem(at: storageURL)
        }
        playlists = []
        songs = []
        loadError = false
        message = "Historical song data removed. Spotify and original files are unchanged."
    }

    nonisolated static func read(_ url: URL) throws -> Document {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try parse(handle.read(upToCount: byteLimit + 1) ?? Data())
    }

    nonisolated static func parse(_ data: Data) throws -> Document {
        guard data.count <= byteLimit else { throw ImportError.tooLarge }
        guard var doc = try? JSONDecoder().decode(Document.self, from: data),
              doc.format == "minideck-wrapped-playlists", doc.version == 1,
              !doc.playlists.isEmpty, doc.playlists.count <= 50 else { throw ImportError.invalid }
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard date.date(from: doc.capturedAt) != nil || ISO8601DateFormatter().date(from: doc.capturedAt) != nil
        else { throw ImportError.invalid }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: Date())
        func validID(_ value: String) -> Bool {
            value.count == 22 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        var years = Set<Int>()
        var ids = Set<String>()
        for index in doc.playlists.indices {
            let p = doc.playlists[index]
            guard (2008...currentYear).contains(p.year), years.insert(p.year).inserted,
                  validID(p.id), ids.insert(p.id).inserted, p.url == "https://open.spotify.com/playlist/\(p.id)",
                  p.name.contains(String(p.year)), p.name.utf8.count <= 500, !p.items.isEmpty, p.items.count <= 500
            else { throw ImportError.invalid }
            var positions = Set<Int>()
            for item in p.items {
                guard (1...10_000).contains(item.position), positions.insert(item.position).inserted,
                      validID(item.trackID), !item.title.isEmpty,
                      [item.title, item.artist, item.album].allSatisfy({ $0.utf8.count <= 1_000 })
                else { throw ImportError.invalid }
            }
            doc.playlists[index].items.sort { $0.position < $1.position }
        }
        doc.playlists.sort { $0.year > $1.year }
        return doc
    }
}
