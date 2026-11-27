import Foundation

// MARK: - Sonos direkt im WLAN

/// Ein Sonos-Raum (oder eine Gruppe von Räumen), angesprochen über seinen Koordinator.
struct SonosRoom: Identifiable, Equatable {
    let id: String          // UUID des Koordinators, z. B. RINCON_…
    var name: String        // „Sonos Kino + Wohnzimmer Mobil“
    var host: String        // IP des Koordinators
}

/// Spielt, was gerade in Spotify läuft (Playlist oder Album samt Titel und Stelle), auf einem Sonos-Raum weiter.
/// Spotify meldet Sonos-Lautsprecher über die Web-API nicht zuverlässig, deshalb geht Lotse den lokalen Weg:
/// Räume per SSDP finden, die Warteschlange über UPnP füllen. Am Lautsprecher wird nichts eingestellt.
enum Sonos {
    /// Spotify ist auf Sonos als Dienst 9 hinterlegt (Europa); die Kontonummer kommt aus den Sonos-Favoriten.
    static let sid = 9
    static let serviceType = 2311

    // MARK: Räume finden

    /// Sucht per SSDP einen Sonos-Lautsprecher und liest von ihm die Gruppen aller Räume.
    static func discover() async -> [SonosRoom] {
        let hosts = await ssdp()
        for h in hosts {
            if let xml = await soap(h, "ZoneGroupTopology", "GetZoneGroupState", ""), !xml.isEmpty {
                return rooms(fromZoneGroupState: xml)
            }
        }
        return []
    }

    /// Aus GetZoneGroupState: je Gruppe ein Raum, unsichtbare Geräte (Boost, Bridge) zählen nicht.
    static func rooms(fromZoneGroupState raw: String) -> [SonosRoom] {
        let s = unescape(raw)
        var out: [SonosRoom] = []
        for g in matches(#"<ZoneGroup Coordinator="([^"]+)"[^>]*>(.*?)</ZoneGroup>"#, s) {
            let coord = g[1]
            var names: [String] = [], host = ""
            for m in matches(#"<ZoneGroupMember ([^>]*)>"#, g[2]) {
                let attrs = m[1]
                if attrs.contains(#"Invisible="1""#) || attrs.contains(#"IsZoneBridge="1""#) { continue }
                guard let uuid = first(#"UUID="([^"]+)""#, attrs), let name = first(#"ZoneName="([^"]+)""#, attrs) else { continue }
                if uuid == coord { host = first(#"Location="http://([^:/"]+)"#, attrs) ?? ""; names.insert(name, at: 0) } else { names.append(name) }
            }
            if !host.isEmpty, !names.isEmpty { out.append(SonosRoom(id: coord, name: names.joined(separator: " + "), host: host)) }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func ssdp() async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var hosts: [String] = []
                let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
                guard fd >= 0 else { cont.resume(returning: []); return }
                defer { close(fd) }
                var tv = timeval(tv_sec: 0, tv_usec: 300_000)
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                var addr = sockaddr_in()
                addr.sin_family = sa_family_t(AF_INET)
                addr.sin_port = in_port_t(1900).bigEndian
                addr.sin_addr.s_addr = inet_addr("239.255.255.250")
                let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:ZonePlayer:1\r\n\r\n"
                for _ in 0..<2 {
                    _ = msg.withCString { p in withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, p, strlen(p), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                    } }
                }
                let end = Date().addingTimeInterval(1.5)
                var buf = [UInt8](repeating: 0, count: 2048)
                while Date() < end {
                    let n = recv(fd, &buf, buf.count, 0)
                    guard n > 0 else { continue }
                    let text = String(decoding: buf[0..<n], as: UTF8.self)
                    if let h = first(#"(?i)LOCATION:\s*http://([^:/\s]+)"#, text), !hosts.contains(h) { hosts.append(h) }
                }
                cont.resume(returning: hosts)
            }
        }
    }

    // MARK: Abspielen

    /// Was Spotify gerade spielt: Titel, Zusammenhang (Playlist/Album) und Stelle in Sekunden.
    struct Playing: Equatable {
        var track: String          // spotify:track:ID
        var context: String?       // spotify:playlist:ID oder spotify:album:ID
        var seconds: Int
    }

    /// Kontonummern, unter denen Spotify auf den Sonos hinterlegt ist – die zuletzt gemerkte zuerst.
    static func accounts(_ host: String) async -> [(sn: String, token: String)] {
        let body = "<ObjectID>FV:2</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>*</Filter><StartingIndex>0</StartingIndex><RequestedCount>100</RequestedCount><SortCriteria></SortCriteria>"
        let xml = unescape(unescape(await soap(host, "ContentDirectory", "Browse", body, path: "/MediaServer/ContentDirectory/Control") ?? ""))
        return accounts(fromFavorites: xml, remembered: UserDefaults.standard.string(forKey: "sonosSpotifySN"))
    }

    static func accounts(fromFavorites xml: String, remembered: String?) -> [(sn: String, token: String)] {
        var seen: [(sn: String, token: String, count: Int)] = []
        for item in matches(#"<item .*?</item>"#, xml) {
            guard let sn = first(#"sid=\#(sid)[^"<]*?sn=(\d+)"#, item[0]),
                  let token = first(#"SA_RINCON\#(serviceType)_X_#Svc\#(serviceType)-([0-9a-f]+)-Token"#, item[0]) else { continue }
            if let i = seen.firstIndex(where: { $0.sn == sn }) { seen[i].count += 1 } else { seen.append((sn, token, 1)) }
        }
        var list: [(sn: String, token: String)] = seen.sorted { $0.count > $1.count }.map { (sn: $0.sn, token: $0.token) }
        if let r = remembered, let i = list.firstIndex(where: { $0.sn == r }) { list.insert(list.remove(at: i), at: 0) }
        return list
    }

    /// Füllt die Warteschlange des Raums mit Playlist/Album (sonst dem einzelnen Titel), springt an Titel und Stelle
    /// und spielt. Gibt true zurück, wenn der Raum danach spielt.
    static func play(_ p: Playing, on room: SonosRoom) async -> Bool {
        let accts = await accounts(room.host)
        let tries = accts.isEmpty ? [("1", "0")] : accts
        for (sn, token) in tries {
            if await attempt(p, on: room, sn: sn, token: token) {
                UserDefaults.standard.set(sn, forKey: "sonosSpotifySN")
                return true
            }
        }
        return false
    }

    private static func attempt(_ p: Playing, on room: SonosRoom, sn: String, token: String) async -> Bool {
        let h = room.host
        _ = await soap(h, "AVTransport", "RemoveAllTracksFromQueue", "<InstanceID>0</InstanceID>")
        let (uri, meta) = enqueueItem(p, sn: sn, token: token)
        let add = "<InstanceID>0</InstanceID><EnqueuedURI>\(esc(uri))</EnqueuedURI><EnqueuedURIMetaData>\(esc(meta))</EnqueuedURIMetaData><DesiredFirstTrackNumberEnqueued>0</DesiredFirstTrackNumberEnqueued><EnqueueAsNext>0</EnqueueAsNext>"
        guard await soap(h, "AVTransport", "AddURIToQueue", add) != nil else { return false }
        _ = await soap(h, "AVTransport", "SetAVTransportURI", "<InstanceID>0</InstanceID><CurrentURI>x-rincon-queue:\(room.id)#0</CurrentURI><CurrentURIMetaData></CurrentURIMetaData>")
        if p.context != nil, let n = await queueIndex(h, track: p.track), n > 1 {
            _ = await soap(h, "AVTransport", "Seek", "<InstanceID>0</InstanceID><Unit>TRACK_NR</Unit><Target>\(n)</Target>")
        }
        guard await soap(h, "AVTransport", "Play", "<InstanceID>0</InstanceID><Speed>1</Speed>") != nil else { return false }
        if p.seconds > 3 {
            try? await Task.sleep(nanoseconds: 700_000_000)
            _ = await soap(h, "AVTransport", "Seek", "<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>\(clock(p.seconds))</Target>")
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let state = await soap(h, "AVTransport", "GetTransportInfo", "<InstanceID>0</InstanceID>") ?? ""
        return state.contains("PLAYING") || state.contains("TRANSITIONING")
    }

    /// URI und Beschreibung, wie die Sonos-App sie für Spotify in die Warteschlange legt.
    static func enqueueItem(_ p: Playing, sn: String, token: String) -> (uri: String, meta: String) {
        let desc = "SA_RINCON\(serviceType)_X_#Svc\(serviceType)-\(token)-Token"
        if let c = p.context, c.hasPrefix("spotify:playlist:") || c.hasPrefix("spotify:album:") {
            let album = c.hasPrefix("spotify:album:")
            let id = (album ? "1004206c" : "1006206c") + enc(c)
            let cls = album ? "object.container.album.musicAlbum" : "object.container.playlistContainer"
            return ("x-rincon-cpcontainer:\(id)?sid=\(sid)&flags=8300&sn=\(sn)", didl(id: id, cls: cls, desc: desc))
        }
        let id = "00032020" + enc(p.track)
        return ("x-sonos-spotify:\(enc(p.track))?sid=\(sid)&flags=8224&sn=\(sn)", didl(id: id, cls: "object.item.audioItem.musicTrack", desc: desc))
    }

    /// Stelle des Titels in der Warteschlange (1-basiert), gesucht in Seiten zu 500.
    private static func queueIndex(_ host: String, track: String) async -> Int? {
        let needle = enc(track).lowercased()
        var start = 0
        while start < 3000 {
            let body = "<ObjectID>Q:0</ObjectID><BrowseFlag>BrowseDirectChildren</BrowseFlag><Filter>res</Filter><StartingIndex>\(start)</StartingIndex><RequestedCount>500</RequestedCount><SortCriteria></SortCriteria>"
            let xml = unescape(unescape(await soap(host, "ContentDirectory", "Browse", body, path: "/MediaServer/ContentDirectory/Control") ?? ""))
            let items = matches(#"<item .*?</item>"#, xml)
            if items.isEmpty { return nil }
            if let i = items.firstIndex(where: { $0[0].lowercased().contains(needle) }) { return start + i + 1 }
            start += items.count
        }
        return nil
    }

    // MARK: UPnP

    @discardableResult
    static func soap(_ host: String, _ service: String, _ action: String, _ args: String, path: String? = nil) async -> String? {
        let ns = service == "ContentDirectory" ? "urn:schemas-upnp-org:service:ContentDirectory:1" : "urn:schemas-upnp-org:service:\(service):1"
        let p = path ?? (service == "AVTransport" ? "/MediaRenderer/AVTransport/Control" : "/\(service)/Control")
        guard let url = URL(string: "http://\(host):1400\(p)") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 5)
        r.httpMethod = "POST"
        r.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        r.setValue("\"\(ns)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        r.httpBody = """
        <?xml version="1.0"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:\(action) xmlns:u="\(ns)">\(args)</u:\(action)></s:Body></s:Envelope>
        """.data(using: .utf8)
        guard let (data, resp) = try? await URLSession.shared.data(for: r) else { return nil }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code != 200 { log("Sonos: \(action) abgelehnt (\(code))"); return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Hilfen

    private static func didl(id: String, cls: String, desc: String) -> String {
        #"<DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"><item id="\#(id)" restricted="true"><dc:title></dc:title><upnp:class>\#(cls)</upnp:class><desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/">\#(desc)</desc></item></DIDL-Lite>"#
    }

    static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        return (s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s).replacingOccurrences(of: "%3A", with: "%3a")
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    static func clock(_ s: Int) -> String { String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) }

    private static func matches(_ pattern: String, _ s: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    private static func first(_ pattern: String, _ s: String) -> String? { matches(pattern, s).first.map { $0[1] } }

    static func selfTest() -> [String] {
        var bad: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { bad.append("Sonos: \(what)") } }
        let zgs = #"<ZoneGroups><ZoneGroup Coordinator="RINCON_B" ID="x"><ZoneGroupMember UUID="RINCON_A" Location="http://10.0.0.2:1400/xml/device_description.xml" ZoneName="Wohnzimmer"/><ZoneGroupMember UUID="RINCON_B" Location="http://10.0.0.3:1400/xml/device_description.xml" ZoneName="Kino"/></ZoneGroup><ZoneGroup Coordinator="RINCON_C" ID="y"><ZoneGroupMember UUID="RINCON_C" Location="http://10.0.0.4:1400/x" ZoneName="Boost" Invisible="1" IsZoneBridge="1"/></ZoneGroup></ZoneGroups>"#
        let r = rooms(fromZoneGroupState: esc(zgs))
        check(r == [SonosRoom(id: "RINCON_B", name: "Kino + Wohnzimmer", host: "10.0.0.3")], "Gruppen falsch gelesen: \(r)")
        let fav = #"<item id="1"><res>x-rincon-cpcontainer:x?sid=9&flags=8300&sn=15</res><r:resMD><desc>SA_RINCON2311_X_#Svc2311-2c8440c0-Token</desc></r:resMD></item><item id="2"><res>x?sid=9&flags=1&sn=1</res><desc>SA_RINCON2311_X_#Svc2311-0-Token</desc></item><item id="3"><res>x?sid=9&flags=1&sn=1</res><desc>SA_RINCON2311_X_#Svc2311-0-Token</desc></item>"#
        check(accounts(fromFavorites: fav, remembered: nil).map(\.sn) == ["1", "15"], "Konten nach Häufigkeit")
        check(accounts(fromFavorites: fav, remembered: "15").map(\.sn) == ["15", "1"], "gemerktes Konto zuerst")
        let pl = enqueueItem(Playing(track: "spotify:track:T1", context: "spotify:playlist:P1", seconds: 0), sn: "15", token: "ab")
        check(pl.uri == "x-rincon-cpcontainer:1006206cspotify%3aplaylist%3aP1?sid=9&flags=8300&sn=15", "Playlist-URI \(pl.uri)")
        let tr = enqueueItem(Playing(track: "spotify:track:T1", context: nil, seconds: 0), sn: "1", token: "0")
        check(tr.uri == "x-sonos-spotify:spotify%3atrack%3aT1?sid=9&flags=8224&sn=1", "Titel-URI \(tr.uri)")
        check(tr.meta.contains("SA_RINCON2311_X_#Svc2311-0-Token"), "Beschreibung ohne Konto")
        check(clock(3725) == "1:02:05", "Zeitformat")
        return bad
    }
}
