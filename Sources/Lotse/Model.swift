import SwiftUI
import AppKit

enum IslandMode { case compact, peek, drop, expanded }
enum Tab: String, CaseIterable { case home, work, mix, stow }

struct Notice: Identifiable {
    enum Kind { case system, claude, calendar, info }
    let id = UUID()
    var kind: Kind
    var appID: String?
    var appName: String
    var title: String
    var body: String
    var date: Date = Date()
    var url: URL? = nil
    var sessionID: String? = nil
    var brief = false              // kurze Bestätigung ohne Knöpfe
    var symbol: String? = nil      // Symbol für kleine Meldungen (Laden, Kopfhörer …)
    var card: String? = nil        // gestaltete Geräte-Karte, z. B. "headphones"
    /// Nummer des Eintrags in der Mitteilungszentrale – verschwindet er dort (gelesen, weggeklickt), geht er auch hier.
    var recordID: Int64? = nil
    /// Wie lange der Hinweis stehen bleibt (Sekunden); nil = übliche Dauer. Termin-Erinnerungen bleiben länger.
    var hold: TimeInterval? = nil
    /// Leiser Ton beim Erscheinen (Termin beginnt gleich).
    var sound = false
    /// Der Termin hinter einer Erinnerung – daraus baut die Insel die Terminkarte.
    var event: CalEvent? = nil
    /// Kleine Meldung ohne Knöpfe (Pille oder Geräte-Karte).
    var small: Bool { brief || card != nil }
}

extension Notice.Kind {
    init(demo: String) {
        switch demo {
        case "calendar": self = .calendar
        case "claude": self = .claude
        case "info": self = .info
        default: self = .system
        }
    }
}

/// Eine App, die gerade Ton ausgibt (für den Mixer).
struct MixApp: Identifiable, Equatable {
    let id: String
    var name: String
    var url: URL?
    var scriptable: Bool           // hat einen eigenen Regler (Spotify, Musik)
    var level: Double? = nil       // 0…1, nur für Apps mit eigenem Regler
}

/// Wozu ein Kalender gehört. Die Zuordnung hängt am Kalender; jeder Termin erbt sie.
enum CalRole: String, CaseIterable {
    case none, work, personal
    var title: String { self == .work ? "Arbeit" : self == .personal ? "Privat" : "Ohne Angabe" }
    var symbol: String? { self == .work ? "briefcase.fill" : self == .personal ? "house.fill" : nil }

    /// Vorschlag aus Konto und Name – nur solange du nichts selbst festgelegt hast.
    static func guess(account: String, title: String, exchange: Bool) -> CalRole {
        let t = (account + " " + title).lowercased()
        if ["feiertag", "holiday", "geburtstag", "birthday"].contains(where: t.contains) { return .none }
        if ["privat", "familie", "family", "zuhause", "home", "personal"].contains(where: t.contains) { return .personal }
        if ["arbeit", "work", "büro", "buero", "office", "firma", "team"].contains(where: t.contains) { return .work }
        if ["gmail.com", "googlemail.com", "icloud", "me.com", "mac.com", "gmx.", "web.de", "t-online", "outlook.com", "hotmail", "yahoo"].contains(where: t.contains) { return .personal }
        if exchange || t.contains("@") { return .work }      // Exchange oder Adresse mit eigener Domain
        return .none
    }
}

struct CalendarChoice: Identifiable, Equatable {
    let id: String
    var title: String
    var account: String
    var enabled: Bool
    var role: CalRole = .none
}

struct CalEvent: Identifiable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var color: Color
    var joinURL: URL?
    var allDay = false
    var role: CalRole = .none
    /// Ort des Termins (leer, wenn keiner eingetragen ist) und Name des Kalenders.
    var place = ""
    var calendar = ""

    /// Wo der Termin stattfindet: der Dienst des Beitritts-Links oder der eingetragene Ort.
    var whereLabel: String {
        if let h = joinURL?.host?.lowercased() {
            if h.contains("meet.google") { return "Google Meet" }
            if h.contains("zoom") { return "Zoom" }
            if h.contains("teams") { return "Teams" }
            if h.contains("webex") { return "Webex" }
            return "Videocall"
        }
        return place.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    /// Der Titel, wie er gezeigt werden darf: Im Besprechungsmodus bleiben private Termine ohne Namen.
    func label(discreet: Bool) -> String { discreet && role == .personal ? "Privater Termin" : title }

    /// Titel mit kleinem Symbol davor (Aktentasche = Arbeit, Haus = privat).
    func marked(discreet: Bool) -> Text {
        guard let s = role.symbol else { return Text(label(discreet: discreet)) }
        return Text("\(Text(Image(systemName: s)).font(.system(size: 8.5)).baselineOffset(1)) \(label(discreet: discreet))")
    }
}

/// Eine geparkte Datei in der Ablage.
struct ShelfItem: Identifiable, Equatable {
    var id: String { url.path }
    var url: URL
    var added: Date

    static func load() -> [ShelfItem] {
        let raw = UserDefaults.standard.array(forKey: "shelf") as? [[String: Any]] ?? []
        return raw.compactMap { d in
            guard let p = d["path"] as? String, let t = d["added"] as? Double else { return nil }
            return ShelfItem(url: URL(fileURLWithPath: p), added: Date(timeIntervalSince1970: t))
        }
    }
    static func save(_ items: [ShelfItem]) {
        UserDefaults.standard.set(items.map { ["path": $0.url.path, "added": $0.added.timeIntervalSince1970] }, forKey: "shelf")
    }
}

enum WaveStyle: String, CaseIterable {
    case fine, bold, comet, breath, outline, off
    var title: String {
        switch self {
        case .fine: return "Feine Welle"
        case .bold: return "Kräftige Welle"
        case .comet: return "Komet (Lichtpunkt läuft am Rand entlang)"
        case .breath: return "Atem (Rand glimmt auf und ab)"
        case .outline: return "Umriss (Licht läuft um die ganze Pille)"
        case .off: return "Aus"
        }
    }
}

struct ClaudeSession: Identifiable {
    enum Status { case working, waiting, done }
    let id: String
    var project: String
    var status: Status
    var message: String
    var updated: Date
    var cwd: String = ""
    var transcript: String = ""
    var detail: String = ""        // was Claude gerade tut, z. B. „Bash · swift build“
    var model: String = ""
    var planDone = 0
    var planTotal = 0
    var planStep = ""
    var contextPercent: Int? = nil
    var summary = ""               // ein Satz: was Claude zuletzt erreicht hat
    var tookSeconds: Int? = nil    // Dauer des letzten Durchgangs
    var doneAt: Date? = nil
    var startedAt: Date? = nil     // Beginn des laufenden Durchgangs
    var host = ""                  // Kennung der Session in der Claude-App (local_…)
    var bundle = ""
    var titled = false
}

/// Eine Freigabe, die Claude gerade erfragt und die aus der Insel beantwortet werden kann.
struct PermissionAsk: Identifiable {
    let id: String                 // Dateiname der Antwort
    var sessionID: String
    var project: String
    var tool: String
    var detail: String             // der vollständige Befehl bzw. die Datei
    var summary = ""               // Claudes eigene Kurzbeschreibung in Klartext
    var risk = ""                  // warum der Befehl heikel ist – leer = unauffällig
    /// Stellt Claude eine Frage (statt um eine Freigabe zu bitten), stehen hier Frage und Antwortmöglichkeiten.
    var questions: [Question] = []
    var isQuestion: Bool { !questions.isEmpty }

    struct Question: Identifiable {
        let id = UUID()
        var header: String
        var text: String
        var options: [String]
        var multi: Bool
    }
    var date = Date()
}

struct UsageLimit: Identifiable {
    var id: String { label }
    var label: String
    var percent: Double
    var resets: Date?
}

struct Track {
    var title: String
    var artist: String
    var isPlaying: Bool
    var artworkURL: String?
    var artwork: NSImage?
}

final class IslandModel: ObservableObject {
    @Published var mode: IslandMode = .compact {
        didSet {
            // Nach dem Zuklappen eine wartende Termin-Erinnerung nachreichen (höchstens drei Minuten alt).
            guard mode == .compact, oldValue == .expanded, let w = waitingPeek else { return }
            waitingPeek = nil
            guard Date().timeIntervalSince(w.since) < 180 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.post(w.notice) }
        }
    }
    @Published var tab: Tab = .home
    @Published var glass: GlassStyle = GlassStyle(rawValue: UserDefaults.standard.string(forKey: "glass") ?? "") ?? .liquid {
        didSet { if glass != .preview { UserDefaults.standard.set(glass.rawValue, forKey: "glass") } }
    }
    @Published var usageHint = ""

    /// Farbschema der Insel.
    @Published var palette = Theme.palette {
        didSet { Theme.palette = palette; UserDefaults.standard.set(palette.rawValue, forKey: "palette") }
    }

    /// Wie die Ruhe-Pille zeigt, dass Claude arbeitet.
    @Published var wave: WaveStyle = WaveStyle(rawValue: UserDefaults.standard.string(forKey: "wave") ?? "") ?? .fine {
        didSet { UserDefaults.standard.set(wave.rawValue, forKey: "wave") }
    }
    /// Bis dahin läuft die Welle zur Ansicht, auch wenn Claude gerade nicht arbeitet.
    @Published var wavePreviewUntil = Date.distantPast

    // Mitschnitt eines Calls (nur Ton)
    @Published var recState: RecState = .idle {
        didSet {
            // Ein neuer Mitschnitt beginnt ohne altes Transkript; ein fertiger wird auf Wunsch gleich mitgeschrieben.
            if case .done(let url) = recState {
                transcript = .none
                if autoTranscribe, url.pathExtension == "m4a" { transcribe?(url) }
            } else if recState == .starting { transcript = .none }
        }
    }
    var toggleRecording: (() -> Void)?
    @Published var transcript: TranscriptState = .none
    @Published var autoTranscribe = UserDefaults.standard.object(forKey: "autoTranscribe") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoTranscribe, forKey: "autoTranscribe") }
    }
    @Published var transcriptLanguage = UserDefaults.standard.string(forKey: "transcriptLanguage") ?? "de-DE" {
        didSet { UserDefaults.standard.set(transcriptLanguage, forKey: "transcriptLanguage") }
    }
    var transcribe: ((URL) -> Void)?
    var askClaude: ((URL) -> Void)?

    /// Claudes Verbrauch von heute (aus den Protokollen auf diesem Mac).
    @Published var today: ClaudeDay?
    /// Wetter der nächsten Stunden – erscheint nach einem Klick auf die Wetter-Kachel.
    @Published var forecast: [HourWeather] = []
    @Published var showForecast = false

    // Verlauf der Zwischenablage
    @Published var clips: [Clip] = []
    @Published var clipboardOn = UserDefaults.standard.object(forKey: "clipboardOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(clipboardOn, forKey: "clipboardOn")
            if !clipboardOn { clips = [] }
        }
    }
    var copyClip: ((Clip) -> Void)?

    // Wetter, Schnellzugriffe
    @Published var weather: Weather?
    @Published var weatherCity = ""
    var setWeatherCity: ((String) -> Void)?
    var askWeatherCity: (() -> Void)?
    var showFolders: (() -> Void)?

    // Mixer
    @Published var volume = 0.0            // Gesamtlautstärke 0…1
    @Published var muted = false
    @Published var volumeAdjustable = false
    @Published var outputName = ""
    @Published var outputs: [AudioOut] = []
    var setOutput: ((AudioOut) -> Void)?
    @Published var mixApps: [MixApp] = []
    var setVolume: ((Double) -> Void)?
    var setMuted: ((Bool) -> Void)?
    var setAppLevel: ((String, Double) -> Void)?

    // Besprechungsmodus: im Call keine Inhalte in Hinweisen, beim Bildschirmteilen gar keine Hinweise.
    enum Meeting: String { case auto, on, off }
    @Published var meetingSetting = Meeting(rawValue: UserDefaults.standard.string(forKey: "meeting") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(meetingSetting.rawValue, forKey: "meeting") }
    }
    @Published var inCall = false
    @Published var sharing = false
    /// Inhalte von Hinweisen verbergen (im Call).
    var discreet: Bool { meetingSetting == .on || (meetingSetting == .auto && (inCall || sharing)) }
    /// Gar nicht aufklappen (Bildschirm wird geteilt oder der Modus ist von Hand eingeschaltet).
    var silent: Bool { meetingSetting == .on || (meetingSetting == .auto && sharing) }

    /// Welche Mitteilungen aufklappen dürfen.
    @Published var filter = NoticeFilter.load() { didSet { filter.save() } }
    /// Gehört eine Mitteilung der Claude-App zu einer Session, die Lotse schon über die Hooks kennt?
    func isHookSession(thread: String, ident: String) -> Bool {
        let hay = (thread + " " + ident).lowercased()
        return sessions.contains { s in
            let ids = [s.id, s.host.replacingOccurrences(of: "local_", with: "")].map { $0.lowercased() }.filter { $0.count >= 8 }
            return ids.contains { hay.contains($0) }
        }
    }

    /// Ist die Insel gerade auf dem Bildschirm zu sehen (nicht in einem Vollbild-Space)?
    @Published var islandVisible = true

    /// Die Freigabe, die der Nutzer in diesem Moment wirklich vor sich hat.
    var visibleAsk: PermissionAsk? {
        guard islandVisible else { return nil }
        switch mode {
        case .peek: return peekAsk
        case .expanded: return tab == .home ? asks.first : nil
        default: return nil
        }
    }

    /// Holt eine wartende Freigabe wieder nach vorn (z. B. wenn ein Kürzel gedrückt wird, sie aber verdeckt ist).
    func resurfaceAsk() {
        guard let ask = asks.first else { return }
        if mode == .expanded { withAnimation(Self.spring) { tab = .home }; return }
        post(Notice(kind: .claude, appID: Apps.claude, appName: "Claude · \(ask.project)",
                    title: "Claude wartet auf dein OK", body: ask.summary.isEmpty ? ask.detail : ask.summary,
                    sessionID: ask.sessionID))
    }
    @Published var hasNotch = false
    @Published var notchWidth: CGFloat = 0
    @Published var topInset: CGFloat = 28

    @Published var notices: [Notice] = []        // gespiegelte System-Mitteilungen
    @Published var peekNotice: Notice?
    @Published var unread = 0
    @Published var events: [CalEvent] = []
    /// Alle Termine der nächsten sieben Tage (mit ganztägigen) – für die Wochenansicht im Überblick.
    /// Titel von Terminen, die nur in ausgeblendeten Kalendern stehen – deren Mac-Mitteilungen bleiben draußen.
    var hiddenEventTitles: Set<String> = []
    @Published var week: [CalEvent] = []
    @Published var showWeek = false
    @Published var calendars: [CalendarChoice] = []
    var toggleCalendar: ((String) -> Void)?
    var requestCalendar: (() -> Void)?
    var setCalendarRole: ((String, CalRole) -> Void)?
    /// Filter der Wochenansicht: alle, nur Arbeit oder nur Privates.
    @Published var weekRole: CalRole = .none
    var openSetup: (() -> Void)?
    @Published var sessions: [ClaudeSession] = []
    @Published var asks: [PermissionAsk] = []
    @Published var limits: [UsageLimit] = []
    @Published var limitsUpdated: Date?
    @Published var track: Track?
    @Published var now = Date()
    @Published var calendarDenied = false
    @Published var notificationsDenied = false

    // Arbeitsplatz
    @Published var note = "" { didSet { save() } }
    @Published var focusMinutes = 25 { didSet { save() } }
    @Published var focusEnd: Date?
    @Published var focusPaused: TimeInterval?

    // Ablage
    // Ablage: geparkte Dateien. Lotse merkt sich nur, wo sie liegen – kopiert wird nichts,
    // und nach der eingestellten Zeit verschwindet der Eintrag wieder (die Datei selbst bleibt, wo sie ist).
    @Published var shelf: [ShelfItem] = ShelfItem.load() { didSet { ShelfItem.save(shelf) } }
    /// Minuten, nach denen ein Eintrag die Ablage verlässt. 0 = bleibt, bis du ihn entfernst.
    @Published var shelfMinutes = UserDefaults.standard.object(forKey: "shelfMinutes") as? Int ?? 30 {
        didSet { UserDefaults.standard.set(shelfMinutes, forKey: "shelfMinutes"); pruneShelf() }
    }
    /// Sekunden, die die Maus auf der Pille ruhen muss, bevor die Insel aufklappt.
    @Published var hoverDelay = UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.2 {
        didSet { UserDefaults.standard.set(hoverDelay, forKey: "hoverDelay") }
    }
    /// Abgeschaltete Reiter und Kacheln (Einstellungen → Allgemein).
    @Published var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenParts") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(hidden), forKey: "hiddenParts")
            if hidden.contains("tab." + tab.rawValue) { tab = .home }
        }
    }
    func shows(_ part: String) -> Bool { !hidden.contains(part) }

    func pruneShelf() {
        let fm = FileManager.default
        let limit = TimeInterval(shelfMinutes * 60)
        let keep = shelf.filter { fm.fileExists(atPath: $0.url.path) && (shelfMinutes == 0 || Date().timeIntervalSince($0.added) < limit) }
        if keep.count != shelf.count { withAnimation(Self.spring) { shelf = keep } }
    }

    func convertShelfImages() {
        let images = shelf.map(\.url).filter { Stow.isImage($0) }
        guard !images.isEmpty else { return }
        withAnimation(Self.spring) { stowResult = []; stowMessage = ""; stowFiles = images }
    }

    @Published var stowFiles: [URL] = []
    @Published var stowBusy = false
    @Published var stowResult: [URL] = []
    @Published var stowMessage = ""

    /// Aktuelle Größe der Insel, vom View gemeldet – für die Maus-Erkennung.
    var pillSize: CGSize = CGSize(width: 310, height: 28)
    /// Gemessene Breite dessen, was rechts in der Ruhe-Pille steht (Laufzeit, Zähler, Timer).
    @Published var trailWidth: CGFloat = 0
    var musicAction: ((String) -> Void)?
    var answer: ((PermissionAsk, String) -> Void)?
    var openSession: ((ClaudeSession) -> Void)?
    var releaseKeyboard: (() -> Void)?

    private var hovering = false
    private var hoverWork: DispatchWorkItem?
    private var peekWork: DispatchWorkItem?
    private var focusWork: DispatchWorkItem?
    private var clock: Timer?
    private var loaded = false

    /// Wie im Referenzfilm: zügig, aber ohne Nachfedern.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.95)

    init(persist: Bool = true) {
        if persist { load() }
        loaded = persist
        clock = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.now = Date()
            self?.pruneShelf()
        }
        pruneShelf()
    }

    // MARK: Hinweise und Hover

    /// Offen halten, solange etwas auf eine Entscheidung wartet.
    var pinned: Bool { !stowFiles.isEmpty || pinnedOpen }

    /// Per Tastenkürzel geöffnet – bleibt offen, bis Esc oder das Kürzel erneut gedrückt wird.
    @Published var pinnedOpen = false

    func togglePinned() {
        withAnimation(Self.spring) {
            pinnedOpen.toggle()
            if pinnedOpen {
                if mode != .expanded { tab = .home }
                mode = .expanded; unread = 0
            } else {
                releaseKeyboard?()
                // Lag die Maus nie auf der Insel, klappt sonst niemand sie wieder zu.
                if !hovering, stowFiles.isEmpty, mode == .expanded { hoverWork?.cancel(); mode = .compact }
            }
        }
    }

    // „Leeren" lässt sich ein paar Sekunden lang zurücknehmen.
    @Published var cleared: [Notice] = []
    private var clearWork: DispatchWorkItem?

    func clearNotices() {
        clearWork?.cancel()
        withAnimation(Self.spring) { cleared = notices; notices = [] }
        let work = DispatchWorkItem { [weak self] in withAnimation(Self.spring) { self?.cleared = [] } }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }

    func restoreNotices() {
        clearWork?.cancel()
        withAnimation(Self.spring) { notices = cleared + notices; cleared = [] }
    }

    /// - peek: Insel kurz aufklappen.  - count: im Zähler der zugeklappten Pille mitzählen.
    func post(_ notice: Notice, peek: Bool = true, count: Bool? = nil) {
        if notice.kind == .system {
            notices.insert(notice, at: 0)
            if notices.count > 30 { notices.removeLast(notices.count - 30) }
            if mode != .expanded, count ?? peek { unread += 1 }
        }
        // Freigaben und kurze Bestätigungen kommen immer durch; alles andere schweigt, solange der Bildschirm geteilt wird.
        // Nur Lotses eigene kleine Meldungen (Laden, Kopfhörer) kommen immer durch – eine Mail-Karte nicht.
        // „Termin beginnt gleich" kommt auch beim Bildschirmteilen durch – dann ohne Titel.
        let meetingNow = notice.kind == .calendar && notice.sound
        let urgent = meetingNow || (notice.small && notice.kind == .info) || (notice.sessionID != nil && asks.contains { $0.sessionID == notice.sessionID })
        if notice.kind == .calendar { log("Termin-Erinnerung: \(discreet ? "(Titel verborgen)" : notice.title) – \(notice.body)\(silent && !urgent ? " · stumm (Bildschirm wird geteilt)" : mode == .expanded ? " · Insel offen, folgt beim Zuklappen" : "")") }
        if notice.sound, UserDefaults.standard.object(forKey: "calendarSound") as? Bool ?? true, !inCall { Self.playMeetingSound() }
        if silent, !urgent {
            if notice.kind != .system, mode != .expanded { unread += 1 }
            return
        }
        // Ist die Insel offen, aber auf einem anderen Reiter: für eine Freigabe zum Überblick wechseln.
        if urgent, !notice.small, mode == .expanded, tab != .home { withAnimation(Self.spring) { tab = .home } }
        // Eine offene Freigabe im Kurz-Hinweis wird von anderen Hinweisen nicht verdrängt.
        if mode == .peek, peekAsk != nil, !urgent { return }
        // Ist die Insel gerade offen, geht eine Termin-Erinnerung nicht verloren: Sie erscheint, sobald die Insel zuklappt.
        if peek, mode == .expanded, notice.kind == .calendar { waitingPeek = (notice, Date()); return }
        guard peek, mode == .compact || mode == .peek else { return }
        peekWork?.cancel()
        var shown = notice
        if discreet, !urgent {
            // Im Call: zeigen, dass etwas da ist – aber nicht, was drinsteht.
            switch notice.kind {
            case .system: shown.title = "Neue Mitteilung"
            case .calendar: shown.title = "Termin"
            case .claude: shown.appName = "Claude"
            case .info: break
            }
            // Wann ein Termin beginnt, verrät nichts – nur der Titel bleibt verborgen.
            if notice.kind != .calendar { shown.body = "" }
        }
        if mode == .peek {
            // Ein neuer Hinweis ersetzt den alten nicht an Ort und Stelle: Die Insel zieht sich kurz zusammen
            // und wächst dann zum nächsten wieder auf.
            withAnimation(Self.spring) { mode = .compact }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { [weak self] in self?.present(shown) }
        } else {
            present(shown)
        }
    }

    private func present(_ shown: Notice) {
        guard mode == .compact || mode == .peek else { return }
        peekHeld = false
        peekWork?.cancel()
        withAnimation(Self.spring) {
            peekNotice = shown
            mode = .peek
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .peek else { return }
            // Eine offene Freigabe bleibt stehen, bis sie beantwortet ist.
            if self.peekAsk != nil { return }
            withAnimation(Self.spring) { self.mode = .compact }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (shown.hold ?? (shown.card == "mail" ? 5 : shown.card != nil ? 3.6 : shown.brief ? 2.2 : 6)), execute: work)
    }

    /// Der Ton der Termin-Erinnerung: ein Echolot-Ping (Resources/Termin.wav). Fehlt die Datei, ein Systemton.
    private static let meetingSound: NSSound? = Bundle.main.url(forResource: "Termin", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: true) } ?? NSSound(named: "Tink")
    static func playMeetingSound() {
        meetingSound?.stop()
        meetingSound?.play()
    }

    /// Termin-Erinnerung, die auf das Zuklappen der Insel wartet.
    private var waitingPeek: (notice: Notice, since: Date)?

    /// Die Freigabe, die zum gerade gezeigten Hinweis gehört.
    var peekAsk: PermissionAsk? {
        guard let sid = peekNotice?.sessionID else { return nil }
        return asks.first { $0.sessionID == sid }
    }

    private var peekHeld = false

    /// Solange die Maus auf einem Hinweis liegt, bleibt er stehen; danach verschwindet er nach kurzer Zeit.
    func holdPeek(_ on: Bool) {
        guard mode == .peek, on != peekHeld else { return }
        peekHeld = on
        peekWork?.cancel()
        guard !on else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode == .peek, self.peekAsk == nil else { return }
            withAnimation(Self.spring) { self.mode = .compact }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func dismissPeek() {
        peekHeld = false
        peekWork?.cancel()
        guard mode == .peek else { return }
        withAnimation(Self.spring) { mode = .compact }
    }

    func setHover(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        hoverWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.mode != .drop else { return }
            withAnimation(Self.spring) {
                if inside {
                    self.peekWork?.cancel()
                    if self.mode != .expanded {
                        self.tab = self.stowFiles.isEmpty ? .home : .stow
                        if self.hidden.contains("tab." + self.tab.rawValue) { self.tab = .home }
                    }
                    self.mode = .expanded
                    self.unread = 0
                } else {
                    self.mode = .compact
                }
            }
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? hoverDelay : 0.35), execute: work)
    }

    func setDragging(_ dragging: Bool) {
        if dragging, mode == .compact || mode == .peek {
            peekWork?.cancel()
            withAnimation(Self.spring) { mode = .drop }
        } else if !dragging, mode == .drop {
            withAnimation(Self.spring) { mode = stowFiles.isEmpty ? .compact : .expanded }
        }
    }

    /// Losgelassene Dateien wandern in die Ablage. Umgewandelt wird erst auf Wunsch.
    func acceptDrop(_ urls: [URL]) {
        var list = shelf
        for u in urls where !list.contains(where: { $0.url == u }) { list.insert(ShelfItem(url: u, added: Date()), at: 0) }
        withAnimation(Self.spring) {
            shelf = Array(list.prefix(24))
            stowFiles = []; stowResult = []; stowMessage = ""
            tab = .stow
            mode = .expanded
        }
    }

    /// Beendet das Umwandeln und zeigt wieder die Ablage.
    func closeStow() {
        withAnimation(Self.spring) { stowFiles = []; stowResult = []; stowMessage = "" }
    }

    func runStow(_ job: Stow.Job) {
        let files = stowFiles
        stowBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let out = Stow.run(job, files: files)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                withAnimation(Self.spring) {
                    self.stowBusy = false
                    self.stowResult = out
                    self.stowMessage = out.isEmpty
                        ? "Das hat nicht geklappt."
                        : (out.count == 1 ? "Gespeichert: \(out[0].lastPathComponent)" : "\(out.count) Dateien gespeichert")
                }
            }
        }
    }

    func open(_ notice: Notice) {
        if let sid = notice.sessionID, let s = sessions.first(where: { $0.id == sid }) { openSession?(s) }
        else if let url = notice.url { log("Öffne \(url.scheme ?? "")://\(url.host ?? "")\(url.path.prefix(24))…"); NSWorkspace.shared.open(url) }
        // Eine Termin-Erinnerung ohne Beitritts-Link wird nur weggeklickt – die Kalender-App bleibt zu.
        else if notice.kind == .calendar {}
        else if let id = notice.appID { log("Öffne App \(id) (Mitteilung ohne Ziel)"); Apps.activate(id) }
        notices.removeAll { $0.id == notice.id }
    }

    var nextEvent: CalEvent? { events.first { $0.end > now } }

    // MARK: Fokus-Timer

    var focusRunning: Bool { focusEnd != nil }

    func focusRemaining(at date: Date = Date()) -> TimeInterval {
        if let end = focusEnd { return max(0, end.timeIntervalSince(date)) }
        return focusPaused ?? TimeInterval(focusMinutes * 60)
    }

    func focusToggle() {
        focusWork?.cancel()
        if let end = focusEnd {
            focusPaused = max(0, end.timeIntervalSinceNow)
            focusEnd = nil
            return
        }
        let secs = focusPaused ?? TimeInterval(focusMinutes * 60)
        focusPaused = nil
        focusEnd = Date().addingTimeInterval(secs)
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.focusEnd = nil
            NSSound(named: "Glass")?.play()
            self.post(Notice(kind: .info, appID: nil, appName: "Fokus", title: "Fokuszeit vorbei",
                             body: "\(self.focusMinutes) Minuten geschafft. Zeit für eine Pause."))
        }
        focusWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + secs, execute: work)
    }

    func focusReset() {
        focusWork?.cancel()
        focusEnd = nil
        focusPaused = nil
    }

    func focusAdjust(_ delta: Int) {
        guard !focusRunning, focusPaused == nil else { return }
        focusMinutes = min(120, max(5, focusMinutes + delta))
    }

    // MARK: Speichern

    private struct Saved: Codable {
        var note = ""
        var focusMinutes = 25
    }

    private static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lotse/arbeitsplatz.json")

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        note = s.note; focusMinutes = s.focusMinutes
    }

    private func save() {
        guard loaded else { return }
        try? FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Saved(note: note, focusMinutes: focusMinutes)) {
            try? data.write(to: Self.file, options: .atomic)
        }
    }
}

enum Apps {
    static let claude = "com.anthropic.claudefordesktop"
    static let spotify = "com.spotify.client"
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func icon(_ id: String?) -> NSImage {
        guard let id else { return NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)! }
        if let i = icons[id] { return i }
        let img = url(id).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)!
        icons[id] = img
        return img
    }

    static func name(_ id: String) -> String {
        if let n = names[id] { return n }
        var n = "System"       // Systemdienste ohne eigene App (z. B. Spielmodus)
        if let u = url(id) {
            n = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
        }
        names[id] = n
        return n
    }

    static func activate(_ id: String) {
        guard let u = url(id) else { return }
        NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum Fmt {
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = format; return f
    }
    static let time = make("HH:mm")
    static let day = make("EEEE, d. MMMM")
    static let shortDay = make("EE d.")

    static func until(_ date: Date, now: Date) -> String {
        if date <= now { return "läuft" }
        let mins = Int(ceil(date.timeIntervalSince(now) / 60))
        if mins < 60 { return "in \(mins) Min" }
        if Calendar.current.isDate(date, inSameDayAs: now) { return time.string(from: date) }
        return "morgen " + time.string(from: date)
    }

    static func ago(_ date: Date, now: Date) -> String {
        let mins = Int(now.timeIntervalSince(date) / 60)
        if mins < 1 { return "jetzt" }
        if mins < 60 { return "vor \(mins) Min" }
        return "vor \(mins / 60) Std"
    }

    /// Verstrichene Zeit: „4:07", ab einer Stunde „1:04:07".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

func log(_ s: String) {
    let line = "\(Date()) \(s)\n"
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Lotse.log")
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}
