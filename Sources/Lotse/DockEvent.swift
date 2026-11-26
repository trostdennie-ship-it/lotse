import AppKit
import Combine
import SwiftUI

// MARK: - Nächster Termin neben dem Dock

/// Was das Termin-Widget links neben dem Dock zeigt. Reine Rechnung, damit sie sich prüfen lässt.
enum DockEvent {
    /// Der Termin, um den es geht: der nächste, der noch nicht vorbei ist, ohne ganztägige, höchstens 24 Stunden voraus.
    static func pick(_ events: [CalEvent], now: Date) -> CalEvent? {
        events.filter { !$0.allDay && $0.end > now && $0.start.timeIntervalSince(now) < 24 * 3600 }
            .min { $0.start < $1.start }
    }

    /// Ob das Widget stehen soll: ein Termin in den nächsten acht Stunden, oder rechts läuft Musik
    /// (dann steht links „Heute nichts mehr“, damit das Dock nicht schief wirkt).
    static func wanted(_ e: CalEvent?, now: Date, musicShown: Bool) -> Bool {
        if let e, e.start.timeIntervalSince(now) < 8 * 3600 { return true }
        return musicShown
    }

    /// Die Zeile unter dem Titel und ob sie drängt (weniger als eine Stunde oder läuft schon).
    static func line(_ e: CalEvent, now: Date) -> (text: String, urgent: Bool) {
        let start = Fmt.time.string(from: e.start), end = Fmt.time.string(from: e.end)
        if e.start <= now { return ("läuft · bis \(end)", true) }
        let mins = Int(ceil(e.start.timeIntervalSince(now) / 60))
        if mins < 60 { return ("in \(mins) Min · \(start)", true) }
        if !Calendar.current.isDate(e.start, inSameDayAs: now) { return ("morgen · \(start) – \(end)", false) }
        return ("\(start) – \(end)", false)
    }

    static func selfTest() -> [String] {
        var bad: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { bad.append("Termin am Dock: \(what)") } }
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 13, minute: 35))!
        func ev(_ id: String, _ from: Double, _ len: Double = 60, allDay: Bool = false) -> CalEvent {
            CalEvent(id: id, title: id, start: now.addingTimeInterval(from * 60), end: now.addingTimeInterval((from + len) * 60),
                     color: .blue, joinURL: nil, allDay: allDay)
        }
        check(pick([ev("ganztags", -600, 1440, allDay: true), ev("vorbei", -120), ev("später", 200), ev("gleich", 25)], now: now)?.id == "gleich",
              "nimmt nicht den nächsten Termin")
        check(pick([ev("übermorgen", 30 * 60)], now: now) == nil, "Termin in mehr als 24 Stunden")
        check(line(ev("x", 25), now: now) == ("in 25 Min · 14:00", true), "Zeile kurz vorher: \(line(ev("x", 25), now: now))")
        check(line(ev("x", -10, 40), now: now) == ("läuft · bis 14:05", true), "Zeile läuft: \(line(ev("x", -10, 40), now: now))")
        check(line(ev("x", 145), now: now) == ("16:00 – 17:00", false), "Zeile später: \(line(ev("x", 145), now: now))")
        check(line(ev("x", 20 * 60), now: now).text.hasPrefix("morgen"), "Zeile morgen")
        check(wanted(ev("x", 145), now: now, musicShown: false), "Termin heute soll stehen")
        check(!wanted(ev("x", 10 * 60), now: now, musicShown: false), "Termin in zehn Stunden ohne Musik soll nicht stehen")
        check(wanted(nil, now: now, musicShown: true), "mit Musik soll links etwas stehen")
        check(!wanted(nil, now: now, musicShown: false), "ohne Termin und Musik soll nichts stehen")
        return bad
    }
}

struct DockEventView: View {
    @ObservedObject var model: IslandModel
    @State private var hovered: String?

    private var event: CalEvent? { DockEvent.pick(model.events, now: model.now) }

    var body: some View {
        HStack(spacing: 10) {
            Button { openWeek() } label: {
                HStack(spacing: 10) {
                    dayBlock
                    if let e = event {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(e.color).frame(width: 3, height: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            e.marked(discreet: model.discreet).font(Theme.font(13, .medium)).foregroundStyle(Theme.text)
                            let l = DockEvent.line(e, now: model.now)
                            Text(l.text).font(Theme.font(11)).monospacedDigit()
                                .foregroundStyle(l.urgent ? Theme.accent : Theme.muted)
                        }
                        .lineLimit(1)
                    } else {
                        Text(model.calendarDenied ? "Kein Kalenderzugriff" : "Heute nichts mehr")
                            .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                }
                .opacity(hovered == "body" ? 1 : 0.92)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Termine der Woche zeigen")
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h ? "body" : (hovered == "body" ? nil : hovered) } }
            Spacer(minLength: 4)
            if let e = event { action(e) }
        }
        .padding(.leading, 12).padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EE"; return f
    }()

    private var dayBlock: some View {
        VStack(spacing: -3) {
            Text(Self.weekday.string(from: model.now).uppercased().replacingOccurrences(of: ".", with: ""))
                .font(Theme.font(10, .medium)).foregroundStyle(Theme.muted)
            Text("\(Calendar.current.component(.day, from: model.now))")
                .font(Theme.font(22, .light)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .frame(width: 34)
    }

    /// Rechts ein Knopf, wenn es etwas zu tun gibt: losgehen (Route) oder beitreten (Link). Sonst nichts.
    @ViewBuilder private func action(_ e: CalEvent) -> some View {
        let soon = e.start.timeIntervalSince(model.now)
        if let c = model.leave, c.event.id == e.id, soon > -60 {
            let late = c.plan.leaveAt <= model.now
            chip(c.plan.mode.symbol, late ? "Los!" : "Los " + Fmt.time.string(from: c.plan.leaveAt), key: "leave", strong: late,
                 help: "Route in Google Maps öffnen") {
                if let u = Leave.mapsURL(address: c.place.address, mode: c.plan.mode) { NSWorkspace.shared.open(u) }
            }
        } else if let url = e.joinURL, soon < 15 * 60, e.end > model.now {
            chip("video.fill", "Beitreten", key: "join", strong: soon < 5 * 60, help: "Dem Termin beitreten") { NSWorkspace.shared.open(url) }
        }
    }

    private func chip(_ symbol: String, _ title: String, key: String, strong: Bool, help: String, _ run: @escaping () -> Void) -> some View {
        let on = hovered == key || strong
        return Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(Theme.font(12, .medium)).monospacedDigit()
            }
            .foregroundStyle(on ? Theme.onIce : Theme.text)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(on ? Color.white.opacity(0.92) : Theme.raised))
            .scaleEffect(hovered == key ? 1.05 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(title)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h ? key : (hovered == key ? nil : hovered) } }
    }

    private func openWeek() {
        withAnimation(IslandModel.spring) {
            model.tab = .home; model.showWeek = true; model.showForecast = false; model.mode = .expanded
        }
    }
}

private final class EventPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class EventHost: NSHostingView<DockEventView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DockEventWindow {
    /// Wo das Widget gerade steht – die Ablage setzt sich links daneben.
    static var current: CGRect?

    private let model: IslandModel
    private let panel: EventPanel
    private var timer: Timer?
    private var bag: [Any] = []
    private var lastState = ""

    init(model: IslandModel) {
        self.model = model
        panel = EventPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = EventHost(rootView: DockEventView(model: model))
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            bag.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.update() }
            })
        }
        bag.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.update() })
        for p in [model.$dockEventOn.map { _ in () }.eraseToAnyPublisher(), model.$dockMusicShown.map { _ in () }.eraseToAnyPublisher(),
                  model.$dockShelfCovers.map { _ in () }.eraseToAnyPublisher(), model.$events.map { _ in () }.eraseToAnyPublisher()] {
            bag.append(p.receive(on: RunLoop.main).sink { [weak self] in DispatchQueue.main.async { self?.update() } })
        }
        update()
    }

    func update() {
        if model.dockEventOn, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        } else if !model.dockEventOn { timer?.invalidate(); timer = nil }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let now = Date()
        let wanted = model.dockEventOn && DockEvent.wanted(DockEvent.pick(model.events, now: now), now: now, musicShown: model.dockMusicShown)
        var spot: CGRect?
        if wanted, DockMusicWindow.dockNormallyBottom {
            let dock = DockReader.frame()
            if let i = DockSpot.pick(dock: dock, screens: screens.map { ($0.frame, $0.visibleFrame) }) {
                spot = DockSpot.left(dock: dock, screen: screens[i].frame, visible: screens[i].visibleFrame, width: DockSpot.width)
            }
        }
        Self.current = spot
        // Steht der Termin unten, gehört er nicht mehr in die Laufschrift – auch wenn die Ablage ihn kurz verdeckt.
        if model.dockEventHint != (spot != nil) { model.dockEventHint = spot != nil }
        let shown = model.dockShelfCovers ? nil : spot
        if let r = shown {
            if panel.frame != r { panel.setFrame(r, display: true) }
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
            }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
        let state = shown != nil ? "sichtbar" : !model.dockEventOn ? "ausgeblendet (abgeschaltet)" : !wanted ? "ausgeblendet (nichts anstehend)"
            : model.dockShelfCovers ? "ausgeblendet (Ablage liegt davor)" : "ausgeblendet (Dock nicht unten oder kein Platz)"
        if state != lastState { lastState = state; log("Termin am Dock: \(state)") }
    }

    deinit {
        timer?.invalidate()
        bag.forEach { if !($0 is AnyCancellable) { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) } }
    }
}
