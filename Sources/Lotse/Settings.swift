import SwiftUI
import AppKit
import ServiceManagement

/// Das Einstellungsfenster: alles, was vorher in Untermenüs des Segelboot-Menüs verteilt war.
/// Bewusst ein gewöhnliches Mac-Fenster mit Reitern – Einstellungen sollen vertraut aussehen, nicht wie die Insel.
final class SettingsWindow {
    private var window: NSWindow?
    private let model: IslandModel
    private let snap: WindowSnap

    init(model: IslandModel, snap: WindowSnap) { self.model = model; self.snap = snap }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                             styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Lotse – Einstellungen"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model, snap: snap))
            w.center()
            window = w
        }
        // Die Insel klappt zu, damit sie das Fenster nicht verdeckt.
        if model.pinnedOpen { model.togglePinned() }
        if model.mode == .expanded { model.mode = .compact }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: IslandModel
    let snap: WindowSnap

    @State private var tab = 0
    private static let tabs: [(String, String)] = [
        ("Allgemein", "gearshape"), ("Mitteilungen", "bell"), ("Kalender", "calendar"),
        ("Schnellzugriff und Ablage", "folder"), ("Fenster", "macwindow"), ("Hilfe", "questionmark.circle"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Eigene Reiterleiste: die von macOS versteckt Reiter hinter einem Pfeil, sobald der Platz knapp wird.
            HStack(spacing: 4) {
                ForEach(Array(Self.tabs.enumerated()), id: \.offset) { i, t in
                    Button { tab = i } label: {
                        VStack(spacing: 4) {
                            Image(systemName: t.1).font(.system(size: 17))
                            Text(t.0).font(.system(size: 11)).lineLimit(1).fixedSize()
                        }
                        .foregroundStyle(tab == i ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(tab == i ? Color.primary.opacity(0.10) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            Divider()
            Group {
                switch tab {
                case 0: GeneralPane(model: model)
                case 1: NoticesPane(model: model)
                case 2: CalendarPane(model: model)
                case 3: QuickPane(model: model)
                case 4: WindowsPane(model: model, snap: snap)
                default: HelpPane(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 760, height: 540)
    }
}

// MARK: Allgemein

private struct GeneralPane: View {
    @ObservedObject var model: IslandModel
    @State private var login = SMAppService.mainApp.status == .enabled

    private func part(_ title: String, _ key: String) -> some View {
        Toggle(title, isOn: Binding(get: { model.shows(key) },
                                    set: { on in if on { model.hidden.remove(key) } else { model.hidden.insert(key) } }))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Lotse beim Anmelden starten", isOn: $login)
                    .onChange(of: login) { _, on in
                        do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                        catch { log("Login-Item: \(error)") }
                        login = SMAppService.mainApp.status == .enabled
                    }
            }
            Section("Bedienung") {
                LabeledContent("Aufklappen nach") {
                    HStack {
                        Slider(value: $model.hoverDelay, in: 0.05...1.0, step: 0.05).frame(width: 180)
                        Text(String(format: "%.2f s", model.hoverDelay)).monospacedDigit().frame(width: 52, alignment: .trailing)
                    }
                }
                Text("So lange muss der Zeiger auf der Pille ruhen, bevor die Insel aufklappt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Was die Insel zeigt") {
                part("Reiter „Fokus, Zwischenablage, Termine“", "tab.work")
                part("Reiter „Lautstärke“", "tab.mix")
                part("Reiter „Ablage“", "tab.stow")
                part("Überblick: Musik", "home.music")
                part("Überblick: Wetter", "home.weather")
                part("Überblick: Datum und nächster Termin", "home.date")
                part("Überblick: Mitteilungen", "home.notices")
            }
            Section("Mitschnitt") {
                Toggle("Nach dem Mitschnitt automatisch mitschreiben", isOn: $model.autoTranscribe)
                Picker("Sprache des Calls", selection: $model.transcriptLanguage) {
                    Text("Deutsch").tag("de-DE")
                    Text("Englisch").tag("en-US")
                }
                Text("Mitgeschrieben wird auf diesem Mac; der Ton verlässt ihn nicht. Beim ersten Mal lädt macOS einmalig das Sprachmodell von Apple.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Losgehen") {
                Toggle("Rechtzeitig zum Aufbruch erinnern", isOn: $model.leaveOn)
                Text(model.locationDenied
                     ? "Standort ist für Lotse ausgeschaltet – in Systemeinstellungen → Datenschutz & Sicherheit → Ortungsdienste einschalten."
                     : "Bei Terminen mit Adresse rechnet Lotse mit Apple Karten die Fahrzeit aus und meldet sich fünf Minuten vor dem Losgehen. Die Route öffnet Google Maps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Zwischenablage") {
                Toggle("Verlauf der Zwischenablage führen", isOn: $model.clipboardOn)
                Text("Lotse merkt sich die letzten 40 kopierten Texte, Bilder und Dateien – nur im Arbeitsspeicher, nach dem Beenden sind sie weg. Als vertraulich markierte Inhalte aus Passwort-Managern werden übersprungen.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Aussehen") {
                Picker("Farben", selection: $model.palette) {
                    ForEach(Palette.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Fläche der Insel", selection: $model.glass) {
                    ForEach([GlassStyle.liquid, .frosted, .solid], id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Anzeige, wenn Claude arbeitet", selection: Binding(get: { model.wave }, set: { style in
                    model.wave = style
                    // 20 Sekunden zur Ansicht laufen lassen, auch wenn Claude gerade nicht arbeitet.
                    model.wavePreviewUntil = Date().addingTimeInterval(20)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 20.5) { model.now = Date() }
                })) {
                    ForEach(WaveStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("Nach dem Umstellen läuft die Anzeige 20 Sekunden zur Ansicht an der Pille.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Das Boot") {
                LabeledContent("Segelt, fährt die Strecke, Leuchtturm, Seegang, Gewitter, Anlegen") {
                    Button("Zustände vorführen") { model.runTour() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Mitteilungen

private struct NoticesPane: View {
    @ObservedObject var model: IslandModel

    private var apps: [(id: String, name: String)] {
        var ids = NoticeFilter.messengers + ["com.apple.mail", "com.google.chrome", "com.apple.ical", Apps.claude]
        for n in model.notices { if let a = n.appID?.lowercased(), !ids.contains(a) { ids.append(a) } }
        var seen = Set<String>()
        return ids.filter { Apps.url($0) != nil }.compactMap { id in
            let name = Apps.name(id)
            return seen.insert(name).inserted ? (id, name) : nil
        }
    }

    var body: some View {
        Form {
            Section("Besprechungsmodus") {
                Picker("Modus", selection: $model.meetingSetting) {
                    Text("Automatisch").tag(IslandModel.Meeting.auto)
                    Text("Jetzt einschalten").tag(IslandModel.Meeting.on)
                    Text("Aus").tag(IslandModel.Meeting.off)
                }
                .pickerStyle(.segmented)
                Text("Automatisch: Im Call zeigt Lotse Hinweise ohne Inhalt, beim Teilen des Bildschirms klappt nichts auf.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Diese Apps dürfen die Insel aufklappen") {
                ForEach(apps, id: \.id) { app in
                    Toggle(app.name, isOn: Binding(get: { model.filter.popsUp(app: app.id) },
                                                   set: { on in if on != model.filter.popsUp(app: app.id) { model.filter.toggle(app: app.id) } }))
                }
                Text("Ohne Haken erscheinen Mitteilungen der App nur leise in der Liste.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Kalender & Wetter

private struct CalendarPane: View {
    @ObservedObject var model: IslandModel
    @State private var city = ""

    private var accounts: [String] {
        var out: [String] = []
        for c in model.calendars where !out.contains(c.account) { out.append(c.account) }
        return out
    }

    var body: some View {
        Form {
            Section("Wetter") {
                HStack {
                    TextField("Ort", text: $city, prompt: Text("z. B. Hamburg"))
                        .onSubmit { model.setWeatherCity?(city) }
                    Button("Sichern") { model.setWeatherCity?(city) }.disabled(city == model.weatherCity)
                }
                Text("Der Ortsname wird an den Wetterdienst Open-Meteo geschickt. Leer lassen, um das Wetter abzuschalten.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Erinnerungen") {
                Toggle("Ton, wenn ein Termin beginnt", isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "calendarSound") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "calendarSound") }))
                Button("Ton anhören") { IslandModel.playMeetingSound() }
                Text("Lotse erinnert fünf Minuten vorher ohne Ton (bleibt zwölf Sekunden stehen) und zum Beginn mit Ton – diese Erinnerung bleibt eine Minute stehen, bis du sie wegklickst oder beitrittst. Im Call bleibt der Ton aus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.calendars.isEmpty {
                Section("Kalender") { Text("Keine Kalender gefunden.").foregroundStyle(.secondary) }
            } else {
                Section {
                    Text("Lege je Kalender fest, ob er zur Arbeit gehört oder privat ist. Termine tragen dann eine Aktentasche oder ein Haus, die Wochenansicht lässt sich danach filtern, und im Besprechungsmodus zeigt Lotse private Termine ohne Titel.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(accounts, id: \.self) { account in
                Section(account) {
                    ForEach(model.calendars.filter { $0.account == account }) { c in
                        HStack {
                            Toggle(c.title, isOn: Binding(get: { c.enabled }, set: { _ in model.toggleCalendar?(c.id) }))
                            Spacer()
                            Picker("", selection: Binding(get: { c.role }, set: { model.setCalendarRole?(c.id, $0) })) {
                                ForEach(CalRole.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            .labelsHidden().frame(width: 130).disabled(!c.enabled)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { city = model.weatherCity }
    }
}

// MARK: Fenster & Ordner

private struct WindowsPane: View {
    @ObservedObject var model: IslandModel
    let snap: WindowSnap
    @State private var snapping = false
    @State private var trusted = false

    var body: some View {
        Form {
            Section("Fenster anordnen") {
                Toggle("Fenster beim Ziehen an den Bildschirmrand einrasten", isOn: $snapping)
                    .onChange(of: snapping) { _, on in if on != snap.enabled { snap.enabled = on }; trusted = snap.trusted }
                if snapping, !trusted {
                    LabeledContent("Dafür fehlt die Freigabe „Bedienungshilfen“.") {
                        Button("Freigabe öffnen") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                Text("Links und rechts: Hälfte · oben: ganzer Bildschirm · Ecken: Viertel · unten: Drittel, je nach Stelle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            snapping = snap.enabled; trusted = snap.trusted
        }
    }
}

// MARK: Schnellzugriff und Ablage

private struct QuickPane: View {
    @ObservedObject var model: IslandModel
    @State private var folders: [String] = []

    var body: some View {
        Form {
            Section("Schnellzugriff auf Ordner") {
                if folders.isEmpty { Text("Noch kein Ordner festgelegt.").foregroundStyle(.secondary) }
                ForEach(folders, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(FileManager.default.displayName(atPath: path))
                            Text((path as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Entfernen") { save(folders.filter { $0 != path }) }
                    }
                }
                Button("Ordner hinzufügen …") { add() }
                Text("Die Ordner öffnest du über das Ordner-Symbol oben rechts in der Insel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ablage") {
                Picker("Dateien verschwinden aus der Ablage", selection: $model.shelfMinutes) {
                    Text("nach 10 Minuten").tag(10)
                    Text("nach 30 Minuten").tag(30)
                    Text("nach 1 Stunde").tag(60)
                    Text("nach 4 Stunden").tag(240)
                    Text("nie").tag(0)
                }
                Text("Die Ablage merkt sich nur, wo eine Datei liegt. Es wird nichts kopiert, und beim Verschwinden wird nichts gelöscht.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { folders = UserDefaults.standard.stringArray(forKey: "quickFolders") ?? [] }
    }

    private func save(_ list: [String]) {
        folders = list
        UserDefaults.standard.set(list, forKey: "quickFolders")
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = "Hinzufügen"
        panel.message = "Wähle Ordner für den Schnellzugriff in Lotse."
        panel.begin { answer in
            guard answer == .OK else { return }
            var list = folders
            for u in panel.urls where !list.contains(u.path) { list.append(u.path) }
            save(list)
        }
    }
}

// MARK: Kurz erklärt

private struct HelpPane: View {
    @ObservedObject var model: IslandModel

    private static let keys: [(String, String)] = [
        ("⌃⌥I", "Insel öffnen und offen halten"), ("Esc", "Insel wieder schließen"),
        ("⌃⌥J", "Zur Claude-Session springen, die dich braucht"),
        ("⌃⌥Y", "Sichtbare Claude-Freigabe erlauben (nicht bei riskanten Befehlen)"),
        ("⌃⌥N", "Sichtbare Claude-Freigabe ablehnen"),
    ]
    private static let tricks: [(String, String)] = [
        ("Dateien parken", "Dateien auf die Insel ziehen. Im Reiter „Ablage“ liegen sie bereit und lassen sich in jede App herausziehen."),
        ("Bilder umwandeln", "In der Ablage auf „Bilder umwandeln“ klicken – die Kopie landet neben dem Original."),
        ("Fenster in Drittel", "Ein Fenster an den unteren Bildschirmrand ziehen: links, Mitte oder rechts."),
        ("Früher Kopiertes wieder einfügen", "Im Reiter mit der Uhr steht der Verlauf der Zwischenablage – anklicken, dann wie gewohnt einfügen."),
        ("Ton umschalten", "Im Reiter „Lautstärke“ unten ein Ausgabegerät anklicken."),
        ("Kalender und Wetter", "Ein Klick auf die Kachel öffnet die jeweilige App."),
        ("Hinweis später lesen", "„Später“ schließt die Karte, der Hinweis bleibt in der Liste."),
    ]

    var body: some View {
        Form {
            Section("Tastenkürzel") {
                ForEach(Self.keys, id: \.0) { key, what in
                    LabeledContent(what) { Text(key).font(.system(.body, design: .monospaced)) }
                }
            }
            Section("Was man leicht übersieht") {
                ForEach(Self.tricks, id: \.0) { title, what in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(what).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button("Einrichtung erneut öffnen") { model.openSetup?() }
                Button("Einen Test-Hinweis zeigen") {
                    model.post(Notice(kind: .claude, appID: Apps.claude, appName: "Lotse", title: "So sieht ein Hinweis aus",
                                      body: "Fahr mit der Maus über die Insel, um alles zu sehen."))
                }
            }
        }
        .formStyle(.grouped)
    }
}
