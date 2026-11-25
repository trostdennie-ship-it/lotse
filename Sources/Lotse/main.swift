import AppKit
import SwiftUI
import ServiceManagement

// MARK: - Fenster

final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Tastatur nur, wenn ein Textfeld (Aufgabe, Notiz) angeklickt wird – nie für Knöpfe.
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// macOS zeichnet Glas in Fenstern, die nicht aktiv sind, absichtlich matt (keine Lichtkante, keine
    /// Lichtbrechung). Die Insel ist nie das aktive Fenster – deshalb meldet sie sich hier als aktiv.
    /// Das ist eine interne AppKit-Abfrage: Fällt sie in einem späteren macOS weg, wird das Glas wieder matt.
    @objc(_hasActiveAppearance) func lotseHasActiveAppearance() -> Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    /// Film-Aufnahme: Das Fenster gibt sich als Retina aus. So zeichnet SwiftUI Schrift und Boot in doppelter Auflösung,
    /// und zusammen mit der doppelten Größe landet jedes dieser Pixel genau auf einem Bildschirmpixel.
    override var backingScaleFactor: CGFloat { FilmState.active ? 2 : super.backingScaleFactor }
}

final class HostView: NSHostingView<IslandView> {
    weak var model: IslandModel?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Dateien, die auf die Insel gezogen werden, landen in der Ablage.
    private func files(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = files(sender)
        guard !urls.isEmpty else { return false }
        model?.acceptDrop(urls)
        return true
    }
}

final class IslandController {
    static let size = CGSize(width: 920, height: 880)
    let model: IslandModel
    let panel = IslandPanel()
    private var monitors: [Any] = []
    private var tracker: Timer?
    private var wasInside = false
    private var ticks = 0
    private var peekAnchor: NSPoint?
    private var mouseWasDown = false
    private var dragCountAtDown = 0
    private var draggingFiles = false

    init(model: IslandModel) {
        self.model = model
        if FilmState.active {
            // Film-Aufnahme: Die Insel wird vergrößert gezeichnet (Standard 2×), damit die Aufnahme auch auf einem
            // Bildschirm ohne Retina scharf genug für Nahaufnahmen ist.
            let k = FilmState.scale
            let film = NSHostingView(rootView: IslandView(model: model)
                .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
                .scaleEffect(k, anchor: .top)
                .frame(width: Self.size.width * k, height: Self.size.height * k, alignment: .top))
            film.sizingOptions = []
            panel.contentView = film
        } else {
        let host = HostView(rootView: IslandView(model: model))
        host.model = model
        host.sizingOptions = []
        host.registerForDraggedTypes([.fileURL])
        panel.contentView = host
        }
        model.releaseKeyboard = { [weak self] in self?.releaseKeyboard() }
        reposition()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { [weak self] _ in
            self?.checkMouse()
        }) { monitors.append(m) }
        // Klicks in der Insel mitschreiben – hilft zu prüfen, ob Knöpfe ankommen.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown], handler: { e in
            log("Klick in Insel bei \(Int(e.locationInWindow.x)),\(Int(e.locationInWindow.y))"); return e
        }) { monitors.append(m) }
        // Globale Maus-Events kommen nicht zuverlässig an – deshalb zusätzlich die Mausposition direkt abfragen.
        // In allen Run-Loop-Modi laufen lassen: Sonst steht die Maus-Prüfung still, solange ein Dialog oder Menü offen ist,
        // und die Insel bleibt aufgeklappt über dem Dialog hängen.
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.checkMouse() }
        RunLoop.main.add(t, forMode: .common)
        tracker = t
        RunLoop.main.add(tracker!, forMode: .common)
        panel.orderFrontRegardless()
    }

    /// Die Insel sitzt auf dem Bildschirm mit der Menüleiste: am Notch, sonst als Pille oben mittig.
    func reposition() {
        // Für die Film-Aufnahme: der Bildschirm mit Notch, auch wenn ein anderer der Hauptbildschirm ist.
        guard let s = (FilmState.active ? NSScreen.screens.first { $0.safeAreaInsets.top > 0 } : nil) ?? NSScreen.screens.first else { return }
        let notchH = s.safeAreaInsets.top
        let menuH = s.frame.maxY - s.visibleFrame.maxY
        model.hasNotch = notchH > 0
        if notchH > 0, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
            model.notchWidth = s.frame.width - l.width - r.width
            model.topInset = notchH
        } else {
            model.notchWidth = 0
            model.topInset = min(max(menuH, 26), 34)
        }
        if FilmState.active {
            // Im Film sitzt die Insel immer an einem Notch – auch wenn dieser Bildschirm keinen hat.
            model.hasNotch = true; model.notchWidth = 185; model.topInset = 32
            let k = FilmState.scale, w = Self.size.width * k, fh = Self.size.height * k
            panel.setFrame(NSRect(x: s.frame.midX - w / 2, y: s.frame.maxY - fh, width: w, height: fh), display: true)
            panel.orderFrontRegardless()
            return
        }
        let h = min(Self.size.height, s.frame.height)      // nie höher als der Bildschirm
        panel.setFrame(NSRect(x: s.frame.midX - Self.size.width / 2, y: s.frame.maxY - h,
                              width: Self.size.width, height: h), display: true)
        panel.orderFrontRegardless()
    }

    /// Tastatur wieder an die vorherige App abgeben (Esc in Aufgabe/Notiz).
    private func releaseKeyboard() {
        panel.makeFirstResponder(nil)
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Erkennt, ob gerade Dateien durch die Gegend gezogen werden.
    private func detectFileDrag() -> Bool {
        let down = NSEvent.pressedMouseButtons & 1 == 1
        let board = NSPasteboard(name: .drag)
        if down, !mouseWasDown { dragCountAtDown = board.changeCount; draggingFiles = false }
        if down, !draggingFiles, board.changeCount != dragCountAtDown {
            draggingFiles = board.types?.contains(.fileURL) ?? false
            dragCountAtDown = board.changeCount
        }
        if !down { draggingFiles = false }
        mouseWasDown = down
        return draggingFiles
    }

    private func checkMouse() {
        if FilmState.active { return }       // während der Aufnahme steuert das Drehbuch, nicht die Maus
        let p = NSEvent.mouseLocation
        let f = panel.frame
        let visible = panel.isOnActiveSpace      // in Vollbild-Spaces ist die Insel nicht zu sehen
        if model.islandVisible != visible { model.islandVisible = visible }
        let dragging = visible && detectFileDrag()
        model.setDragging(dragging)

        let margin: CGFloat = dragging ? 36 : (model.mode == .compact ? 0 : 10)
        var size = model.pillSize
        // Zugeklappt zählt die berechnete Pillengröße. Die gemessene kann veraltet sein – etwa solange ein Dialog offen ist
        // und die Insel nicht neu gezeichnet wird; dann klappte sie schon weit vor der Pille auf.
        if model.mode == .compact {
            size = CGSize(width: IslandView.compactWidth(model), height: min(size.height, max(model.topInset, 30)))
        }
        let rect = NSRect(x: f.midX - size.width / 2 - margin, y: f.maxY - size.height - margin,
                          width: size.width + 2 * margin, height: size.height + margin + 4)
        // Wird gerade ein Fenster an den Rand gezogen, bleibt die Insel zu.
        let inside = visible && rect.contains(p) && !WindowSnap.dragging

        // Klappt ein Hinweis unter dem ruhenden Zeiger auf, soll das nicht gleich alles öffnen:
        // erst eine echte Mausbewegung zählt als Hover.
        var trigger = inside
        if model.mode == .peek {
            if peekAnchor == nil { peekAnchor = p }
            // Über der Karte selbst klappt nichts auf – dort will man die Knöpfe treffen. Die große Insel
            // öffnet sich aus einem Hinweis heraus nur über die Kopfzeile ganz oben.
            let inHeader = p.y >= f.maxY - model.topInset
            trigger = inside && inHeader && model.peekAsk == nil && hypot(p.x - peekAnchor!.x, p.y - peekAnchor!.y) > 6
            model.holdPeek(inside && !inHeader)
        } else {
            peekAnchor = nil
        }
        // Offen bleiben, solange getippt wird oder die Ablage auf eine Entscheidung wartet.
        let hold = visible && (panel.isKeyWindow || model.pinned)

        ticks += 1
        if ProcessInfo.processInfo.environment["LOTSE_DEBUG"] != nil, ticks % 15 == 0 {
            log("debug maus \(p) rect \(rect) pill \(size) mode \(model.mode) drag \(dragging) key \(panel.isKeyWindow)")
        }
        let clickable = inside || hold
        if clickable != wasInside {
            wasInside = clickable
            panel.ignoresMouseEvents = !clickable
            log("Maus \(clickable ? "über" : "verlässt") Insel, Größe \(Int(size.width))×\(Int(size.height))")
        }
        if !dragging { model.setHover(trigger || hold) }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let meetMenu = NSMenu()
    private lazy var settings = SettingsWindow(model: model, snap: snap)
    private lazy var onboarding = OnboardingWindow(model: model, snap: snap)

    @objc private func openSettings() { settings.show() }

    var model: IslandModel!
    var controller: IslandController?
    var sources: [Any] = []
    var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    let snap = WindowSnap()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        // Probe ohne Insel: `Lotse --transcribe <Tondatei> [Sprache]` schreibt den Text auf die Konsole.
        if let i = args.firstIndex(of: "--transcribe"), args.count > i + 1 {
            let file = URL(fileURLWithPath: args[i + 1]), language = args.count > i + 2 ? args[i + 2] : "de-DE"
            Task {
                if #available(macOS 26.0, *) {
                    do { print(try await Transcriber.transcribe(file, language: language) { print("…", $0) }) }
                    catch { print("FEHLER:", error) }
                }
                exit(0)
            }
            return
        }
        if args.contains("--selftest") {
            let problems = Risk.selfTest() + WindowSnap.selfTest() + ClaudeHooks.selfTest() + Leave.selfTest()
            print(problems.isEmpty ? "Selbsttest: Risiko-Regeln, Einrast-Zonen, Claude-Hooks und Losgehen in Ordnung" : problems.joined(separator: "\n"))
            exit(problems.isEmpty ? 0 : 1)
        }
        // Für die Installation durch Claude: Hooks eintragen bzw. den Stand der Einrichtung als Text ausgeben.
        if args.contains("--connect-claude") {
            do { try ClaudeHooks.install(); print("Claude Code verbunden: Hooks stehen in ~/.claude/settings.json") ; exit(0) }
            catch { print("FEHLER: \(error.localizedDescription)"); exit(1) }
        }
        if args.contains("--disconnect-claude") {
            do { try ClaudeHooks.remove(); print("Lotses Hooks sind aus ~/.claude/settings.json entfernt"); exit(0) }
            catch { print("FEHLER: \(error.localizedDescription)"); exit(1) }
        }
        // Film-Aufnahme: spielt eine Vorführung am Notch ab und schneidet dabei nur das eigene Insel-Fenster mit.
        if let i = args.firstIndex(of: "--film"), args.count > i + 1 {
            FilmState.active = true
            let (m, _) = Demo.build(mode: "week", notch: true)
            let fleet = Demo.build(mode: "multi", notch: true).0.sessions
            m.mode = .compact; m.tab = .home; m.showWeek = false; m.sessions = []; m.notices = []; m.unread = 0
            m.palette = .amber; Theme.palette = .amber; m.glass = .liquid
            model = m
            controller = IslandController(model: m)
            if #available(macOS 15.0, *) {
                let film = Film(model: m, panel: controller!.panel, dir: URL(fileURLWithPath: args[i + 1]), fleet: fleet)
                sources = [film]
                film.start()
            }
            return
        }
        if let i = args.firstIndex(of: "--snapshot-setup"), args.count > i + 2 {
            Demo.snapshotSetup(to: args[i + 1], step: Int(args[i + 2]) ?? 0)
            NSApp.terminate(nil)
            return
        }
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 2 {
            Demo.snapshot(to: args[i + 1], mode: args[i + 2], notch: args.contains("--notch"))
            NSApp.terminate(nil)
            return
        }

        model = IslandModel()
        controller = IslandController(model: model)
        let cal = CalendarSource(model: model), claude = ClaudeSource(model: model)
        let notes = NotificationSource(model: model), music = MusicSource(model: model)
        model.toggleCalendar = { [weak cal] id in cal?.toggleCalendar(id) }
        model.requestCalendar = { [weak cal] in cal?.request() }
        model.setCalendarRole = { [weak cal] id, role in cal?.setRole(id, role) }
        model.openSetup = { [weak self] in self?.onboarding.show() }
        let usage = UsageSource(model: model)
        cal.start(); claude.start(); notes.start(); music.start(); usage.start()
        let keys = Hotkeys(model: model)
        keys.start()
        let news = SmallNews(model: model)
        news.start()
        let mixer = MixerBridge(model: model)
        mixer.start()
        var recorder: Any = 0
        if #available(macOS 15.0, *) {
            let r = CallRecorder(model: model)
            r.start()
            recorder = r
        }
        let scribe = TranscriptBridge(model: model)
        scribe.start()
        let stats = ClaudeStats(model: model)
        stats.start()
        let clipboard = ClipboardSource(model: model)
        clipboard.start()
        let weather = WeatherSource(model: model)
        weather.start()
        model.askWeatherCity = { [weak self] in self?.openSettings() }
        model.showFolders = { [weak self] in self?.showFolders() }
        let meeting = MeetingDetector()
        meeting.calendarHint = { [weak self] in
            guard let self else { return false }
            let now = Date()
            return self.model.events.contains { $0.joinURL != nil && $0.start <= now && $0.end > now }
        }
        meeting.onChange = { [weak self] call, share in
            guard let self else { return }
            if call != self.model.inCall || share != self.model.sharing {
                log("Besprechungsmodus: Call \(call ? "ja" : "nein"), Bildschirmfreigabe \(share ? "erkannt" : "nein")")
            }
            self.model.inCall = call
            self.model.sharing = share
        }
        meeting.start()
        let away = AwayWatcher(model: model)
        away.start()
        model.showAway = { [weak away] since in away?.show(since: since) }
        let leave = LeaveWatcher(model: model)
        leave.start()
        sources = [cal, claude, notes, music, usage, keys, meeting, news, mixer, weather, clipboard, recorder, stats, scribe, away, leave]
        snap.start()
        setupMenu()
        log("Lotse gestartet")
        // Stand der Einrichtung als Textdatei – so kann auch Claude nachsehen, was noch fehlt.
        let statusFile = ClaudeSource.base.appendingPathComponent("einrichtung.txt")
        var lastReport = ""
        let writeStatus = { [weak self] in
            guard let self else { return }
            let r = SetupStatus.read(model: self.model, snap: self.snap).report
            if r != lastReport { lastReport = r; try? (r + "\n").write(to: statusFile, atomically: true, encoding: .utf8) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { writeStatus() }
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in writeStatus() }
        // Erster Start: durch die Einrichtung führen.
        if !OnboardingWindow.done || args.contains("--setup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.onboarding.show() }
        }
    }

    /// Das Pixel-Segelboot für die Menüleiste – dasselbe Boot wie in der Insel, einfarbig, damit macOS es
    /// je nach heller oder dunkler Menüleiste selbst einfärbt.
    private static func menuBoat() -> NSImage {
        let art = Mascot.boat
        let px: CGFloat = 2, w = 24.0, h = 20.0
        let hair = 1 / (NSScreen.main?.backingScaleFactor ?? 2)
        let img = NSImage(size: NSSize(width: w, height: h), flipped: true) { _ in
            for (y, row) in art.enumerated() {
                for (x, c) in row.enumerated() where c != "." {
                    // Kästchen rasten einzeln auf ganze Punkte ein: scharf auch ohne Retina.
                    let x0 = (CGFloat(x) * px).rounded(), x1 = (CGFloat(x + 1) * px).rounded()
                    let y0 = (CGFloat(y) * px).rounded(), y1 = (CGFloat(y + 1) * px).rounded()
                    // Schmaler Spalt zwischen den Kästchen wie im App-Symbol.
                    // Der Spalt ist nur abgedunkelt, nicht leer – sonst wirkt das Boot neben anderen Symbolen grau.
                    let a: CGFloat = c == "s" || c == "h" ? 0.8 : 1
                    NSColor.black.withAlphaComponent(a * (hair >= 1 ? 0.42 : 0.5)).setFill()
                    NSRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).fill()
                    NSColor.black.withAlphaComponent(a).setFill()
                    NSRect(x: x0, y: y0, width: x1 - x0 - hair, height: y1 - y0 - hair).fill()
                }
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Lotse"
        return img
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.menuBoat()
        let menu = NSMenu()
        // Das Menü bleibt kurz: Alles Einstellbare steht im Einstellungsfenster. Nur der Besprechungsmodus
        // ist hier direkt erreichbar, weil man ihn mitten im Call schnell braucht.
        menu.addItem(withTitle: "Einstellungen …", action: #selector(openSettings), keyEquivalent: ",").target = self
        let meet = NSMenuItem(title: "Besprechungsmodus", action: nil, keyEquivalent: "")
        meetMenu.delegate = self
        meet.submenu = meetMenu
        menu.addItem(meet)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Lotse beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    // MARK: Wetter-Ort und Schnellzugriff auf Ordner

    /// Vor einem Dialog klappt die Insel zu; der Dialog liegt außerdem über ihr.
    private func makeRoom(for window: NSWindow) {
        if model.pinnedOpen { model.togglePinned() }
        withAnimation(IslandModel.spring) { if model.mode == .expanded { model.mode = .compact } }
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
    }

    private var folders: [String] {
        get { UserDefaults.standard.stringArray(forKey: "quickFolders") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "quickFolders") }
    }

    /// Kleines Menü am Ordner-Symbol: festgelegte Ordner öffnen, hinzufügen, entfernen.
    private func showFolders() {
        let menu = NSMenu()
        for path in folders {
            let i = menu.addItem(withTitle: FileManager.default.displayName(atPath: path), action: #selector(openFolder(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = path
            i.image = NSWorkspace.shared.icon(forFile: path); i.image?.size = NSSize(width: 16, height: 16)
        }
        if !folders.isEmpty { menu.addItem(.separator()) }
        menu.addItem(withTitle: "Ordner hinzufügen …", action: #selector(addFolder), keyEquivalent: "").target = self
        if !folders.isEmpty {
            let remove = NSMenuItem(title: "Ordner entfernen", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for path in folders {
                let i = sub.addItem(withTitle: FileManager.default.displayName(atPath: path), action: #selector(removeFolder(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = path
            }
            remove.submenu = sub
            menu.addItem(remove)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    }

    @objc private func addFolder() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = "Hinzufügen"
        panel.message = "Wähle Ordner für den Schnellzugriff in Lotse."
        makeRoom(for: panel)
        // Nicht blockierend öffnen: So läuft Lotse währenddessen normal weiter.
        panel.begin { [weak self] answer in
            guard let self, answer == .OK else { return }
            var list = self.folders
            for u in panel.urls where !list.contains(u.path) { list.append(u.path) }
            self.folders = list
        }
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func removeFolder(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String { folders.removeAll { $0 == path } }
    }

    @objc private func setMeeting(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = IslandModel.Meeting(rawValue: raw) else { return }
        model.meetingSetting = m
        sender.menu?.items.forEach { $0.state = ($0.representedObject as? String) == raw ? .on : .off }
        log("Besprechungsmodus eingestellt: \(raw)")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === meetMenu {
            // Jedes Mal neu aufbauen: Der Modus lässt sich auch im Einstellungsfenster umstellen.
            menu.removeAllItems()
            for (mode, title) in [(IslandModel.Meeting.auto, "Automatisch (im Call ohne Inhalte, beim Teilen stumm)"),
                                  (.on, "Jetzt einschalten (stumm, bis ich ihn ausschalte)"), (.off, "Aus")] {
                let i = menu.addItem(withTitle: title, action: #selector(setMeeting(_:)), keyEquivalent: "")
                i.target = self; i.representedObject = mode.rawValue; i.state = model.meetingSetting == mode ? .on : .off
            }
            return
        }
    }

}

// MARK: - Beispielbild (zum Prüfen des Layouts ohne Bildschirmaufnahme)

enum Demo {
    @MainActor static func snapshot(to path: String, mode: String, notch: Bool) {
        let (m, tall) = build(mode: mode, notch: notch)
        render(m, tall: tall, to: path)
    }

    /// Ein Modell mit Beispieldaten für den genannten Zustand (Probebilder, Vorführung).
    @MainActor static func build(mode: String, notch: Bool) -> (IslandModel, Bool) {
        let m = IslandModel(persist: false)
        StagedMascot.instant = true
        m.glass = .liquid
        let now = Date()
        if CommandLine.arguments.contains("--amber") { Theme.palette = .amber }
        if let i = CommandLine.arguments.firstIndex(of: "--palette"), i + 1 < CommandLine.arguments.count,
           let p = Palette(rawValue: CommandLine.arguments[i + 1]) { Theme.palette = p }
        m.hasNotch = notch; m.notchWidth = notch ? 185 : 0; m.topInset = notch ? 32 : 28
        func ev(_ id: String, _ title: String, _ from: Double, _ mins: Double, join: Bool = false) -> CalEvent {
            CalEvent(id: id, title: title, start: now.addingTimeInterval(from * 60), end: now.addingTimeInterval((from + mins) * 60),
                     color: .blue, joinURL: join ? URL(string: "https://zoom.us/j/1") : nil,
                     role: ["3", "p"].contains(id) ? .personal : .work)
        }
        m.events = [ev("0", "Wochenstart Team", -190, 30), ev("p", "Angebot durchgehen", -95, 45),
                    ev("1", "Jour fixe", 12, 60, join: true), ev("2", "Abstimmung Kampagnenplanung", 95, 30),
                    ev("3", "Call Agentur", 150, 30), ev("4", "Review Entwurf", 200, 45)]
        m.track = Track(title: "Weightless", artist: "Marconi Union", isPlaying: true)
        var a = ClaudeSession(id: "a", project: "Lotse", status: .working, message: "", updated: now.addingTimeInterval(-20))
        a.detail = "Baut Lotse und installiert die neue Version"; a.model = "Fable 5.2"; a.planDone = 2; a.planTotal = 5
        a.planStep = "Arbeitsplatz bauen"; a.contextPercent = 41; a.startedAt = now.addingTimeInterval(-247)
        var b = ClaudeSession(id: "b", project: "Video", status: .done, message: "", updated: now.addingTimeInterval(-600))
        b.model = "Opus 5.5"
        b.summary = "Der Schnitt steht: Intro gekürzt, Untertitel eingebrannt, Export als 9:16 liegt im Ordner."
        b.tookSeconds = 20; b.doneAt = now.addingTimeInterval(-30)
        m.sessions = [a, b]
        m.limits = [
            UsageLimit(label: "5 Stunden", percent: 83, resets: now.addingTimeInterval(2.4 * 3600)),
            UsageLimit(label: "Woche", percent: 18, resets: now.addingTimeInterval(4.2 * 86400)),
        ]
        m.notices = [
            Notice(kind: .system, appID: "com.tdesktop.Telegram", appName: "Telegram", title: "Anna", body: "Kannst du heute Abend noch Brot mitbringen?", date: now.addingTimeInterval(-120)),
            Notice(kind: .system, appID: "com.apple.mail", appName: "Mail", title: "Angebot Q1", body: "Anbei die überarbeitete Fassung – bitte bis Mittwoch freigeben.", date: now.addingTimeInterval(-2400)),
        ]
        m.weather = Weather(city: "Hamburg", temperature: 8, high: 10, low: 4, symbol: "cloud.sun.fill")
        m.today = ClaudeDay(tokens: 4_260_000, sessions: 6, tools: 812, top: "Lotse")
        m.forecast = (0..<8).map { i in
            HourWeather(time: now.addingTimeInterval(Double(i) * 3600), temperature: 8 - i / 2,
                        symbol: ["cloud.sun.fill", "cloud.fill", "cloud.rain.fill", "cloud.rain.fill", "cloud.fill", "cloud.moon.fill", "moon.stars.fill", "moon.stars.fill"][i],
                        rain: [10, 20, 70, 85, 40, 15, 5, 0][i])
        }
        if mode == "forecast" { m.showForecast = true }
        m.note = "Plakat-Idee: eine große Zahl, viel Luft, Grau auf Grau."
        m.clips = [Clip(text: "https://meet.google.com/abc-defg-hij", date: now.addingTimeInterval(-40), app: "Google Chrome"),
                   Clip(text: "Hallo Anna,\nanbei die überarbeitete Fassung des Angebots.", date: now.addingTimeInterval(-300), app: "Mail"),
                   Clip(text: "Angebot Q1.pdf", date: now.addingTimeInterval(-900), app: "Finder",
                        kind: .files([URL(fileURLWithPath: "/tmp/Angebot Q1.pdf")])),
                   Clip(text: "swift build -c release", date: now.addingTimeInterval(-2400), app: "Terminal"),
                   Clip(text: "Freitags-Clip – 16:9 und 9:16", date: now.addingTimeInterval(-5400), app: "Slack")]
        m.peekNotice = Notice(kind: .claude, appID: Apps.claude, appName: "Claude · Lotse", title: "Claude ist fertig", body: "Die Aufgabe in „Lotse“ ist abgeschlossen.")

        var tall = false
        if mode.hasSuffix("multi") {
            // Drei Sessions arbeiten zugleich, eine wartet, eine ist fertig.
            var c = ClaudeSession(id: "c", project: "Video", status: .working, message: "", updated: now.addingTimeInterval(-8))
            c.detail = "Rendert die Untertitel neu"; c.model = "Opus 5.5"; c.planDone = 3; c.planTotal = 4; c.startedAt = now.addingTimeInterval(-912)
            var d = ClaudeSession(id: "d", project: "Website", status: .working, message: "", updated: now.addingTimeInterval(-3))
            d.detail = "Prüft die Startseite im Browser"; d.model = "Sonnet 5.5"; d.startedAt = now.addingTimeInterval(-64)
            var e = ClaudeSession(id: "e", project: "Auswertung", status: .waiting, message: "", updated: now.addingTimeInterval(-95))
            e.model = "Fable 5.2"
            m.sessions = [m.sessions[0], c, d, e, m.sessions[1]]
            m.unread = 0
        }
        switch mode {
        case "compact-multi": m.events = []; m.sessions.removeAll { $0.status == .waiting }
        case "multi": m.mode = .expanded; tall = true
        case "compact": m.unread = 2
        case "compact-work": m.unread = 0; m.events = []
            if let d = ProcessInfo.processInfo.environment["LOTSE_DONE"].flatMap({ Int($0) }) { m.sessions[0].planDone = d }
        case "transcript":
            m.mode = .expanded; m.tab = .work; tall = true
            m.autoTranscribe = false
            m.recState = .done(URL(fileURLWithPath: "/tmp/Mitschnitt.m4a"))
            m.transcript = .ready(URL(fileURLWithPath: "/tmp/Mitschnitt.txt"))
        case "rec":
            m.mode = .expanded; m.tab = .work; tall = true
            m.recState = .recording(since: now.addingTimeInterval(-754))
        case "forecast": m.mode = .expanded; tall = true
        case "week":
            m.mode = .expanded; tall = true; m.showWeek = true
            let day0 = Calendar.current.startOfDay(for: now)
            func w(_ d: Int, _ h: Double, _ title: String, allDay: Bool = false, role: CalRole = .work) -> CalEvent {
                let s = day0.addingTimeInterval(Double(d) * 86400 + h * 3600)
                return CalEvent(id: "w\(d)\(h)\(title)", title: title, start: s, end: s.addingTimeInterval(allDay ? 86400 : 3600),
                                color: Theme.accent, joinURL: nil, allDay: allDay, role: role)
            }
            let hourNow = now.timeIntervalSince(day0) / 3600
            m.week = [w(0, max(0, hourNow - 3), "Wochenstart Team"), w(0, max(0, hourNow - 0.4), "Angebot durchgehen"), w(0, min(23, hourNow + 2), "Jour fixe"),
                      w(1, 10, "Zahnarzt", role: .personal), w(1, 13, "Mittagessen Kundin"), w(1, 16, "Abstimmung Kampagnenplanung"),
                      w(2, 0, "Feiertag", allDay: true, role: .none), w(2, 11, "Review Entwurf"),
                      w(3, 9.5, "Teamrunde"), w(3, 15, "Call Agentur"),
                      w(4, 12, "Wochenabschluss"), w(4, 19, "Sport", role: .personal), w(6, 18, "Familie", role: .personal)]
        case "storm":
            m.mode = .expanded; tall = true
            m.sessions[0].planTotal = 0
            m.limits[0] = UsageLimit(label: "5 Stunden", percent: 94, resets: now.addingTimeInterval(1800))
        case let w where w.hasPrefix("wave-"):
            m.unread = 0; m.events = []; m.wave = WaveStyle(rawValue: String(w.dropFirst(5))) ?? .fine
        case "compact-calm": m.sessions = []; m.track?.isPlaying = false; m.events = []
        case "peek": m.mode = .peek
        case "away":
            m.notices += [Notice(kind: .system, appID: "com.apple.mail", appName: "Mail", title: "Stadtwerke", body: "Ihre Abschlagsrechnung", date: now.addingTimeInterval(-3000)),
                          Notice(kind: .system, appID: "com.apple.mail", appName: "Mail", title: "Newsletter", body: "", date: now.addingTimeInterval(-6000))]
            m.sessions[1].doneAt = now.addingTimeInterval(-1200)
            var w = ClaudeSession(id: "w", project: "Website", status: .waiting, message: "", updated: now.addingTimeInterval(-900)); w.model = "Opus 5.5"
            m.sessions.append(w)
            m.away = AwaySummary.collect(m, since: now.addingTimeInterval(-8.5 * 3600))
            m.peekNotice = Notice(kind: .info, appName: "Willkommen zurück", title: "Willkommen zurück", body: "", card: "away", hold: 45)
            m.mode = .peek; tall = true
        case "leave", "leave-late":
            m.leave = LeaveCard.demo(now: now, minutesToLeave: mode == "leave" ? 5 : -7)
            m.peekNotice = Notice(kind: .info, appName: "Losgehen", title: "Kundentermin", body: "", card: "leave", hold: 120)
            m.mode = .peek; tall = true
        case "leave-ask":
            m.peekNotice = Notice(kind: .info, appName: "Losgehen", title: "Standort für „Losgehen“", body: "", card: "leave-ask", hold: 60)
            m.mode = .peek; tall = true
        case "peek-system": m.peekNotice = m.notices[0]; m.mode = .peek
        case "peek-cal", "peek-cal-long":
            let long = mode == "peek-cal-long"
            let e = CalEvent(id: "p", title: long ? "Abstimmung Kampagnenplanung Q1 mit Agentur und Einkauf" : "Jour fixe Vertrieb",
                             start: now.addingTimeInterval(60), end: now.addingTimeInterval(3660), color: Color(red: 0.36, green: 0.62, blue: 0.95),
                             joinURL: long ? nil : URL(string: "https://meet.google.com/abc"), role: .work, place: long ? "Raum Elbe, 3. OG" : "", calendar: "Arbeit")
            m.now = now
            m.peekNotice = Notice(kind: .calendar, appID: "com.apple.iCal", appName: "Kalender · Arbeit", title: e.title,
                                  body: "Beginnt in 1 Min" + (long ? "" : " · klicken zum Beitreten"), url: e.joinURL, sound: true, event: e)
            m.mode = .peek
        case "ask", "home-ask", "ask-risk", "question":
            m.sessions[0].status = .waiting
            var ask = PermissionAsk(id: "x", sessionID: "a", project: "Lotse", tool: "Bash", detail: "npm test")
            ask.summary = "Führt die Tests des Projekts aus"
            if mode == "question" {
                ask.tool = "AskUserQuestion"
                ask.questions = [
                    .init(header: "Bedienung", text: "Wie ordnest du Fenster mit Magnet heute an – was soll Lotse davon können?",
                          options: ["Tastenkürzel", "An den Rand ziehen", "Knöpfe in der Insel"], multi: true),
                    .init(header: "Kürzel", text: "⌃⌥I und ⌃⌥J sind in Lotse schon belegt. Wie lösen wir das?",
                          options: ["Magnets Kürzel gewinnen", "Lotses Kürzel bleiben", "Ich nutze eigene Kürzel"], multi: false)]
            }
            if mode == "ask-risk" {
                ask.detail = "rm -rf ~/Documents/Claude/Projects/Lotse/build && sudo cp -R /tmp/lotse-build/Lotse.app /Applications/"
                ask.summary = "Räumt den Build-Ordner auf und installiert die App"
                ask.risk = Risk.bash(ask.detail)
            }
            m.asks = [ask]
            m.peekNotice = Notice(kind: .claude, appID: Apps.claude, appName: "Claude · Lotse", title: "Claude wartet auf dein OK", body: "npm test", sessionID: "a")
            if mode != "home-ask" { m.mode = .peek } else { m.mode = .expanded; tall = true }
        case "done":
            m.sessions = [m.sessions[1]]
            m.peekNotice = Notice(kind: .claude, appID: Apps.claude, appName: "Claude", title: "Claude ist fertig", body: m.sessions[0].summary, sessionID: "b")
            m.mode = .peek
        case "home-done": m.sessions = [m.sessions[1]]; m.mode = .expanded; tall = true
        case "voyage":
            m.mode = .expanded; tall = true
            if let d = ProcessInfo.processInfo.environment["LOTSE_DONE"].flatMap({ Int($0) }) { m.sessions[0].planDone = d }
        case "brief":
            m.peekNotice = Notice(kind: .info, appID: nil, appName: "", title: "Lädt", body: "82 %", brief: true, symbol: "bolt.fill")
            m.mode = .peek
        case "mail":
            DeviceCard.freeze = 1.2
            m.peekNotice = Notice(kind: .system, appID: "com.apple.mail", appName: "Mail", title: "Anna Berger", body: "Angebot Q1 – überarbeitete Fassung", card: "mail")
            m.mode = .peek
        case "card", "card-early":
            DeviceCard.freeze = mode == "card" ? 0.8 : 0.3
            m.peekNotice = Notice(kind: .info, appID: nil, appName: "", title: "AirPods Pro", body: "Verbunden", card: "headphones")
            m.mode = .peek
        case "drop": m.mode = .drop
        case "work": m.mode = .expanded; m.tab = .work; tall = true
        case "mix":
            m.volume = 0.57; m.volumeAdjustable = true; m.outputName = "Externe Kopfhörer"
            m.outputs = [AudioOut(id: 1, name: "Externe Kopfhörer", symbol: "headphones", current: true),
                         AudioOut(id: 2, name: "MacBook Pro-Lautsprecher", symbol: "laptopcomputer", current: false),
                         AudioOut(id: 3, name: "LG HDR WQHD", symbol: "display", current: false)]
            m.mixApps = [MixApp(id: "com.spotify.client", name: "Spotify", url: Apps.url("com.spotify.client"), scriptable: true, level: 0.8),
                         MixApp(id: "com.google.chrome", name: "Google Chrome", url: Apps.url("com.google.Chrome"), scriptable: false),
                         MixApp(id: "us.zoom.xos", name: "Zoom", url: Apps.url("us.zoom.xos"), scriptable: false)]
            m.mode = .expanded; m.tab = .mix; tall = true
        case "stow": m.mode = .expanded; m.tab = .stow; tall = true; m.shelf = []
        case "to-claude", "to-claude-multi":
            m.mode = .expanded; m.tab = .stow; tall = true
            m.claudeFiles = (mode == "to-claude" ? ["/System/Library/QuickLook/iWork.qlgenerator/Contents/Resources/fallback-image-bullet.pdf"]
                : ["/etc/hosts", "/System/Library/Desktop Pictures/Solid Colors/Teal.png", "/Library/Fonts/Arial Unicode.ttf"])
                .map { URL(fileURLWithPath: $0) }
        case "shelf":
            m.mode = .expanded; m.tab = .stow; tall = true
            m.shelf = ["/Applications/Safari.app", "/System/Library/Desktop Pictures/Solid Colors/Teal.png", "/etc/hosts",
                       "/Library/Fonts/Arial Unicode.ttf", "/System/Applications/Calendar.app"]
                .map { ShelfItem(url: URL(fileURLWithPath: $0), added: now) }
        default: m.mode = .expanded; tall = true
        }

        return (m, tall)
    }

    @MainActor private static func render(_ m: IslandModel, tall: Bool, to path: String) {
        // Für Filmmaterial: LOTSE_W / LOTSE_H (Breite und Höhe in Punkt), LOTSE_SCALE (Auflösung), LOTSE_BG=dark|flat|key (Hintergrund).
        let env = ProcessInfo.processInfo.environment
        let height = env["LOTSE_H"].flatMap { Double($0) }.map { CGFloat($0) } ?? (tall ? 560 : 280)
        let wall: [Color]
        switch env["LOTSE_BG"] ?? "" {
        case "dark": wall = [Color(red: 0.17, green: 0.16, blue: 0.155), Color(red: 0.115, green: 0.11, blue: 0.105), Color(red: 0.075, green: 0.07, blue: 0.07)]
        case "flat": wall = [Color(red: 0.082, green: 0.078, blue: 0.075), Color(red: 0.082, green: 0.078, blue: 0.075)]
        case "key": wall = [Color(red: 1, green: 0, blue: 1), Color(red: 1, green: 0, blue: 1)]
        default: wall = [Color(red: 0.55, green: 0.62, blue: 0.78), Color(red: 0.80, green: 0.62, blue: 0.55), Color(red: 0.30, green: 0.36, blue: 0.50)]
        }
        let view = IslandView(model: m)
            .frame(width: env["LOTSE_W"].flatMap { Double($0) }.map { CGFloat($0) } ?? 900, height: height)
            .background(LinearGradient(colors: wall, startPoint: .topLeading, endPoint: .bottomTrailing))
        let r = ImageRenderer(content: view)
        r.scale = env["LOTSE_SCALE"].flatMap { Double($0) }.map { CGFloat($0) } ?? 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
