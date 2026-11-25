import SwiftUI
import AppKit
import EventKit
import ServiceManagement

/// Der Einrichtungsassistent für den ersten Start. Er führt durch alles, was Lotse von außen braucht:
/// die Verbindung zu Claude Code, den Kalender, die Mitteilungen anderer Apps (samt Chrome) und die
/// Freigaben, die nur du selbst in den Systemeinstellungen erteilen kannst.
/// Jeder Schritt zeigt live, ob er erledigt ist; nichts davon ist Pflicht.
final class OnboardingWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let model: IslandModel
    private let snap: WindowSnap

    init(model: IslandModel, snap: WindowSnap) { self.model = model; self.snap = snap }

    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarded") }
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Lotse einrichten"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: OnboardingView(model: model, snap: snap) { [weak self] in self?.finish() })
            w.center()
            window = w
        }
        if model.pinnedOpen { model.togglePinned() }
        if model.mode == .expanded { model.mode = .compact }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        window?.close()
    }

    /// Auch wer das Fenster einfach schließt, wird beim nächsten Start nicht erneut gefragt.
    func windowWillClose(_ notification: Notification) {
        Self.done = true
        UserDefaults.standard.set(true, forKey: "snapAsked")
        window = nil
    }
}

/// Was der Assistent über den Zustand des Macs weiß. Wird im Sekundentakt neu gelesen.
struct SetupStatus: Equatable {
    var hooks = ClaudeHooks.State.missing
    var claudeApp = false
    var calendar = EKAuthorizationStatus.notDetermined
    var notices = false
    var chrome = false
    var accessibility = false

    static func read(model: IslandModel, snap: WindowSnap) -> SetupStatus {
        SetupStatus(hooks: ClaudeHooks.state(),
                    claudeApp: Apps.url(Apps.claude) != nil,
                    calendar: EKEventStore.authorizationStatus(for: .event),
                    notices: !model.notificationsDenied,
                    chrome: Apps.url("com.google.Chrome") != nil,
                    accessibility: snap.trusted)
    }

    /// Kurzfassung als Text. Die laufende App schreibt sie nach „einrichtung.txt“, damit auch Claude den Stand prüfen kann.
    var report: String {
        func line(_ ok: Bool, _ name: String, _ todo: String) -> String { (ok ? "✓ " : "– ") + name + (ok ? "" : " – " + todo) }
        return [
            line(hooks == .connected, "Claude Code verbunden",
                 hooks == .unreadable ? "~/.claude/settings.json ist kein gültiges JSON" : "im Assistenten „Mit Claude verbinden“ klicken"),
            line(claudeApp, "Claude-App gefunden", "Claude für den Mac installieren (für Sprung zur Session und Nutzungsstände)"),
            line(calendar == .fullAccess, "Kalenderzugriff", "im Assistenten erlauben oder Systemeinstellungen → Datenschutz & Sicherheit → Kalender → Lotse: Vollzugriff"),
            line(notices, "Mitteilungen anderer Apps lesbar", "Systemeinstellungen → Datenschutz & Sicherheit → Festplattenvollzugriff → Lotse einschalten, dann Lotse neu starten"),
            line(accessibility, "Fenster einrasten (optional)", "Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → Lotse einschalten"),
        ].joined(separator: "\n")
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: IslandModel
    let snap: WindowSnap
    let close: () -> Void
    @State var step = Probe.setupStep
    @State private var status = SetupStatus()
    @State private var hookError = ""
    @State private var city = ""
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var snapping = false
    @State private var copied = ""
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let steps = ["Willkommen", "Claude", "Kalender", "Mitteilungen", "Extras", "Fertig"]

    private func ok(_ i: Int) -> Bool? {
        switch i {
        case 1: return status.hooks == .connected
        case 2: return status.calendar == .fullAccess
        case 3: return status.notices
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Links: die Schritte mit ihrem Stand.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "sailboat.fill").foregroundStyle(Color.accentColor)
                    Text("Lotse").font(.system(size: 15, weight: .semibold))
                }
                .padding(.bottom, 14).padding(.leading, 8)
                ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, name in
                    Button { step = i } label: {
                        HStack(spacing: 8) {
                            Group {
                                if let ok = ok(i) {
                                    Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(ok ? Color.green : Color.secondary)
                                } else {
                                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary)
                                }
                            }
                            .frame(width: 16)
                            Text(name).font(.system(size: 13, weight: step == i ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(step == i ? Color.primary.opacity(0.10) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(14)
            .frame(width: 176)
            .background(Color.primary.opacity(0.04))
            Divider()
            // Rechts: der Schritt selbst, darunter Zurück/Weiter.
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) { page }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 26).padding(.top, 24)
                Divider()
                HStack {
                    if step > 0 { Button("Zurück") { step -= 1 } }
                    Spacer()
                    if step < Self.steps.count - 1 {
                        Button(ok(step) == false ? "Überspringen" : "Weiter") { step += 1 }.keyboardShortcut(.defaultAction)
                    } else {
                        Button("Vorführung zeigen") { close(); model.runTour() }
                        Button("Los geht’s") { close() }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            }
        }
        .frame(width: 760, height: 540)
        .onAppear {
            status = .read(model: model, snap: snap)
            city = model.weatherCity
            snapping = snap.enabled
        }
        .onReceive(tick) { _ in
            let now = SetupStatus.read(model: model, snap: snap)
            if now != status { status = now }
        }
    }

    // MARK: Bausteine

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(.system(size: 20, weight: .semibold))
            Text(sub).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 4)
    }

    private func state(_ ok: Bool, _ yes: String, _ no: String) -> some View {
        Label(ok ? yes : no, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(ok ? Color.green : Color.orange)
    }

    private func note(_ t: String) -> some View {
        Text(t).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func point(_ n: String, _ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).frame(width: 14, alignment: .trailing)
            Text(.init(t)).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func open(_ url: String) { if let u = URL(string: url) { NSWorkspace.shared.open(u) } }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copied == text { copied = "" } }
    }

    private func restart() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open '\(Bundle.main.bundlePath)'"]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: Seiten

    @ViewBuilder private var page: some View {
        switch step {
        case 0: welcome
        case 1: claude
        case 2: calendar
        case 3: notices
        case 4: extras
        default: finish
        }
    }

    @ViewBuilder private var welcome: some View {
        title("Willkommen an Bord", "Lotse ist die kleine Insel oben in der Mitte deines Bildschirms. Sie zeigt, woran Claude arbeitet, deinen nächsten Termin, Musik und Mitteilungen – und klappt auf, wenn du mit dem Zeiger darauf ruhst.")
        point("1", "**Zeiger auf die Insel** – sie klappt auf. Zeiger weg – sie klappt wieder zu.")
        point("2", "**Rechtsklick auf die Insel** oder das Segelboot in der Menüleiste öffnet die Einstellungen.")
        point("3", "**Dateien auf die Insel ziehen** legt sie für kurze Zeit in der Ablage ab.")
        Spacer().frame(height: 6)
        note("Die nächsten Schritte verbinden Lotse mit Claude, deinem Kalender und den Mitteilungen deiner Apps. Einige Freigaben kann nur du selbst in den Systemeinstellungen erteilen – der Assistent öffnet jeweils die richtige Stelle und zeigt, sobald es geklappt hat. Du kannst jeden Schritt überspringen und später über Einstellungen → Hilfe zurückkommen.")
    }

    @ViewBuilder private var claude: some View {
        title("Claude verbinden", "Damit die Insel zeigt, woran Claude Code arbeitet, wann es fertig ist und wann es eine Freigabe braucht, trägt Lotse ein paar Hooks in die Einstellungen von Claude Code ein.")
        switch status.hooks {
        case .connected: state(true, "Claude Code ist verbunden.", "")
        case .partial: state(false, "", "Die Verbindung ist unvollständig – bitte erneut verbinden.")
        case .missing: state(false, "", "Claude Code ist noch nicht verbunden.")
        case .unreadable: state(false, "", "Die Datei ~/.claude/settings.json ist beschädigt. Lotse fasst sie nicht an.")
        }
        if status.hooks != .connected, status.hooks != .unreadable {
            Button("Mit Claude verbinden") {
                do { try ClaudeHooks.install(); hookError = "" } catch { hookError = error.localizedDescription }
                status = .read(model: model, snap: snap)
            }
            .controlSize(.large)
        }
        if !hookError.isEmpty { Text(hookError).font(.system(size: 12)).foregroundStyle(.red) }
        if status.hooks == .connected {
            note("Wichtig: Die Hooks gelten erst für Sessions, die danach beginnen. Eine laufende Claude-Session erscheint erst in der Insel, wenn du sie neu startest oder eine neue öffnest.")
        }
        Spacer().frame(height: 2)
        note("Was dabei passiert: Lotse ergänzt Einträge in ~/.claude/settings.json und legt vorher einmalig die Sicherung settings.json.vor-lotse daneben. Einträge anderer Werkzeuge bleiben stehen. Die Hooks geben nur das Nötige weiter (Projekt, Status, Name des Werkzeugs) – keine Dateiinhalte, keine Prompts – und alles bleibt auf diesem Mac.")
        if !status.claudeApp {
            state(false, "", "Die Claude-App für den Mac wurde nicht gefunden.")
            note("Ohne sie fehlen der Sprung zur Session und die Nutzungsstände (5-Stunden- und Wochenlimit).")
        } else {
            note("Nutzungsstände (5-Stunden- und Wochenlimit): Dafür muss Claude Code einmal im Terminal angemeldet sein – Terminal öffnen, „claude“ starten, dann „/login“. Fehlt die Anmeldung, bleibt nur diese Anzeige leer.")
        }
    }

    private var accounts: [String] {
        var out: [String] = []
        for c in model.calendars where !out.contains(c.account) { out.append(c.account) }
        return out
    }

    @ViewBuilder private var calendar: some View {
        title("Kalender", "Lotse zeigt deinen nächsten Termin, erinnert fünf Minuten vorher und zum Beginn und bietet bei Zoom-, Teams- und Meet-Links „Beitreten“ an. Es liest dafür die Kalender, die in der Kalender-App deines Macs eingerichtet sind.")
        switch status.calendar {
        case .fullAccess:
            state(true, "Kalenderzugriff erteilt.", "")
            if model.calendars.isEmpty {
                note("Es wurden keine Kalender gefunden. Füge dein Konto (z. B. Google) unter Systemeinstellungen → Internetaccounts hinzu und schalte dort „Kalender“ ein.")
                Button("Internetaccounts öffnen") { open("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") }
            } else {
                note("Welche Kalender sollen in der Insel erscheinen, und welche gehören zur Arbeit, welche sind privat? Lotse hat einen Vorschlag gemacht – korrigiere, was nicht stimmt. Private Termine zeigt Lotse im Besprechungsmodus ohne Titel.")
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(accounts, id: \.self) { account in
                            Text(account).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
                            ForEach(model.calendars.filter { $0.account == account }) { c in
                                HStack {
                                    Toggle(c.title, isOn: Binding(get: { c.enabled }, set: { _ in model.toggleCalendar?(c.id) }))
                                        .toggleStyle(.checkbox).font(.system(size: 13))
                                    Spacer()
                                    Picker("", selection: Binding(get: { c.role }, set: { model.setCalendarRole?(c.id, $0) })) {
                                        ForEach(CalRole.allCases, id: \.self) { Text($0.title).tag($0) }
                                    }
                                    .labelsHidden().controlSize(.small).frame(width: 120).disabled(!c.enabled)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 190)
                note("Fehlt ein Konto? Systemeinstellungen → Internetaccounts → Konto hinzufügen und „Kalender“ einschalten.")
            }
        case .notDetermined:
            state(false, "", "Lotse darf den Kalender noch nicht lesen.")
            Button("Kalenderzugriff erlauben") { model.requestCalendar?() }.controlSize(.large)
            note("macOS fragt gleich nach – bitte „Vollzugriff erlauben“ wählen. Lotse liest Termine nur, es ändert nichts.")
        default:
            state(false, "", "Der Kalenderzugriff wurde abgelehnt oder nur eingeschränkt erteilt.")
            Button("Systemeinstellungen öffnen") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") }
            note("Dort bei Lotse „Vollzugriff“ wählen. Danach Lotse neu starten.")
            Button("Lotse neu starten") { restart() }
        }
    }

    @ViewBuilder private var notices: some View {
        title("Mitteilungen anderer Apps", "Lotse hat keinen eigenen Draht zu Slack, Mail oder Chrome. Es liest mit, was macOS in die Mitteilungszentrale einträgt – dafür braucht es Festplattenvollzugriff.")
        state(status.notices, "Lotse kann Mitteilungen lesen.", "Der Festplattenvollzugriff fehlt noch.")
        if !status.notices {
            point("1", "Systemeinstellungen öffnen und bei **Lotse** den Schalter einschalten.")
            point("2", "macOS will Lotse danach neu starten – das ist richtig so.")
            HStack {
                Button("Festplattenvollzugriff öffnen") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") }.controlSize(.large)
                Button("Lotse neu starten") { restart() }
            }
        }
        Divider().padding(.vertical, 2)
        Text("Damit auch wirklich etwas ankommt").font(.system(size: 13, weight: .semibold))
        point("•", "Mitteilungen einer App **nicht ganz abschalten** – sonst trägt macOS nichts ein und Lotse sieht nichts. Stören die Banner, in Systemeinstellungen → Mitteilungen → App nur den Haken bei **„Schreibtisch“** entfernen; „Mitteilungszentrale“ muss an bleiben.")
        if status.chrome {
            point("•", "**Gmail in Chrome:** in Gmail unter Einstellungen → Allgemein → „Desktop-Benachrichtigungen“ einschalten und Chrome die Benachrichtigungen für mail.google.com erlauben.")
            point("•", "**Google Kalender in Chrome blockieren** (calendar.google.com) – Lotse meldet Termine selbst, sonst kommt jeder doppelt. Wer mag, blockiert auch claude.ai.")
            HStack {
                Button("Mitteilungen in den Systemeinstellungen") { open("x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
                Button(copied.isEmpty ? "Chrome-Adresse kopieren" : "Kopiert – in Chrome einfügen") { copy("chrome://settings/content/notifications") }
            }
        } else {
            Button("Mitteilungen in den Systemeinstellungen") { open("x-apple.systempreferences:com.apple.Notifications-Settings.extension") }
        }
        note("Welche Apps die Insel aufklappen dürfen, stellst du später unter Einstellungen → Mitteilungen ein.")
    }

    @ViewBuilder private var extras: some View {
        title("Extras", "Alles hier ist freiwillig und lässt sich später in den Einstellungen ändern.")
        Toggle("Fenster beim Ziehen an den Bildschirmrand einrasten", isOn: $snapping)
            .onChange(of: snapping) { _, on in if on != snap.enabled { snap.enabled = on } }
        if snapping {
            if status.accessibility {
                state(true, "Freigabe „Bedienungshilfen“ erteilt.", "")
            } else {
                HStack {
                    state(false, "", "Dafür fehlt die Freigabe „Bedienungshilfen“.")
                    Button("Freigabe öffnen") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") }
                }
            }
        }
        Divider().padding(.vertical, 2)
        HStack {
            Text("Wetter-Ort").font(.system(size: 13))
            TextField("Ort", text: $city, prompt: Text("z. B. Berlin")).frame(width: 200)
                .onSubmit { model.setWeatherCity?(city) }
            Button("Sichern") { model.setWeatherCity?(city) }.disabled(city == model.weatherCity)
        }
        note("Nur der Ortsname geht an den Wetterdienst Open-Meteo. Leer lassen, um das Wetter abzuschalten.")
        Picker("Farben", selection: $model.palette) {
            ForEach(Palette.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .frame(width: 330)
        Toggle("Lotse beim Anmelden starten", isOn: $login)
            .onChange(of: login) { _, on in
                do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                catch { login = SMAppService.mainApp.status == .enabled }
            }
        Divider().padding(.vertical, 2)
        note("Erst beim ersten Benutzen fragt macOS nach: Mitschnitt eines Calls (Bildschirm- und Systemaudioaufnahme, Mikrofon), Transkript (Spracherkennung) und Musiksteuerung für Spotify (Automation). Jeweils erlauben – Lotse nimmt nur auf, wenn du selbst „Aufnehmen“ drückst, und alles bleibt auf diesem Mac.")
    }

    @ViewBuilder private var finish: some View {
        title("Alles klar zum Ablegen", "So steht es um die Einrichtung:")
        state(status.hooks == .connected, "Claude Code ist verbunden.", "Claude Code ist nicht verbunden – die Insel zeigt dann keine Sessions.")
        state(status.calendar == .fullAccess, "Der Kalender ist freigegeben.", "Kein Kalenderzugriff – Termine und Erinnerungen fehlen.")
        state(status.notices, "Mitteilungen anderer Apps kommen an.", "Kein Festplattenvollzugriff – Mitteilungen anderer Apps fehlen.")
        Spacer().frame(height: 4)
        note("Offene Punkte kannst du links direkt anklicken. Den Assistenten findest du später unter Einstellungen → Hilfe → „Einrichtung erneut öffnen“. Wenn etwas nicht klappt, steht in ~/Library/Logs/Lotse.log, was Lotse gerade tut – Claude kann die Datei für dich lesen.")
    }
}

extension Demo {
    /// Probebild einer Assistenten-Seite: `Lotse --snapshot-setup <png> <schritt 0…5>`.
    @MainActor static func snapshotSetup(to path: String, step: Int) {
        Probe.setupStep = step
        let m = IslandModel(persist: false)
        m.calendars = [CalendarChoice(id: "1", title: "Arbeit", account: "Google", enabled: true),
                       CalendarChoice(id: "2", title: "Privat", account: "Google", enabled: true),
                       CalendarChoice(id: "3", title: "Feiertage in Deutschland", account: "Google", enabled: false)]
        let host = NSHostingView(rootView: OnboardingView(model: m, snap: WindowSnap()) {})
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 540)
        let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
