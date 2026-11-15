// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// A dotted version such as "1.6.3", read from a release tag such as "v1.6.3".
struct ReleaseVersion: Comparable, CustomStringConvertible {
    let parts: [Int]

    /// Accepts "1.6.3", "v1.6.3" or "Mini Deck 1.6.3". Returns nil when no number is found.
    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: #"\d+(\.\d+)*"#, options: .regularExpression) {
            trimmed = String(trimmed[range])
        } else {
            return nil
        }
        let numbers = trimmed.split(separator: ".").compactMap { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 4 else { return nil }
        parts = numbers
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for i in 0..<count {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }

    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    /// True when `latest` is a newer release than `current`. Unreadable versions never count as newer.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let new = ReleaseVersion(latest), let old = ReleaseVersion(current) else { return false }
        return old < new
    }
}

/// The fields Mini Deck reads from GitHub's latest-release reply.
struct LatestRelease: Decodable, Equatable {
    let tag: String
    let page: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name", page = "html_url", draft, prerelease
    }

    static func parse(_ data: Data) -> LatestRelease? {
        guard let release = try? JSONDecoder().decode(LatestRelease.self, from: data),
              !release.draft, !release.prerelease,
              release.page.scheme == "https", release.page.host == "github.com" else { return nil }
        return release
    }

    /// Checks at most once a day unless the person asks.
    static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= 24 * 3600 || now < lastCheck
    }
}
