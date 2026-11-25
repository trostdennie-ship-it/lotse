import AppKit
import SwiftUI
import EventKit
import SQLite3

// MARK: - Kalender

final class CalendarSource {
    private let model: IslandModel
    private let store = EKEventStore()
    private var timer: Timer?
    private var alerted = Set<String>()
    private var exact: Timer?

    init(model: IslandModel) { self.model = model }

    private var started = false

    func start() {
        // Beim allerersten Start fragt der Einrichtungsassistent nach dem Kalender – nicht ein Dialog aus dem Nichts.
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined, !OnboardingWindow.done, !asking { return }
        guard !started else { return }
        started = true
        store.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.model.calendarDenied = !granted
                guard granted else { return }
                NotificationCenter.default.addObserver(
                    forName: .EKEventStoreChanged, object: self.store, queue: .main
                ) { [weak self] _ in self?.reload() }
                self.timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                    self?.reload()
                }
                self.reload()
            }
        }
    }

    private var asking = false
    /// Aus dem Assistenten: jetzt wirklich nach dem Zugriff fragen.
    func request() { asking = true; start() }

    private var loggedCalendars = ""

    /// Liest die Kalender, die macOS kennt, und merkt, welche davon angezeigt werden sollen.
    /// Vorgabe: Gibt es Konten aus dem Netz (Google, Exchange, iCloud …), bleiben rein lokale Kalender aus.
    private func chosenCalendars() -> [EKCalendar] {
        let all = store.calendars(for: .event)
        let hasNetwork = all.contains { $0.source.sourceType != .local && $0.source.sourceType != .birthdays && $0.source.sourceType != .subscribed }
        let off = Set(UserDefaults.standard.stringArray(forKey: "calendarsOff") ?? [])
        let on = Set(UserDefaults.standard.stringArray(forKey: "calendarsOn") ?? [])
        // Ganze Konten, die nicht in den Notch sollen (z. B. Exchange, iCloud).
        let accountsOff = Set(UserDefaults.standard.stringArray(forKey: "calendarAccountsOff") ?? [])
        var choices: [CalendarChoice] = []
        var picked: [EKCalendar] = []
        let saved = UserDefaults.standard.dictionary(forKey: "calendarRoles") as? [String: String] ?? [:]
        for c in all.sorted(by: { ($0.source.title, $0.title) < ($1.source.title, $1.title) }) {
            let local = c.source.sourceType == .local || c.source.sourceType == .birthdays
            let standard = !(hasNetwork && local) && !accountsOff.contains(c.source.title)
            let enabled = on.contains(c.calendarIdentifier) || (standard && !off.contains(c.calendarIdentifier))
            let role = saved[c.calendarIdentifier].flatMap(CalRole.init(rawValue:))
                ?? CalRole.guess(account: c.source.title, title: c.title, exchange: c.source.sourceType == .exchange)
            roles[c.calendarIdentifier] = role
            choices.append(CalendarChoice(id: c.calendarIdentifier, title: c.title, account: c.source.title, enabled: enabled, role: role))
            if enabled { picked.append(c) }
        }
        if choices != model.calendars { model.calendars = choices }
        let summary = choices.map { "\($0.enabled ? "✓" : "–") \($0.account) / \($0.title)\($0.role == .none ? "" : " [" + $0.role.title + "]")" }.joined(separator: "; ")
        if summary != loggedCalendars { loggedCalendars = summary; log("Kalender: \(summary)") }
        return picked
    }

    /// Arbeit oder privat, je Kalender.
    private var roles: [String: CalRole] = [:]

    func setRole(_ id: String, _ role: CalRole) {
        var saved = UserDefaults.standard.dictionary(forKey: "calendarRoles") as? [String: String] ?? [:]
        saved[id] = role.rawValue
        UserDefaults.standard.set(saved, forKey: "calendarRoles")
        reload()
    }

    /// Schaltet einen Kalender ein oder aus (aus dem Menü).
    func toggleCalendar(_ id: String) {
        guard let c = model.calendars.first(where: { $0.id == id }) else { return }
        var off = Set(UserDefaults.standard.stringArray(forKey: "calendarsOff") ?? [])
        var on = Set(UserDefaults.standard.stringArray(forKey: "calendarsOn") ?? [])
        if c.enabled { off.insert(id); on.remove(id) } else { on.insert(id); off.remove(id) }
        UserDefaults.standard.set(Array(off), forKey: "calendarsOff")
        UserDefaults.standard.set(Array(on), forKey: "calendarsOn")
        reload()
    }

    private func reload() {
        let now = Date()
        let cal = Calendar.current
        let end = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        let chosen = chosenCalendars()
        // Termine aus ausgeblendeten Kalendern merken: macOS meldet sie trotzdem, Lotse soll sie nicht spiegeln.
        let chosenIDs = Set(chosen.map(\.calendarIdentifier))
        let hiddenCals = store.calendars(for: .event).filter { !chosenIDs.contains($0.calendarIdentifier) }
        let from = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        let to = cal.date(byAdding: .day, value: 8, to: cal.startOfDay(for: now))!
        func titles(_ cals: [EKCalendar]) -> Set<String> {
            guard !cals.isEmpty else { return [] }
            return Set(store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: cals))
                .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        }
        model.hiddenEventTitles = titles(hiddenCals).subtracting(titles(chosen))
        // Mitteilungen, die vor dem ersten Laden des Kalenders eingelesen wurden (z. B. beim Start), nachträglich aussortieren.
        let hidden = model.hiddenEventTitles
        if !hidden.isEmpty {
            func isHidden(_ n: Notice) -> Bool {
                n.appID?.lowercased() == "com.apple.ical"
                    && [n.title, n.body].contains { hidden.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            }
            let gone = model.notices.filter(isHidden).count
            if gone > 0 { model.notices.removeAll(where: isHidden); log("Kalender: \(gone) Mitteilung(en) aus ausgeblendeten Kalendern aussortiert") }
            if let p = model.peekNotice, isHidden(p) { model.dismissPeek() }
        }
        // Für Einladungen: Sie gelten nur, wenn der Termin in einem angezeigten Kalender steht (auch weiter voraus).
        let far = cal.date(byAdding: .day, value: 120, to: cal.startOfDay(for: now))!
        model.shownEventTitles = chosen.isEmpty ? [] : Set(store.events(matching: store.predicateForEvents(withStart: from, end: far, calendars: chosen))
            .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) })
        guard !chosen.isEmpty else { model.events = []; model.week = []; return }
        let raw = store.events(matching: store.predicateForEvents(withStart: cal.startOfDay(for: now), end: end, calendars: chosen))
        let events = raw
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(60)
            .map { e in
                CalEvent(
                    id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                    title: e.title ?? "Termin", start: e.startDate, end: e.endDate,
                    color: Color(nsColor: e.calendar.color), joinURL: Self.joinURL(e),
                    role: roles[e.calendar.calendarIdentifier] ?? .none,
                    place: e.location ?? "", calendar: e.calendar.title)
            }
        model.events = Array(events)
        // Die Woche: heute und die sechs Tage danach, diesmal mit ganztägigen Terminen.
        let weekEnd = cal.date(byAdding: .day, value: 7, to: cal.startOfDay(for: now))!
        let weekRaw = store.events(matching: store.predicateForEvents(withStart: cal.startOfDay(for: now), end: weekEnd, calendars: chosen))
        var week: [CalEvent] = []
        for e in weekRaw where e.status != .canceled && !Self.declined(e) {
            week.append(CalEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                                 title: e.title ?? "Termin", start: e.startDate, end: e.endDate,
                                 color: Color(nsColor: e.calendar.color), joinURL: Self.joinURL(e), allDay: e.isAllDay,
                                 role: roles[e.calendar.calendarIdentifier] ?? .none))
        }
        week.sort { ($0.start, $0.title) < ($1.start, $1.title) }
        model.week = Array(week.prefix(150))
        model.now = now

        for e in events {
            let secs = e.start.timeIntervalSince(now)
            let key5 = e.id + "-5", key0 = e.id + "-0"
            let app = e.role == .none ? "Kalender" : "Kalender · \(e.role.title)"
            // Fünf Minuten vorher still, zum Beginn mit Ton. Damit beides pünktlich kommt, weckt `exact`
            // (unten) genau zu diesen Zeitpunkten; das Lesen alle 30 Sekunden ist nur das Netz darunter.
            if secs <= 300, secs > 2, !alerted.contains(key5) {
                alerted.insert(key5)
                model.post(Notice(kind: .calendar, appID: "com.apple.iCal", appName: app, title: e.title,
                                  body: "Beginnt \(Fmt.until(e.start, now: now)) · \(Fmt.time.string(from: e.start))",
                                  url: e.joinURL, hold: 12, event: e))
            } else if secs <= 2, secs > -120, !alerted.contains(key0) {
                alerted.insert(key0); alerted.insert(key5)
                model.post(Notice(kind: .calendar, appID: "com.apple.iCal", appName: app, title: e.title,
                                  body: "Beginnt jetzt", url: e.joinURL, hold: 60, sound: true, event: e))
            }
        }
        // Nächster fälliger Zeitpunkt: fünf Minuten vor einem Termin oder sein Beginn.
        let due = events.flatMap { [$0.start.addingTimeInterval(-300), $0.start.addingTimeInterval(-1)] }
            .map { $0.timeIntervalSince(now) }.filter { $0 > 0.5 }.min()
        exact?.invalidate()
        if let due, due < 3600 {
            exact = Timer.scheduledTimer(withTimeInterval: due + 0.2, repeats: false) { [weak self] _ in self?.reload() }
        }
    }

    private static func declined(_ e: EKEvent) -> Bool {
        e.attendees?.first { $0.isCurrentUser }?.participantStatus == .declined
    }

    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https://[^\s<>"]*(zoom\.us|teams\.microsoft\.com|teams\.live\.com|meet\.google\.com|webex\.com|whereby\.com)/[^\s<>"]+"#)

    private static func joinURL(_ e: EKEvent) -> URL? {
        let hay = [e.url?.absoluteString, e.location, e.notes].compactMap { $0 }.joined(separator: " ")
        guard let m = linkPattern.firstMatch(in: hay, range: NSRange(hay.startIndex..., in: hay)),
              let r = Range(m.range, in: hay) else { return nil }
        return URL(string: String(hay[r]))
    }
}

// MARK: - Claude Code (über Hooks, die Ereignisse als Dateien ablegen)

final class ClaudeSource {
    private let model: IslandModel
    private var watcher: DispatchSourceFileSystemObject?
    private var timer: Timer?
    private var plans: [String: [(text: String, status: String)]] = [:]

    /// Hintergrund-Befehle je Session (was, seit wann) und Sessions, deren Durchgang damit endete.
    private var background: [String: (what: String, since: Date)] = [:]
    private var resumed = Set<String>()

    static let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lotse")
    static let events = base.appendingPathComponent("events")
    static let answers = base.appendingPathComponent("answers")
    static let hook = base.appendingPathComponent("claude-hook.sh")
    static let askHook = base.appendingPathComponent("claude-ask.sh")

    init(model: IslandModel) { self.model = model }

    func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.events, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.answers, withIntermediateDirectories: true)
        write(Self.hook, """
        #!/bin/sh
        # Lotse: legt Claude-Code-Hook-Ereignisse fuer die Insel ab. Blockiert nie.
        d="$HOME/Library/Application Support/Lotse/events"
        [ -d "$d" ] || exit 0
        pgrep -xq Lotse || exit 0
        f="$d/$(date +%s)-$$-$RANDOM"
        # Nur das Nötige behalten (keine Dateiinhalte/Tool-Ausgaben) und merken, wo die Session läuft.
        /usr/bin/jq -c --arg h "$CLAUDE_CODE_HOST_SESSION_ID" --arg e "$CLAUDE_CODE_ENTRYPOINT" --arg b "$__CFBundleIdentifier" \
            'del(.tool_response, .tool_input.content, .tool_input.new_string, .tool_input.old_string, .prompt) | (if (.last_assistant_message | type) == "string" then .last_assistant_message |= .[0:600] else . end) + {lotse_host:$h, lotse_entry:$e, lotse_bundle:$b}' \
            > "$f.tmp" 2>/dev/null || cat > "$f.tmp" 2>/dev/null
        mv "$f.tmp" "$f.json" 2>/dev/null
        exit 0
        """)
        // Freigabe-Hook: meldet die Anfrage und wartet kurz auf die Antwort aus der Insel.
        // Ohne Antwort endet er ohne Entscheidung – dann fragt Claude ganz normal selbst.
        write(Self.askHook, """
        #!/bin/sh
        b="$HOME/Library/Application Support/Lotse"
        [ -d "$b/events" ] || exit 0
        pgrep -xq Lotse || exit 0
        id="ask-$(date +%s)-$$"
        in=$(cat)
        tool=$(printf '%s' "$in" | /usr/bin/jq -r '.tool_name // ""' 2>/dev/null)
        printf '%s' "$in" | /usr/bin/jq -c --arg h "$CLAUDE_CODE_HOST_SESSION_ID" --arg e "$CLAUDE_CODE_ENTRYPOINT" --arg b "$__CFBundleIdentifier" \
            '(if ((.tool_name // "") | test("^(Edit|Write|MultiEdit|NotebookEdit)$")) then del(.tool_input.content, .tool_input.new_string, .tool_input.old_string) else . end) + {lotse_host:$h, lotse_entry:$e, lotse_bundle:$b}' \
            > "$b/events/$id.tmp" 2>/dev/null || exit 0
        mv "$b/events/$id.tmp" "$b/events/$id.json" 2>/dev/null || exit 0
        # Eine Frage an dich ist keine Freigabe: nur melden, beantwortet wird sie in Claude.
        [ "$tool" = "AskUserQuestion" ] && exit 0
        a="$b/answers/$id"
        finish() { rm -f "$a"; : > "$b/events/$id.end"; }
        trap 'finish; exit 0' TERM INT HUP
        i=0
        while [ $i -lt 225 ]; do
            if [ -f "$a" ]; then
                r=$(cat "$a"); finish
                case "$r" in
                    allow) printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' ;;
                    deny) printf '%s' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"In Lotse abgelehnt."}}}' ;;
                esac
                exit 0
            fi
            sleep 0.2
            i=$((i+1))
        done
        finish
        exit 0
        """)

        // Altlasten verwerfen
        for dir in [Self.events, Self.answers] {
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] { try? fm.removeItem(at: f) }
        }

        model.answer = { [weak self] ask, reply in self?.answer(ask, reply) }
        model.openSession = { [weak self] s in self?.open(s) }

        let fd = Darwin.open(Self.events.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
            src.setEventHandler { [weak self] in self?.drain() }
            src.setCancelHandler { close(fd) }
            src.resume()
            watcher = src
        }
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.drain(); self?.prune()
        }
    }

    private func write(_ url: URL, _ script: String) {
        try? script.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func drain() {
        let fm = FileManager.default
        let all: [URL] = (try? fm.contentsOfDirectory(at: Self.events, includingPropertiesForKeys: nil)) ?? []
        var dated: [(url: URL, date: Date)] = []
        for u in all where u.pathExtension == "json" || u.pathExtension == "end" {
            let d = (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
            dated.append((u, d ?? Date()))
        }
        dated.sort { a, b in a.date == b.date ? a.url.lastPathComponent < b.url.lastPathComponent : a.date < b.date }
        let files: [URL] = dated.map { $0.url }
        for f in files {
            defer { try? fm.removeItem(at: f) }
            let stem = f.deletingPathExtension().lastPathComponent
            if f.pathExtension == "end" { endAsk(stem); continue }
            guard let data = try? Data(contentsOf: f),
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            handle(j, file: stem)
        }
    }

    // MARK: Ereignisse

    private func handle(_ j: [String: Any], file: String) {
        // Beispiel-Hinweise zum Ansehen (ausgelöst über eine Datei im Ereignis-Ordner).
        if j["hook_event_name"] as? String == "LotseTour" { model.runTour(); return }
        if j["hook_event_name"] as? String == "LotseFleet" { model.runFleet(); return }
        if j["hook_event_name"] as? String == "LotseAway" {
            model.showAway?(Date().addingTimeInterval(-60 * (j["minutes"] as? Double ?? 180))); return
        }
        if j["hook_event_name"] as? String == "LotseDemo" {
            let kind = Notice.Kind(demo: j["kind"] as? String ?? "")
            var demo = Notice(kind: j["card"] != nil && j["app"] == nil ? .info : kind, appID: j["app"] as? String, appName: j["name"] as? String ?? "Beispiel",
                              title: j["title"] as? String ?? "", body: j["body"] as? String ?? "",
                              url: (j["url"] as? String).flatMap { URL(string: $0) },
                              brief: j["brief"] as? Bool ?? false, symbol: j["symbol"] as? String, card: j["card"] as? String)
            demo.hold = (j["hold"] as? NSNumber)?.doubleValue; demo.sound = j["sound"] as? Bool ?? false
            // Probe einer Termin-Erinnerung: "start_in" (Sekunden bis zum Beginn), dazu "minutes", "place", "role", "url".
            if kind == .calendar, let startIn = (j["start_in"] as? NSNumber)?.doubleValue {
                let start = Date().addingTimeInterval(startIn)
                demo.event = CalEvent(id: "demo", title: demo.title, start: start,
                                      end: start.addingTimeInterval(((j["minutes"] as? NSNumber)?.doubleValue ?? 60) * 60),
                                      color: Theme.accent, joinURL: demo.url, role: CalRole(rawValue: j["role"] as? String ?? "") ?? .none,
                                      place: j["place"] as? String ?? "")
            }
            model.post(demo)
            return
        }
        guard let event = j["hook_event_name"] as? String,
              let sid = j["session_id"] as? String else { return }
        let cwd = j["cwd"] as? String ?? ""
        let project = cwd.isEmpty ? "Claude" : URL(fileURLWithPath: cwd).lastPathComponent
        let message = j["message"] as? String ?? ""
        let tool = j["tool_name"] as? String ?? ""
        let input = j["tool_input"] as? [String: Any] ?? [:]

        /// Session anlegen oder an Ort und Stelle aktualisieren (ohne die Reihenfolge zu wirbeln).
        func update(_ status: ClaudeSession.Status? = nil, message msg: String? = nil, front: Bool = false,
                    refresh: Bool = false, _ change: ((inout ClaudeSession) -> Void)? = nil) {
            var s = model.sessions.first { $0.id == sid }
                ?? ClaudeSession(id: sid, project: project, status: status ?? .working, message: "", updated: Date())
            if let status { s.status = status }
            if let msg { s.message = msg }
            if !cwd.isEmpty { s.cwd = cwd; if !s.titled { s.project = project } }
            if let t = j["transcript_path"] as? String { s.transcript = t }
            if let m = j["model"] as? String, !m.isEmpty { s.model = Self.pretty(model: m) }
            if let h = j["lotse_host"] as? String, !h.isEmpty { s.host = h }
            if let b = j["lotse_bundle"] as? String, !b.isEmpty { s.bundle = b }
            if let n = j["session_title"] as? String, !n.isEmpty { s.project = n }
            if refresh, let info = self.desktopInfo(s.host) {
                if let n = info.title { s.project = n }
                if let m = info.model { s.model = m }
            } else if s.titled { s.project = model.sessions.first { $0.id == sid }?.project ?? s.project }
            s.titled = s.project != project
            if refresh { log("Claude-Session „\(s.project)“ · \(s.model.isEmpty ? "Modell unbekannt" : s.model) · \(s.host.isEmpty ? "ohne App-Kennung" : "mit App-Kennung")") }
            s.updated = Date()
            change?(&s)
            if let i = model.sessions.firstIndex(where: { $0.id == sid }), !front {
                model.sessions[i] = s
            } else {
                model.sessions.removeAll { $0.id == sid }
                model.sessions.insert(s, at: 0)
            }
        }

        switch event {
        case "SessionStart":
            if model.sessions.contains(where: { $0.id == sid }) || j["model"] != nil {
                if model.sessions.contains(where: { $0.id == sid }) { update() }
                else if let m = j["model"] as? String { pendingModels[sid] = Self.pretty(model: m) }
            }
        case "UserPromptSubmit":
            if resumed.remove(sid) != nil { background[sid] = nil }
            update(.working, message: "", front: true, refresh: true) { s in
                s.detail = ""; s.summary = ""; s.doneAt = nil; s.tookSeconds = nil; s.startedAt = Date()
                if let m = self.pendingModels[sid], s.model.isEmpty { s.model = m }
            }
        case "PreToolUse":
            // Der Durchgang läuft wieder: Was vorher im Hintergrund lief, hat sich gemeldet.
            if resumed.remove(sid) != nil { background[sid] = nil }
            // Befehle, die Claude in den Hintergrund schickt (z. B. ein Rendern), laufen über das Ende des Durchgangs hinaus.
            if tool == "Bash", input["run_in_background"] as? Bool == true {
                background[sid] = (input["description"] as? String ?? "Befehl", Date())
            }
            let plan = plan(sid, tool: tool, input: input)
            update(model.asks.contains { $0.sessionID == sid } ? nil : .working) { s in
                if let plan { s.planDone = plan.done; s.planTotal = plan.total; s.planStep = plan.step }
                else if let d = Self.describe(tool, input) { s.detail = d }
            }
        case "PostToolUse", "PostToolUseFailure":
            // Nur die Freigabe abräumen, die zu genau diesem Werkzeugaufruf gehört – ein zweiter Agent
            // derselben Session darf eine noch offene Anfrage nicht mit wegnehmen.
            let done = Self.argument(tool, input)
            model.asks.removeAll { $0.sessionID == sid && $0.tool == tool && $0.detail == done }
            if !model.asks.contains(where: { $0.sessionID == sid }),
               model.sessions.first(where: { $0.id == sid })?.status == .waiting { update(.working, message: "") }
        case "PermissionRequest":
            var ask = PermissionAsk(id: file, sessionID: sid, project: project, tool: tool,
                                    detail: Self.argument(tool, input))
            // Nur bei Befehlen und Agenten ist „description" Claudes eigene Erklärung – bei anderen Werkzeugen ein Parameter.
            if ["Bash", "Task", "Agent"].contains(tool) {
                ask.summary = (input["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            ask.risk = Risk.assess(tool: tool, input: input, cwd: cwd, detail: ask.detail)
            if tool == "AskUserQuestion" {
                ask.risk = ""
                ask.questions = ((input["questions"] as? [[String: Any]]) ?? []).compactMap { q in
                    guard let text = q["question"] as? String, !text.isEmpty else { return nil }
                    let options = ((q["options"] as? [[String: Any]]) ?? []).compactMap { $0["label"] as? String }
                    return PermissionAsk.Question(header: q["header"] as? String ?? "", text: text, options: options,
                                                  multi: q["multiSelect"] as? Bool ?? false)
                }
            }
            let isQuestion = ask.isQuestion
            model.asks.removeAll { $0.sessionID == sid }
            update(.waiting, message: isQuestion ? "hat eine Frage" : "wartet auf dein OK", front: true, refresh: true)
            let name = model.sessions.first { $0.id == sid }?.project ?? project
            var named = ask; named.project = name
            model.asks.insert(named, at: 0)
            model.post(Notice(kind: .claude, appID: Apps.claude, appName: "Claude · \(name)",
                              title: isQuestion ? "Claude hat eine Frage" : "Claude wartet auf dein OK",
                              body: isQuestion ? ask.questions[0].text
                                  : (!ask.summary.isEmpty ? ask.summary : (ask.detail.isEmpty ? Self.readable(tool) : ask.detail)), sessionID: sid))
        case "Notification":
            // Nur echte Rückfragen melden – nicht „idle", Login-Hinweise u. Ä.
            let type = j["notification_type"] as? String
            let wanted: Set<String> = ["permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"]
            // Limit erreicht / läuft wieder: als ruhiger Hinweis zeigen.
            if let type, type.hasPrefix("quota") || type.contains("rate_limit") {
                model.post(Notice(kind: .claude, appID: Apps.claude, appName: "Claude",
                                  title: "Nutzungslimit", body: message.isEmpty ? "Claude meldet ein Limit." : message, sessionID: sid))
                break
            }
            guard type == nil || wanted.contains(type!) else { break }
            // Läuft dafür schon eine Freigabe in der Insel, nicht doppelt melden.
            if model.asks.contains(where: { $0.sessionID == sid }) { break }
            update(.waiting, message: message.isEmpty ? "wartet auf dich" : message, front: true)
            model.post(Notice(kind: .claude, appID: Apps.claude,
                              appName: "Claude · \(model.sessions.first { $0.id == sid }?.project ?? project)",
                              title: "Claude braucht dich", body: message.isEmpty ? "Wartet auf deine Eingabe." : message,
                              sessionID: sid))
        case "Stop":
            // Kurze Antworten nicht jedes Mal aufpoppen lassen – nur wenn Claude eine Weile gearbeitet hat.
            let before = model.sessions.first { $0.id == sid }
            let started = turnStart[sid] ?? before?.updated ?? Date()
            // Nur blitzschnelle Antworten (unter 5 s) klappen die Insel nicht auf.
            let quick = before != nil && Date().timeIntervalSince(started) < 5
            model.asks.removeAll { $0.sessionID == sid }
            let reported = (j["background_tasks"] as? [[String: Any]])?.contains { ($0["status"] as? String) != "completed" } ?? false
            // Selbst gemerkt: ein Hintergrund-Befehl aus diesem Durchgang, höchstens 45 Minuten alt.
            let own = background[sid].flatMap { Date().timeIntervalSince($0.since) < 45 * 60 ? $0.what : nil }
            if reported || own != nil {
                // Der Durchgang ist zu Ende, aber im Hintergrund läuft noch etwas – das ist nicht „fertig“.
                resumed.insert(sid)
                update(.working, message: "", refresh: true) { s in
                    s.detail = own.map { "Im Hintergrund: \($0)" } ?? "wartet auf Hintergrundarbeit"
                    s.planStep = ""
                }
                log("Claude-Session wartet auf Hintergrundarbeit\(own.map { ": " + $0 } ?? "")")
                break
            }
            let took = max(1, Int(Date().timeIntervalSince(started)))
            let summary = Self.firstSentence(j["last_assistant_message"] as? String ?? "")
            update(.done, message: "", front: true, refresh: true) { s in
                s.detail = ""; s.planStep = ""
                s.summary = summary; s.tookSeconds = took; s.doneAt = Date(); s.startedAt = nil
            }
            if !quick {
                let name = model.sessions.first { $0.id == sid }?.project ?? project
                model.post(Notice(kind: .claude, appID: Apps.claude, appName: "Claude",
                                  title: "Claude ist fertig", body: summary.isEmpty ? "„\(name)“ ist abgeschlossen." : summary,
                                  sessionID: sid))
            }
        case "SessionEnd":
            model.sessions.removeAll { $0.id == sid }
            model.asks.removeAll { $0.sessionID == sid }
            plans[sid] = nil; turnStart[sid] = nil; pendingModels[sid] = nil
        default:
            break
        }
        if event == "UserPromptSubmit" { turnStart[sid] = Date() }
    }

    private var turnStart: [String: Date] = [:]
    private var pendingModels: [String: String] = [:]

    // MARK: Freigaben

    private func answer(_ ask: PermissionAsk, _ reply: String) {
        log("Freigabe \(reply) für \(ask.tool)")
        // Bei einer Frage wartet kein Hook auf eine Antwort – sie wird in Claude beantwortet.
        if !ask.isQuestion {
            try? reply.write(to: Self.answers.appendingPathComponent(ask.id), atomically: true, encoding: .utf8)
        }
        model.asks.removeAll { $0.id == ask.id }
        if let i = model.sessions.firstIndex(where: { $0.id == ask.sessionID }) {
            model.sessions[i].status = reply == "pass" ? .waiting : .working
            model.sessions[i].message = reply == "pass" ? "wartet auf dich" : ""
        }
        if model.peekNotice?.sessionID == ask.sessionID { model.dismissPeek() }
        // Kurz bestätigen, was gerade entschieden wurde.
        if reply != "pass" {
            let first = ask.detail.components(separatedBy: "\n").first ?? ""
            let what = !ask.summary.isEmpty ? ask.summary : (first.isEmpty ? Self.readable(ask.tool) : first)
            model.post(Notice(kind: .info, appID: Apps.claude, appName: ask.project,
                              title: reply == "allow" ? "Erlaubt" : "Abgelehnt", body: what, brief: true))
        }
    }

    /// Der erste Satz von Claudes letzter Antwort – ohne Markdown-Zeichen, höchstens gut eine Zeile lang.
    static func firstSentence(_ text: String) -> String {
        let line = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " #*>-_`|\t")) }
            .first { $0.count > 3 } ?? ""
        var s = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        if let r = s.range(of: #"(?<=.{24})[.!?](\s|$)"#, options: .regularExpression) { s = String(s[..<r.lowerBound]) + String(s[r.lowerBound]) }
        if s.count > 150 { s = String(s.prefix(149)) + "…" }
        return s
    }

    /// Werkzeugname ohne die technische Kennung davor („mcp__<id>__send_message" → „send_message").
    static func readable(_ tool: String) -> String {
        tool.hasPrefix("mcp__") ? (tool.components(separatedBy: "__").last ?? tool) : tool
    }

    /// Macht einen Befehl lesbar: Heimatordner als ~, lange Pfade auf den letzten Teil gekürzt.
    static func shorten(_ command: String) -> String {
        var s = command.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        s = s.replacingOccurrences(of: #"(?:~|)(?:/[^/\s"']+){3,}/([^/\s"']+)"#, with: "…/$1", options: .regularExpression)
        return s
    }

    /// Der Hook ist beendet (beantwortet, abgelaufen oder von Claude abgebrochen).
    private func endAsk(_ id: String) {
        guard model.asks.contains(where: { $0.id == id }) else { return }
        let sid = model.asks.first { $0.id == id }?.sessionID
        model.asks.removeAll { $0.id == id }
        if model.peekNotice?.sessionID == sid { model.dismissPeek() }
    }

    // MARK: Zur Session springen

    private static let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")

    /// Alle Session-Dateien der Claude-App (…/<Konto>/<Organisation>/local_<id>.json).
    private func desktopFiles() -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for a in (try? fm.contentsOfDirectory(at: Self.store, includingPropertiesForKeys: nil)) ?? [] {
            for o in (try? fm.contentsOfDirectory(at: a, includingPropertiesForKeys: nil)) ?? [] {
                out += ((try? fm.contentsOfDirectory(at: o, includingPropertiesForKeys: nil)) ?? [])
                    .filter { $0.lastPathComponent.hasPrefix("local_") && $0.pathExtension == "json" }
            }
        }
        return out
    }

    /// Titel und Modell, wie die Claude-App sie für diese Session führt. Liest nur diese Felder.
    private func desktopInfo(_ host: String) -> (title: String?, model: String?)? {
        guard !host.isEmpty, let f = desktopFiles().first(where: { $0.lastPathComponent == host + ".json" }),
              let data = try? Data(contentsOf: f),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let title = (j["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var model = (j["model"] as? String).map { Self.pretty(model: $0) }
        let levels = ["low": "niedrig", "medium": "mittel", "high": "hoch", "xhigh": "sehr hoch", "max": "maximal"]
        if let m = model, let e = j["effort"] as? String, !e.isEmpty { model = "\(m) · Aufwand \(levels[e] ?? e)" }
        return (title, model)
    }

    private func open(_ s: ClaudeSession) {
        var id = s.host
        if id.isEmpty {
            // Ohne Kennung aus dem Hook: die Session-Datei suchen, die zu dieser Claude-Code-Session gehört.
            let needle = Data("\"\(s.id)\"".utf8)
            id = desktopFiles().first { (try? Data(contentsOf: $0))?.range(of: needle) != nil }?
                .deletingPathExtension().lastPathComponent ?? ""
        }
        if id.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
           let url = URL(string: "claude://code/continue?session=\(id)&source=url_external") {
            log("Öffne Claude-Session \(id.prefix(14))…")
            NSWorkspace.shared.open(url)
        } else if !s.bundle.isEmpty, s.bundle != Apps.claude {
            Apps.activate(s.bundle)      // Session läuft in einem Terminal o. Ä.
        } else {
            Apps.activate(Apps.claude)
        }
    }

    // MARK: Lesbare Beschreibungen

    private func plan(_ sid: String, tool: String, input: [String: Any]) -> (done: Int, total: Int, step: String)? {
        let isPlan = tool == "TodoWrite" || tool.hasSuffix("update_plan")
        guard isPlan else { return nil }
        var items = plans[sid] ?? []
        if let raw = (input["todos"] ?? input["items"]) as? [[String: Any]] {
            items = raw.map { (($0["content"] ?? $0["activeForm"]) as? String ?? "", $0["status"] as? String ?? "pending") }
        } else if input["advance"] as? Bool == true {
            if let i = items.firstIndex(where: { $0.status == "in_progress" }) {
                items[i].status = "completed"
                if i + 1 < items.count { items[i + 1].status = "in_progress" }
            }
        } else {
            for n in (input["done"] as? [Int]) ?? [] where n >= 1 && n <= items.count { items[n - 1].status = "completed" }
            if let n = input["start"] as? Int, n >= 1, n <= items.count { items[n - 1].status = "in_progress" }
        }
        plans[sid] = items
        guard !items.isEmpty else { return nil }
        let done = items.filter { $0.status == "completed" }.count
        return (done, items.count, items.first { $0.status == "in_progress" }?.text ?? "")
    }

    /// Was genau freigegeben wird – vollständig, damit vor dem Erlauben nichts verborgen bleibt.
    static func argument(_ tool: String, _ input: [String: Any]) -> String {
        func path(_ key: String) -> String {
            (input[key] as? String ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        switch tool {
        case "Bash": return (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case "Edit", "Write", "MultiEdit", "Read": return path("file_path")
        case "NotebookEdit": return path("notebook_path")
        case "Grep", "Glob": return input["pattern"] as? String ?? ""
        case "WebFetch": return input["url"] as? String ?? ""
        case "WebSearch": return input["query"] as? String ?? ""
        case "Task", "Agent": return input["description"] as? String ?? ""
        default:
            // Unbekannte und externe Werkzeuge: alle Parameter als „Name: Wert"-Zeilen.
            return input.keys.sorted().map { key -> String in
                let v = input[key]!
                var s = v as? String ?? ((try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed, .sortedKeys]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "\(v)")
                if s.count > 240 { s = String(s.prefix(239)) + "…" }
                return "\(key): \(s)"
            }.joined(separator: "\n")
        }
    }

    /// Kurzform fürs Statusfeld: nur der Dateiname bzw. die Adresse ohne Pfad.
    private static func brief(_ tool: String, _ input: [String: Any]) -> String {
        let full = argument(tool, input)
        switch tool {
        case "Edit", "Write", "MultiEdit", "Read", "NotebookEdit": return URL(fileURLWithPath: full).lastPathComponent
        case "WebFetch": return URL(string: full)?.host ?? full
        default: return full
        }
    }

    static func describe(_ tool: String, _ input: [String: Any]) -> String? {
        var arg = brief(tool, input).components(separatedBy: "\n").first ?? ""
        if arg.count > 70 { arg = String(arg.prefix(69)) + "…" }
        switch tool {
        case "Bash":
            // Claude liefert zu jedem Befehl eine Kurzbeschreibung in Klartext – die ist lesbarer als der Befehl.
            let said = (input["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !said.isEmpty { return said }
            var cmd = shorten(argument(tool, input).components(separatedBy: "\n").first ?? "")
            if cmd.count > 70 { cmd = String(cmd.prefix(69)) + "…" }
            return cmd.isEmpty ? "führt einen Befehl aus" : "führt aus: \(cmd)"
        case "Edit", "MultiEdit", "NotebookEdit": return "bearbeitet \(arg)"
        case "Write": return "schreibt \(arg)"
        case "Read": return "liest \(arg)"
        case "Grep", "Glob": return "sucht \(arg)"
        case "WebFetch": return "liest \(arg)"
        case "WebSearch": return "sucht im Web: \(arg)"
        case "Task", "Agent": return "Agent: \(arg)"
        case "Skill": return "lädt Skill \(input["skill"] as? String ?? "")"
        case "Workflow": return "steuert einen Workflow"
        case "AskUserQuestion": return "stellt dir eine Frage"
        default:
            if tool.hasPrefix("mcp__") { return "nutzt \(tool.components(separatedBy: "__").last ?? tool)" }
            return tool.isEmpty ? nil : "nutzt \(tool)"
        }
    }

    /// „claude-opus-5-5-20260101“ → „Opus 5.5“
    static func pretty(model id: String) -> String {
        var parts = id.replacingOccurrences(of: "[1m]", with: "").components(separatedBy: "-")
        parts.removeAll { $0 == "claude" || $0 == "anthropic" || $0.count >= 8 && Int($0) != nil }
        let words = parts.filter { Int($0) == nil }.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let nums = parts.filter { Int($0) != nil }
        let out = (words + [nums.joined(separator: ".")]).filter { !$0.isEmpty }.joined(separator: " ")
        return out.isEmpty ? id : out
    }

    private func prune() {
        let now = Date()
        model.sessions.removeAll {
            now.timeIntervalSince($0.updated) > ($0.status == .done ? 15 * 60 : 45 * 60)
        }
        model.asks.removeAll { now.timeIntervalSince($0.date) > 90 }
    }
}

// MARK: - System-Mitteilungen (liest die Datenbank der Mitteilungszentrale, braucht Festplattenvollzugriff)

final class NotificationSource {
    private struct Row {
        var id: Int64
        var date: Date
        var key: String
        var notice: Notice?
        var pop = true          // darf die Insel aufklappen (laut Filter)
        var thread = ""
        var ident = ""
    }

    /// Systemmeldungen, die im Notch nur stören (z. B. „Spielmodus: Ein“, sobald ein Spiel im Vordergrund ist).
    private static let ignored: Set<String> = ["com.apple.gamepolicynotifications"]

    private let model: IslandModel
    private let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
    private var lastID: Int64 = -1
    private var lastStamp: [Date?] = []
    /// Geplante Mitteilungen (z. B. Kalender-Erinnerungen) stehen schon vor der Zustellung in der DB.
    private var pending: [Int64: Date] = [:]
    private var posted: [String] = []
    private var timer: Timer?
    private var loggedError = false

    init(model: IslandModel) { self.model = model }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
        // Wer eine App nach vorn holt, hat ihre Mitteilungen gesehen – Slack & Co. räumen die Mitteilungszentrale
        // beim Lesen nämlich nicht selbst auf. Browser zählen nicht: Chrome im Vordergrund heißt nicht „Gmail gelesen".
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier?.lowercased(), !Self.browsers.contains(where: id.hasPrefix) else { return }
            // Erst zählen, wenn die App drei Sekunden vorn geblieben ist (kein Durchwechseln mit ⌘-Tab).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let self, NSWorkspace.shared.frontmostApplication?.bundleIdentifier?.lowercased() == id else { return }
                let before = self.model.notices.count
                self.model.notices.removeAll { $0.kind == .system && $0.appID?.lowercased() == id }
                let gone = before - self.model.notices.count
                if gone > 0 {
                    self.model.unread = max(0, self.model.unread - gone)
                    log("Mitteilungen: \(gone) von \(id) als gelesen entfernt (App im Vordergrund)")
                }
            }
        }
    }

    private static let browsers = ["com.google.chrome", "com.apple.safari", "company.thebrowser", "org.mozilla.firefox",
                                   "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.opera", "com.vivaldi.vivaldi"]

    private func stamp() -> [Date?]? {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: path) else { return nil }
        return [path, path + "-wal"].map { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
    }

    private func poll() {
        guard let s = stamp() else {
            let fd = Darwin.open(path, O_RDONLY); let e = errno; if fd >= 0 { close(fd) }
            fail("Datenbank nicht lesbar (Festplattenvollzugriff fehlt?) – errno \(fd >= 0 ? 0 : e)"); return
        }
        let now = Date()
        let due = pending.filter { $0.value <= now }.map(\.key)
        if lastID >= 0, s == lastStamp, due.isEmpty { return }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            fail("open: " + (db.map { String(cString: sqlite3_errmsg($0)) } ?? "?")); sqlite3_close(db); return
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 250)

        // Fällig gewordene geplante Mitteilungen frisch nachlesen (Inhalt kann sich geändert haben).
        if !due.isEmpty {
            let ids = due.map(String.init).joined(separator: ",")
            guard let rows = read(db, "WHERE r.rec_id IN (\(ids))", nil) else { return }
            for id in due { pending[id] = nil }
            for row in rows {
                if row.date > now.addingTimeInterval(1) { pending[row.id] = row.date } else { emit(row, peek: true) }
            }
        }

        let initial = lastID < 0
        let seenID = Int64(UserDefaults.standard.integer(forKey: "lastNoticeID"))
        guard let rows = read(db, initial ? "ORDER BY r.rec_id DESC LIMIT 8"
                                          : "WHERE r.rec_id > ?1 ORDER BY r.rec_id ASC LIMIT 20",
                              initial ? nil : lastID) else { return }
        var maxID = max(lastID, 0)
        for row in rows.sorted(by: { $0.id < $1.id }) {
            maxID = max(maxID, row.id)
            if row.date > now { pending[row.id] = row.date; continue }
            if !initial { emit(row, peek: true) }
            // Beim Start nur Frisches, still – außer es kam an, während Lotse gerade neu startete (Update, Neubau):
            // Das hat noch niemand gesehen und klappt deshalb auf.
            else if now.timeIntervalSince(row.date) < 3 * 3600 {
                emit(row, peek: seenID > 0 && row.id > seenID && now.timeIntervalSince(row.date) < 600)
            }
        }
        if maxID > seenID { UserDefaults.standard.set(maxID, forKey: "lastNoticeID") }
        if initial { log("Mitteilungen verbunden, letzte ID \(maxID), geplant \(pending.count)") }
        dropRead(db, now: now)
        model.notificationsDenied = false
        loggedError = false
        lastStamp = rows.count >= 20 ? [] : s   // volle Seite: beim nächsten Tick weiterlesen
        lastID = maxID
    }

    /// Liefert nil, wenn die Abfrage nicht sauber durchlief – dann wird nichts fortgeschrieben.
    private func read(_ db: OpaquePointer, _ tail: String, _ bind: Int64?) -> [Row]? {
        let sql = "SELECT r.rec_id, a.identifier, r.data, r.delivered_date FROM record r "
            + "JOIN app a ON a.app_id = r.app_id " + tail
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            fail("prepare: " + String(cString: sqlite3_errmsg(db))); return nil
        }
        defer { sqlite3_finalize(stmt) }
        if let bind { sqlite3_bind_int64(stmt, 1, bind) }

        var rows: [Row] = []
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            defer { rc = sqlite3_step(stmt) }
            let id = sqlite3_column_int64(stmt, 0)
            let date = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? Date() : Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3))
            var row = Row(id: id, date: date, key: "", notice: nil)
            defer { rows.append(row) }
            guard let cApp = sqlite3_column_text(stmt, 1), let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let app = String(cString: cApp)
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
            guard !app.hasPrefix("_"), app != Bundle.main.bundleIdentifier,
                  !Self.ignored.contains(app.lowercased()),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let req = plist["req"] as? [String: Any] else { continue }
            let title = req["titl"] as? String ?? ""
            let sub = req["subt"] as? String ?? ""
            let body = req["body"] as? String ?? ""
            if title.isEmpty && body.isEmpty { continue }

            // Der Wichtig-Filter entscheidet: aufklappen, nur leise in die Liste, oder ganz weglassen.
            var verdict = NoticeVerdict.popUp
            if let facts = NoticeExtractor.facts(app: app, plist: plist) {
                verdict = model.filter.verdict(for: facts)
                // Erinnerungen an Termine meldet Lotse selbst – die gespiegelte Kopie bleibt leise.
                if facts.kind == .calendar, facts.category.contains("TriggeredEvent"), verdict == .popUp { verdict = .quiet }
                // Termine aus Kalendern, die in Lotse ausgeblendet sind, gar nicht übernehmen.
                if facts.kind == .calendar, [title, sub].contains(where: { model.hiddenEventTitles.contains($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) {
                    verdict = .drop
                }
                // Einladungen meldet macOS aus allen Konten. Steht der Termin in keinem angezeigten Kalender, bleibt sie draußen.
                if app.lowercased() == "com.apple.ical", facts.category.contains("EventInvitation"), let shown = model.shownEventTitles,
                   !shown.contains(title.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    verdict = .drop
                }
            }
            // Neue Mail bekommt eine eigene Karte mit Umschlag – außer du hast Mail im Menü „Darf aufklappen" abgewählt.
            let appID = app.lowercased()
            let origin = NoticeExtractor.facts(app: app, plist: plist)?.origin ?? ""
            let isMail = ["com.apple.mail", "com.microsoft.outlook", "com.readdle.smartemail-mac"].contains(appID)
                || origin.hasPrefix("mail.google.com") || origin.hasPrefix("outlook.")
            if isMail, !model.filter.user.contains(where: { $0.app == appID }) { verdict = .popUp }
            if verdict == .drop { continue }

            let name = Apps.name(app)
            row.thread = req["thre"] as? String ?? ""
            row.ident = req["iden"] as? String ?? ""
            row.pop = verdict == .popUp
            row.key = [app, req["iden"] as? String ?? "", title, sub, body].joined(separator: "|")
            row.notice = Notice(kind: .system, appID: app, appName: name, title: title.isEmpty ? name : title,
                                body: [sub, body].filter { !$0.isEmpty }.joined(separator: " – "), date: date)
            row.notice?.recordID = id
            // Chats, Cowork und geplante Aufgaben der Claude-App: ein Klick soll genau dort landen.
            if app.lowercased() == Apps.claude { row.notice?.url = Self.claudeLink(req) }
            if isMail {
                row.notice?.card = "mail"
                // Gmail im Browser: die Adresse der Seite ist keine Information – Absender und Betreff reichen.
                if origin.hasPrefix("mail.google.com") {
                    row.notice?.appName = "Gmail"
                    row.notice?.body = [sub, body].filter { !$0.isEmpty && !$0.hasPrefix("mail.google.com") }.joined(separator: " – ")
                }
            }
        }
        return rc == SQLITE_DONE ? rows : nil
    }

    /// Baut aus einer Mitteilung der Claude-App den Link zum Chat bzw. zur Cowork-Session.
    /// Die App liefert die Route meist mit; sonst wird sie aus der Kennung der Mitteilung abgeleitet.
    static func claudeLink(_ req: [String: Any]) -> URL? {
        var route = NoticeArchive.userInfo(req["usda"] as? Data)["route"] as? String ?? ""
        let ident = req["iden"] as? String ?? ""
        func tail(after prefix: String) -> String { String(ident.dropFirst(prefix.count)) }
        // Code-Sessions auf diesem Mac: Die App nennt die Session in der Kennung („idle-local_…") – direkt dorthin springen.
        let thread = req["thre"] as? String ?? ""
        var local: String?
        for text in [ident, thread] where local == nil {
            if let r = text.range(of: "local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) { local = String(text[r]) }
        }
        if let local, let url = URL(string: "claude://code/continue?session=\(local)&source=url_external") { return url }
        if route.isEmpty {
            if ident.hasPrefix("hub-awaiting-") { route = "/chat/" + tail(after: "hub-awaiting-") }
            else if ident.hasPrefix("cowork-idle-") { route = "/cowork/" + tail(after: "cowork-idle-") }
            else if ident.hasPrefix("scheduled-"), let r = ident.range(of: "-awaiting-") {
                route = "/cowork/" + String(ident[ident.index(ident.startIndex, offsetBy: "scheduled-".count)..<r.lowerBound])
            }
        }
        // Nur bekannte, harmlose Routen öffnen.
        guard route.range(of: "^/(chat|cowork|project|epitaxy)/[A-Za-z0-9_-]{6,80}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "claude://claude.ai" + route)
    }

    /// Wann Lotse einen Eintrag zum ersten Mal gesehen hat.
    private var seen: [Int64: Date] = [:]

    /// Gleicht die Liste mit der Mitteilungszentrale ab: Was dort nicht mehr steht – weil du die Nachricht in der App
    /// gelesen oder die Mitteilung weggeklickt hast –, verschwindet auch aus der Insel.
    private func dropRead(_ db: OpaquePointer, now: Date) {
        let ids = model.notices.compactMap(\.recordID)
        seen = seen.filter { ids.contains($0.key) }
        guard !ids.isEmpty else { return }
        var stmt: OpaquePointer?
        let sql = "SELECT rec_id FROM record WHERE rec_id IN (\(ids.map(String.init).joined(separator: ",")))"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        var present = Set<Int64>()
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW { present.insert(sqlite3_column_int64(stmt, 0)); rc = sqlite3_step(stmt) }
        guard rc == SQLITE_DONE else { return }      // unsauber gelesen: lieber nichts entfernen
        var gone = 0
        for id in ids where !present.contains(id) {
            guard let i = model.notices.firstIndex(where: { $0.recordID == id }) else { continue }
            // Manche Apps lassen ihre Mitteilung nur als Banner aufblitzen und räumen sie sofort ab.
            // Das ist kein „gelesen" – solche Einträge bleiben stehen und werden nicht weiter verfolgt.
            if now.timeIntervalSince(seen[id] ?? now) < 15 { model.notices[i].recordID = nil; continue }
            model.notices.remove(at: i)
            gone += 1
        }
        if gone > 0 {
            model.unread = max(0, model.unread - gone)
            log("Mitteilungen: \(gone) in der Mitteilungszentrale erledigt – aus der Insel entfernt")
        }
    }

    private func emit(_ row: Row, peek: Bool) {
        guard let n = row.notice, !posted.contains(row.key) else { return }
        // Beim Start Übernommenes gilt als schon länger da.
        seen[row.id] = peek ? Date() : .distantPast
        posted.append(row.key)
        if posted.count > 200 { posted.removeFirst(100) }
        // Claude-Code-Sessions meldet Lotse schon über die Hooks. Kommt die Mitteilung der Claude-App
        // direkt danach, ist es dieselbe Nachricht – Chats, Cowork und geplante Aufgaben kommen dagegen nur hier an.
        if n.appID?.lowercased() == Apps.claude, model.isHookSession(thread: row.thread, ident: row.ident) { return }
        model.post(n, peek: peek && row.pop, count: peek)
    }

    private func fail(_ why: String) {
        model.notificationsDenied = true
        if !loggedError { loggedError = true; log("Mitteilungen: \(why)") }
    }
}

// MARK: - Musik (Spotify)

final class MusicSource {
    private let model: IslandModel
    private let queue = DispatchQueue(label: "lotse.music")

    init(model: IslandModel) { self.model = model }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main
        ) { [weak self] n in
            guard let self, let info = n.userInfo else { return }
            let state = info["Player State"] as? String ?? ""
            if state == "Stopped" { self.model.track = nil; return }
            let title = info["Name"] as? String ?? ""
            let artist = info["Artist"] as? String ?? ""
            let same = self.model.track?.title == title && self.model.track?.artist == artist
            self.model.track = Track(title: title, artist: artist, isPlaying: state == "Playing",
                                     artworkURL: same ? self.model.track?.artworkURL : nil,
                                     artwork: same ? self.model.track?.artwork : nil)
            if !same { self.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Apps.spotify { self?.model.track = nil }
        }
        model.musicAction = { [weak self] cmd in self?.run("tell application \"Spotify\" to \(cmd)") { _ in } }
        refresh()
    }

    private var running: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Apps.spotify).isEmpty
    }

    private func run(_ source: String, done: @escaping (String?) -> Void) {
        guard running else { done(nil); return }
        queue.async {
            var err: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&err).stringValue
            if let err { log("AppleScript: \(err[NSAppleScript.errorMessage] ?? err)") }
            DispatchQueue.main.async { done(out) }
        }
    }

    /// Fragt Titel, Status und Cover ab (löst beim ersten Mal die Automations-Abfrage aus).
    private func refresh() {
        let script = """
        tell application "Spotify"
            set t to current track
            return (name of t) & linefeed & (artist of t) & linefeed & (player state as string) & linefeed & (artwork url of t)
        end tell
        """
        run(script) { [weak self] out in
            guard let self, let parts = out?.components(separatedBy: "\n"), parts.count >= 4 else { return }
            if parts[2] == "stopped" { return }
            var t = Track(title: parts[0], artist: parts[1], isPlaying: parts[2] == "playing", artworkURL: parts[3])
            if self.model.track?.artworkURL == parts[3] { t.artwork = self.model.track?.artwork }
            self.model.track = t
            guard t.artwork == nil, let url = URL(string: parts[3]) else { return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let img = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    if self.model.track?.artworkURL == parts[3] { self.model.track?.artwork = img }
                }
            }.resume()
        }
    }
}
