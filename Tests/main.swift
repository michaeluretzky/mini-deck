// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

// Checks the listening-history math without a music app or account.
// Built and run by the Build workflow: see .github/workflows/build.yml.

import Foundation

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func expect(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok {
        failures += 1
        print("FAIL line \(line): \(what)")
    }
}

MainActor.assumeIsolated {
    let day: Double = 86_400
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
        let report = StatsBook.report(track: track, facts: facts, account: SpotifyAccount(), library: library)
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

    let log = ListeningLog()
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
                                        recent: remotePlays, rankedSongs: [:])
    expect(remote.song.tiles.first?.value == "1×", "account recent play displayed")
    expect(remote.album.tiles.first?.value == "1", "same-name album from another artist excluded")
    expect(remote.artist.tiles.first?.value == "#48", "account artist rank preserved")
    expect(remote.song.caption == StatsBook.spotifyLabel, "account source explicitly covers all devices")
    expect([remote.song, remote.artist, remote.album].flatMap(\.tiles).allSatisfy { !$0.caption.contains("here") },
           "live account card has no device-local metrics")
    let absent = StatsBook.spotifyReport(track: remoteTrack, top: [:], recent: [], rankedSongs: [:])
    expect(absent.isEmpty, "missing history is not mislabeled New or zero lifetime plays")

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

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
