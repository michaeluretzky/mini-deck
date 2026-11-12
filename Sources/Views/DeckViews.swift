// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

struct DeckRoot: View {
    let hub: Hub

    var body: some View {
        DeckCard(hub: hub, deck: hub.deck, pointer: hub.pointer, spectrum: hub.spectrum, stage: hub.stage, prefs: hub.prefs)
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in
                Color.clear.onChange(of: g.size.height, initial: true) { _, height in
                    DispatchQueue.main.async { hub.stage.fit(height: height, growDown: hub.pointer.drawerOpen) }
                }
            })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .coordinateSpace(.named(Space.deck))
    }
}

struct DeckCard: View {
    let hub: Hub
    let deck: Deck
    let pointer: Pointer
    let spectrum: Spectrum
    let stage: Stage
    let prefs: Prefs

    var body: some View {
        let sw = deck.swatch
        let hot = pointer.over(Zone.card)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                CoverTile(deck: deck, pointer: pointer)
                Group {
                    if deck.hasTrack {
                        NowPlayingColumn(deck: deck, pointer: pointer, spectrum: spectrum, prefs: prefs)
                    } else {
                        IdleColumn(deck: deck)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if pointer.drawerOpen && deck.hasTrack {
                Capsule()
                    .fill(LinearGradient(colors: [sw.lead.opacity(0.45), sw.echo.opacity(0.1)], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                InfoDrawer(hub: hub, deck: deck)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .padding(Metrics.inset)
        .frame(width: Metrics.card, alignment: .topLeading)
        .background { Backdrop(swatch: sw) }
        .overlay(alignment: .topTrailing) { HUDBadge(message: deck.hud, swatch: sw) }
        .clipShape(.rect(cornerRadius: Metrics.corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .strokeBorder(LinearGradient(colors: [sw.lead.opacity(hot ? 0.75 : 0.5), sw.echo.opacity(hot ? 0.45 : 0.2)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .environment(\.colorScheme, .dark)
        .contentShape(.rect)
        .zone(Zone.card, pointer)
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { _ in pointer.frozen = true; stage.dragMoved() }
            .onEnded { _ in stage.dragEnded(); pointer.frozen = false })
        .contextMenu { CardMenu(hub: hub, deck: deck, stage: stage, prefs: prefs) }
        .padding(Metrics.halo)
        .background { Halo(swatch: sw, spectrum: spectrum, playing: deck.isPlaying) }
        .animation(.smooth(duration: 0.25), value: pointer.drawerOpen)
        .animation(.easeInOut(duration: 0.25), value: deck.track.title)
        .animation(.easeInOut(duration: 0.7), value: sw)
        .animation(.easeOut(duration: 0.15), value: deck.hud)
    }
}

struct CoverTile: View {
    let deck: Deck
    let pointer: Pointer

    var body: some View {
        let hot = deck.hasTrack && pointer.over(Zone.cover)
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.08))
            if deck.hasTrack, let image = deck.cover {
                // already sized to this screen's pixels, so draw 1:1
                Image(nsImage: image)
                    .interpolation(.none)
                    .frame(width: Metrics.cover, height: Metrics.cover)
                    .id(deck.track.album)
                    .transition(.opacity)
            } else {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if deck.hasTrack {
                Image(systemName: "text.below.photo.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.55))
                    .font(.system(size: 13))
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.45)))
                    .padding(5)
                    .opacity(hot ? 1 : 0)
            }
        }
        .frame(width: Metrics.cover, height: Metrics.cover)
        .clipShape(.rect(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(hot ? 0.4 : 0.06), lineWidth: hot ? 1.5 : 1)
        }
        .shadow(color: deck.swatch.ground.opacity(0.9), radius: 6, y: 3)
        .zone(Zone.cover, pointer)
        .onTapGesture(count: 2) { deck.revealApp() }
        .help("Rest the pointer here for the song, the artist and your listening stats. Double-click to open \(deck.source.appName).")
        .animation(.easeOut(duration: 0.15), value: hot)
    }
}

struct NowPlayingColumn: View {
    let deck: Deck
    let pointer: Pointer
    let spectrum: Spectrum
    let prefs: Prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: 7) {
                    if prefs.soundBars {
                        SoundBars(spectrum: spectrum, playing: deck.isPlaying, tint: deck.swatch.lead)
                            .padding(.top, 4)
                    }
                    Text("\(Text(deck.track.title).font(.system(size: 16, weight: .bold)))\(Text("  ·  ").foregroundStyle(.tertiary))\(Text(deck.track.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary))")
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(deck.track.album)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(deck.track.title + "\n" + deck.track.artist)
            .transition(.opacity)

            Transport(deck: deck, pointer: pointer)
                .frame(maxWidth: .infinity)
                .zone(Zone.transport, pointer)

            Scrubber(deck: deck, pointer: pointer)
        }
    }
}

struct IdleColumn: View {
    let deck: Deck

    var body: some View {
        let name = deck.source.appName
        VStack(alignment: .leading, spacing: 7) {
            Text(deck.appOpen ? "Nothing is playing" : "No music app is open")
                .font(.system(size: 15, weight: .semibold))
            Text(deck.appOpen ? "Start a song in \(name) and it will appear here."
                              : "Open Spotify or Apple Music to control it from here.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if deck.appOpen {
                Button("Bring \(name) Forward") { deck.revealApp() }
                    .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    ForEach(Source.allCases.filter { Players.isInstalled($0) }) { app in
                        Button(app.appName) { Players.reveal(app) }
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Transport

struct Squish: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct Pad: View {
    let symbol: String
    var size: CGFloat = 14
    var lit: Bool?
    let tip: String
    let tint: Color
    let pointer: Pointer
    let act: () -> Void

    var body: some View {
        let id = "pad." + symbol
        let hot = pointer.over(id)
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(lit == true ? tint : Color.primary)
                .opacity(lit == false ? (hot ? 0.75 : 0.4) : (hot ? 1 : 0.8))
                .frame(width: 30, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(Squish())
        .zone(id, pointer)
        .overlay(alignment: .bottom) {
            if lit == true { Circle().fill(tint).frame(width: 3, height: 3).offset(y: 2) }
        }
        .scaleEffect(hot ? 1.1 : 1)
        .animation(.easeOut(duration: 0.12), value: hot)
        .help(tip)
    }
}

struct PlayDisc: View {
    let playing: Bool
    let fill: Color
    let glyph: Color
    let pointer: Pointer
    let act: () -> Void

    var body: some View {
        let hot = pointer.over("pad.play")
        Button(action: act) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(glyph)
                .offset(x: playing ? 0 : 1)
                .frame(width: 36, height: 36)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(Squish())
        .zone("pad.play", pointer)
        .scaleEffect(hot ? 1.07 : 1)
        .animation(.easeOut(duration: 0.12), value: hot)
        .help(playing ? "Pause" : "Play")
    }
}

struct Transport: View {
    let deck: Deck
    let pointer: Pointer

    var body: some View {
        let tint = deck.swatch.lead
        HStack(spacing: 8) {
            Pad(symbol: "shuffle", size: 12, lit: deck.track.shuffle,
                tip: deck.track.shuffle ? "Turn shuffle off" : "Turn shuffle on", tint: tint, pointer: pointer, act: deck.toggleShuffle)
            Pad(symbol: "backward.end.fill", tip: "Previous track", tint: tint, pointer: pointer, act: deck.skipBack)
            PlayDisc(playing: deck.isPlaying, fill: tint, glyph: deck.swatch.ground, pointer: pointer, act: deck.togglePlay)
            Pad(symbol: "forward.end.fill", tip: "Next track", tint: tint, pointer: pointer, act: deck.skipForward)
            Pad(symbol: "repeat", size: 12, lit: deck.track.loop,
                tip: deck.track.loop ? "Turn repeat off" : "Turn repeat on", tint: tint, pointer: pointer, act: deck.toggleRepeat)
        }
    }
}

enum Clock {
    static func short(_ t: Double) -> String {
        let s = max(0, Int(t))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? "\(h):\(two(m)):\(two(sec))" : "\(m):\(two(sec))"
    }

    private static func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

    static func runtime(_ seconds: Int) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        f.unitsStyle = .short
        return f.string(from: TimeInterval(max(60, seconds))) ?? ""
    }
}

struct Scrubber: View {
    let deck: Deck
    let pointer: Pointer
    private var dragFraction: Double? { pointer.scrub }

    var body: some View {
        TimelineView(.periodic(from: .now, by: deck.isPlaying ? 0.25 : 30)) { context in
            let length = deck.track.length
            let played = deck.elapsed(at: context.date)
            let fraction = dragFraction ?? (length > 0 ? played / length : 0)
            let shown = dragFraction.map { $0 * length } ?? played
            VStack(spacing: 2) {
                bar(fraction)
                HStack {
                    Text(Clock.short(shown))
                        .foregroundStyle(dragFraction == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(deck.swatch.lead))
                    Spacer()
                    Text("-" + Clock.short(max(0, length - shown)))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
            }
        }
    }

    private func bar(_ fraction: Double) -> some View {
        let hot = pointer.over(Zone.scrubber) || dragFraction != nil
        return GeometryReader { g in
            let w = max(1, g.size.width)
            let h: CGFloat = hot ? 6 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: h)
                Capsule()
                    .fill(LinearGradient(colors: [deck.swatch.lead, deck.swatch.echo], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(h, w * fraction), height: h)
                Circle().fill(Color.white)
                    .frame(width: 11, height: 11)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                    .offset(x: w * fraction - 5.5)
                    .opacity(hot ? 1 : 0)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in pointer.scrub = min(1, max(0, v.location.x / w)) }
                .onEnded { v in
                    deck.seek(fraction: min(1, max(0, v.location.x / w)))
                    pointer.scrub = nil
                })
        }
        .frame(height: 14)
        .zone(Zone.scrubber, pointer)
        .animation(.easeOut(duration: 0.12), value: hot)
        .help("Click or drag to move through the track")
    }
}

// MARK: - Sound bars and glow

struct SoundBars: View {
    let spectrum: Spectrum
    let playing: Bool
    let tint: Color

    var body: some View {
        Group {
            if spectrum.feed == .imitation && playing {
                TimelineView(.animation(minimumInterval: 1.0 / 24)) { context in
                    columns(Imitation.levels(at: context.date.timeIntervalSinceReferenceDate))
                }
            } else {
                columns(playing && spectrum.feed == .live ? spectrum.bands : [])
            }
        }
        .frame(width: 21, height: 14, alignment: .bottom)
        .help(spectrum.feed == .live ? "Following the music"
              : "To make these follow the music, allow Mini Deck in System Settings > Privacy & Security > Screen & System Audio Recording")
    }

    private func columns(_ levels: [Float]) -> some View {
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                let v = i < levels.count ? CGFloat(min(1, max(0, levels[i]))) : 0
                RoundedRectangle(cornerRadius: 1).fill(tint).frame(width: 3, height: 2.5 + 11.5 * v)
            }
        }
        .frame(height: 14, alignment: .bottom)
        .animation(.linear(duration: 0.06), value: levels)
    }
}

struct Halo: View {
    let swatch: Swatch
    let spectrum: Spectrum
    let playing: Bool

    var body: some View {
        let kick = (spectrum.feed == .live && playing) ? Double(spectrum.bands.first ?? 0) : 0
        RoundedRectangle(cornerRadius: Metrics.corner + 2, style: .continuous)
            .fill(AngularGradient(colors: [swatch.lead, swatch.echo, swatch.lead], center: .center))
            .padding(Metrics.halo - 5)
            .blur(radius: 13)
            .opacity((playing ? Metrics.glow : Metrics.glow * 0.56) + 0.4 * kick)
            .animation(.easeOut(duration: 0.12), value: kick)
    }
}

struct FrostedGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct Backdrop: View {
    let swatch: Swatch

    var body: some View {
        ZStack {
            FrostedGlass()
            swatch.ground.opacity(0.84)
            LinearGradient(colors: [swatch.lead.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .center)
            EllipticalGradient(colors: [swatch.echo.opacity(0.4), .clear], center: .bottomTrailing,
                               startRadiusFraction: 0, endRadiusFraction: 0.75)
        }
    }
}

struct HUDBadge: View {
    let message: HUDMessage?
    let swatch: Swatch

    var body: some View {
        if let message {
            Label(message.text, systemImage: message.symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(swatch.ground.opacity(0.94), in: Capsule())
                .overlay(Capsule().strokeBorder(swatch.lead.opacity(0.45), lineWidth: 1))
                .foregroundStyle(.white)
                .padding(9)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}

// MARK: - Hover drawer: the music, the artist, your listening

struct Heading: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.9)
            .foregroundStyle(.secondary)
    }
}

struct Blurb: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.primary.opacity(0.88))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Waiting: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct Quiet: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct FactChip: View {
    let symbol: String
    let text: String
    let tint: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
            Text(text).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }
    }
}

/// Lays chips out left to right and wraps to a new line when they run out of room.
struct Flow: Layout {
    var spacing: CGFloat = 12
    var lineSpacing: CGFloat = 5

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], sizes: [CGSize], size: CGSize) {
        var points: [CGPoint] = [], sizes: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += line + lineSpacing
                line = 0
            }
            points.append(CGPoint(x: x, y: y))
            sizes.append(size)
            widest = max(widest, x + size.width)
            line = max(line, size.height)
            x += size.width + spacing
        }
        return (points, sizes, CGSize(width: min(widest, width), height: y + line))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let laid = arrange(bounds.width, subviews)
        for (i, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + laid.points[i].x, y: bounds.minY + laid.points[i].y),
                       anchor: .topLeading, proposal: ProposedViewSize(laid.sizes[i]))
        }
    }
}

struct InfoDrawer: View {
    let hub: Hub
    let deck: Deck

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            MusicSection(deck: deck)
            Rule()
            ArtistSection(deck: deck)
            Rule()
            ListeningSection(hub: hub, deck: deck)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Rule: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
}

extension Deck {
    var albumNotes: AlbumNotes? {
        if case .found(let n) = notes { return n }
        return nil
    }
    var notesPending: Bool { notes == .idle || notes == .loading }
}

/// 1. About this song and album.
struct MusicSection: View {
    let deck: Deck

    var body: some View {
        let n = deck.albumNotes
        VStack(alignment: .leading, spacing: 6) {
            Heading(text: "About this song & album")
            if let note = deck.songNote {
                Blurb(text: note)
            }
            if let n, n.hasFacts {
                Flow {
                    if let year = n.year { FactChip(symbol: "calendar", text: "Released \(year)", tint: deck.swatch.lead) }
                    if let count = n.songCount {
                        FactChip(symbol: "music.note.list", text: count == 1 ? "1 song" : "\(count) songs", tint: deck.swatch.lead)
                    }
                    if let seconds = n.runtime { FactChip(symbol: "clock", text: Clock.runtime(seconds), tint: deck.swatch.lead) }
                    if let genre = n.genre { FactChip(symbol: "tag", text: genre, tint: deck.swatch.lead) }
                }
            }
            if let summary = n?.summary {
                Blurb(text: summary)
            }
            if deck.notesPending {
                Waiting(text: "Looking up the album…")
            } else if deck.songNote == nil && n?.summary == nil && n?.hasFacts != true {
                Quiet(text: "No details found for this song or album.")
            }
        }
    }
}

/// 2. About the artist or band.
struct ArtistSection: View {
    let deck: Deck

    var body: some View {
        let p = deck.albumNotes?.artist
        VStack(alignment: .leading, spacing: 6) {
            Heading(text: p?.kind == .band ? "About the band" : "About the artist")
            Text(p?.name ?? deck.creditedArtist)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let p, p.hasFacts {
                Flow {
                    if let origin = p.origin { FactChip(symbol: "mappin.and.ellipse", text: origin, tint: deck.swatch.lead) }
                    if let years = years(p) { FactChip(symbol: "calendar", text: years, tint: deck.swatch.lead) }
                    if !p.genres.isEmpty {
                        FactChip(symbol: "guitars", text: p.genres.joined(separator: " · "), tint: deck.swatch.lead)
                    }
                }
            }
            if let bio = p?.summary {
                Blurb(text: bio)
            } else if deck.notesPending {
                Waiting(text: "Looking up the artist…")
            } else if p?.hasFacts != true {
                Quiet(text: "No artist details found.")
            }
        }
    }

    private func years(_ p: ArtistProfile) -> String? {
        guard let began = p.began else { return nil }
        if let ended = p.ended { return "\(began)–\(ended)" }
        switch p.kind {
        case .band: return "Formed \(began)"
        case .person: return "Born \(began)"
        case .other: return "Since \(began)"
        }
    }
}

/// 3. The user's own listening numbers.
struct ListeningSection: View {
    let hub: Hub
    let deck: Deck

    var body: some View {
        let report = StatsBook.report(track: deck.track, facts: deck.facts, account: hub.account,
                                      library: hub.library, log: hub.log, counting: hub.prefs.countPlays)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Heading(text: "Your listening")
                Spacer(minLength: 0)
                Button { hub.showHistory() } label: {
                    Label("History", systemImage: "clock.arrow.circlepath").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(deck.swatch.lead)
                .help("Open your full listening history")
            }
            ScopeBlock(title: "This song", scope: report.song, tint: deck.swatch.lead)
            ScopeBlock(title: "This artist", scope: report.artist, tint: deck.swatch.lead)
            ScopeBlock(title: "This album", scope: report.album, tint: deck.swatch.lead)
            prompt(report.prompt)
            if report.isEmpty && report.prompt == .none {
                Quiet(text: hub.prefs.countPlays ? "Keep listening and your stats for this song, artist and album will appear here."
                                                 : "Turn on Count Plays on This Mac in the menu bar to see stats here.")
            }
        }
    }

    @ViewBuilder
    private func prompt(_ p: ListeningReport.Prompt) -> some View {
        switch p {
        case .none:
            EmptyView()
        case .loading:
            Waiting(text: "Loading your stats…")
        case .waiting:
            HStack(spacing: 8) {
                Waiting(text: "Finish signing in to Spotify in your browser.")
                Spacer(minLength: 0)
                Button("Cancel") { hub.account.cancelSignIn() }.controlSize(.mini)
            }
        case .connectSpotify:
            action("Connect Spotify to see where this song and artist rank for you.", "Connect…")
        case .reconnectSpotify:
            action("Your Spotify sign-in expired.", "Reconnect…")
        case .problem(let why):
            action(why, "Try Again…")
        }
    }

    private func action(_ text: String, _ label: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Quiet(text: text)
            Spacer(minLength: 0)
            Button(label) { hub.askToConnectSpotify() }.controlSize(.small)
        }
    }
}

/// Tiles and a short song list for one subject: the song, the artist or the album.
struct ScopeBlock: View {
    let title: String
    let scope: StatScope
    let tint: Color

    var body: some View {
        if !scope.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.primary.opacity(0.85))
                if !scope.tiles.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .topLeading), count: 3),
                              alignment: .leading, spacing: 6) {
                        ForEach(Array(scope.tiles.enumerated()), id: \.offset) { item in StatCell(tile: item.element, tint: tint) }
                    }
                }
                if !scope.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(scope.linesTitle).font(.system(size: 9.5)).foregroundStyle(.secondary)
                        ForEach(Array(scope.lines.enumerated()), id: \.offset) { i, line in
                            HStack(spacing: 6) {
                                Text("\(i + 1)").font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(tint).frame(width: 12, alignment: .trailing)
                                Text(line.title).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(line.detail).font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04), in: .rect(cornerRadius: 7, style: .continuous))
                }
                Text(scope.caption).font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct StatCell: View {
    let tile: StatTile
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol = tile.symbol {
                    Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).foregroundStyle(tint)
                }
                Text(tile.value)
                    .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(tile.caption)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.06), in: .rect(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Right-click menu

struct CardMenu: View {
    let hub: Hub
    let deck: Deck
    let stage: Stage
    let prefs: Prefs

    var body: some View {
        if deck.hasTrack {
            Button(deck.isPlaying ? "Pause" : "Play", action: deck.togglePlay)
            Button("Next Track", action: deck.skipForward)
            Button("Previous Track", action: deck.skipBack)
            Divider()
            Toggle("Shuffle", isOn: Binding(get: { deck.track.shuffle }, set: { _ in deck.toggleShuffle() }))
            Toggle("Repeat", isOn: Binding(get: { deck.track.loop }, set: { _ in deck.toggleRepeat() }))
            Divider()
            if deck.source == .spotify {
                Button("Copy Track Link", action: deck.copyLink).disabled(deck.shareURL == nil)
            }
        }
        Toggle("Sound Bars", isOn: Binding(get: { prefs.soundBars }, set: { prefs.soundBars = $0 }))
        Button(deck.appOpen ? "Show \(deck.source.appName)" : "Open \(deck.source.appName)") { deck.revealApp() }
        if deck.source == .spotify && !hub.account.isConnected && hub.account.status != .waiting {
            Button("Connect Spotify Account…") { hub.askToConnectSpotify() }
        }
        Divider()
        Menu("Move To") {
            ForEach(Corner.allCases) { corner in
                Button(corner.title) { stage.park(at: corner) }
            }
        }
        Button("Hide Player") { stage.hide() }
    }
}
