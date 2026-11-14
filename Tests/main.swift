// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

// Checks the listening-history math without a music app or account.
// Built and run by the Build workflow: see .github/workflows/build.yml.

import Foundation
import Observation

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok {
        failures += 1
        print("FAIL line \(line): \(what)")
    }
}

await MainActor.run {
    // MARK: Catalog release dates

    expect(ReleaseDateText.display("2020-09-02") == "September 2, 2020", "full release date uses month day, year")
    expect(ReleaseDateText.display("2020-09-02T00:00:00Z") == "September 2, 2020", "Apple timestamp retains calendar day")
    expect(ReleaseDateText.display("2020-09-02T00:00:00+14:00") == "September 2, 2020", "release date does not shift with timezone")
    expect(ReleaseDateText.display("2020-09") == "September 2020", "month precision does not invent a day")
    expect(ReleaseDateText.display("2020") == "2020", "year precision does not invent a month")
    expect(ReleaseDateText.display("2000-02-29") == "February 29, 2000", "Gregorian leap century accepted")
    expect(ReleaseDateText.display("2024-02-29") == "February 29, 2024", "leap day accepted")
    expect(ReleaseDateText.display("1900-02-29") == nil, "non-leap century rejected")
    for invalid in ["2023-02-29", "2020-04-31", "2020-00-01", "2020-13-01", "2020-01-00",
                    "2020-1-02", "2020--02", "0000", "", "unknown", "2020-09-02-extra"] {
        expect(ReleaseDateText.display(invalid) == nil, "invalid release date rejected: \(invalid)")
    }
    expect(ReleaseDateText.display(nil) == nil, "absent release date remains absent")
    expect(ReleaseDateText.display(" 2020-09-02\n") == "September 2, 2020", "catalog whitespace trimmed")
    expect(AlbumNotes(releaseDate: "2020-09-02").hasFacts, "full album release date is a fact")
    expect(!AlbumNotes(releaseDate: "unknown").hasFacts, "invalid album release date is not a fact")
    expect(LinerNotesService.yearPrefix("1980-09-02") == "1980", "artist life-span year formatting stays unchanged")

    let day: Double = 86_400
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                   CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                   CGRect(x: 0, y: 900, width: 1600, height: 1200)]
    expect(WindowGeometry.screenIndex(for: CGRect(x: -800, y: 100, width: 488, height: 220), screens: screens) == 1,
           "negative-coordinate monitor selected by overlap")
    expect(WindowGeometry.screenIndex(for: CGRect(x: 100, y: 1200, width: 488, height: 220), screens: screens) == 2,
           "vertically stacked monitor selected")
    expect(WindowGeometry.screenIndex(for: CGRect(x: 1700, y: 100, width: 488, height: 220), screens: screens) == 0,
           "offscreen saved position selects nearest remaining monitor")
    let area = CGRect(x: -1930, y: 30, width: 1940, height: 1020)
    let right = CGRect(x: area.maxX - 488, y: area.maxY - 220, width: 488, height: 220)
    let small = WindowGeometry.resized(right, to: CGSize(width: 340, height: 120), in: area, growDown: false)
    expect(small.maxX == right.maxX && small.maxY == right.maxY, "compact resize preserves top-right alignment")
    let restored = WindowGeometry.resized(small, to: right.size, in: area, growDown: false)
    expect(restored == right, "normal resize restores the same aligned frame")
    let off = CGRect(x: -2200, y: -200, width: 488, height: 220)
    expect(WindowGeometry.origin(for: off, in: area, snap: 20, clamp: true, scale: 2) == area.origin,
           "card clamps to the current monitor's visible area")
    let huge = CGRect(x: -1000, y: 0, width: 488, height: 1300)
    expect(WindowGeometry.origin(for: huge, in: area, snap: 20, clamp: true, scale: 2).y + huge.height == area.maxY,
           "oversize panel keeps its header visible")
    let now = Date().timeIntervalSince1970

    // MARK: Music library reader

    let json = """
    {"n":["Song A","Song B","Song C","Song D","Intro",null],
     "a":["The Band","The Band","The Band","Other Artist","Various",""],
     "b":["First Album","First Album","Second Album (Deluxe Edition)","Solo","Mixtape",""],
     "c":["The Band","The Band","The Band","","Various",""],
     "p":[10,4,0,7,null,3],
     "d":[\(now - day),\(now - 3 * day),null,\(now - 60),null,0]}
    """
    let scan = MusicLibrary.parse(Data(json.utf8))
    expect(scan != nil, "library JSON parses")
    if let scan {
        expect(scan.totals[TitleTidy.key("The Band")] == MusicLibrary.Total(plays: 14, songs: 3), "band totals")
        expect(scan.mostPlayed.map(\.title) == ["Song A", "Song D", "Song B", ""], "most played order")
        expect(scan.recentlyPlayed.map(\.title) == ["Song D", "Song A", "Song B"], "recently played order, skips missing dates")
        expect(scan.topAlbums.first?.album == "First Album" && scan.topAlbums.first?.plays == 14, "top album by plays")
        expect(!scan.topAlbums.contains { $0.album == "Second Album (Deluxe Edition)" }, "unplayed album left out")

        let library = MusicLibrary()
        library.apply(scan)
        expect(library.rank(for: "the band") == 1, "artist rank ignores case")
        expect(library.rank(for: "Other Artist") == 2, "second artist rank")
        expect(library.songs(byArtist: "The Band").count == 3, "songs by artist")
        expect(library.songs(onAlbum: "Second Album", artists: ["The Band"]).count == 1, "album match ignores edition words")
        expect(library.songs(onAlbum: "First Album", artists: ["Someone Else"]).isEmpty, "album needs the same artist")

        // The drawer report for a song from that library
        var track = Snapshot()
        track.source = .music
        track.title = "Song A"
        track.artist = "The Band"
        track.album = "First Album"
        track.albumArtist = "The Band"
        let facts = LibraryFacts(plays: 10, skips: 1, lastPlayed: Date(timeIntervalSince1970: now - day), added: nil, favorite: true)
        let report = StatsBook.report(track: track, facts: facts, account: SpotifyAccount(loadStoredCredentials: false), library: library)
        expect(report.song.tiles.count == 3, "song row holds 3 tiles")
        expect(report.song.tiles.first?.value == "10", "song plays tile")
        expect(report.artist.tiles.first?.value == "14", "artist plays tile")
        expect(report.artist.tiles.contains { $0.value == "2/3" && $0.caption == "songs played" }, "artist songs played")
        expect(report.artist.lines.map(\.title) == ["Song A", "Song B"], "top songs by artist")
        expect(report.album.tiles.first?.value == "14", "album plays tile")
        expect(report.album.tiles.contains { $0.value == "2/2" }, "album songs played")
        expect(report.album.caption == StatsBook.musicLabel, "album caption names the source")
    }
    expect(MusicLibrary.parse(Data(#"{"n":["x"],"a":[],"b":[],"c":[],"p":[],"d":[]}"#.utf8)) == nil, "uneven columns rejected")
    expect(MusicLibrary.parse(Data("not json".utf8)) == nil, "bad JSON rejected")

    // MARK: Plays counted on this Mac

    let log = ListeningLog(persist: false)
    log.clear()
    var snap = Snapshot()
    snap.source = .spotify
    snap.state = .playing
    snap.title = "Night Drive"
    snap.artist = "Neon Coast, Guest"
    snap.album = "City Lights"
    var clock = Date()
    for second in 0..<40 {
        snap.position = Double(second * 2)
        log.tick(snap, now: clock)
        clock = clock.addingTimeInterval(2)
    }
    expect(log.song(artist: "Neon Coast", title: "Night Drive")?.seconds == 78, "listening time adds up")
    let song = log.song(artist: "Neon Coast", title: "Night Drive")
    expect(song?.plays == 1, "a play counts after 30 seconds")
    expect(song?.album == "City Lights", "album saved with the song")
    expect(log.songs(byArtist: "neon coast").count == 1, "songs by artist")
    expect(log.songs(onAlbum: "City Lights", artists: ["Neon Coast"]).count == 1, "songs on album")
    expect(log.topAlbums().first?.album == "City Lights", "top albums from this Mac")
    expect(log.recentSongs().first?.title == "Night Drive", "recent songs")
    expect(log.topArtists().first?.name == "Neon Coast", "top artists from this Mac")
    log.clear()

    // MARK: Account-only live stats and full-history import

    var remoteTrack = Snapshot()
    remoteTrack.source = .spotify
    remoteTrack.title = "Across Devices"
    remoteTrack.artist = "The Band"
    remoteTrack.albumArtist = "The Band"
    remoteTrack.album = "Account Album"
    remoteTrack.trackID = "spotify:track:0123456789012345678901"
    let remotePlays = [
        SpotifyAccount.Play(trackID: "0123456789012345678901", artistKeys: [TitleTidy.key("The Band")],
                            at: Date(), title: "Across Devices", artist: "The Band", album: "Account Album"),
        SpotifyAccount.Play(trackID: "other", artistKeys: [TitleTidy.key("Other Artist")],
                            at: Date(), title: "Different", artist: "Other Artist", album: "Account Album")
    ]
    let remote = StatsBook.spotifyReport(track: remoteTrack, top: [.medium: .init(artists: [TitleTidy.key("The Band"): 48])],
                                        recent: remotePlays, rankedSongs: [:], span: .medium)
    expect(remote.song.tiles.first?.caption == "last in recent history", "recent timestamp is qualified, not a play count")
    expect(remote.album.tiles.first?.value == StatsBook.ago(remotePlays[0].at), "album timestamp comes from matching artist")
    expect(remote.artist.tiles.first?.value == "#48", "account artist rank preserved")
    expect(remote.song.caption == StatsBook.spotifyLabel, "account source explicitly covers all devices")
    expect([remote.song, remote.artist, remote.album].flatMap(\.tiles).allSatisfy { !$0.caption.contains("here") },
           "live account card has no device-local metrics")
    let absent = StatsBook.spotifyReport(track: remoteTrack, top: [:], recent: [], rankedSongs: [:])
    expect(absent.isEmpty, "missing history is not mislabeled New or zero lifetime plays")
    let ranks: [SpotifyAccount.Span: SpotifyAccount.Top] = [
        .short: .init(artists: [TitleTidy.key("The Band"): 30], tracks: ["0123456789012345678901": 40]),
        .medium: .init(artists: [TitleTidy.key("The Band"): 2], tracks: ["0123456789012345678901": 3])
    ]
    let ranked = SpotifyAccount.Ranked(title: "Across Devices", subtitle: "The Band",
                                      id: "0123456789012345678901", artistKeys: [TitleTidy.key("The Band")], album: "Account Album")
    let short = StatsBook.spotifyReport(track: remoteTrack, top: ranks, recent: remotePlays,
                                       rankedSongs: [.medium: [ranked]], span: .short)
    expect(short.song.tiles.first?.value == "#40", "song rank isolated to selected timeframe")
    expect(short.artist.tiles.first?.value == "#30", "artist rank is not best across timeframes")
    expect(short.artist.lines.isEmpty && short.album.lines.isEmpty, "lists do not leak another timeframe")
    let medium = StatsBook.spotifyReport(track: remoteTrack, top: ranks, recent: remotePlays,
                                        rankedSongs: [.medium: [ranked]], span: .medium)
    expect(medium.song.tiles.first?.value == "#3", "changing timeframe changes the supplied song rank")
    expect(medium.artist.lines.first?.detail == "#1 · 6 months", "advanced list preserves supplied position and period")
    let missingSpan = StatsBook.spotifyReport(track: remoteTrack, top: ranks, recent: [],
                                             rankedSongs: [.medium: [ranked]], span: .long)
    expect(missingSpan.isEmpty, "missing timeframe does not fall back to another period")
    let liveTiles = [short.song, short.artist, short.album].flatMap(\.tiles)
    expect(liveTiles.allSatisfy { $0.caption.hasPrefix("Spotify ranking") || $0.caption == "last in recent history" },
           "live tiles contain only supplied rankings or qualified timestamps")
    expect(short.album.tiles.count == 1 && short.album.tiles[0].caption == "last in recent history",
           "live album has no synthetic rank, count or listened duration")

    let extended = """
    [
      {"ts":"2020-01-01T12:00:00Z","ms_played":180000,"master_metadata_track_name":"Across Devices","master_metadata_album_artist_name":"The Band","master_metadata_album_album_name":"Account Album","spotify_track_uri":"spotify:track:0123456789012345678901","ip_addr":"PRIVATE","platform":"phone"},
      {"ts":"2020-01-02T12:00:00.000Z","ms_played":10000,"master_metadata_track_name":"Across Devices","master_metadata_album_artist_name":"The Band","master_metadata_album_album_name":"Account Album","spotify_track_uri":"spotify:track:0123456789012345678901","platform":"web"},
      {"ts":"2020-01-03T12:00:00Z","ms_played":120000,"master_metadata_track_name":"Second Song","master_metadata_album_artist_name":"The Band","master_metadata_album_album_name":"Account Album","spotify_track_uri":"spotify:track:1123456789012345678901"},
      {"ts":"2020-01-04T12:00:00Z","ms_played":90000,"master_metadata_track_name":null,"master_metadata_album_artist_name":null,"spotify_episode_uri":"spotify:episode:example"},
      {"ts":"bad","ms_played":120000,"master_metadata_track_name":"Bad Date","master_metadata_album_artist_name":"The Band"},
      {"ts":"2020-01-04T12:00:00Z","ms_played":-1,"master_metadata_track_name":"Invalid Time","master_metadata_album_artist_name":"The Band"}
    ]
    """
    let parsed = try? SpotifyArchive.parse(Data(extended.utf8))
    expect(parsed?.events.count == 3, "full export retains valid music on every platform")
    expect(parsed?.skipped == 3, "podcasts and invalid rows reported as skipped")
    if let parsed {
        let indexed = SpotifyArchive.index(parsed.events + parsed.events)
        expect(indexed.events.count == 3, "overlapping/repeated imports are deduplicated")
        expect(indexed.songs.count == 2, "export song grouping")
        let song = indexed.songs[remoteTrack.trackID]
        expect(song?.plays == 1, "sub-30-second listen not a qualifying play")
        expect(song?.milliseconds == 190000, "short listens still contribute actual listening time")
        expect(indexed.artists[TitleTidy.key("The Band")]?.plays == 2, "account-wide artist plays")
        expect(indexed.albums.values.first?.plays == 2, "account-wide album plays")
        let report = StatsBook.importedReport(track: remoteTrack, snapshot: indexed, coverage: "test export")
        expect(report.song.tiles.first?.value == "1", "imported song stats shown")
        expect(report.artist.tiles.first?.value == "2", "imported artist stats shown")
        expect(report.album.tiles.first?.value == "2", "imported album stats shown")
        expect(report.song.caption.contains("all devices") && report.song.caption.contains("test export"), "import coverage labeled")
        let saved = String(data: (try? JSONEncoder().encode(indexed.events)) ?? Data(), encoding: .utf8) ?? ""
        expect(!saved.contains("PRIVATE") && !saved.contains("platform") && !saved.contains("ip_addr"), "sensitive export fields stripped")
        expect((try? JSONDecoder().decode([SpotifyArchive.Event].self, from: Data(saved.utf8))) == indexed.events,
               "sanitized archive round-trips")
    }
    expect((try? SpotifyArchive.parse(Data(#"[{"endTime":"2020-01-01 12:00","msPlayed":100}]"#.utf8))) == nil,
           "standard account export not mislabeled lifetime history")
    expect((try? SpotifyArchive.parse(Data("not json".utf8))) == nil, "malformed export rejected")

    // Artist audience: never confuse followers or another artist's biography with monthly listeners.
    expect(AudiencePages.monthlyListeners(in: #"<meta property="og:description" content="Artist · 25.4M monthly listeners.">"#) == "25.4M",
           "rounded public monthly listener metadata kept as published")
    expect(AudiencePages.monthlyListeners(in: #"<meta content="Artist · 25,399,931 monthly listeners." name="description">"#) == "25,399,931",
           "exact public monthly listener metadata parses")
    expect(AudiencePages.monthlyListeners(in: #"<meta name="description" content="25M followers"><p>50M monthly listeners</p>"#) == nil,
           "followers and arbitrary body text rejected")
    expect(AudiencePages.monthlyListeners(in: "<html>Sign in</html>") == nil, "missing audience count stays unavailable")
    expect(AudiencePages.artistURL(id: "../wrong") == nil, "invalid artist ID rejected")
    expect(AudiencePages.artistID(URL(string: "https://example.com/artist/0123456789012345678901")!) == nil,
           "audience links restricted to Spotify")

    // MARK: Saved files from 1.2 have no album field

    let old = #"{"title":"Old","artist":"Someone","plays":2,"seconds":90,"first":0,"last":0}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try? decoder.decode(ListeningLog.Song.self, from: Data(old.utf8))
    expect(decoded?.plays == 2 && decoded?.album == nil, "1.2 history still loads")

    // MARK: Playback reader compilation

    // `st` is an AppleScript reserved token. Swift compilation cannot catch
    // invalid identifiers inside embedded AppleScript, so compile every local
    // binding even on CI machines without Spotify installed.
    let bindingPattern = try! NSRegularExpression(pattern: #"(?m)^\s*set ([A-Za-z][A-Za-z0-9]*) to "#)
    for source in Source.allCases {
        let reader = Players.readerSource(source)
        let text = reader as NSString
        let names = bindingPattern.matches(in: reader, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range(at: 1)) }
        let bindings = names.map { "set \($0) to 0" }.joined(separator: "\n")
        var error: NSDictionary?
        let script = NSAppleScript(source: bindings)
        expect(!names.isEmpty && script?.compileAndReturnError(&error) == true,
               "\(source.name) reader variable names compile")
        if Players.isInstalled(source) {
            let fullScript = NSAppleScript(source: reader)
            error = nil
            expect(fullScript?.compileAndReturnError(&error) == true,
                   "\(source.name) full reader compiles: \(error?.description ?? "OK")")
        }
    }

    // MARK: Formatting

    expect(StatsBook.plays(1) == "1 play" && StatsBook.plays(3) == "3 plays", "play wording")
    expect(StatsBook.ago(Date().addingTimeInterval(-300)) == "5 min ago", "minutes ago")
}

@MainActor
func checkImportPersistence() async {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiniDeck-import-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let input = folder.appendingPathComponent("Streaming_History_Audio_test.json")
        let destination = folder.appendingPathComponent("saved/spotify-import.json")
        let fixture = #"[{"ts":"2021-01-01T00:00:00Z","ms_played":60000,"master_metadata_track_name":"Test Song","master_metadata_album_artist_name":"Test Artist","master_metadata_album_album_name":"Test Album","spotify_track_uri":"spotify:track:0123456789012345678901","ip_addr":"never-save-this"}]"#
        try Data(fixture.utf8).write(to: input)
        let archive = SpotifyArchive(storageURL: destination)
        for _ in 0..<200 where archive.loading { try await Task.sleep(for: .milliseconds(10)) }
        expect(!archive.loading, "archive startup load completes")
        try await archive.importFiles([input])
        expect(archive.snapshot.events.count == 1, "file import succeeds")
        try await archive.importFiles([input])
        expect(archive.snapshot.events.count == 1, "file re-import does not double-count")
        let saved = try String(contentsOf: destination, encoding: .utf8)
        expect(!saved.contains("never-save-this") && !saved.contains("ip_addr"), "saved file excludes private fields")
        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "saved import is user-readable only")
        let reopened = SpotifyArchive(storageURL: destination)
        for _ in 0..<200 where reopened.loading { try await Task.sleep(for: .milliseconds(10)) }
        expect(reopened.snapshot.events == archive.snapshot.events, "saved import reloads after restart")
        try Data("invalid".utf8).write(to: input)
        do {
            try await archive.importFiles([input])
            expect(false, "invalid file must fail")
        } catch {
            expect(archive.snapshot.events.count == 1, "failed import preserves loaded records")
            expect(try String(contentsOf: destination, encoding: .utf8) == saved, "failed import preserves saved file")
        }
        try Data("damaged".utf8).write(to: destination)
        let damaged = SpotifyArchive(storageURL: destination)
        for _ in 0..<200 where damaged.loading { try await Task.sleep(for: .milliseconds(10)) }
        expect(damaged.loadError != nil, "damaged saved archive is reported, not silently discarded")
        try Data(fixture.utf8).write(to: input)
        do {
            try await damaged.importFiles([input])
            expect(false, "damaged archive must not be overwritten")
        } catch {
            expect(try String(contentsOf: destination, encoding: .utf8) == "damaged", "damaged saved data left untouched")
        }
        try damaged.clear()
        expect(!FileManager.default.fileExists(atPath: destination.path), "explicit removal clears only saved import")
        expect(FileManager.default.fileExists(atPath: input.path), "original export survives removal")
    } catch {
        expect(false, "import persistence test: \(error.localizedDescription)")
    }
}

@MainActor
func checkPointer() async {
    let pointer = Pointer()
    pointer.register(Zone.card, CGRect(x: 0, y: 0, width: 448, height: 700))
    pointer.register(Zone.cover, CGRect(x: 12, y: 12, width: 132, height: 132))
    pointer.register(Zone.transport, CGRect(x: 170, y: 100, width: 240, height: 40))
    pointer.register(Zone.scrubber, CGRect(x: 170, y: 155, width: 240, height: 30))
    pointer.location = CGPoint(x: 20, y: 20)
    try? await Task.sleep(for: .milliseconds(180))
    expect(pointer.drawerOpen, "cover hover opens the drawer")
    nonisolated(unsafe) var invalidations = 0
    withObservationTracking {
        _ = pointer.over(Zone.cover)
    } onChange: {
        invalidations += 1
    }
    for x in 21...120 { pointer.location = CGPoint(x: x, y: 30) }
    expect(invalidations == 0, "100 moves inside one region do not invalidate observed hover state")
    pointer.location = CGPoint(x: 250, y: 300)
    expect(invalidations == 1, "region boundary publishes one hover change")
    expect(pointer.drawerOpen, "drawer stays open while reading statistics")
    pointer.location = nil
    expect(pointer.drawerOpen, "transient tracking-area exit does not collapse immediately")
    pointer.location = CGPoint(x: 250, y: 300)
    try? await Task.sleep(for: .milliseconds(180))
    expect(pointer.drawerOpen, "re-entry cancels delayed close")
    pointer.location = CGPoint(x: 200, y: 115)
    expect(!pointer.drawerOpen, "transport controls close the drawer without waiting")
    pointer.location = CGPoint(x: 20, y: 20)
    pointer.location = nil
    try? await Task.sleep(for: .milliseconds(180))
    expect(!pointer.drawerOpen, "brief cover crossing cancels opening")
    pointer.location = CGPoint(x: 20, y: 20)
    try? await Task.sleep(for: .milliseconds(180))
    pointer.frozen = true
    expect(!pointer.drawerOpen && pointer.hovered.isEmpty, "drag freeze closes and clears hover")
    pointer.frozen = false
    try? await Task.sleep(for: .milliseconds(180))
    expect(pointer.drawerOpen, "unfreezing restores hover without extra pointer motion")
    pointer.location = nil
    try? await Task.sleep(for: .milliseconds(180))
    expect(!pointer.drawerOpen, "real pointer exit closes after grace period")
    pointer.location = CGPoint(x: 20, y: 20)
    pointer.scrub = 0.5
    pointer.resetLayout()
    try? await Task.sleep(for: .milliseconds(150))
    expect(pointer.zones.isEmpty && pointer.hovered.isEmpty, "mode change clears stale hover regions")
    expect(!pointer.drawerOpen && pointer.scrub == nil, "mode change cancels pending drawer and scrub")
    pointer.register(Zone.card, CGRect(x: 0, y: 0, width: 300, height: 250))
    pointer.register(Zone.cover, CGRect(x: 10, y: 10, width: 60, height: 60))
    pointer.location = CGPoint(x: 25, y: 25)
    try? await Task.sleep(for: .milliseconds(160))
    expect(pointer.drawerOpen, "compact cover opens its hover panel after a layout reset")
}

@MainActor
func checkWrapped() async {
    let first = WrappedLibrary.Item(position: 1, trackID: String(repeating: "a", count: 22),
                                    title: "Fixture Song", artist: "Fixture Artist", album: "Fixture Album")
    let third = WrappedLibrary.Item(position: 3, trackID: String(repeating: "b", count: 22),
                                    title: "Another Fixture", artist: "Fixture Artist", album: "Fixture Album")
    let id = String(repeating: "c", count: 22)
    let list = WrappedLibrary.Playlist(year: 2024, id: id, name: "Your Top Songs 2024",
                                      url: "https://open.spotify.com/playlist/\(id)", items: [third, first])
    let document = WrappedLibrary.Document(capturedAt: "2025-01-01T00:00:00Z", playlists: [list])
    do {
        let data = try JSONEncoder().encode(document)
        let parsed = try WrappedLibrary.parse(data)
        expect(parsed.playlists[0].items.map(\.position) == [1, 3], "Wrapped preserves supplied positions, including gaps")
        var raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        raw["username"] = "PRIVATE_USERNAME"
        raw["token"] = "PRIVATE_TOKEN"
        let sanitized = try WrappedLibrary.parse(JSONSerialization.data(withJSONObject: raw))
        let savedText = String(decoding: try JSONEncoder().encode(sanitized), as: UTF8.self)
        expect(!savedText.contains("PRIVATE"), "unknown private fields are not retained")
        raw["version"] = 999
        expect((try? WrappedLibrary.parse(JSONSerialization.data(withJSONObject: raw))) == nil, "unknown Wrapped snapshot version rejected")
        expect((try? WrappedLibrary.parse(Data("[]".utf8))) == nil, "streaming export is not mistaken for Wrapped playlists")
        expect((try? WrappedLibrary.parse(Data(repeating: 0, count: WrappedLibrary.byteLimit + 1))) == nil,
               "Wrapped import has a bounded size")
        var duplicate = document
        duplicate.playlists.append(list)
        expect((try? WrappedLibrary.parse(JSONEncoder().encode(duplicate))) == nil, "duplicate Wrapped years rejected")
        let badURL = WrappedLibrary.Playlist(year: 2024, id: id, name: "Your Top Songs 2024",
                                             url: "file:///private/data", items: [first])
        let badDocument = WrappedLibrary.Document(capturedAt: document.capturedAt, playlists: [badURL])
        expect((try? WrappedLibrary.parse(JSONEncoder().encode(badDocument))) == nil, "Wrapped links restricted to matching Spotify playlist URLs")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MiniDeck-Wrapped-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("original.json")
        let destination = folder.appendingPathComponent("private/saved.json")
        try data.write(to: input)
        let library = WrappedLibrary(storageURL: destination)
        for _ in 0..<200 where library.loading { try await Task.sleep(for: .milliseconds(10)) }
        try await library.importFile(input)
        expect(library.yearsContaining("spotify:track:\(first.trackID)") == [2024], "Wrapped matching uses exact Spotify track ID")
        expect(library.yearsContaining("spotify:track:\(String(repeating: "z", count: 22))").isEmpty,
               "missing Wrapped entry is not guessed by artist or title")
        try await library.importFile(input)
        expect(library.playlists.count == 1, "reimport replaces a year without duplicating it")
        let olderID = String(repeating: "d", count: 22)
        let older = WrappedLibrary.Playlist(year: 2022, id: olderID, name: "2022",
            url: "https://open.spotify.com/playlist/\(olderID)", items: [first])
        let historical = WrappedLibrary.history(from: [list, older])
        expect(historical.count == 2, "historical songs deduplicate by exact track ID across years")
        expect(historical.first { $0.trackID == first.trackID }?.years == [2024, 2022],
               "historical years remain explicit, not a synthetic continuous date range")
        expect(library.songs.count == 2, "import refreshes the cached historical song index")
        var track = Snapshot()
        track.source = .spotify
        track.trackID = "spotify:track:" + first.trackID
        track.title = first.title
        track.artist = first.artist
        track.album = first.album
        var report = ListeningReport()
        StatsBook.addHistorical(track: track, songs: historical, into: &report)
        report.song.trim(); report.artist.trim(); report.album.trim()
        expect(report.song.tiles.first?.value == "2024, 2022", "song report incorporates historical years")
        expect(!report.artist.isEmpty && !report.album.isEmpty, "artist and album incorporate matching historical records")
        expect([report.song, report.artist, report.album].flatMap(\.tiles).allSatisfy {
            $0.caption == "years in history" && !$0.value.contains("#")
        }, "historical records never manufacture play counts, time or rankings")
        let integrated = StatsBook.report(track: track, facts: nil, account: SpotifyAccount(loadStoredCredentials: false),
                                         library: MusicLibrary(), historical: historical)
        expect(!integrated.song.isEmpty, "historical song data is part of the normal report without live API results")
        track.trackID = "spotify:track:" + String(repeating: "z", count: 22)
        track.artist = "Unrelated Artist"
        var unrelated = ListeningReport()
        StatsBook.addHistorical(track: track, songs: historical, into: &unrelated)
        expect(unrelated.isEmpty, "matching titles and album names alone do not associate another artist")
        track.source = .music
        let musicOnly = StatsBook.report(track: track, facts: nil, account: SpotifyAccount(loadStoredCredentials: false),
                                        library: MusicLibrary(), historical: historical)
        expect(musicOnly.isEmpty, "Spotify historical evidence is not added to Apple Music")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = SpotifyAccount.Play(trackID: first.trackID, artistKeys: [], at: date,
                                        title: first.title, artist: first.artist, album: first.album)
        let earlier = SpotifyAccount.Play(trackID: first.trackID, artistKeys: [], at: date.addingTimeInterval(-60))
        let imported = SpotifyArchive.Total(title: first.title, artist: first.artist, album: first.album,
                                            first: date.addingTimeInterval(-120), last: date.addingTimeInterval(-90))
        let combined = AccountHistory.songs(recent: [recent, earlier], historical: historical,
                                            imported: ["spotify:track:" + first.trackID: imported])
        expect(combined.count == 2, "overall history unifies recent, imported and year-level records by ID")
        expect(combined.first?.recent == date && combined.first?.years == [2024, 2022],
               "unified song retains actual recent timestamp and historical years")
        expect(combined.first?.imported == imported.last, "unified song preserves imported timing separately")
        expect(combined.last?.latest == nil, "year-only history never gets a fabricated playback timestamp")
        expect(AccountHistory.songs(recent: [], historical: historical).count == 2,
               "overall history remains available without recent API data")
        let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
        expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600, "saved Wrapped file has private permissions")
        let reload = WrappedLibrary(storageURL: destination)
        for _ in 0..<200 where reload.loading { try await Task.sleep(for: .milliseconds(10)) }
        expect(reload.playlists == library.playlists, "Wrapped snapshot reload preserves source entries")
        expect(reload.songs == library.songs, "restart restores integrated historical song data")
        try Data("corrupt".utf8).write(to: destination)
        let damaged = WrappedLibrary(storageURL: destination)
        for _ in 0..<200 where damaged.loading { try await Task.sleep(for: .milliseconds(10)) }
        expect(damaged.loadError, "damaged Wrapped snapshot is reported")
        do {
            try await damaged.importFile(input)
            expect(false, "damaged Wrapped snapshot must not be overwritten")
        } catch {
            expect(try String(contentsOf: destination, encoding: .utf8) == "corrupt", "damaged Wrapped snapshot preserved")
        }
        try damaged.clear()
        expect(FileManager.default.fileExists(atPath: input.path), "removing saved Wrapped leaves the original file intact")
        expect(!FileManager.default.fileExists(atPath: destination.path), "removing saved Wrapped deletes only the saved copy")
        try library.clear()
        expect(library.songs.isEmpty, "removing historical data clears the integrated song index")
    } catch {
        expect(false, "Wrapped test: \(error.localizedDescription)")
    }
}

await checkImportPersistence()
await checkWrapped()
await checkPointer()
print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
