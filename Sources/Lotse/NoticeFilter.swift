import Foundation

// MARK: - Fakten, die sich aus einer Zeile der Mitteilungs-DB ableiten lassen

enum NoticeKind: String, Codable, Sendable, CaseIterable {
    case direct      // 1:1-Nachricht
    case group       // Gruppenchat (WhatsApp-Gruppe, iMessage-Gruppe)
    case channel     // Slack-Kanal, WhatsApp-Kanal/Newsletter
    case reaction    // Reaktion, Status, sonstiges Messenger-Rauschen
    case call        // Anruf / verpasster Anruf
    case calendar    // Termin-Erinnerung, Einladung
    case web         // Web-Push aus Chrome
    case agent       // Claude: Sitzung fertig / wartet
    case system      // Systemdienste
    case other
}

struct NoticeFacts: Sendable {
    var app: String                 // Bundle-ID, klein geschrieben (so steht sie in app.identifier)
    var title = ""
    var subtitle = ""
    var body = ""
    var category = ""               // req.cate
    var thread = ""                 // req.thre
    var ident = ""                  // req.iden
    var kind: NoticeKind = .other
    var sender: String?             // Anzeigename der Person (falls ermittelbar)
    var conversation: String?       // Anzeigename von Kanal/Gruppe bzw. der Person bei DMs
    var origin: String?             // Host bei Chrome-Web-Push, z. B. "calendar.google.com"
    var conversationKey: String     // stabiler Schlüssel für Regeln/Stummschalten
}

// MARK: - Archive (req.usda = NSDictionary, req.uncc = private UN-Klassen)

/// Ersatzklassen für die privaten Klassen in `req.uncc`; nur die Felder, die Lotse braucht.
final class LotseCommContact: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let displayName: String?
    let handle: String?
    init?(coder: NSCoder) {
        displayName = coder.decodeObject(of: NSString.self, forKey: "displayName") as String?
        handle = coder.decodeObject(of: NSString.self, forKey: "handle") as String?
    }
    func encode(with coder: NSCoder) {}
}

final class LotseCommContext: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    let identifier: String?
    let displayName: String?        // Gruppenname; bei 1:1 leer ("$null")
    let recipientCount: Int
    let mentionsCurrentUser: Bool
    let replyToCurrentUser: Bool
    let sender: LotseCommContact?
    init?(coder: NSCoder) {
        identifier = coder.decodeObject(of: NSString.self, forKey: "identifier") as String?
        displayName = coder.decodeObject(of: NSString.self, forKey: "displayName") as String?
        recipientCount = coder.decodeInteger(forKey: "recipientCount")
        mentionsCurrentUser = coder.decodeBool(forKey: "mentionsCurrentUser")
        replyToCurrentUser = coder.decodeBool(forKey: "replyToCurrentUser")
        sender = coder.decodeObject(of: LotseCommContact.self, forKey: "sender")
    }
    func encode(with coder: NSCoder) {}
}

enum NoticeArchive {
    /// Nur reine Plist-Typen zulassen: der Inhalt stammt von fremden Apps, also nie beliebige Klassen instanziieren.
    private static var plistClasses: [AnyClass] {
        [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self, NSData.self, NSDate.self, NSNull.self, NSURL.self, NSUUID.self]
    }

    /// `req.usda`: NSKeyedArchiver-Archiv eines userInfo-Dictionarys. Enthält es fremde Klassen, kommt [:] zurück.
    static func userInfo(_ data: Data?) -> [String: Any] {
        guard let data, let u = try? NSKeyedUnarchiver(forReadingFrom: data) else { return [:] }
        u.requiresSecureCoding = true
        u.decodingFailurePolicy = .setErrorAndReturn
        defer { u.finishDecoding() }
        guard let d = u.decodeObject(of: plistClasses, forKey: NSKeyedArchiveRootObjectKey) as? [AnyHashable: Any] else { return [:] }
        var out: [String: Any] = [:]
        for (k, v) in d { if let k = k as? String { out[k] = v } }
        return out
    }

    /// `req.uncc`: Kommunikations-Kontext (INSendMessageIntent-Spende), z. B. von WhatsApp und Nachrichten.
    static func context(_ data: Data?) -> LotseCommContext? {
        guard let data, let u = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        u.requiresSecureCoding = true
        u.decodingFailurePolicy = .setErrorAndReturn
        u.setClass(LotseCommContext.self, forClassName: "_UNNotificationCommunicationContext")
        u.setClass(LotseCommContact.self, forClassName: "_UNNotificationContact")
        defer { u.finishDecoding() }
        return u.decodeObject(of: LotseCommContext.self, forKey: NSKeyedArchiveRootObjectKey)
    }
}

// MARK: - Extraktion je App

enum NoticeExtractor {
    static let slack = "com.tinyspeck.slackmacgap"
    static let whatsapp = "net.whatsapp.whatsapp"
    static let messages = "com.apple.mobilesms"
    static let telegram: Set<String> = ["com.tdesktop.telegram", "ru.keepcoder.telegram"]
    static let teams = "com.microsoft.teams2"
    static let claude = "com.anthropic.claudefordesktop"
    static let chromePrefix = "com.google.chrome"

    /// `app`: app.identifier, `plist`: deserialisierte Spalte record.data.
    static func facts(app rawApp: String, plist: [String: Any]) -> NoticeFacts? {
        guard let req = plist["req"] as? [String: Any] else { return nil }
        let app = rawApp.lowercased()
        var f = NoticeFacts(app: app, conversationKey: app)
        f.title = req["titl"] as? String ?? ""
        f.subtitle = req["subt"] as? String ?? ""
        f.body = req["body"] as? String ?? ""
        f.category = req["cate"] as? String ?? ""
        f.thread = req["thre"] as? String ?? ""
        f.ident = req["iden"] as? String ?? ""
        let info = NoticeArchive.userInfo(req["usda"] as? Data)

        switch app {
        case slack:
            slackFacts(&f)
        case whatsapp:
            whatsAppFacts(&f, info: info, ctx: NoticeArchive.context(req["uncc"] as? Data))
        case messages:
            let ctx = NoticeArchive.context(req["uncc"] as? Data)
            let isGroup = f.category.contains("Group") || (ctx?.recipientCount ?? 0) > 1
            f.kind = isGroup ? .group : .direct
            f.sender = ctx?.sender?.displayName ?? (f.title.isEmpty ? nil : f.title)
            f.conversation = isGroup ? (ctx?.displayName ?? f.title) : f.sender
        case "com.apple.mobilephone", "com.apple.facetime":
            f.kind = .call
            f.sender = f.title.isEmpty ? nil : f.title
        case "com.apple.ical", "com.apple.reminders":
            f.kind = .calendar
        case claude:
            f.kind = .agent
            if let s = info["sessionId"] as? String { f.thread = s }
            // Auf diesem Rechner gesehen: iden „idle-…“/„cowork-idle-…“ (Durchlauf fertig) und „hub-awaiting-…“/
            // „scheduled-…-awaiting-…“ (wartet auf den Nutzer); notificationType remote_turn_complete / remote_idle.
            let type = info["notificationType"] as? String ?? ""
            if f.ident.contains("awaiting") || f.category == "PERMISSION_REQUEST" { f.category = "awaiting" }
            else if f.ident.contains("idle-") || type == "remote_turn_complete" || type == "remote_idle" { f.category = "finished" }
        default:
            if app.hasPrefix("_system_center_:") { f.kind = .system }
            else if app.hasPrefix(chromePrefix) { chromeFacts(&f, info: info) }
            else if telegram.contains(app) || app == teams {
                // Keine Zeilen auf diesem Rechner: Titel = Chat-/Absendername, Art unbekannt.
                f.kind = f.subtitle.isEmpty ? .direct : .group
                f.sender = f.subtitle.isEmpty ? f.title : f.subtitle
                f.conversation = f.title
            }
        }
        if !f.thread.isEmpty, app != slack { f.conversationKey = app + "|" + f.thread }
        else if let c = f.conversation { f.conversationKey = app + "|" + f.kind.rawValue + "|" + c.lowercased() }
        return f
    }

    /// Slack (alte NSUserNotification-Schiene): keine Kategorie, kein Thread, keine Kanal-ID – nur der Titeltext.
    private static let slackDM = ["New message from ", "Neue Nachricht von "]
    private static let slackChannel = ["New message in ", "Neue Nachricht in "]

    private static func slackFacts(_ f: inout NoticeFacts) {
        if let p = slackDM.first(where: { f.title.hasPrefix($0) }) {
            f.kind = .direct
            f.sender = String(f.title.dropFirst(p.count))
            f.conversation = f.sender
        } else if let p = slackChannel.first(where: { f.title.hasPrefix($0) }) {
            f.kind = .channel
            var name = String(f.title.dropFirst(p.count))
            if name.hasPrefix("#") { name.removeFirst() }
            f.conversation = name
            // Im Kanal beginnt der Text mit „Absender: “.
            if let r = f.body.range(of: ": "), f.body.distance(from: f.body.startIndex, to: r.lowerBound) <= 40,
               !f.body[..<r.lowerBound].contains("\n") {
                f.sender = String(f.body[..<r.lowerBound])
            }
        }
    }

    private static func whatsAppFacts(_ f: inout NoticeFacts, info: [String: Any], ctx: LotseCommContext?) {
        let jid = (info["jid"] as? String) ?? f.thread
        let server = jid.split(separator: "@").last.map(String.init) ?? ""
        let flaggedGroup = info["is-group-chat"] as? Bool
        switch server {
        case "g.us": f.kind = .group
        case "newsletter": f.kind = .channel
        case "broadcast": f.kind = .reaction
        default: f.kind = (flaggedGroup == true || (ctx?.recipientCount ?? 0) > 0) ? .group : .direct
        }
        f.sender = ctx?.sender?.displayName
        f.conversation = f.kind == .direct ? (ctx?.sender?.displayName ?? (info["chat-name"] as? String))
                                           : (ctx?.displayName ?? (info["chat-name"] as? String))
        // Registrierte Nachrichten-Kategorien: message, message2, message-with-reaction, message2-with-reaction,
        // message-no-quick-actions, message-otp … – alle sind echte Nachrichten; nur diese drei sind Rauschen.
        let cat = f.category
        if cat.contains("call") { f.kind = .call }
        else if cat == "incoming-reaction" || cat == "message-react-only" || cat.contains("status") { f.kind = .reaction }
        else if !cat.isEmpty, !cat.hasPrefix("message") { f.kind = .other }
        if !jid.isEmpty { f.thread = jid }
    }

    /// Chrome: Web-Push trägt die Herkunft im Untertitel und (laut Chromium-Quelltext) in userInfo["notificationOrigin"].
    private static func chromeFacts(_ f: inout NoticeFacts, info: [String: Any]) {
        f.kind = .web
        let candidates = [info["notificationOrigin"] as? String, f.subtitle]
        for c in candidates {
            guard let c, !c.isEmpty else { continue }
            if let h = URL(string: c)?.host ?? URL(string: "https://" + c)?.host, h.contains("."),
               h.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil {
                f.origin = h.lowercased(); break
            }
        }
        if f.app.hasPrefix("com.google.chrome.app.") { f.conversation = f.app }   // installierte Web-App = eigene Bundle-ID
        f.thread = f.origin ?? ""
    }
}

// MARK: - Regelmodell

enum NoticeVerdict: String, Codable, Sendable {
    case popUp     // Insel klappt auf
    case quiet     // nur in die Liste, kein Aufklappen
    case drop      // gar nicht übernehmen
}

struct NoticeRule: Codable, Sendable, Identifiable {
    var id = UUID()
    /// Bundle-ID; endet sie auf „*“, gilt sie als Präfix. nil = jede App.
    var app: String?
    /// Leere Menge = jede Art.
    var kinds: Set<NoticeKind> = []
    /// Host-Endung, z. B. „google.com“ trifft „calendar.google.com“.
    var origin: String?
    /// Teiltext in Kanal-/Gruppen-/Chatname oder exakter conversationKey.
    var conversation: String?
    /// Teiltext im Absendernamen.
    var sender: String?
    /// Teiltext in req.cate.
    var category: String?
    var verdict: NoticeVerdict

    private enum CodingKeys: String, CodingKey { case id, app, kinds, origin, conversation, sender, category, verdict }

    init(id: UUID = UUID(), app: String? = nil, kinds: Set<NoticeKind> = [], origin: String? = nil, conversation: String? = nil,
         sender: String? = nil, category: String? = nil, verdict: NoticeVerdict) {
        self.id = id; self.app = app; self.kinds = kinds; self.origin = origin; self.conversation = conversation
        self.sender = sender; self.category = category; self.verdict = verdict
    }

    /// Fehlende Felder und unbekannte Arten (aus einer neueren Version) werden toleriert.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        app = try c.decodeIfPresent(String.self, forKey: .app)
        let raw = try c.decodeIfPresent([String].self, forKey: .kinds) ?? []
        kinds = Set(raw.compactMap(NoticeKind.init(rawValue:)))
        // Regel galt nur für Arten, die diese Version nicht kennt: nicht zur „gilt für alles“-Regel werden lassen.
        if !raw.isEmpty, kinds.isEmpty { throw DecodingError.dataCorruptedError(forKey: .kinds, in: c, debugDescription: "unbekannte Art") }
        origin = try c.decodeIfPresent(String.self, forKey: .origin)
        conversation = try c.decodeIfPresent(String.self, forKey: .conversation)
        sender = try c.decodeIfPresent(String.self, forKey: .sender)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        verdict = try c.decode(NoticeVerdict.self, forKey: .verdict)
    }

    func matches(_ f: NoticeFacts) -> Bool {
        if let app = app?.lowercased() {
            if app.hasSuffix("*") { guard f.app.hasPrefix(app.dropLast()) else { return false } }
            else { guard f.app == app else { return false } }
        }
        if !kinds.isEmpty, !kinds.contains(f.kind) { return false }
        if let origin = origin?.lowercased() {
            guard let h = f.origin, h == origin || h.hasSuffix("." + origin) else { return false }
        }
        if let c = conversation?.lowercased() {
            guard f.conversationKey.lowercased() == c || (f.conversation?.lowercased().contains(c) ?? false) else { return false }
        }
        if let s = sender?.lowercased() {
            guard f.sender?.lowercased().contains(s) ?? false else { return false }
        }
        if let cat = category?.lowercased() {
            guard f.category.lowercased().contains(cat) else { return false }
        }
        return true
    }
}

struct NoticeFilter: Codable, Sendable {
    /// Eigene Regeln des Nutzers – werden vor den Vorgaben geprüft. Nur sie werden gespeichert.
    var user: [NoticeRule] = []
    /// Vorgaben kommen immer aus dem Programm, damit ein Update sie verbessern kann.
    var defaults: [NoticeRule] { NoticeFilter.standard }
    var fallback: NoticeVerdict = .quiet

    private enum CodingKeys: String, CodingKey { case user, fallback }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Eine kaputte Regel verwirft nur sich selbst, nicht die ganze Liste.
        user = ((try? c.decodeIfPresent([Lossy].self, forKey: .user)) ?? [])?.compactMap(\.rule) ?? []
        fallback = (try? c.decodeIfPresent(NoticeVerdict.self, forKey: .fallback)) ?? .quiet
    }
    private struct Lossy: Decodable {
        let rule: NoticeRule?
        init(from decoder: Decoder) throws { rule = try? NoticeRule(from: decoder) }
    }

    /// Erste passende Regel gewinnt.
    func verdict(for f: NoticeFacts) -> NoticeVerdict {
        for r in user where r.matches(f) { return r.verdict }
        for r in defaults where r.matches(f) { return r.verdict }
        return fallback
    }

    static let messengers = ["com.tinyspeck.slackmacgap", "net.whatsapp.whatsapp", "com.apple.mobilesms",
                             "com.tdesktop.telegram", "ru.keepcoder.telegram", "com.microsoft.teams2"]

    static let standard: [NoticeRule] = {
        var r: [NoticeRule] = [
            // Systemgeplapper nie
            NoticeRule(app: "_system_center_:*", verdict: .drop),
            NoticeRule(app: "com.apple.gamepolicynotifications", verdict: .drop),
            NoticeRule(kinds: [.system], verdict: .drop),
            // Slack-Bots, die als „DM“ kommen (Kalender-Integration u. ä.)
            NoticeRule(app: "com.tinyspeck.slackmacgap", sender: "Google Calendar", verdict: .quiet),
        ]
        for m in messengers {
            r.append(NoticeRule(app: m, kinds: [.direct, .call], verdict: .popUp))
            r.append(NoticeRule(app: m, kinds: [.group, .channel, .reaction], verdict: .quiet))
            r.append(NoticeRule(app: m, verdict: .popUp))      // Art nicht erkennbar: lieber zeigen
        }
        r += [
            NoticeRule(kinds: [.call], verdict: .popUp),
            NoticeRule(kinds: [.calendar], verdict: .popUp),
            // Claude Desktop: „fertig“ und „wartet auf dich“ klappen auf (Wunsch des Nutzers), Sonstiges ebenfalls
            NoticeRule(kinds: [.agent], verdict: .popUp),
            // Chrome nur für benannte Herkünfte; installierte Web-Apps (Google Meet) immer
            NoticeRule(app: "com.google.chrome.app.*", verdict: .popUp),
            NoticeRule(app: "com.google.chrome*", origin: "calendar.google.com", verdict: .popUp),
            NoticeRule(app: "com.google.chrome*", origin: "meet.google.com", verdict: .popUp),
            NoticeRule(app: "com.google.chrome*", origin: "mail.google.com", verdict: .popUp),
            NoticeRule(app: "com.google.chrome*", origin: "claude.ai", verdict: .popUp),
            NoticeRule(app: "com.google.chrome*", verdict: .quiet),
            NoticeRule(app: "com.apple.mail", verdict: .quiet),
            NoticeRule(app: "com.microsoft.outlook", verdict: .quiet),
            NoticeRule(app: "com.apple.*", verdict: .quiet),
        ]
        return r
    }()
}


extension NoticeFilter {
    private static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lotse/filter.json")

    static func load() -> NoticeFilter {
        guard let data = try? Data(contentsOf: file), let f = try? JSONDecoder().decode(NoticeFilter.self, from: data) else { return NoticeFilter() }
        return f
    }

    func save() {
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: Self.file, options: .atomic) }
    }

    /// Die Art, in der eine App typischerweise meldet (für das Menü „Darf aufklappen").
    private static func typicalKind(_ app: String) -> NoticeKind {
        if app == NoticeExtractor.claude { return .agent }
        if app == "com.apple.ical" || app == "com.apple.reminders" { return .calendar }
        if app == "com.apple.facetime" || app == "com.apple.mobilephone" { return .call }
        if app.hasPrefix(NoticeExtractor.chromePrefix) { return .web }
        return .direct
    }

    /// Darf diese App grundsätzlich aufklappen? (für das Menü)
    func popsUp(app: String) -> Bool {
        let id = app.lowercased()
        return verdict(for: NoticeFacts(app: id, kind: Self.typicalKind(id), conversationKey: "")) == .popUp
    }

    /// Schaltet für eine App um, ob ihre Mitteilungen die Insel aufklappen dürfen.
    mutating func toggle(app: String) {
        let id = app.lowercased()
        let want = !popsUp(app: id)
        user.removeAll { $0.app == id && $0.kinds.isEmpty && $0.origin == nil && $0.conversation == nil && $0.sender == nil && $0.category == nil }
        // Nur dann eine pauschale Regel anlegen, wenn die Vorgaben nicht schon das Gewünschte liefern –
        // sonst würde „wieder einschalten" auch Gruppen und Kanäle laut machen.
        if popsUp(app: id) != want { user.insert(NoticeRule(app: id, verdict: want ? .popUp : .quiet), at: 0) }
    }
}
