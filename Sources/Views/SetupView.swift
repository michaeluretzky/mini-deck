// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import SwiftUI

@MainActor @Observable
final class SetupPicks {
    var step = min(3, max(0, UserDefaults.standard.integer(forKey: "minideck.setupStep"))) {
        didSet { UserDefaults.standard.set(step, forKey: "minideck.setupStep") }
    }
    var manualStep = 0
    var clientID = ""
    var notice = ""
}

struct SetupView: View {
    let hub: Hub
    let picks: SetupPicks
    let close: () -> Void
    private let steps = ["Playback", "Full account history", "Live Spotify (optional)", "Help & finish"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Set up Mini Deck").font(.system(size: 26, weight: .bold))
                Text("Start with playback. Add full account history without creating a developer app.")
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(steps.indices, id: \.self) { index in
                        Button {
                            picks.step = index
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: complete(index) ? "checkmark.circle.fill" : "\(index + 1).circle")
                                    .foregroundStyle(complete(index) ? Color.green : Color.secondary)
                                Text(steps[index]).font(.system(size: 12, weight: .medium))
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(picks.step == index ? Color.accentColor.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    Text("Your progress is saved.\nOptional steps can be skipped.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .padding(12).frame(width: 205)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch picks.step {
                        case 0: playback
                        case 1: history
                        case 2: spotify
                        default: help
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(22)
                }
            }
            Divider()
            HStack {
                Button("Back") { picks.step = max(0, picks.step - 1) }.disabled(picks.step == 0)
                Spacer()
                Button("Use Mini Deck now", action: close)
                if picks.step < 3 {
                    Button("Continue") { picks.step += 1 }.buttonStyle(.borderedProminent)
                } else {
                    Button("Done", action: close).buttonStyle(.borderedProminent)
                }
            }.padding(16)
        }
        .frame(minWidth: 720, minHeight: 570)
    }

    private func complete(_ step: Int) -> Bool {
        switch step {
        case 0: hub.deck.hasTrack
        case 1: hub.archive.hasHistory
        case 2: hub.account.isConnected
        default: false
        }
    }

    private var playback: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your player, automatically detected").font(.title2.bold())
            Text("Open Spotify or Music and play a song. Mini Deck follows the active app automatically; no developer setup is needed for playback controls.")
            Label(Players.isInstalled(.spotify) ? "Spotify is installed" : "Spotify was not found",
                  systemImage: Players.isInstalled(.spotify) ? "checkmark.circle" : "info.circle")
            Label(Players.isInstalled(.music) ? "Music is installed" : "Music was not found",
                  systemImage: Players.isInstalled(.music) ? "checkmark.circle" : "info.circle")
            Label(hub.deck.hasTrack ? "Playback is being detected" : "Waiting for a playing track",
                  systemImage: hub.deck.hasTrack ? "waveform" : "clock")
                .foregroundStyle(hub.deck.hasTrack ? Color.green : Color.secondary)
            HStack {
                Button("Open Spotify") { Players.reveal(.spotify) }.disabled(!Players.isInstalled(.spotify))
                Button("Open Music") { Players.reveal(.music) }.disabled(!Players.isInstalled(.music))
            }
            Divider()
            Text("If macOS asks to let Mini Deck control Spotify or Music, choose Allow to enable playback detection. You remain in control of all permissions.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Automation settings") {
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Full account history, no developer app").font(.title2.bold())
            Text("Spotify's Extended Streaming History export contains listening records across your devices. Mini Deck calculates song, artist and album totals locally.")
            instruction("Request the right export", "Open Spotify's privacy page, find Download your data, and request Extended streaming history. Spotify requires your sign-in and confirmation, and prepares the export separately.")
            Button("Open Spotify data request") { open("https://www.spotify.com/account/privacy/") }
                .buttonStyle(.borderedProminent)
            instruction("Download and unzip", "When Spotify makes it available, download the export and unzip it. Keep all Streaming_History_Audio JSON files together; selecting only some files gives partial history.")
            instruction("Import once, or automate future imports", "Choose the JSON files now, or select an export folder once. Automatic import checks only that folder, waits for stable files, and deduplicates repeats.")
            HStack {
                Button(hub.archive.busy ? "Importing…" : "Choose history files…") { hub.importSpotifyHistory() }
                    .disabled(hub.archive.busy || hub.archive.loading)
                Button("Choose auto-import folder…") { hub.chooseAutoImportFolder() }
            }
            if let folder = hub.archive.watchedFolderName {
                Label("Auto-import enabled: \(folder)", systemImage: "folder.badge.gearshape")
                Button("Stop automatic imports") { hub.archive.stopWatching() }
            }
            if hub.archive.hasHistory {
                Label("\(hub.archive.snapshot.events.count) music records imported", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(hub.archive.coverage).font(.callout).foregroundStyle(.secondary)
            }
            if !hub.archive.message.isEmpty { Text(hub.archive.message).font(.callout).foregroundStyle(.secondary) }
            Text("Only music metadata and play timing are retained. IP addresses, device details and locations are discarded. The export stays on your Mac; it is not uploaded.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Spotify: what the export includes", destination: URL(string: "https://support.spotify.com/us/article/understanding-your-data/")!)
        }
    }

    private var spotify: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live account stats are optional").font(.title2.bold())
            Text("Connect for Spotify's recent plays and top rankings across devices. You can skip this entirely if you use the full-history import.")
            if hub.account.isConnected {
                Label("Spotify account connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Your saved connection is reused automatically. Mini Deck refreshes live data while it runs.")
            } else if hub.account.status == .waiting {
                ProgressView()
                Text("Finish Spotify's sign-in and approval in your browser. This guide updates automatically when it succeeds.")
                Button("Cancel sign-in") { hub.account.cancelSignIn() }
            } else {
                if let clientID = SpotifyAccount.bundledClientID {
                    Button("Connect Spotify") { hub.account.connect(clientID: clientID) }
                        .buttonStyle(.borderedProminent)
                    Text("This build includes a distributor-provided public Client ID. Spotify still requires your sign-in and approval; access depends on that registration's quota/allowlist.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                manualSpotify
            }
            switch hub.account.status {
            case .failed(let why): Text(why).foregroundStyle(.red).textSelection(.enabled)
            case .expired: Text("Your connection expired. Reconnect using the setup below.").foregroundStyle(.secondary)
            default: EmptyView()
            }
            Link("Spotify's developer access rules", destination: URL(string: "https://developer.spotify.com/documentation/web-api/concepts/quota-modes")!)
                .font(.caption)
        }
    }

    private var manualSpotify: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Text("Guided manual setup").font(.headline)
            Text("Step \(picks.manualStep + 1) of 4").font(.caption).foregroundStyle(.secondary)
            switch picks.manualStep {
            case 0:
                instruction("Create your Spotify app", "Open the Developer Dashboard and choose Create app. Use Mini Deck as the name and Personal music statistics as the description. Development-mode app owners need Spotify Premium. Review and accept Spotify's terms yourself.")
                Button("Open Developer Dashboard") { open("https://developer.spotify.com/dashboard") }
                Button("Copy app name") { copy("Mini Deck") }
            case 1:
                instruction("Add the redirect and API", "Paste this exact Redirect URI, click Add, select Web API only, and save. Do not change http to https or replace 127.0.0.1 with localhost.")
                Text(SpotifyAccount.redirect).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Button("Copy redirect URI") { copy(SpotifyAccount.redirect) }
            case 2:
                instruction("Get your Client ID", "Open the app's Settings and copy Client ID, not Client Secret. If this registration belongs to someone else, its owner must add your account in User Management before account stats will work.")
                Button("Open Developer Dashboard") { open("https://developer.spotify.com/dashboard") }
            default:
                instruction("Paste and connect", "Paste the 32-character Client ID below, then approve Spotify's sign-in in your browser. Never enter your password or Client Secret here.")
                HStack {
                    TextField("Spotify Client ID", text: Binding(get: { picks.clientID }, set: { picks.clientID = $0 }))
                        .textFieldStyle(.roundedBorder)
                    Button("Paste") {
                        picks.clientID = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        picks.notice = SpotifyAccount.looksLikeClientID(picks.clientID) ? "Client ID format looks valid." : "Expected a 32-character hexadecimal Client ID."
                    }
                }
                Button("Connect Spotify") { hub.account.connect(clientID: picks.clientID) }
                    .disabled(!SpotifyAccount.looksLikeClientID(picks.clientID.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .buttonStyle(.borderedProminent)
            }
            if !picks.notice.isEmpty { Text(picks.notice).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Previous step") { picks.manualStep = max(0, picks.manualStep - 1); picks.notice = "" }
                    .disabled(picks.manualStep == 0)
                Spacer()
                if picks.manualStep < 3 {
                    Button("I've done this · Next") { picks.manualStep += 1; picks.notice = "" }
                }
            }
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready when you are").font(.title2.bold())
            instruction("Nothing playing on the card?", "Play a song in the desktop Spotify or Music app. Set Follow to Automatic in Mini Deck's menu. In macOS Privacy & Security > Automation, check Mini Deck's access to that music app.")
            instruction("History looks incomplete?", "Live Spotify stats cover recent plays and top lists, not your lifetime totals. Import every audio JSON file from Extended Streaming History. The displayed coverage is the imported files' range, not a guarantee that every file was supplied.")
            instruction("Automatic import hasn't run?", "Choose a folder containing extracted JSON files, not a ZIP. Files must be stable across two checks, about 30 seconds apart. Folder permissions can be renewed by choosing it again.")
            instruction("Spotify refuses access?", "Check the exact redirect URI, app-owner Premium status, and User Management allowlist. A development app is not an unrestricted public sign-in service.")
            instruction("Monthly listeners show a link?", "Spotify's public page did not supply verifiable listener metadata. Open the link to view the artist in Spotify. Apple Music's public artist API does not supply monthly listeners. Followers are never substituted.")
            instruction("Privacy and control", "Use Listening Stats to stop auto-import, remove imported history, or disconnect Spotify. Removing imported history also stops its watcher; your original files remain untouched.")
            HStack {
                Button("Open listening history") { hub.showHistory() }
                Link("Full written guide", destination: URL(string: "https://github.com/michaeluretzky/mini-deck/blob/main/SETUP.md")!)
            }
        }
    }

    private func instruction(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        picks.notice = "Copied."
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

@MainActor
final class SetupWindow {
    private var window: NSWindow?
    private let picks = SetupPicks()

    func show(hub: Hub, step: Int? = nil) {
        if let step { picks.step = min(3, max(0, step)) }
        if window == nil {
            let panel = SetupPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 650),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered, defer: false)
            panel.title = "Mini Deck Setup & Help"
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: SetupView(hub: hub, picks: picks, close: { [weak panel] in panel?.close() }))
            panel.center()
            window = panel
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// The menu-bar app has no Edit menu; preserve standard field shortcuts.
@MainActor
private final class SetupPanel: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            let actions: [String: Selector] = ["v": #selector(NSText.paste(_:)), "c": #selector(NSText.copy(_:)),
                                               "x": #selector(NSText.cut(_:)), "a": #selector(NSText.selectAll(_:))]
            if let action = actions[event.charactersIgnoringModifiers?.lowercased() ?? ""],
               NSApp.sendAction(action, to: nil, from: nil) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
