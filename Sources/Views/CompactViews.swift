// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import SwiftUI

struct CompactPlayingColumn: View {
    let deck: Deck
    let pointer: Pointer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.track.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .lineLimit(1)
                    Text(deck.track.artist)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ServiceBadge(deck: deck)
            }
            HStack(spacing: 4) {
                control("backward.end.fill", label: "Previous track", action: deck.skipBack)
                control(deck.isPlaying ? "pause.fill" : "play.fill",
                        label: deck.isPlaying ? "Pause" : "Play", action: deck.togglePlay)
                control("forward.end.fill", label: "Next track", action: deck.skipForward)
                Spacer(minLength: 0)
            }
            .zone(Zone.transport, pointer)
        }
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(deck.swatch.lead)
                .frame(width: 25, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(Squish())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Compact mode intentionally excludes album sections and all listening statistics.
struct CompactInfoDrawer: View {
    let deck: Deck
    let account: SpotifyAccount

    var body: some View {
        let notes = deck.albumNotes
        let album = deck.source == .spotify && account.currentAlbum?.trackID == deck.track.trackID
            ? account.currentAlbum?.album : nil
        VStack(alignment: .leading, spacing: 6) {
            Heading(text: "About this song")
            summary(deck.songNote ?? "\(deck.track.title) · \(deck.track.album)")
            if let date = ReleaseDateText.display(album?.release_date)
                ?? ReleaseDateText.display(notes?.releaseDate) {
                Text("Album released \(date)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Rule()
            Heading(text: notes?.artist?.kind == .band ? "About the band" : "About the artist")
            summary(notes?.artist?.summary ?? artistFallback)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artistFallback: String {
        let profile = deck.albumNotes?.artist
        let facts = [profile?.origin, profile?.genres.first].compactMap { $0 }
        return ([profile?.name ?? deck.creditedArtist] + facts).joined(separator: " · ")
    }

    private func summary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.primary.opacity(0.88))
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}
