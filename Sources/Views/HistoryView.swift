// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

enum HistorySource: String, CaseIterable, Identifiable {
    case spotify, music, mac
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spotify: "Spotify"
        case .music: "Apple Music"
        case .mac: "This Mac"
        }
    }
}

enum HistoryList: String, CaseIterable, Identifiable {
    case recent, songs, artists, albums
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recent: "Recent"
        case .songs: "Top Songs"
        case .artists: "Top Artists"
        case .albums: "Top Albums"
        }
    }
}

struct HistoryRow: Identifiable, Hashable {
    let rank: Int?
    let title: String
    let subtitle: String
    let detail: String
    var id: String { "\(rank ?? 0)\u{1F}\(title)\u{1F}\(subtitle)\u{1F}\(detail)" }
}

/// What the history window shows for one source and list.
struct HistoryPage {
    enum Empty: Equatable {
        case none
        case connectSpotify
        case reconnectSpotify
        case loading
        case openMusic
        case message(String)
    }
    var rows: [HistoryRow] = []
    var note = ""
    var empty: Empty = .none
}

/// Builds history lists from the Spotify account, the Music library and plays counted on this Mac.
@MainActor
enum HistoryBook {
    static func page(_ source: HistorySource, _ list: HistoryList, span: SpotifyAccount.Span, hub: Hub) -> HistoryPage {
        var page: HistoryPage
        switch source {
        case .spotify: page = spotify(list, span: span, account: hub.account)
        case .music: page = music(list, library: hub.library)
        case .mac: page = mac(list, log: hub.log, counting: hub.prefs.countPlays)
        }
        if page.rows.isEmpty && page.empty == .none {
            page.empty = .message("Nothing here yet. Keep listening.")
        }
        return page
    }

    private static func spotify(_ list: HistoryList, span: SpotifyAccount.Span, account: SpotifyAccount) -> HistoryPage {
        var page = HistoryPage()
        switch account.status {
        case .off, .failed: page.empty = .connectSpotify; return page
        case .expired: page.empty = .reconnectSpotify; return page
        case .waiting: page.empty = .message("Finish signing in to Spotify in your browser."); return page
        case .on: break
        }
        if account.updated == nil { page.empty = .loading; return page }
        switch list {
        case .recent:
            page.rows = account.recent.map { HistoryRow(rank: nil, title: $0.title, subtitle: $0.artist, detail: StatsBook.ago($0.at)) }
            page.note = "Your last \(account.recent.count) plays on any device, from Spotify."
        case .songs:
            page.rows = (account.topSongs[span] ?? []).enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.title, subtitle: $0.element.subtitle, detail: "")
            }
            page.note = "Your top songs over the last \(span.label), from Spotify."
        case .artists:
            page.rows = (account.topArtists[span] ?? []).enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.title, subtitle: "", detail: "")
            }
            page.note = "Your top artists over the last \(span.label), from Spotify."
        case .albums:
            // Spotify has no top-albums list, so count how many of your top songs come from each album.
            var counts: [String: (album: String, artist: String, songs: Int, best: Int)] = [:]
            for (i, song) in (account.topSongs[span] ?? []).enumerated() where !song.album.isEmpty {
                let key = TitleTidy.key(song.album) + "/" + (song.artistKeys.first ?? "")
                var entry = counts[key] ?? (song.album, song.subtitle, 0, i + 1)
                entry.songs += 1
                entry.best = min(entry.best, i + 1)
                counts[key] = entry
            }
            let ordered = counts.values.sorted { $0.songs != $1.songs ? $0.songs > $1.songs : $0.best < $1.best }
            page.rows = ordered.enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.album, subtitle: $0.element.artist,
                           detail: $0.element.songs == 1 ? "1 top song" : "\($0.element.songs) top songs")
            }
            page.note = "Albums ranked by how many of your top 50 songs (last \(span.label)) they hold."
        }
        return page
    }

    private static func music(_ list: HistoryList, library: MusicLibrary) -> HistoryPage {
        var page = HistoryPage()
        if library.scanned == nil {
            page.empty = library.scanning ? .loading : (Players.isRunning(.music) ? .loading : .openMusic)
            return page
        }
        switch list {
        case .recent:
            page.rows = library.recentlyPlayed.map {
                HistoryRow(rank: nil, title: $0.title, subtitle: $0.artist, detail: $0.lastPlayed.map(StatsBook.ago) ?? "")
            }
            page.note = "Songs by the last time you played them, from your Music library."
        case .songs:
            page.rows = library.mostPlayed.enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.title, subtitle: $0.element.artist,
                           detail: StatsBook.plays($0.element.plays))
            }
            page.note = "Most played songs of all time, from your Music library."
        case .artists:
            page.rows = library.topArtists.enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.name,
                           subtitle: $0.element.total.songs == 1 ? "1 song" : "\($0.element.total.songs) songs",
                           detail: StatsBook.plays($0.element.total.plays))
            }
            page.note = "Artists by total plays, from your Music library."
        case .albums:
            page.rows = library.topAlbums.enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.album, subtitle: $0.element.artist,
                           detail: StatsBook.plays($0.element.plays))
            }
            page.note = "Albums by total plays, from your Music library."
        }
        if let scanned = library.scanned {
            page.note += " Updated \(StatsBook.ago(scanned).lowercased())."
        }
        return page
    }

    private static func mac(_ list: HistoryList, log: ListeningLog, counting: Bool) -> HistoryPage {
        var page = HistoryPage()
        if log.isEmpty {
            page.empty = .message(counting ? "Mini Deck hasn't counted any plays yet. A song counts after 30 seconds."
                                           : "Turn on Count Plays on This Mac in the menu bar to build this history.")
            return page
        }
        switch list {
        case .recent:
            page.rows = log.recentSongs().map {
                HistoryRow(rank: nil, title: $0.title, subtitle: $0.artist, detail: StatsBook.ago($0.last))
            }
        case .songs:
            page.rows = log.topSongs().enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.title, subtitle: $0.element.artist,
                           detail: StatsBook.plays($0.element.plays))
            }
        case .artists:
            page.rows = log.topArtists().enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.name, subtitle: StatsBook.plays($0.element.plays),
                           detail: StatsBook.duration($0.element.seconds))
            }
        case .albums:
            page.rows = log.topAlbums().enumerated().map {
                HistoryRow(rank: $0.offset + 1, title: $0.element.album, subtitle: $0.element.artist,
                           detail: StatsBook.duration($0.element.seconds))
            }
        }
        page.note = "Counted by Mini Deck on this Mac since \(StatsBook.shortDate(log.book.since)). Spotify and Music combined."
        return page
    }
}

struct HistoryView: View {
    let hub: Hub
    @State private var source: HistorySource
    @State private var list: HistoryList = .recent
    @State private var span: SpotifyAccount.Span = .short

    init(hub: Hub) {
        self.hub = hub
        _source = State(initialValue: hub.deck.source == .music ? .music : .spotify)
    }

    var body: some View {
        let page = HistoryBook.page(source, list, span: span, hub: hub)
        VStack(alignment: .leading, spacing: 10) {
            Picker("Source", selection: $source) {
                ForEach(HistorySource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Picker("List", selection: $list) {
                    ForEach(HistoryList.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if source == .spotify && list != .recent {
                    Picker("Time", selection: $span) {
                        ForEach(SpotifyAccount.Span.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                }
            }

            if page.rows.isEmpty {
                emptyState(page.empty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(page.rows.enumerated()), id: \.offset) { item in HistoryRowView(row: item.element) }
                    .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            if !page.note.isEmpty {
                Text(page.note).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(minWidth: 440, minHeight: 420)
        .onAppear { hub.refreshHistory() }
        .onChange(of: source) { hub.refreshHistory() }
    }

    @ViewBuilder
    private func emptyState(_ empty: HistoryPage.Empty) -> some View {
        VStack(spacing: 10) {
            switch empty {
            case .none:
                EmptyView()
            case .loading:
                ProgressView()
                Text("Loading your history…").foregroundStyle(.secondary)
            case .connectSpotify:
                Text("Connect your Spotify account to see your recent plays and top songs, artists and albums.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Connect Spotify…") { hub.askToConnectSpotify() }
            case .reconnectSpotify:
                Text("Your Spotify sign-in expired.").foregroundStyle(.secondary)
                Button("Reconnect…") { hub.askToConnectSpotify() }
            case .openMusic:
                Text("Open the Music app so Mini Deck can read your library's play history.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button("Open Music") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Source.music.bundle) {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { hub.refreshHistory() }
                }
            case .message(let text):
                Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }
}

struct HistoryRowView: View {
    let row: HistoryRow

    var body: some View {
        HStack(spacing: 10) {
            if let rank = row.rank {
                Text("\(rank)")
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if !row.detail.isEmpty {
                Text(row.detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A normal window for the history list. Reused while open.
@MainActor
final class HistoryWindow {
    private var window: NSWindow?

    func show(hub: Hub) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Listening History"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: HistoryView(hub: hub))
            w.setFrameAutosaveName("MiniDeckHistory")
            if !w.setFrameUsingName("MiniDeckHistory") { w.center() }
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
