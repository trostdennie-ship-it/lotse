import AppKit
import CryptoKit
import Network
import Security

// MARK: - Spotify Connect: Musik in einen anderen Raum schicken

/// Ein Gerät, auf dem Spotify spielen kann (Sonos-Raum, dieser Mac, Handy …).
struct SpotifyDevice: Identifiable, Equatable {
    let id: String
    var name: String
    var type: String
    var active: Bool

    var symbol: String {
        switch type.lowercased() {
        case "computer": return "laptopcomputer"
        case "smartphone": return "iphone"
        case "tv": return "tv"
        case "tablet": return "ipad"
        default: return "hifispeaker.fill"
        }
    }
}

/// Anmeldung bei Spotify (PKCE, ohne Geheimnis) und das Umschalten des Geräts über die Web-API.
/// Die Client-ID legt die Person selbst auf developer.spotify.com an; das Token liegt im Schlüsselbund.
@MainActor
final class SpotifyConnect {
    static let shared = SpotifyConnect()
    static let port: UInt16 = 43821
    static var redirect: String { "http://127.0.0.1:\(port)/callback" }
    static let scopes = "user-read-playback-state user-modify-playback-state"

    weak var model: IslandModel?
    private var access: (token: String, until: Date)?
    private var listener: NWListener?
    private var verifier = ""
    private var state = ""

    var clientID: String {
        get { UserDefaults.standard.string(forKey: "spotifyClientID") ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "spotifyClientID") }
    }

    var connected: Bool { Keychain.read("spotify-refresh") != nil }

    // MARK: Anmelden

    /// Öffnet die Spotify-Anmeldung im Browser und wartet auf 127.0.0.1 auf die Rückmeldung.
    func signIn() {
        guard !clientID.isEmpty else { return }
        verifier = Self.randomString(64)
        state = Self.randomString(16)
        startListener()
        var c = URLComponents(string: "https://accounts.spotify.com/authorize")!
        c.queryItems = [
            .init(name: "client_id", value: clientID), .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirect), .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge_method", value: "S256"), .init(name: "code_challenge", value: Self.challenge(verifier)),
            .init(name: "state", value: state),
        ]
        if let u = c.url { NSWorkspace.shared.open(u) }
        log("Spotify: Anmeldung im Browser geöffnet")
    }

    func signOut() {
        Keychain.delete("spotify-refresh")
        access = nil
        model?.spotifyDevices = []
        model?.spotifyConnected = false
        log("Spotify: abgemeldet")
    }

    private func startListener() {
        listener?.cancel()
        guard let l = try? NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!) else {
            log("Spotify: Port \(Self.port) belegt"); return
        }
        let expected = state
        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let req = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let path = req.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let q = URLComponents(string: "http://x" + path)?.queryItems ?? []
                let code = q.first { $0.name == "code" }?.value
                let ok = code != nil && q.first { $0.name == "state" }?.value == expected
                let body = ok ? "Lotse ist mit Spotify verbunden. Du kannst dieses Fenster schließen."
                              : "Anmeldung nicht abgeschlossen. Versuch es in den Lotse-Einstellungen noch einmal."
                let html = "<html><meta charset=utf-8><body style='font:16px -apple-system;padding:40px'>\(body)</body></html>"
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n" + html
                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                guard path.hasPrefix("/callback") else { return }
                Task { @MainActor [weak self] in
                    self?.listener?.cancel(); self?.listener = nil
                    if ok, let code { await self?.exchange(code) } else { log("Spotify: Anmeldung abgebrochen") }
                }
            }
        }
        l.start(queue: .main)
        listener = l
        // Nach fünf Minuten ohne Rückmeldung wieder zumachen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self, weak l] in
            if let l, self?.listener === l { l.cancel(); self?.listener = nil }
        }
    }

    private func exchange(_ code: String) async {
        let form = ["grant_type": "authorization_code", "code": code, "redirect_uri": Self.redirect,
                    "client_id": clientID, "code_verifier": verifier]
        if await token(form) { log("Spotify: verbunden"); await refreshDevices() }
    }

    /// Holt ein Zugangs-Token; speichert ein neues Refresh-Token im Schlüsselbund.
    private func token(_ form: [String: String]) async -> Bool {
        var r = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        r.httpBody = Self.formBody(form).data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = j["access_token"] as? String else {
            log("Spotify: Token abgelehnt"); return false
        }
        access = (t, Date().addingTimeInterval(TimeInterval((j["expires_in"] as? Int ?? 3600) - 60)))
        if let rt = j["refresh_token"] as? String { Keychain.write("spotify-refresh", rt) }
        model?.spotifyConnected = true
        return true
    }

    private func bearer() async -> String? {
        if let a = access, a.until > Date() { return a.token }
        guard let rt = Keychain.read("spotify-refresh"), !clientID.isEmpty else { return nil }
        return await token(["grant_type": "refresh_token", "refresh_token": rt, "client_id": clientID]) ? access?.token : nil
    }

    // MARK: Geräte

    func refreshDevices() async {
        guard let t = await bearer() else { return }
        var r = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/devices")!)
        r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = j["devices"] as? [[String: Any]] else { return }
        let devices = list.compactMap { d -> SpotifyDevice? in
            guard let id = d["id"] as? String, let name = d["name"] as? String else { return nil }
            return SpotifyDevice(id: id, name: name, type: d["type"] as? String ?? "", active: d["is_active"] as? Bool ?? false)
        }
        model?.spotifyDevices = Self.sorted(devices)
    }

    /// Schickt die laufende Wiedergabe auf das Gerät und spielt dort weiter.
    func play(on device: SpotifyDevice) async {
        guard let t = await bearer() else { return }
        // Spielt gerade ein Sonos-Raum, den Lotse gestartet hat, wird er angehalten – die Musik zieht ja um.
        if let m = model, let id = m.sonosActive, let room = m.sonosRooms.first(where: { $0.id == id }) {
            await Sonos.soap(room.host, "AVTransport", "Pause", "<InstanceID>0</InstanceID>")
            m.sonosActive = nil
        }
        var r = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        r.httpMethod = "PUT"
        r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["device_ids": [device.id], "play": true])
        let code = ((try? await URLSession.shared.data(for: r))?.1 as? HTTPURLResponse)?.statusCode ?? 0
        log("Spotify: Wiedergabe umgeschaltet (\(device.type), Antwort \(code))")
        if let m = model { m.spotifyDevices = m.spotifyDevices.map { var d = $0; d.active = d.id == device.id; return d } }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        await refreshDevices()
    }

    /// Was gerade in Spotify läuft – für die Übergabe an Sonos.
    func playing() async -> Sonos.Playing? {
        guard let t = await bearer() else { return nil }
        var r = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player")!)
        r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = j["item"] as? [String: Any], let uri = item["uri"] as? String, uri.hasPrefix("spotify:track:") else { return nil }
        let ctx = (j["context"] as? [String: Any])?["uri"] as? String
        return Sonos.Playing(track: uri, context: ctx, seconds: (j["progress_ms"] as? Int ?? 0) / 1000)
    }

    /// Sonos-Räume im WLAN, höchstens alle 30 Sekunden neu gesucht.
    private var roomsAt: Date?
    func refreshRooms() async {
        if let a = roomsAt, Date().timeIntervalSince(a) < 30, !(model?.sonosRooms.isEmpty ?? true) { return }
        roomsAt = Date()
        let rooms = await Sonos.discover()
        model?.sonosRooms = rooms
        log("Sonos: \(rooms.count) Räume gefunden")
    }

    /// Übergibt die laufende Musik an einen Sonos-Raum und hält Spotify auf dem Mac an.
    func play(on room: SonosRoom) async {
        guard let p = await playing() else { log("Sonos: In Spotify läuft gerade nichts"); return }
        let ok = await Sonos.play(p, on: room)
        log("Sonos: Übergabe \(ok ? "gelungen" : "fehlgeschlagen") (\(p.context == nil ? "Titel" : "mit Playlist/Album"))")
        if ok {
            // Erst Spotify auf dem Mac anhalten, dann gehören die Tasten dem Raum.
            model?.musicAction?("pause")
            try? await Task.sleep(nanoseconds: 300_000_000)
            model?.sonosActive = room.id
        }
    }

    // MARK: Reine Rechnung

    /// Lautsprecher zuerst, dann der Rest, jeweils nach Name.
    nonisolated static func sorted(_ d: [SpotifyDevice]) -> [SpotifyDevice] {
        d.sorted { a, b in
            let sa = a.type.lowercased() == "speaker", sb = b.type.lowercased() == "speaker"
            return sa != sb ? sa : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    nonisolated static func challenge(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func randomString(_ n: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    nonisolated static func formBody(_ f: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return f.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&")
    }

    nonisolated static func selfTest() -> [String] {
        var bad: [String] = []
        // Gegengerechnet mit openssl (SHA-256, Base64url ohne „=“).
        if challenge("dBjftJeZ4CVP-mJ92K9ehv7S7Qb7Fe8qDmY_CKwUiZqQ") != "FOqum1LbL5TA1c37ZuJGL2hRpV2lnaJRdSXsl0yYUcw" {
            bad.append("Spotify: PKCE-Prüfwert falsch")
        }
        let s = sorted([SpotifyDevice(id: "1", name: "Mac", type: "Computer", active: true),
                    SpotifyDevice(id: "2", name: "Wohnzimmer", type: "Speaker", active: false),
                    SpotifyDevice(id: "3", name: "Bad", type: "Speaker", active: false)]).map(\.id)
        if s != ["3", "2", "1"] { bad.append("Spotify: Reihenfolge der Geräte \(s)") }
        if formBody(["a": "x y+z"]) != "a=x%20y%2Bz" { bad.append("Spotify: Formular-Kodierung") }
        return bad
    }
}

/// Minimaler Zugriff auf den Schlüsselbund für das Spotify-Token.
enum Keychain {
    private static let service = "local.lotse.app"

    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecReturnData as String: true]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        delete(key)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key, kSecValueData as String: Data(value.utf8),
                                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
    }
}
