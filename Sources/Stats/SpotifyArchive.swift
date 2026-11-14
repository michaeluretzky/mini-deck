// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Sanitized, account-wide Spotify export. Never retains IP, location, device,
/// username, private-session flags, or raw export files.
@MainActor @Observable
final class SpotifyArchive {
    struct Event: Codable, Hashable, Sendable {
        let ended: Date
        let milliseconds: Int64
        let title: String
        let artist: String
        let album: String
        let uri: String
        var durationKnown: Bool? = nil
        var songKey: String { uri.isEmpty ? [artist, title, album].map(SpotifyArchive.nameKey).joined(separator: "\u{1F}") : uri }
        var albumKey: String { SpotifyArchive.nameKey(artist) + "\u{1F}" + SpotifyArchive.nameKey(album) }
        var identity: String {
            let track = uri.isEmpty ? songKey : uri
            return "\(ended.timeIntervalSince1970)|\(track)|\(milliseconds)"
        }
    }

    struct Total: Sendable {
        var title: String
        var artist: String
        var album: String
        var plays = 0
        var milliseconds: Int64 = 0
        var first: Date
        var last: Date
        var seconds: Double { Double(milliseconds) / 1000 }
        mutating func add(_ event: Event) {
            // Every supplied music event is an overall play, including short listens.
            plays += 1
            milliseconds += event.milliseconds
            first = min(first, event.ended)
            last = max(last, event.ended)
        }
    }

    struct Snapshot: Sendable {
        var events: [Event] = []
        var songs: [String: Total] = [:]
        var artists: [String: Total] = [:]
        var albums: [String: Total] = [:]
        var songsByArtist: [String: [Total]] = [:]
        var artistRanks: [String: Int] = [:]
        var topSongs: [Total] = []
        var topArtists: [Total] = []
        var topAlbums: [Total] = []
        var first: Date? { events.first?.ended }
        var last: Date? { events.last?.ended }
        var isEmpty: Bool { events.isEmpty }
    }

    struct Parsed: Sendable {
        let events: [Event]
        let skipped: Int
    }

    enum ImportError: LocalizedError {
        case noFiles, tooLarge, wrongFormat, noSongs, unavailable, busy, savedUnreadable
        var errorDescription: String? {
            switch self {
            case .noFiles: "Choose the extracted Streaming_History_Audio*.json or endsong*.json files, or their folder."
            case .tooLarge: "The selected export is too large. Import fewer JSON files at a time (64 MB per file, 256 MB per batch)."
            case .wrongFormat: "This is not a supported Extended Streaming History JSON file. Request Extended streaming history, not Account data."
            case .noSongs: "No valid music records were found. Podcast/video-only files and invalid records are not added."
            case .unavailable: "The history file could not be read."
            case .busy: "History is already loading or importing. Wait for it to finish and try again."
            case .savedUnreadable: "The saved Spotify import could not be read and has not been overwritten. Remove the saved import from Listening Stats, then re-import your original export."
            }
        }
    }

    private struct Raw: Decodable {
        let ts: String?
        let ms_played: Int64?
        let master_metadata_track_name: String?
        let master_metadata_album_artist_name: String?
        let master_metadata_album_album_name: String?
        let spotify_track_uri: String?
    }

    private(set) var snapshot = Snapshot()
    private(set) var busy = false
    private(set) var loading = false
    private(set) var message = ""
    private(set) var watchedFolderName: String?
    private(set) var loadError: String?
    private(set) var syncError: String?
    private(set) var journal = SpotifyJournal()
    @ObservationIgnored private var imported = Snapshot()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastRefresh = Date.distantPast
    @ObservationIgnored private var revision = 0
    @ObservationIgnored private let storageURL: URL?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    private static let watchKey = "minideck.spotifyExportFolder"

    init(storageURL: URL? = SpotifyArchive.defaultURL) {
        self.storageURL = storageURL
        if let storageURL {
            loading = true
            Task {
                let loaded = await Task.detached(priority: .utility) {
                    guard FileManager.default.fileExists(atPath: storageURL.path) else { return (Snapshot(), false) }
                    guard let data = try? Data(contentsOf: storageURL),
                          let events = try? JSONDecoder().decode([Event].self, from: data) else { return (Snapshot(), true) }
                    return (Self.index(events), false)
                }.value
                imported = loaded.0
                if let url = journalURL, FileManager.default.fileExists(atPath: url.path) {
                    if let data = try? Data(contentsOf: url),
                       let saved = try? JSONDecoder().decode(SpotifyJournal.self, from: data) {
                        journal = saved
                    } else {
                        syncError = "Saved ongoing history could not be read; it has not been overwritten."
                    }
                }
                let base = imported, live = journal
                snapshot = await Task.detached(priority: .utility) {
                    Self.combined(base, additions: live.additions(after: base.last))
                }.value
                if loaded.1 {
                    loadError = ImportError.savedUnreadable.localizedDescription
                    message = loadError ?? ""
                }
                loading = false
                if !loaded.1, storageURL == Self.defaultURL { restoreWatch() }
            }
        }
    }

    var hasHistory: Bool { !snapshot.isEmpty }
    var exportCutoff: Date? { imported.last }
    var syncNote: String {
        if let syncError { return syncError }
        let sync = journal.lastSync.map { "Account checked \(StatsBook.ago($0))." }
            ?? "Connect Spotify for recent playback from other devices."
        return "Overall plays include short listens. Export + saved account records + observed Mac playback. \(sync) Listening time includes only measured duration; API-only plays have unknown duration. Gaps while Mini Deck is closed or offline may remain."
    }
    private var journalURL: URL? {
        storageURL?.deletingLastPathComponent().appendingPathComponent("spotify-live.json")
    }

    func observe(_ track: SwiftSnapshot, now: Date = Date()) {
        guard !loading, syncError == nil else { return }
        let newPlay = journal.observe(track, now: now)
        if newPlay || now.timeIntervalSince(lastRefresh) >= 20 { scheduleRefresh() }
    }

    func ingestRecent(_ plays: [SpotifyAccount.Play], complete: Bool = true) {
        guard !loading, syncError == nil else { return }
        let previous = journal.lastSync
        journal.ingest(plays, now: Date())
        if !complete { journal.lastSync = previous }
        scheduleRefresh()
    }

    func flush() {
        guard !loading, syncError == nil, let url = journalURL else { return }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(journal).write(to: url, options: [.atomic])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { syncError = "Ongoing history could not be saved. Check available disk space and folder permissions." }
    }

    func clearOngoing() throws {
        guard !loading else { throw ImportError.busy }
        if let url = journalURL, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        journal = SpotifyJournal()
        syncError = nil
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        revision += 1
        guard refreshTask == nil else { return }
        lastRefresh = Date()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            let version = self.revision, base = self.imported, live = self.journal
            let result = await Task.detached(priority: .utility) {
                Self.combined(base, additions: live.additions(after: base.last))
            }.value
            self.refreshTask = nil
            if self.revision == version {
                self.snapshot = result
                self.lastRefresh = Date()
                self.flush()
            } else { self.scheduleRefresh() }
        }
    }
    var coverage: String {
        guard let first = snapshot.first, let last = snapshot.last else { return "No Spotify export imported" }
        return "\(StatsBook.shortDate(first)) – \(StatsBook.shortDate(last))"
    }

    func importFiles(_ urls: [URL]) async throws {
        guard !busy, !loading else { throw ImportError.busy }
        guard loadError == nil else { throw ImportError.savedUnreadable }
        busy = true
        defer { busy = false }
        let existing = imported.events
        let destination = storageURL
        let result = try await Task.detached(priority: .userInitiated) {
            let files = try Self.files(in: urls)
            var imported: [Event] = []
            var skipped = 0
            var size = 0
            for url in files {
                let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                size += fileSize
                guard fileSize <= 64_000_000, size <= 256_000_000 else { throw ImportError.tooLarge }
                let parsed = try Self.parse(Data(contentsOf: url))
                imported += parsed.events
                skipped += parsed.skipped
            }
            guard !imported.isEmpty else { throw ImportError.noSongs }
            let merged = Self.index(existing + imported)
            if let destination {
                let folder = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
                let data = try JSONEncoder().encode(merged.events)
                try data.write(to: destination, options: [.atomic])
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            return (merged, skipped)
        }.value
        let added = result.0.events.count - existing.count
        imported = result.0
        revision += 1
        let base = imported, live = journal
        snapshot = await Task.detached(priority: .utility) {
            Self.combined(base, additions: live.additions(after: base.last))
        }.value
        scheduleRefresh()
        message = "Added \(added) music records; \(result.1) non-music or invalid records skipped. Re-imports are deduplicated."
    }

    func clear() throws {
        guard !busy, !loading else { throw ImportError.busy }
        if let storageURL, FileManager.default.fileExists(atPath: storageURL.path) {
            try FileManager.default.removeItem(at: storageURL)
        }
        imported = Snapshot()
        snapshot = Self.combined(imported, additions: journal.additions(after: nil))
        revision += 1
        message = ""
        loadError = nil
    }

    /// The user explicitly selects one folder. Nothing scans Downloads or
    /// imports personal files without that selection.
    func watchFolder(_ url: URL) throws {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: Self.watchKey)
        startWatch(url)
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedFolderName = nil
        UserDefaults.standard.removeObject(forKey: Self.watchKey)
    }

    private func restoreWatch() {
        guard let data = UserDefaults.standard.data(forKey: Self.watchKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                                relativeTo: nil, bookmarkDataIsStale: &stale), !stale else {
            message = "Choose the auto-import folder again to restore access."
            return
        }
        startWatch(url)
    }

    private func startWatch(_ url: URL) {
        watcher?.cancel()
        watchedFolderName = url.lastPathComponent
        watcher = Task { [weak self] in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            var previous = ""
            var attempted = ""
            while !Task.isCancelled {
                guard let self else { return }
                if !self.busy && !self.loading {
                    let fingerprint = await Task.detached(priority: .utility) {
                        guard let files = try? Self.files(in: [url]) else { return "" }
                        return files.map { file in
                            let info = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                            return "\(file.path)|\(info?.fileSize ?? 0)|\(info?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
                        }.joined(separator: "\n")
                    }.value
                    guard !Task.isCancelled else { return }
                    // Require a stable scan before importing a file still being downloaded.
                    if !fingerprint.isEmpty, fingerprint == previous, fingerprint != attempted {
                        attempted = fingerprint
                        do { try await self.importFiles([url]) }
                        catch { self.message = "Auto-import: \(error.localizedDescription)" }
                    }
                    previous = fingerprint
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    nonisolated static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Mini Deck/spotify-import.json")
    }

    /// Keep edition/live suffixes: different recordings must not silently merge.
    nonisolated static func nameKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated static func parse(_ data: Data) throws -> Parsed {
        guard data.count <= 64_000_000 else { throw ImportError.tooLarge }
        guard let rows = try? JSONDecoder().decode([Raw].self, from: data),
              rows.isEmpty || rows.contains(where: { $0.ts != nil && $0.ms_played != nil }) else {
            throw ImportError.wrongFormat
        }
        let formatter = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var events: [Event] = []
        for row in rows {
            guard let ts = row.ts, let ended = formatter.date(from: ts) ?? fractional.date(from: ts),
                  let ms = row.ms_played, (0...86_400_000).contains(ms),
                  let title = row.master_metadata_track_name, !title.isEmpty,
                  let artist = row.master_metadata_album_artist_name, !artist.isEmpty else { continue }
            events.append(Event(ended: ended, milliseconds: ms, title: title, artist: artist,
                                album: row.master_metadata_album_album_name ?? "", uri: row.spotify_track_uri ?? ""))
        }
        return Parsed(events: events, skipped: rows.count - events.count)
    }

    nonisolated static func index(_ events: [Event]) -> Snapshot {
        var seen = Set<String>()
        var snapshot = Snapshot()
        snapshot.events = events.filter { seen.insert($0.identity).inserted }.sorted { $0.ended < $1.ended }
        for event in snapshot.events {
            let seed = Total(title: event.title, artist: event.artist, album: event.album, first: event.ended, last: event.ended)
            snapshot.songs[event.songKey, default: seed].add(event)
            snapshot.artists[TitleTidy.key(event.artist), default: seed].add(event)
            if !event.album.isEmpty { snapshot.albums[event.albumKey, default: seed].add(event) }
        }
        finishIndexes(&snapshot)
        return snapshot
    }

    /// Reuse the large export index; only add the smaller forward journal.
    nonisolated static func combined(_ base: Snapshot, additions: [Event]) -> Snapshot {
        var snapshot = base
        snapshot.events += additions
        for event in additions {
            let seed = Total(title: event.title, artist: event.artist, album: event.album, first: event.ended, last: event.ended)
            snapshot.songs[event.songKey, default: seed].add(event)
            snapshot.artists[TitleTidy.key(event.artist), default: seed].add(event)
            if !event.album.isEmpty { snapshot.albums[event.albumKey, default: seed].add(event) }
        }
        finishIndexes(&snapshot)
        return snapshot
    }

    nonisolated private static func finishIndexes(_ snapshot: inout Snapshot) {
        snapshot.songsByArtist = [:]
        snapshot.artistRanks = [:]
        // Build lookup/ranking indexes on the worker, never on hover.
        for song in snapshot.songs.values {
            snapshot.songsByArtist[TitleTidy.key(song.artist), default: []].append(song)
        }
        let rankedArtists = snapshot.artists.sorted {
            $0.value.plays != $1.value.plays ? $0.value.plays > $1.value.plays : $0.key < $1.key
        }
        for (offset, item) in rankedArtists.enumerated() { snapshot.artistRanks[item.key] = offset + 1 }
        func ranked(_ totals: [Total]) -> [Total] {
            Array(totals.sorted {
                if $0.plays != $1.plays { return $0.plays > $1.plays }
                if $0.milliseconds != $1.milliseconds { return $0.milliseconds > $1.milliseconds }
                return $0.title < $1.title
            }.prefix(100))
        }
        snapshot.topSongs = ranked(Array(snapshot.songs.values))
        snapshot.topArtists = ranked(Array(snapshot.artists.values))
        snapshot.topAlbums = ranked(Array(snapshot.albums.values))
    }

    nonisolated private static func files(in selections: [URL]) throws -> [URL] {
        var found = Set<URL>()
        for url in selections {
            let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard info.isSymbolicLink != true else { continue }
            if info.isDirectory == true {
                guard let walker = FileManager.default.enumerator(at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                var inspected = 0
                for case let file as URL in walker {
                    inspected += 1
                    guard inspected <= 10_000 else { throw ImportError.tooLarge }
                    let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values.isSymbolicLink == true { walker.skipDescendants(); continue }
                    let name = file.lastPathComponent.lowercased()
                    if values.isRegularFile == true, file.pathExtension.lowercased() == "json",
                       name.hasPrefix("streaming_history_audio") || name.hasPrefix("endsong") {
                        found.insert(file)
                    }
                }
            } else if info.isRegularFile == true, url.pathExtension.lowercased() == "json" {
                found.insert(url)
            }
        }
        guard !found.isEmpty else { throw ImportError.noFiles }
        guard found.count <= 512 else { throw ImportError.tooLarge }
        return found.sorted { $0.path < $1.path }
    }
}
