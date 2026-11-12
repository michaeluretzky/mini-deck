// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit

/// A music app Mini Deck can follow and control.
enum Source: String, CaseIterable, Identifiable, Sendable {
    case spotify, music

    var id: String { rawValue }
    var bundle: String { self == .spotify ? "com.spotify.client" : "com.apple.Music" }
    /// The service name shown in text.
    var name: String { self == .spotify ? "Spotify" : "Apple Music" }
    /// The app name shown on buttons.
    var appName: String { self == .spotify ? "Spotify" : "Music" }
    var changed: Notification.Name {
        Notification.Name(self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo")
    }
}

/// Which app the card follows.
enum SourceChoice: String, CaseIterable, Identifiable, Sendable {
    case automatic, spotify, music

    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .spotify: "Spotify"
        case .music: "Apple Music"
        }
    }
    var fixed: Source? {
        switch self {
        case .automatic: nil
        case .spotify: .spotify
        case .music: .music
        }
    }
}

/// One reading of what the music app is doing.
struct Snapshot: Equatable {
    enum State: String { case playing, paused, stopped }
    var source: Source = .spotify
    var state: State = .stopped
    var title = ""
    var artist = ""
    var album = ""
    var albumArtist = ""
    var artworkURL: URL?
    /// Spotify URI ("spotify:track:...") or the Music app's persistent ID.
    var trackID = ""
    var position: Double = 0
    var length: Double = 0
    var shuffle = false
    var loop = false
    var volume = 0

    var primaryArtist: String { artist.components(separatedBy: ", ").first ?? artist }
}

/// Per-song numbers that the Music app keeps in the user's library.
struct LibraryFacts: Equatable {
    var plays: Int?
    var skips: Int?
    var lastPlayed: Date?
    var added: Date?
    var favorite = false
}

enum PlayerCommand {
    case playPause, next, previous
    case seek(Double)
    case shuffle(Bool)
    case loop(Bool)
    case volume(Int)
}

/// Talks to Spotify and the Music app through Apple Events.
@MainActor
enum Players {
    static func isRunning(_ source: Source) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == source.bundle }
    }

    static func reveal(_ source: Source) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    static func isInstalled(_ source: Source) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundle) != nil
    }

    // MARK: Reading

    // Both readers return the same list:
    //  1 state, 2 name, 3 artist, 4 album, 5 album artist, 6 artwork URL, 7 track ID,
    //  8 position (s), 9 length, 10 shuffle, 11 repeat, 12 volume
    private static func readerSource(_ source: Source) -> String {
        let guarded: [(Int, String)]
        let tail: String
        switch source {
        case .spotify:
            guarded = [(2, "name of tr"), (3, "artist of tr"), (4, "album of tr"), (5, "album artist of tr"),
                       (6, "artwork url of tr"), (7, "spotify url of tr"), (9, "duration of tr")]
            tail = """
            set item 10 of out to shuffling
            set item 11 of out to repeating
            """
        case .music:
            guarded = [(2, "name of tr"), (3, "artist of tr"), (4, "album of tr"), (5, "album artist of tr"),
                       (7, "persistent ID of tr"), (9, "duration of tr")]
            tail = """
            try
            set item 10 of out to shuffle enabled
            end try
            try
            set item 11 of out to ((song repeat as text) is not "off")
            end try
            """
        }
        let fields = guarded.map { "try\nset item \($0.0) of out to (\($0.1))\nend try" }.joined(separator: "\n")
        return """
        tell application id "\(source.bundle)"
        set st to (player state as text)
        if st is "stopped" then return {st}
        set out to {st, "", "", "", "", "", "", 0, 0, false, false, 0}
        try
        set tr to current track
        \(fields)
        end try
        try
        set item 8 of out to player position
        end try
        \(tail)
        try
        set item 12 of out to sound volume
        end try
        return out
        end tell
        """
    }

    private static var readers: [Source: NSAppleScript] = [:]

    private static func reader(_ source: Source) -> NSAppleScript? {
        if let ready = readers[source] { return ready }
        guard let script = compiled(readerSource(source)) else { return nil }
        readers[source] = script
        return script
    }

    static func read(_ source: Source) -> Snapshot? {
        guard isRunning(source), let script = reader(source) else { return nil }
        var error: NSDictionary?
        let list = script.executeAndReturnError(&error)
        guard error == nil, list.numberOfItems >= 1 else { return nil }
        var snap = Snapshot()
        snap.source = source
        let state = list.atIndex(1)?.stringValue ?? ""
        switch state {
        case "playing", "fast forwarding", "rewinding": snap.state = .playing
        case "paused": snap.state = .paused
        default: snap.state = .stopped
        }
        guard snap.state != .stopped, list.numberOfItems >= 12 else { return snap }
        func text(_ i: Int) -> String { list.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double { list.atIndex(i)?.doubleValue ?? 0 }
        snap.title = text(2)
        snap.artist = text(3)
        snap.album = text(4)
        snap.albumArtist = text(5)
        snap.artworkURL = URL(string: text(6)).flatMap { $0.scheme == "https" || $0.scheme == "http" ? $0 : nil }
        snap.trackID = text(7)
        snap.position = number(8)
        snap.length = source == .spotify ? number(9) / 1000 : number(9)
        snap.shuffle = list.atIndex(10)?.booleanValue ?? false
        snap.loop = list.atIndex(11)?.booleanValue ?? false
        snap.volume = Int(number(12).rounded())
        return snap
    }

    // MARK: Music app extras

    /// The cover bytes the Music app holds for the current track.
    static func musicArtwork() -> Data? {
        guard isRunning(.music) else { return nil }
        let source = """
        tell application id "com.apple.Music"
        try
        return raw data of artwork 1 of current track
        end try
        try
        return data of artwork 1 of current track
        end try
        return ""
        end tell
        """
        guard let script = compiled(source) else { return nil }
        var error: NSDictionary?
        let out = script.executeAndReturnError(&error)
        guard error == nil else { return nil }
        let data = out.data
        return data.count > 64 ? data : nil
    }

    private static var factsScript: NSAppleScript?

    /// Play count, skips, last played, date added and favorite flag for the current Music track.
    static func musicFacts() -> LibraryFacts? {
        guard isRunning(.music) else { return nil }
        if factsScript == nil {
            // The favorite flag was renamed in newer Music versions; use whichever this Mac knows.
            for flag in ["favorited", "loved", ""] {
                let flagLine = flag.isEmpty ? "" : "try\nset item 5 of out to (\(flag) of tr)\nend try"
                let source = """
                tell application id "com.apple.Music"
                set tr to current track
                set out to {-1, -1, missing value, missing value, false}
                try
                set item 1 of out to (played count of tr)
                end try
                try
                set item 2 of out to (skipped count of tr)
                end try
                try
                set item 3 of out to (played date of tr)
                end try
                try
                set item 4 of out to (date added of tr)
                end try
                \(flagLine)
                return out
                end tell
                """
                if let script = compiled(source) { factsScript = script; break }
            }
        }
        guard let script = factsScript else { return nil }
        var error: NSDictionary?
        let list = script.executeAndReturnError(&error)
        guard error == nil, list.numberOfItems >= 5 else { return nil }
        func count(_ i: Int) -> Int? {
            guard let d = list.atIndex(i), d.descriptorType != typeNull else { return nil }
            let n = Int(d.int32Value)
            return n >= 0 ? n : nil
        }
        func date(_ i: Int) -> Date? {
            guard let d = list.atIndex(i), d.descriptorType != typeNull else { return nil }
            return d.dateValue
        }
        return LibraryFacts(plays: count(1), skips: count(2), lastPlayed: date(3), added: date(4),
                            favorite: list.atIndex(5)?.booleanValue ?? false)
    }

    // MARK: Commands

    static func send(_ command: PlayerCommand, to source: Source) {
        guard isRunning(source) else { return }
        let line: String
        switch command {
        case .playPause: line = "playpause"
        case .next: line = "next track"
        case .previous: line = "previous track"
        case .seek(let seconds): line = "set player position to \(String(format: "%.2f", seconds))"
        case .volume(let level): line = "set sound volume to \(min(100, max(0, level)))"
        case .shuffle(let on):
            line = source == .spotify ? "set shuffling to \(on)" : "set shuffle enabled to \(on)"
        case .loop(let on):
            line = source == .spotify ? "set repeating to \(on)" : "set song repeat to \(on ? "all" : "off")"
        }
        var error: NSDictionary?
        NSAppleScript(source: "tell application id \"\(source.bundle)\" to \(line)")?.executeAndReturnError(&error)
    }

    private static func compiled(_ source: String) -> NSAppleScript? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        return script.compileAndReturnError(&error) ? script : nil
    }
}
