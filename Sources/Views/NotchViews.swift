// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import SwiftUI

/// Black shape that hangs from the top edge of the screen: small outward curves where it
/// meets the edge, straight sides, and rounded lower corners.
struct NotchOutline: Shape {
    var bottom: CGFloat
    var flare: CGFloat = NotchGeometry.flare

    var animatableData: CGFloat {
        get { bottom }
        set { bottom = newValue }
    }

    func path(in r: CGRect) -> Path {
        let f = min(flare, r.width / 4)
        let b = min(bottom, (r.width - 2 * f) / 2, r.height - f)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + f, y: r.minY + f), control: CGPoint(x: r.minX + f, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + f, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + f + b, y: r.maxY), control: CGPoint(x: r.minX + f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - f - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - f, y: r.maxY - b), control: CGPoint(x: r.maxX - f, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - f, y: r.minY + f))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - f, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// Menu actions for the notch player.
struct NotchActions {
    var useFloating: () -> Void = {}
    var hide: () -> Void = {}
}

/// Reads the sound-bar setting so the notch view itself needs no settings object.
struct NotchHost: View {
    let hub: Hub

    var body: some View {
        NotchRoot(state: hub.notch.state, deck: hub.deck, pointer: hub.notchPointer, spectrum: hub.spectrum,
                  soundBars: hub.prefs.soundBars,
                  actions: NotchActions(useFloating: { hub.setNotchMode(false) }, hide: { hub.notch.hide() }))
    }
}

struct NotchRoot: View {
    let state: NotchState
    let deck: Deck
    let pointer: Pointer
    let spectrum: Spectrum
    let soundBars: Bool
    let actions: NotchActions

    var body: some View {
        let open = state.expanded
        let wings = deck.hasTrack
        let flare = NotchGeometry.flare
        let closedWidth = state.notch.width + (wings ? 2 * NotchGeometry.wing : 0)
        let width = (open ? state.open.width : closedWidth) + 2 * flare
        let height = open ? state.open.height : state.notch.height
        ZStack(alignment: .top) {
            NotchOutline(bottom: open ? 24 : min(10, state.notch.height / 3))
                .fill(Color.black)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(open ? 0.45 : 0), radius: 10, y: 4)
            Group {
                if open {
                    NotchPlayer(state: state, deck: deck, pointer: pointer, spectrum: spectrum, soundBars: soundBars,
                                actions: actions)
                        .frame(width: state.open.width, height: state.open.height, alignment: .top)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else if wings {
                    NotchWings(deck: deck, spectrum: spectrum, soundBars: soundBars, height: state.notch.height,
                               gap: state.notch.width)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(.named(Space.deck))
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: open)
        .animation(.easeInOut(duration: 0.25), value: wings)
    }
}

/// Closed view: the cover on the left of the notch, sound bars on the right.
struct NotchWings: View {
    let deck: Deck
    let spectrum: Spectrum
    let soundBars: Bool
    let height: CGFloat
    let gap: CGFloat

    var body: some View {
        let side = min(24, height - 7)
        HStack(spacing: 0) {
            NotchCover(deck: deck, side: side, corner: 5)
                .frame(width: NotchGeometry.wing, alignment: .center)
            Color.clear.frame(width: gap)
            Group {
                if soundBars {
                    SoundBars(spectrum: spectrum, playing: deck.isPlaying && EnergyPolicy.animates(deck.energyContext),
                              tint: deck.swatch.lead)
                } else {
                    Image(systemName: deck.isPlaying ? "waveform" : "pause.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(deck.swatch.lead)
                }
            }
            .frame(width: NotchGeometry.wing, alignment: .center)
        }
        .frame(height: height)
        .help(deck.track.title + " · " + deck.track.artist)
    }
}

struct NotchCover: View {
    let deck: Deck
    let side: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous).fill(Color.white.opacity(0.1))
            if let image = deck.cover {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "opticaldisc").font(.system(size: side * 0.55)).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: corner, style: .continuous))
        .id(deck.track.album)
        .transition(.opacity)
    }
}

/// Open view: a large cover on the left; song, artist, playback buttons and the playback bar on the right.
struct NotchPlayer: View {
    let state: NotchState
    let deck: Deck
    let pointer: Pointer
    let spectrum: Spectrum
    let soundBars: Bool
    let actions: NotchActions

    static let cover: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            // Keeps the camera area clear.
            Color.clear.frame(height: state.notch.height)
            if deck.hasTrack {
                HStack(alignment: .center, spacing: 16) {
                    Button { deck.revealApp() } label: {
                        NotchCover(deck: deck, side: Self.cover, corner: 12)
                    }
                    .buttonStyle(Squish())
                    .shadow(color: deck.swatch.ground.opacity(0.8), radius: 8, y: 3)
                    .help("Show \(deck.source.appName)")
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.track.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .lineLimit(1)
                                    .help(deck.track.title)
                                Text(deck.track.artist)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .help(deck.track.artist)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(deck.track.title + "\n" + deck.track.artist)
                            .transition(.opacity)
                            if soundBars {
                                SoundBars(spectrum: spectrum, playing: deck.isPlaying && EnergyPolicy.animates(deck.energyContext),
                                          tint: deck.swatch.lead)
                            }
                        }
                        Transport(deck: deck, pointer: pointer, scale: 1)
                            .frame(maxWidth: .infinity)
                            .zone(Zone.transport, pointer)
                        Scrubber(deck: deck, pointer: pointer, scale: 1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 22)
                .padding(.top, 10)
            } else {
                NotchIdle(deck: deck)
                    .padding(.horizontal, 22)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .contextMenu { NotchMenu(deck: deck, actions: actions) }
    }
}

struct NotchIdle: View {
    let deck: Deck

    var body: some View {
        let name = deck.source.appName
        VStack(spacing: 6) {
            Text(deck.controlBlocked ? "Allow Mini Deck to control \(name)"
                 : deck.appOpen ? "Nothing is playing" : "No music app is open")
                .font(.system(size: 15, weight: .semibold))
            Group {
                if deck.controlBlocked {
                    Button("Open Settings") { Players.openAutomationSettings() }
                } else if deck.appOpen {
                    Button("Bring \(name) Forward") { deck.revealApp() }
                } else {
                    HStack(spacing: 6) {
                        ForEach(Source.allCases.filter { Players.isInstalled($0) }) { app in
                            Button(app.appName) { Players.reveal(app) }
                        }
                    }
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }
}

struct NotchMenu: View {
    let deck: Deck
    let actions: NotchActions

    var body: some View {
        if deck.hasTrack {
            Button(deck.isPlaying ? "Pause" : "Play", action: deck.togglePlay)
            Button("Next Track", action: deck.skipForward)
            Button("Previous Track", action: deck.skipBack)
            Divider()
        }
        Button("Show Floating Player Instead", action: actions.useFloating)
        Button("Hide Player", action: actions.hide)
    }
}
