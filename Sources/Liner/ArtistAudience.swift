// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation

/// Public artist audience, not the signed-in listener's personal history.
struct ArtistAudience: Equatable, Sendable {
    let artist: String
    let url: URL
    let monthlyListeners: String?
    let checked: Date
}

/// Best-effort public page metadata. No private Spotify endpoints, tokens,
/// cookies, third-party analytics services, or invented follower-to-listener conversions.
actor AudiencePages {
    static let shared = AudiencePages()
    private var cache: [URL: ArtistAudience] = [:]
    private let session = URLSession(configuration: .ephemeral)

    nonisolated static func artistURL(id: String) -> URL? {
        guard id.count == 22, id.allSatisfy({ $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }) else { return nil }
        return URL(string: "https://open.spotify.com/artist/\(id)")
    }

    nonisolated static func artistID(_ url: URL) -> String? {
        guard url.scheme == "https", url.host == "open.spotify.com" else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[parts.count - 2] == "artist",
              let id = parts.last, artistURL(id: id) != nil else { return nil }
        return id
    }

    func read(artist: String, url: URL) async -> ArtistAudience? {
        guard let id = Self.artistID(url), let canonical = Self.artistURL(id: id) else { return nil }
        if let saved = cache[canonical],
           Date().timeIntervalSince(saved.checked) < (saved.monthlyListeners == nil ? 900 : 21_600) {
            return ArtistAudience(artist: artist, url: canonical, monthlyListeners: saved.monthlyListeners, checked: saved.checked)
        }
        var request = URLRequest(url: canonical, timeoutInterval: 10)
        request.setValue(LinerNotesService.agent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        var count: String?
        if let (data, response) = try? await session.data(for: request),
           !Task.isCancelled, let http = response as? HTTPURLResponse, http.statusCode == 200,
           let finalURL = http.url, Self.artistID(finalURL) == id,
           data.count <= 2_000_000, let html = String(data: data, encoding: .utf8) {
            count = Self.monthlyListeners(in: html)
        }
        guard !Task.isCancelled else { return nil }
        let result = ArtistAudience(artist: artist, url: canonical, monthlyListeners: count, checked: Date())
        if cache.count >= 128 { cache.removeAll() }
        cache[canonical] = result
        return result
    }

    /// Only the page's own description metadata is eligible. Never match
    /// arbitrary biographies, recommended artists, follower counts or scripts.
    nonisolated static func monthlyListeners(in html: String) -> String? {
        guard let tags = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]),
              let attributes = try? NSRegularExpression(pattern: #"([A-Za-z:-]+)\s*=\s*(["'])(.*?)\2"#, options: [.dotMatchesLineSeparators]),
              let count = try? NSRegularExpression(pattern: #"\b([0-9][0-9,]*(?:\.[0-9]+)?\s*[KMB]?)\s+monthly listeners\b"#,
                                                   options: [.caseInsensitive]) else { return nil }
        let text = html as NSString
        for match in tags.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let tag = text.substring(with: match.range) as NSString
            var values: [String: String] = [:]
            for attr in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                values[tag.substring(with: attr.range(at: 1)).lowercased()] = tag.substring(with: attr.range(at: 3))
            }
            let key = (values["property"] ?? values["name"] ?? "").lowercased()
            guard ["description", "og:description", "twitter:description"].contains(key),
                  let raw = values["content"] else { continue }
            let description = raw.replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#160;", with: " ") as NSString
            if let found = count.firstMatch(in: description as String, range: NSRange(location: 0, length: description.length)) {
                let value = description.substring(with: found.range(at: 1)).trimmingCharacters(in: .whitespaces)
                if value.count <= 20 { return value }
            }
        }
        return nil
    }
}
