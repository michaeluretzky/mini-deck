// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import CryptoKit
import Network
import Security

/// Read-only link to the user's Spotify account for top artists, top songs and recent plays.
/// Sign-in uses Authorization Code with PKCE (no client secret). The refresh token lives in the keychain;
/// the short-lived access token stays in memory.
@MainActor @Observable
final class SpotifyAccount {
    enum Status: Equatable {
        case off
        case waiting
        case on
        case expired
        case failed(String)
    }

    enum Span: String, CaseIterable, Sendable {
        case short = "short_term", medium = "medium_term", long = "long_term"
        var label: String {
            switch self {
            case .short: "4 weeks"
            case .medium: "6 months"
            case .long: "12 months"
            }
        }
    }

    struct Top: Equatable, Sendable {
        /// Artist name key -> rank (1 = top).
        var artists: [String: Int] = [:]
        /// Spotify track ID -> rank.
        var tracks: [String: Int] = [:]
    }

    struct Play: Equatable, Sendable {
        let trackID: String
        let artistKeys: [String]
        let at: Date
    }

    static let port: UInt16 = 8974
    static let redirect = "http://127.0.0.1:8974/callback"
    static let scopes = "user-top-read user-read-recently-played"

    private(set) var status: Status = .off
    private(set) var top: [Span: Top] = [:]
    private(set) var recent: [Play] = []
    private(set) var updated: Date?

    @ObservationIgnored var onNotice: ((String) -> Void)?
    @ObservationIgnored private var stored: Vault.Entry?
    @ObservationIgnored private var access: (token: String, until: Date)?
    @ObservationIgnored private var catcher: LoopbackCatcher?
    @ObservationIgnored private var topFetched = Date.distantPast
    @ObservationIgnored private var recentFetched = Date.distantPast
    @ObservationIgnored private var pausedUntil = Date.distantPast
    @ObservationIgnored private var busy = false

    init() {
        if let entry = Vault.load() {
            stored = entry
            status = .on
        }
    }

    var isConnected: Bool { status == .on }

    // MARK: Sign-in

    static func looksLikeClientID(_ s: String) -> Bool {
        s.count == 32 && s.allSatisfy(\.isHexDigit)
    }

    func connect(clientID raw: String) {
        let clientID = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeClientID(clientID) else {
            status = .failed("That Client ID doesn't look right. It's 32 letters and numbers.")
            return
        }
        cancelSignIn()
        let verifier = Self.randomToken(64)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomToken(32)

        let catcher = LoopbackCatcher(port: Self.port)
        let listening = catcher.start(timeout: 300) { [weak self] query in
            guard let self else { return }
            self.catcher = nil
            self.finishSignIn(query, expectedState: state, verifier: verifier, clientID: clientID)
        }
        guard listening else {
            status = .failed("Port \(Self.port) is in use, so sign-in can't finish. Quit the app using it and try again.")
            return
        }
        self.catcher = catcher
        status = .waiting

        var parts = URLComponents(string: "https://accounts.spotify.com/authorize")!
        parts.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes),
        ]
        if let url = parts.url { NSWorkspace.shared.open(url) }
    }

    func cancelSignIn() {
        catcher?.stop()
        catcher = nil
        if status == .waiting { status = stored == nil ? .off : .on }
    }

    func disconnect() {
        cancelSignIn()
        Vault.wipe()
        stored = nil
        access = nil
        top = [:]
        recent = []
        updated = nil
        topFetched = .distantPast
        recentFetched = .distantPast
        status = .off
    }

    private func finishSignIn(_ query: [String: String]?, expectedState: String, verifier: String, clientID: String) {
        guard let query else {
            status = .failed("Sign-in timed out. Try again from the menu.")
            return
        }
        // The state value proves the reply belongs to the request this app made.
        guard let state = query["state"], Self.sameBytes(state, expectedState) else {
            status = .failed("Sign-in was rejected because the reply didn't match. Try again.")
            return
        }
        if let error = query["error"] {
            status = .failed(error == "access_denied" ? "Access wasn't allowed in Spotify." : "Spotify reported: \(error)")
            return
        }
        guard let code = query["code"], !code.isEmpty else {
            status = .failed("Spotify didn't send a sign-in code.")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let reply = await Self.token([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": Self.redirect,
                "client_id": clientID,
                "code_verifier": verifier,
            ])
            switch reply {
            case .granted(let t):
                guard let refresh = t.refresh_token else {
                    self.status = .failed("Spotify didn't return a sign-in that can be kept.")
                    return
                }
                let entry = Vault.Entry(clientID: clientID, refresh: refresh)
                Vault.save(entry)
                self.stored = entry
                self.access = (t.access_token, Date().addingTimeInterval(Double(t.expires_in ?? 3600) - 60))
                self.status = .on
                self.onNotice?("Spotify account connected")
                await self.update(trackChanged: true)
            case .rejected(let why):
                self.status = .failed("Spotify refused the sign-in (\(why)). Check the Redirect URI in your Spotify app.")
            case .offline:
                self.status = .failed("Couldn't reach Spotify. Check your connection and try again.")
            }
        }
    }

    // MARK: Reading stats

    /// Top lists refresh every 30 minutes; recent plays on track changes, at most every 90 seconds.
    func update(trackChanged: Bool) async {
        guard status == .on, !busy, Date() >= pausedUntil else { return }
        let now = Date()
        let wantTop = now.timeIntervalSince(topFetched) > 30 * 60
        let wantRecent = trackChanged && now.timeIntervalSince(recentFetched) > 90
        guard wantTop || wantRecent else { return }
        busy = true
        defer { busy = false }

        if wantTop {
            var fresh: [Span: Top] = [:]
            for span in Span.allCases {
                var t = Top()
                if let a = await get("/me/top/artists?time_range=\(span.rawValue)&limit=50", Paging<WebArtist>.self) {
                    for (i, artist) in a.items.enumerated() where t.artists[TitleTidy.key(artist.name)] == nil {
                        t.artists[TitleTidy.key(artist.name)] = i + 1
                    }
                }
                if let s = await get("/me/top/tracks?time_range=\(span.rawValue)&limit=50", Paging<WebTrack>.self) {
                    for (i, track) in s.items.enumerated() {
                        if let id = track.id { t.tracks[id] = i + 1 }
                    }
                }
                guard status == .on else { return }
                fresh[span] = t
            }
            top = fresh
            topFetched = now
        }
        if wantRecent || wantTop, let r = await get("/me/player/recently-played?limit=50", Paging<WebPlay>.self) {
            recent = r.items.compactMap { item in
                guard let id = item.track.id else { return nil }
                return Play(trackID: id, artistKeys: item.track.artists.map { TitleTidy.key($0.name) },
                            at: Self.parseDate(item.played_at) ?? .distantPast)
            }
            recentFetched = now
        }
        updated = now
    }

    private func accessToken() async -> String? {
        if let access, access.until > Date() { return access.token }
        guard let stored else { return nil }
        let reply = await Self.token([
            "grant_type": "refresh_token",
            "refresh_token": stored.refresh,
            "client_id": stored.clientID,
        ])
        switch reply {
        case .granted(let t):
            access = (t.access_token, Date().addingTimeInterval(Double(t.expires_in ?? 3600) - 60))
            if let rotated = t.refresh_token, rotated != stored.refresh {
                let entry = Vault.Entry(clientID: stored.clientID, refresh: rotated)
                Vault.save(entry)
                self.stored = entry
            }
            return t.access_token
        case .rejected:
            // Refresh tokens expire; ask the user to sign in again instead of retrying.
            Vault.wipe()
            self.stored = nil
            access = nil
            status = .expired
            return nil
        case .offline:
            return nil
        }
    }

    private func get<T: Decodable & Sendable>(_ path: String, _ type: T.Type) async -> T? {
        guard let token = await accessToken(), let url = URL(string: "https://api.spotify.com/v1" + path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200:
            return try? JSONDecoder().decode(T.self, from: data)
        case 401:
            access = nil
        case 403:
            status = .failed("Spotify blocked the request. In your Spotify app's settings, add your account under User Management.")
        case 429:
            let wait = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 300
            pausedUntil = Date().addingTimeInterval(max(60, wait))
        default:
            break
        }
        return nil
    }

    // MARK: Token endpoint

    private struct TokenReply: Decodable, Sendable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
    }

    private enum TokenResult: Sendable {
        case granted(TokenReply)
        case rejected(String)
        case offline
    }

    private struct TokenError: Decodable { let error: String? }

    nonisolated private static func token(_ form: [String: String]) async -> TokenResult {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .offline }
        if http.statusCode == 200, let reply = try? JSONDecoder().decode(TokenReply.self, from: data) {
            return .granted(reply)
        }
        if (400...499).contains(http.statusCode) {
            return .rejected((try? JSONDecoder().decode(TokenError.self, from: data))?.error ?? "error \(http.statusCode)")
        }
        return .offline
    }

    // MARK: Helpers

    nonisolated static func randomToken(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &rng) }
        }
        return String(base64url(Data(bytes)).prefix(length))
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Compares without stopping at the first difference.
    nonisolated static func sameBytes(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in x.indices { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    nonisolated static func parseDate(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Web API shapes

struct Paging<T: Decodable & Sendable>: Decodable, Sendable { let items: [T] }
struct WebArtist: Decodable, Sendable { let id: String?; let name: String }
struct WebTrack: Decodable, Sendable { let id: String?; let name: String; let artists: [WebArtist] }
struct WebPlay: Decodable, Sendable { let track: WebTrack; let played_at: String }

// MARK: - Keychain

/// Keeps the Spotify sign-in in the login keychain, readable only on this Mac.
enum Vault {
    struct Entry: Codable, Equatable {
        let clientID: String
        let refresh: String
    }

    private static let service = "app.minideck.player.spotify"
    private static let account = "spotify-account"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> Entry? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    static func save(_ entry: Entry) {
        guard let data = try? JSONEncoder().encode(entry) else { return }
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            add[kSecAttrLabel as String] = "Mini Deck Spotify sign-in"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func wipe() {
        SecItemDelete(base as CFDictionary)
    }
}

// MARK: - Sign-in callback

/// A one-shot web listener on 127.0.0.1 that catches Spotify's sign-in redirect, then closes.
/// It binds to the loopback address only, so other computers can't reach it.
@MainActor
final class LoopbackCatcher {
    private let port: UInt16
    private var listener: NWListener?
    private var done: (([String: String]?) -> Void)?
    private var timer: Task<Void, Never>?
    private var finished = false

    init(port: UInt16) { self.port = port }

    func start(timeout: TimeInterval, done: @escaping ([String: String]?) -> Void) -> Bool {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return false }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        params.allowLocalEndpointReuse = true
        guard let listener = try? NWListener(using: params) else { return false }
        self.done = done
        listener.newConnectionHandler = { [weak self] connection in
            MainActor.assumeIsolated { self?.serve(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state {
                MainActor.assumeIsolated { self?.finish(nil) }
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
        return true
    }

    func stop() {
        finished = true
        done = nil
        timer?.cancel()
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                guard let self else { connection.cancel(); return }
                let head = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let line = head.components(separatedBy: "\r\n").first ?? ""
                let parts = line.split(separator: " ")
                guard !self.finished, parts.count >= 2, parts[0] == "GET", parts[1].hasPrefix("/callback"),
                      let url = URLComponents(string: "http://127.0.0.1" + parts[1]) else {
                    Self.reply(connection, status: "404 Not Found", message: "Nothing here.")
                    return
                }
                var query: [String: String] = [:]
                for item in url.queryItems ?? [] { query[item.name] = item.value ?? "" }
                let ok = query["code"] != nil
                Self.reply(connection, status: "200 OK",
                           message: ok ? "Mini Deck is connected to your Spotify account. You can close this tab."
                                       : "Sign-in didn't finish. You can close this tab and try again from Mini Deck.")
                self.finish(query)
            }
        }
    }

    private func finish(_ query: [String: String]?) {
        guard !finished else { return }
        finished = true
        timer?.cancel()
        listener?.cancel()
        listener = nil
        let callback = done
        done = nil
        callback?(query)
    }

    private static func reply(_ connection: NWConnection, status: String, message: String) {
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>Mini Deck</title></head>
        <body style="font:16px -apple-system,sans-serif;margin:15vh auto;max-width:28em;text-align:center">
        <p>\(message)</p></body></html>
        """
        let body = Data(html.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }
}
