// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import SwiftUI

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
