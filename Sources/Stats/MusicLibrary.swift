// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Artist totals from the Music app's library: plays, songs and rank.
@MainActor @Observable
final class MusicLibrary {
    struct Total: Equatable, Sendable {
        var plays = 0
        var songs = 0
    }

    private(set) var totals: [String: Total] = [:]
    private(set) var ranks: [String: Int] = [:]
    private(set) var scanned: Date?
    private(set) var scanning = false

    func total(for artist: String) -> Total? { totals[TitleTidy.key(artist)] }
    func rank(for artist: String) -> Int? { ranks[TitleTidy.key(artist)] }

    /// Reads the library at most every 30 minutes, only while the Music app is open.
    func scanIfStale() {
        guard !scanning, Players.isRunning(.music) else { return }
        if let scanned, Date().timeIntervalSince(scanned) < 30 * 60 { return }
        scanning = true
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { Self.readLibrary() }.value
            guard let self else { return }
            self.scanning = false
            guard let result else { return }
            self.totals = result
            let ordered = result.filter { $0.value.plays > 0 }.sorted { $0.value.plays > $1.value.plays }
            var ranks: [String: Int] = [:]
            var place = 0
            var previous = Int.max
            for (i, entry) in ordered.enumerated() {
                if entry.value.plays < previous { place = i + 1; previous = entry.value.plays }
                ranks[entry.key] = place
            }
            self.ranks = ranks
            self.scanned = Date()
        }
    }

    /// Runs off the main thread through osascript so large libraries never stall the card.
    nonisolated private static func readLibrary() -> [String: Total]? {
        let script = """
        tell application id "com.apple.Music"
        set names to artist of every track of library playlist 1
        set plays to played count of every track of library playlist 1
        end tell
        set AppleScript's text item delimiters to (character id 31)
        set a to names as text
        set b to plays as text
        set AppleScript's text item delimiters to ""
        return a & (character id 30) & b
        """
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return nil }
        let watchdog = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        watchdog.cancel()
        guard task.terminationStatus == 0, var text = String(data: data, encoding: .utf8) else { return nil }
        if text.hasSuffix("\n") { text.removeLast() }
        let halves = text.components(separatedBy: "\u{1E}")
        guard halves.count == 2 else { return nil }
        let names = halves[0].components(separatedBy: "\u{1F}")
        let plays = halves[1].components(separatedBy: "\u{1F}")
        guard names.count == plays.count else { return nil }
        var out: [String: Total] = [:]
        for (name, count) in zip(names, plays) {
            let key = TitleTidy.key(name)
            guard !key.isEmpty else { continue }
            var t = out[key] ?? Total()
            t.songs += 1
            t.plays += Int(count) ?? 0
            out[key] = t
        }
        return out
    }
}
