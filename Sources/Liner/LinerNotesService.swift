// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import Foundation
import NaturalLanguage

struct ArtistProfile: Equatable, Sendable {
    enum Kind: Sendable { case band, person, other }
    var name: String
    var kind: Kind = .other
    var origin: String?
    var began: String?
    var ended: String?
    var genres: [String] = []
    var summary: String?
    var spotifyURL: URL?
    var hasFacts: Bool { origin != nil || began != nil || !genres.isEmpty }
}

struct AlbumNotes: Equatable, Sendable {
    var releaseDate: String?
    var songCount: Int?
    var runtime: Int?
    var genre: String?
    var artworkURL: URL?
    var summary: String?
    var artist: ArtistProfile?
    var hasFacts: Bool { ReleaseDateText.display(releaseDate) != nil || songCount != nil || runtime != nil || genre != nil }
    var isEmpty: Bool { !hasFacts && summary == nil && artist == nil && artworkURL == nil }
}

/// Finds album facts and short summaries from free public sources (no accounts or keys):
/// Apple's iTunes Search, MusicBrainz, Wikidata and Wikipedia.
actor LinerNotesService {
    static let shared = LinerNotesService()
    static let agent = "MiniDeck/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1") ( https://github.com/michaeluretzky/mini-deck )"

    private var albums: [String: AlbumNotes?] = [:]
    private var songs: [String: String?] = [:]
    private var brainzSlot = Date.distantPast

    // MARK: Public

    func album(artist: String, title: String) async -> AlbumNotes? {
        let key = TitleTidy.key(artist) + "/" + TitleTidy.key(title)
        if let cached = albums[key] { return cached }
        async let store = Self.appleCatalog(artist: artist, album: title)
        async let brainz = brainzAlbum(artist: artist, album: title)
        async let blurb = Self.albumSummary(title: title, artist: artist)
        var notes = await store ?? AlbumNotes()
        if let b = await brainz {
            if let date = b.releaseDate, ReleaseDateText.display(date) != nil {
                notes.releaseDate = date // First release beats reissue dates; retain source precision.
            }
            notes.artist = b.artist
        }
        notes.summary = await blurb
        if Task.isCancelled { return nil }
        let result: AlbumNotes? = notes.isEmpty ? nil : notes
        albums[key] = .some(result)
        return result
    }

    func song(title: String, artist: String) async -> String? {
        let key = TitleTidy.key(artist) + "/" + TitleTidy.key(title)
        if let cached = songs[key] { return cached }
        let name = TitleTidy.base(title)
        let lead = artist.components(separatedBy: ", ").first ?? artist
        var found: String?
        for candidate in ["\(name) (\(lead) song)", "\(name) (song)", name] {
            if Task.isCancelled { return nil }
            guard let page = await Self.wikiSummary(candidate), page.type == "standard",
                  let text = page.extract else { continue }
            let low = text.lowercased()
            let musical = ["song", "single", "track"].contains { low.contains($0) }
            if musical && low.contains(lead.lowercased()) {
                found = Excerpt.make(text, limit: 210)
                break
            }
        }
        if Task.isCancelled { return nil }
        songs[key] = .some(found)
        return found
    }

    // MARK: Apple

    static func appleCatalog(artist: String, album: String) async -> AlbumNotes? {
        let search = link("https://itunes.apple.com/search",
                          ["term": "\(artist) \(TitleTidy.base(album))", "entity": "album", "limit": "10"])
        guard let found = await fetch(ITunesResults.self, search),
              let hit = TitleTidy.bestMatch(found.results, title: album, name: { $0.collectionName }),
              let id = hit.collectionId else { return nil }
        var notes = AlbumNotes()
        notes.releaseDate = hit.releaseDate
        notes.songCount = hit.trackCount
        notes.genre = hit.primaryGenreName
        notes.artworkURL = hit.artworkUrl100.flatMap { URL(string: $0.replacingOccurrences(of: "100x100bb", with: "600x600bb")) }
        if let list = await fetch(ITunesResults.self, URL(string: "https://itunes.apple.com/lookup?id=\(id)&entity=song")) {
            let ms = list.results.filter { $0.wrapperType == "track" }.compactMap(\.trackTimeMillis).reduce(0, +)
            if ms > 0 { notes.runtime = ms / 1000 }
        }
        return notes
    }

    // MARK: MusicBrainz (asks for at most one request per second)

    private func brainzTurn() async {
        let now = Date()
        let slot = max(now, brainzSlot)
        brainzSlot = slot.addingTimeInterval(1.1)
        let wait = slot.timeIntervalSince(now)
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
    }

    private func brainz<T: Decodable & Sendable>(_ type: T.Type, _ url: URL?) async -> T? {
        await brainzTurn()
        return await Self.fetch(type, url, tries: 3)
    }

    private func brainzAlbum(artist: String, album: String) async -> (releaseDate: String?, artist: ArtistProfile?)? {
        let a = Self.lucene(artist), t = Self.lucene(TitleTidy.base(album))
        var releaseDate: String?
        var artistID: String?
        let groupURL = Self.link("https://musicbrainz.org/ws/2/release-group/",
                                 ["query": "releasegroup:\"\(t)\" AND artist:\"\(a)\"", "fmt": "json", "limit": "5"])
        if let groups = await brainz(MBGroupSearch.self, groupURL),
           let group = TitleTidy.bestMatch(groups.groups, title: album, name: { $0.title }) {
            releaseDate = group.firstReleaseDate
            artistID = group.artistCredit?.first?.artist.id
        }
        if artistID == nil {
            let artistURL = Self.link("https://musicbrainz.org/ws/2/artist/",
                                      ["query": "artist:\"\(a)\"", "fmt": "json", "limit": "3"])
            if let people = await brainz(MBArtistSearch.self, artistURL) {
                artistID = people.artists.first {
                    TitleTidy.key($0.name) == TitleTidy.key(artist) && ($0.score ?? 0) >= 95
                }?.id
            }
        }
        var profile: ArtistProfile?
        if let artistID { profile = await artistProfile(id: artistID, fallbackName: artist) }
        if releaseDate == nil && profile == nil { return nil }
        return (releaseDate, profile)
    }

    private func artistProfile(id: String, fallbackName: String) async -> ArtistProfile? {
        guard let detail = await brainz(MBArtistDetail.self,
                                        URL(string: "https://musicbrainz.org/ws/2/artist/\(id)?inc=url-rels+genres&fmt=json")) else { return nil }
        var profile = ArtistProfile(name: detail.name ?? fallbackName)
        switch detail.type?.lowercased() {
        case "group", "orchestra", "choir": profile.kind = .band
        case "person": profile.kind = .person
        default: profile.kind = .other
        }
        profile.origin = detail.beginArea?.name ?? detail.area?.name
        profile.began = detail.lifeSpan?.begin.flatMap(Self.yearPrefix)
        if detail.lifeSpan?.ended == true { profile.ended = detail.lifeSpan?.end.flatMap(Self.yearPrefix) }
        profile.genres = (detail.genres ?? [])
            .sorted { ($0.count ?? 0) > ($1.count ?? 0) }
            .prefix(2)
            .map { $0.name.capitalized }

        let links: [(kind: String, url: String)] = (detail.relations ?? []).compactMap { r in
            r.url.map { (r.type, $0.resource) }
        }
        profile.spotifyURL = links.compactMap { URL(string: $0.url) }
            .first { AudiencePages.artistID($0) != nil }
        var page: String?
        if let wikidata = links.first(where: { $0.kind == "wikidata" })?.url,
           let qid = wikidata.split(separator: "/").last {
            let file = await Self.fetch(WDEntityFile.self, URL(string: "https://www.wikidata.org/wiki/Special:EntityData/\(qid).json"))
            page = file?.entities.values.first?.sitelinks?["enwiki"]?.title
        }
        if page == nil,
           let wiki = links.first(where: { $0.kind == "wikipedia" && $0.url.contains("en.wikipedia.org/wiki/") })?.url {
            page = wiki.components(separatedBy: "/wiki/").last?.removingPercentEncoding
        }
        if let page, let summary = await Self.wikiSummary(page),
           summary.type != "disambiguation", let text = summary.extract {
            profile.summary = Excerpt.make(text, limit: 230)
        }
        return profile
    }

    // MARK: Wikipedia album page

    static func albumSummary(title: String, artist: String) async -> String? {
        let name = TitleTidy.base(title)
        let lead = (artist.components(separatedBy: ", ").first ?? artist).lowercased()
        for candidate in ["\(name) (\(artist) album)", "\(name) (album)", "\(name) (EP)", name] {
            if Task.isCancelled { return nil }
            guard let page = await wikiSummary(candidate), page.type == "standard",
                  let text = page.extract else { continue }
            let low = text.lowercased()
            let isRecord = ["album", " ep ", "extended play", "mixtape", "soundtrack"].contains { low.contains($0) }
            if isRecord && low.contains(lead) { return Excerpt.make(text, limit: 210) }
        }
        return nil
    }

    // MARK: Helpers

    static func wikiSummary(_ title: String) async -> WikiSummary? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let slug = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return await fetch(WikiSummary.self, URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)"))
    }

    static func fetch<T: Decodable & Sendable>(_ type: T.Type, _ url: URL?, tries: Int = 1) async -> T? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(agent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for attempt in 1...max(1, tries) {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 { return try? JSONDecoder().decode(T.self, from: data) }
                if code != 503 && code != 429 { return nil }
            } catch {
                if Task.isCancelled { return nil }
            }
            if attempt < tries { try? await Task.sleep(for: .seconds(1.5 * Double(attempt))) }
        }
        return nil
    }

    static func link(_ base: String, _ params: KeyValuePairs<String, String>) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=?/;")
        let query = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
        return URL(string: base + "?" + query.joined(separator: "&"))
    }

    static func lucene(_ s: String) -> String { s.filter { $0 != "\"" && $0 != "\\" } }

    static func yearPrefix(_ s: String) -> String? {
        let y = s.prefix(4)
        return y.count == 4 && y.allSatisfy(\.isNumber) ? String(y) : nil
    }
}

/// Title clean-up so "Abbey Road (2019 Mix)" and "Abbey Road" match, but different albums don't.
enum TitleTidy {
    static let editionWords = ["remaster", "edition", "version", "deluxe", "anniversary",
                               "expanded", "live", "mono", "stereo", "bonus", "mix"]

    static func base(_ s: String) -> String {
        var out = ""
        var depth = 0
        for ch in s {
            if ch == "(" || ch == "[" { depth += 1; continue }
            if ch == ")" || ch == "]" { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(ch) }
        }
        if let dash = out.range(of: " - ", options: .backwards) {
            let tail = out[dash.upperBound...].lowercased()
            if editionWords.contains(where: { tail.contains($0) }) { out = String(out[..<dash.lowerBound]) }
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? s : trimmed
    }

    static func key(_ s: String) -> String {
        let folded = base(s).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return String(String.UnicodeScalarView(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }))
    }

    /// Only accept a real title match: showing nothing beats showing the wrong album.
    static func bestMatch<T>(_ items: [T], title: String, name: (T) -> String?) -> T? {
        if let exact = items.first(where: { name($0)?.caseInsensitiveCompare(title) == .orderedSame }) { return exact }
        let wanted = key(title)
        return items.first { name($0).map(key) == wanted }
    }
}

/// The first sentence or two of a Wikipedia summary, tidied up.
enum Excerpt {
    static func make(_ raw: String, limit: Int = 240) -> String? {
        var t = raw.replacingOccurrences(of: #"\(\s*[,;]*\s*\)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #" +(?=[,.;])"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = t
        var out = ""
        tokenizer.enumerateTokens(in: t.startIndex..<t.endIndex) { range, _ in
            let sentence = String(t[range])
            if !out.isEmpty && out.count + sentence.count > limit { return false }
            out += sentence
            return out.count < limit * 6 / 10
        }
        let result = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}

// MARK: - Response shapes

struct ITunesResults: Decodable { let results: [ITunesEntry] }
struct ITunesEntry: Decodable {
    let wrapperType: String?
    let collectionId: Int?
    let collectionName: String?
    let trackCount: Int?
    let releaseDate: String?
    let trackTimeMillis: Int?
    let primaryGenreName: String?
    let artworkUrl100: String?
}

struct MBGroupSearch: Decodable {
    let groups: [MBGroup]
    enum CodingKeys: String, CodingKey { case groups = "release-groups" }
}
struct MBGroup: Decodable {
    let title: String
    let firstReleaseDate: String?
    let artistCredit: [MBCredit]?
    enum CodingKeys: String, CodingKey {
        case title
        case firstReleaseDate = "first-release-date"
        case artistCredit = "artist-credit"
    }
}
struct MBCredit: Decodable { let artist: MBRef }
struct MBRef: Decodable { let id: String }
struct MBArtistSearch: Decodable { let artists: [MBArtistHit] }
struct MBArtistHit: Decodable { let id: String; let name: String; let score: Int? }
struct MBArtistDetail: Decodable {
    let name: String?
    let type: String?
    let area: MBArea?
    let beginArea: MBArea?
    let lifeSpan: MBLifeSpan?
    let genres: [MBGenre]?
    let relations: [MBRelation]?
    enum CodingKeys: String, CodingKey {
        case name, type, area, genres, relations
        case beginArea = "begin-area"
        case lifeSpan = "life-span"
    }
}
struct MBArea: Decodable { let name: String? }
struct MBLifeSpan: Decodable { let begin: String?; let end: String?; let ended: Bool? }
struct MBGenre: Decodable { let name: String; let count: Int? }
struct MBRelation: Decodable { let type: String; let url: MBLink? }
struct MBLink: Decodable { let resource: String }
struct WDEntityFile: Decodable { let entities: [String: WDEntity] }
struct WDEntity: Decodable { let sitelinks: [String: WDSite]? }
struct WDSite: Decodable { let title: String }
struct WikiSummary: Decodable { let type: String?; let extract: String? }
