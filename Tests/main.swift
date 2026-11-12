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
        let report = StatsBook.report(track: track, facts: facts, account: SpotifyAccount(), library: library,
                                      log: ListeningLog(), counting: false)
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

    // MARK: Saved files from 1.2 have no album field

    let old = #"{"title":"Old","artist":"Someone","plays":2,"seconds":90,"first":0,"last":0}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970
    let decoded = try? decoder.decode(ListeningLog.Song.self, from: Data(old.utf8))
    expect(decoded?.plays == 2 && decoded?.album == nil, "1.2 history still loads")

    // MARK: Formatting

    expect(StatsBook.plays(1) == "1 play" && StatsBook.plays(3) == "3 plays", "play wording")
    expect(StatsBook.ago(Date().addingTimeInterval(-300)) == "5 min ago", "minutes ago")
}

print("\(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
