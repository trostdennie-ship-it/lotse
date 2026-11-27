import AppKit
import ApplicationServices
import SwiftUI
import Combine

// MARK: - Musik neben dem Dock

/// Wo das Musik-Widget hinkommt: rechts neben dem Dock, gleich hoch. Reine Rechnung, damit sie sich prüfen lässt.
struct DockSpot {
    static let gap: CGFloat = 8
    static let width: CGFloat = 300

    /// `dock`: Rahmen der Dock-Leiste (Cocoa-Koordinaten) oder nil, wenn er sich nicht lesen lässt – dann die Ecke unten rechts.
    /// nil, wenn das Dock nicht dauerhaft unten steht (seitlich, automatisch ausgeblendet, Vollbild) oder kein Platz ist.
    static func frame(dock: CGRect?, screen: CGRect, visible: CGRect) -> CGRect? {
        place(dock: dock, screen: screen, visible: visible, width: width, leftSide: false)
    }

    /// Dasselbe links vom Dock (Ablage), mit eigener Breite.
    static func left(dock: CGRect?, screen: CGRect, visible: CGRect, width: CGFloat) -> CGRect? {
        place(dock: dock, screen: screen, visible: visible, width: width, leftSide: true)
    }

    private static func place(dock: CGRect?, screen: CGRect, visible: CGRect, width w: CGFloat, leftSide: Bool) -> CGRect? {
        guard visible.minX <= screen.minX, visible.maxX >= screen.maxX else { return nil }   // Dock links oder rechts
        let strip = visible.minY - screen.minY
        guard strip >= minStrip else { return nil }                                           // Dock unten nicht da oder ausgeblendet
        guard let d = dock else {
            return CGRect(x: leftSide ? screen.minX + gap : screen.maxX - w - gap, y: screen.minY, width: w, height: strip)
        }
        // Ein Rahmen außerhalb des Bildschirms gehört zu einem weggeschobenen Dock.
        guard d.minY >= screen.minY - 1, d.maxY <= visible.minY + 8, d.minX >= screen.minX, d.maxX <= screen.maxX else { return nil }
        // Die Glasfläche des Docks endet oben genau am freigehaltenen Streifen und ist etwas höher als die Symbolliste.
        let h = d.height + 2
        let r = CGRect(x: leftSide ? d.minX - gap - w : d.maxX + gap, y: visible.minY - h, width: w, height: h)
        return r.minX >= screen.minX && r.maxX <= screen.maxX ? r : nil
    }

    /// Mindesthöhe des Dock-Streifens: Ein automatisch ausgeblendetes Dock lässt nur ein paar Punkte frei.
    static let minStrip: CGFloat = 20

    /// Auf welchem Bildschirm steht das Dock? Erst nach dem gelesenen Rahmen, sonst nach dem freigehaltenen Streifen unten.
    /// nil: kein Bildschirm hat das Dock unten (Vollbild, seitlich oder ausgeblendet).
    static func pick(dock: CGRect?, screens: [(frame: CGRect, visible: CGRect)]) -> Int? {
        if let d = dock, let i = screens.firstIndex(where: { $0.frame.contains(CGPoint(x: d.midX, y: d.midY)) }) { return i }
        return screens.firstIndex { $0.visible.minY - $0.frame.minY >= minStrip
            && $0.visible.minX <= $0.frame.minX && $0.visible.maxX >= $0.frame.maxX }
    }

    static func selfTest() -> [String] {
        var out: [String] = []
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 76, width: 1512, height: 876)
        func check(_ name: String, _ got: CGRect?, _ want: CGRect?) {
            if got != want { out.append("Dock-Musik \(name): erwartet \(want.map { "\($0)" } ?? "nil"), bekommen \(got.map { "\($0)" } ?? "nil")") }
        }
        // Werte vom MacBook: Symbolliste 10…80, Glas und Streifen enden bei 76.
        check("neben dem Dock", frame(dock: CGRect(x: 400, y: 10, width: 700, height: 70), screen: screen, visible: visible),
              CGRect(x: 1108, y: 4, width: 300, height: 72))
        check("Ersatz-Ecke", frame(dock: nil, screen: screen, visible: visible), CGRect(x: 1512 - 300 - 8, y: 0, width: 300, height: 76))
        check("Dock versteckt", frame(dock: nil, screen: screen, visible: screen), nil)
        check("zu breit", frame(dock: CGRect(x: 400, y: 10, width: 1000, height: 70), screen: screen, visible: visible), nil)
        check("Ausblenden-Streifen", frame(dock: nil, screen: screen, visible: CGRect(x: 0, y: 4, width: 1512, height: 948)), nil)
        check("Dock unter dem Rand", frame(dock: CGRect(x: 400, y: -66, width: 700, height: 70), screen: screen, visible: visible), nil)
        // Zweiter Bildschirm rechts daneben, das Dock steht dort.
        let second = (frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), visible: CGRect(x: 1512, y: 70, width: 1920, height: 980))
        let first = (frame: screen, visible: CGRect(x: 0, y: 0, width: 1512, height: 952))
        if pick(dock: CGRect(x: 2000, y: 0, width: 600, height: 70), screens: [first, second]) != 1 { out.append("Dock-Musik: Dock auf dem zweiten Bildschirm nicht gefunden") }
        if pick(dock: nil, screens: [first, second]) != 1 { out.append("Dock-Musik: Bildschirm mit Dock-Streifen nicht gefunden") }
        check("links neben dem Dock", left(dock: CGRect(x: 400, y: 10, width: 700, height: 70), screen: screen, visible: visible, width: 200),
              CGRect(x: 192, y: 4, width: 200, height: 72))
        check("links Ersatz-Ecke", left(dock: nil, screen: screen, visible: visible, width: 200), CGRect(x: 8, y: 0, width: 200, height: 76))
        check("links kein Platz", left(dock: CGRect(x: 100, y: 10, width: 1300, height: 70), screen: screen, visible: visible, width: 200), nil)
        if pick(dock: nil, screens: [first]) != nil { out.append("Dock-Musik: Vollbild sollte keinen Bildschirm liefern") }
        return out
    }
}

/// Liest den Rahmen der Dock-Leiste über die Bedienungshilfen. Nur lesend, am Dock ändert sich nichts.
enum DockReader {
    /// Beide Widgets fragen jede Sekunde; die Bedienungshilfen werden trotzdem höchstens einmal je Sekunde gefragt.
    private static var cached: (at: Date, frame: CGRect?)?

    static func frame() -> CGRect? {
        if let c = cached, Date().timeIntervalSince(c.at) < 0.9 { return c.frame }
        let f = read()
        cached = (Date(), f)
        return f
    }

    private static func read() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &kids) == .success,
              let children = kids as? [AXUIElement] else { return nil }
        // Die Zeitgrenze gilt je Element: Ein hängendes Dock darf die Insel nicht für Sekunden einfrieren.
        children.forEach { AXUIElementSetMessagingTimeout($0, 0.25) }
        guard let list = children.first(where: { role($0) == kAXListRole as String }) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        var pv: CFTypeRef?, sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sv) == .success,
              let p = pv, let z = sv else { return nil }
        AXValueGetValue(p as! AXValue, .cgPoint, &pos)
        AXValueGetValue(z as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0, let primary = NSScreen.screens.first else { return nil }
        // Bedienungshilfen zählen von oben links, Cocoa von unten links.
        return CGRect(x: pos.x, y: primary.frame.height - pos.y - size.height, width: size.width, height: size.height)
    }

    private static func role(_ e: AXUIElement) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v) == .success ? v as? String : nil
    }
}

// MARK: - Das Widget

struct DockMusicView: View {
    @ObservedObject var model: IslandModel
    @State private var hovered: String?

    var body: some View {
        if let t = model.track {
            HStack(spacing: 10) {
                Button { Apps.activate("com.spotify.client") } label: {
                    HStack(spacing: 10) {
                        Cover(image: t.artwork, size: 46, radius: 9)
                            .scaleEffect(hovered == "cover" ? 1.04 : 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.discreet ? (t.isPlaying ? "Musik läuft" : "Pausiert") : t.title)
                                .font(Theme.font(13, .medium)).foregroundStyle(Theme.text)
                            if !model.discreet {
                                Text(t.artist).font(Theme.font(11)).foregroundStyle(Theme.muted)
                            }
                        }
                        .lineLimit(1)
                    }
                    .opacity(hovered == "cover" ? 1 : 0.92)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Spotify öffnen")
                .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h ? "cover" : (hovered == "cover" ? nil : hovered) } }
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    rooms
                    key("backward.fill", "Zurück", 11) { model.musicAction?("previous track") }
                    key(t.isPlaying ? "pause.fill" : "play.fill", t.isPlaying ? "Pause" : "Abspielen", 15) { model.musicAction?("playpause") }
                    key("forward.fill", "Weiter", 11) { model.musicAction?("next track") }
                }
            }
            .padding(.leading, 12).padding(.trailing, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
        }
    }

    /// Raumwahl über Spotify Connect: Ein Klick zeigt die Geräte (Sonos-Räume, dieser Mac …) und schickt die Musik dorthin.
    private var rooms: some View {
        let on = hovered == "rooms"
        let elsewhere = model.sonosActive != nil || model.spotifyDevices.contains { $0.active && $0.type.lowercased() != "computer" }
        let speakers = Set(model.sonosRooms.flatMap { $0.name.components(separatedBy: " + ") })
        let others = model.spotifyDevices.filter { !speakers.contains($0.name) }
        return Menu {
            if !model.spotifyConnected {
                Button("Mit Spotify verbinden …") { model.openSettings?() }
            } else {
                if !model.sonosRooms.isEmpty {
                    Section("Sonos") {
                        ForEach(model.sonosRooms) { r in
                            Button { Task { await SpotifyConnect.shared.play(on: r) } } label: {
                                Label(r.name, systemImage: model.sonosActive == r.id ? "checkmark" : "hifispeaker.fill")
                            }
                        }
                    }
                }
                if !others.isEmpty {
                    Section("Spotify Connect") {
                        ForEach(others) { d in
                            Button { Task { await SpotifyConnect.shared.play(on: d) } } label: {
                                Label(d.name, systemImage: d.active ? "checkmark" : d.symbol)
                            }
                        }
                    }
                }
                if model.sonosRooms.isEmpty && others.isEmpty {
                    Text("Keine Räume gefunden")
                }
            }
        } label: {
            Image(systemName: elsewhere ? "hifispeaker.2.fill" : "hifispeaker.fill").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? Theme.onIce : elsewhere ? Theme.accent : Theme.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(on ? Color.white.opacity(0.92) : .clear))
                .scaleEffect(on ? 1.08 : 1)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Raum wählen").accessibilityLabel("Raum wählen")
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { hovered = h ? "rooms" : (hovered == "rooms" ? nil : hovered) }
            // Beim Darüberfahren die Geräteliste auffrischen, damit sie beim Klick stimmt.
            if h, model.spotifyConnected {
                Task { await SpotifyConnect.shared.refreshDevices() }
                Task { await SpotifyConnect.shared.refreshRooms() }
            }
        }
    }

    private func key(_ symbol: String, _ label: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        let on = hovered == symbol
        return Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? Theme.onIce : Theme.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(on ? Color.white.opacity(0.92) : .clear))
                .scaleEffect(on ? 1.08 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h ? symbol : (hovered == symbol ? nil : hovered) } }
    }
}

/// Ein randloses Fenster, das nie aktiv wird: Klicks auf die Knöpfe nehmen der vorderen App nicht den Fokus.
private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Der erste Klick zählt sofort, auch wenn Lotse nicht vorne ist.
private final class DockHost: NSHostingView<DockMusicView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DockMusicWindow {
    private let model: IslandModel
    private let panel: DockPanel
    private var timer: Timer?
    private var bag: [Any] = []
    private var lastReason = ""

    init(model: IslandModel) {
        self.model = model
        panel = DockPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = DockHost(rootView: DockMusicView(model: model))
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            bag.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.update() }   // das Dock rückt animiert nach
            })
        }
        bag.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.update() })
        bag.append(model.$track.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.update() } })
        bag.append(model.$dockMusicOn.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.update() } })
        update()
    }

    /// Rechnet die Lage neu und blendet ein oder aus. Der Takt läuft nur, solange es etwas zu zeigen gibt.
    func update() {
        let active = model.dockMusicOn && model.track != nil
        if active, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        } else if !active { timer?.invalidate(); timer = nil }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        let normal = Self.dockNormallyBottom
        let dock = model.dockMusicOn && normal && active ? DockReader.frame() : nil
        let index = normal ? DockSpot.pick(dock: dock, screens: screens.map { ($0.frame, $0.visibleFrame) }) : nil
        let spot = active ? index.flatMap { DockSpot.frame(dock: dock, screen: screens[$0].frame, visible: screens[$0].visibleFrame) } : nil
        // Im Vollbild ist das Dock weg, die Pille soll aber trotzdem nur das Cover zeigen: Kein Bildschirm hat gerade
        // einen Dock-Streifen, obwohl das Dock laut Einstellung unten steht.
        let fullscreen = normal && index == nil
        let hint = model.dockMusicOn && (spot != nil || fullscreen)
        if model.dockMusicHint != hint { model.dockMusicHint = hint }

        let reason = !model.dockMusicOn ? "abgeschaltet" : model.track == nil ? "keine Musik"
            : fullscreen ? "Vollbild" : !normal ? "Dock seitlich oder ausgeblendet" : spot == nil ? "kein Platz neben dem Dock" : ""
        if let r = spot {
            if panel.frame != r { panel.setFrame(r, display: true) }
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
            }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
        let state = spot != nil ? "sichtbar" + (dock.map { " Dock \(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))×\(Int($0.height)), Streifen \(Int(screens[index ?? 0].visibleFrame.minY))" } ?? " (Ecke, ohne Dock-Rahmen)") : "ausgeblendet (\(reason))"
        if state != lastReason {
            lastReason = state
            log("Dock-Musik: \(state)")
        }
        if model.dockMusicShown != (spot != nil) { model.dockMusicShown = spot != nil }
    }

    deinit {
        timer?.invalidate()
        bag.forEach { if !($0 is AnyCancellable) { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) } }
    }

    /// Steht das Dock laut Einstellung unten und wird nicht automatisch ausgeblendet?
    static var dockNormallyBottom: Bool {
        let d = UserDefaults(suiteName: "com.apple.dock")
        return (d?.string(forKey: "orientation") ?? "bottom") == "bottom" && !(d?.bool(forKey: "autohide") ?? false)
    }
}
