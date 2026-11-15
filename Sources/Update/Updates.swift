// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import Foundation

/// Looks for a newer Mini Deck release on GitHub. It sends no personal data:
/// one anonymous request for the public latest-release page, at most once a day.
@MainActor @Observable
final class Updates {
    static let releasesPage = URL(string: "https://github.com/michaeluretzky/mini-deck/releases/latest")!
    private static let api = URL(string: "https://api.github.com/repos/michaeluretzky/mini-deck/releases/latest")!
    private static let lastCheckKey = "minideck.updateLastCheck"
    static let autoKey = "minideck.updateAuto"

    private(set) var available: LatestRelease?
    private(set) var checking = false
    var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: Self.autoKey) }
    }
    @ObservationIgnored var onFound: ((LatestRelease) -> Void)?
    @ObservationIgnored private var timer: Task<Void, Never>?

    let current: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    init() {
        automatic = UserDefaults.standard.object(forKey: Self.autoKey) as? Bool ?? true
    }

    var availableVersion: String? { available.flatMap { ReleaseVersion($0.tag)?.description } }

    /// Checks shortly after launch, then once a day while Mini Deck runs.
    func start() {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                guard let self else { return }
                let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
                if self.automatic, LatestRelease.isDue(lastCheck: last, now: .now) {
                    await self.check(manual: false)
                }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func check(manual: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        var request = URLRequest(url: Self.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MiniDeck/\(current)", forHTTPHeaderField: "User-Agent")
        let release: LatestRelease?
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            release = ok ? LatestRelease.parse(data) : nil
        } catch {
            release = nil
        }
        if release != nil { UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey) }
        if let release, ReleaseVersion.isNewer(release.tag, than: current) {
            let isNew = available != release
            available = release
            if manual { offer(release) } else if isNew { onFound?(release) }
        } else {
            available = nil
            if manual { report(found: release != nil) }
        }
    }

    func openDownload() {
        NSWorkspace.shared.open(available?.page ?? Self.releasesPage)
    }

    private func offer(_ release: LatestRelease) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Mini Deck \(ReleaseVersion(release.tag)?.description ?? release.tag) is available"
        alert.informativeText = "You have \(current). Download the new version from GitHub, then replace the app in your Applications folder. Your settings and history stay on this Mac."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.page) }
    }

    private func report(found: Bool) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = found ? "Mini Deck is up to date" : "Couldn't check for updates"
        alert.informativeText = found ? "You have the latest version, \(current)."
            : "GitHub couldn't be reached. Check your internet connection and try again."
        alert.runModal()
    }
}
