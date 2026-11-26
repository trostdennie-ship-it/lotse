import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Musik neben dem Dock

/// Wo das Musik-Widget hinkommt: rechts neben dem Dock, gleich hoch. Reine Rechnung, damit sie sich prüfen lässt.
struct DockSpot {
    static let gap: CGFloat = 8
    static let width: CGFloat = 300

    /// `dock`: Rahmen der Dock-Leiste (Cocoa-Koordinaten) oder nil, wenn er sich nicht lesen lässt – dann die Ecke unten rechts.
    /// nil, wenn das Dock nicht dauerhaft unten steht (seitlich, automatisch ausgeblendet, Vollbild) oder kein Platz ist.
    static func frame(dock: CGRect?, screen: CGRect, visible: CGRect) -> CGRect? {
        guard visible.minX <= screen.minX, visible.maxX >= screen.maxX else { return nil }   // Dock links oder rechts
        let strip = visible.minY - screen.minY
        guard strip > 0 else { return nil }                                                   // Dock unten nicht da
        guard let d = dock else {
            return CGRect(x: screen.maxX - width - gap, y: screen.minY, width: width, height: strip)
        }
        let r = CGRect(x: d.maxX + gap, y: d.minY, width: width, height: d.height)
        return r.maxX <= screen.maxX ? r : nil
    }

    static func selfTest() -> [String] {
        var out: [String] = []
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 882)
        func check(_ name: String, _ got: CGRect?, _ want: CGRect?) {
            if got != want { out.append("Dock-Musik \(name): erwartet \(want.map { "\($0)" } ?? "nil"), bekommen \(got.map { "\($0)" } ?? "nil")") }
        }
        check("neben dem Dock", frame(dock: CGRect(x: 400, y: 0, width: 700, height: 70), screen: screen, visible: visible),
              CGRect(x: 1108, y: 0, width: 300, height: 70))
        check("Ersatz-Ecke", frame(dock: nil, screen: screen, visible: visible), CGRect(x: 1512 - 300 - 8, y: 0, width: 300, height: 70))
        check("Dock versteckt", frame(dock: nil, screen: screen, visible: screen), nil)
        check("zu breit", frame(dock: CGRect(x: 400, y: 0, width: 1000, height: 70), screen: screen, visible: visible), nil)
        return out
    }
}

/// Liest den Rahmen der Dock-Leiste über die Bedienungshilfen. Nur lesend, am Dock ändert sich nichts.
enum DockReader {
    static func frame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &kids) == .success,
              let list = (kids as? [AXUIElement])?.first(where: { role($0) == kAXListRole as String }) else { return nil }
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

    var body: some View {
        if let t = model.track {
            HStack(spacing: 10) {
                Cover(image: t.artwork, size: 46, radius: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.discreet ? (t.isPlaying ? "Musik läuft" : "Pausiert") : t.title)
                        .font(Theme.font(13, .medium)).foregroundStyle(Theme.text)
                    if !model.discreet {
                        Text(t.artist).font(Theme.font(11)).foregroundStyle(Theme.muted)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
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

    private func key(_ symbol: String, _ label: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size, weight: .semibold)).foregroundStyle(Theme.text)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// Ein randloses Fenster, das nie aktiv wird: Klicks auf die Knöpfe nehmen der vorderen App nicht den Fokus.
private final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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
        panel.contentView = NSHostingView(rootView: DockMusicView(model: model))
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

        guard let screen = NSScreen.screens.first else { return }
        let dock = model.dockMusicOn ? DockReader.frame() : nil
        let bottom = screen.visibleFrame.minY > screen.frame.minY
            && screen.visibleFrame.minX <= screen.frame.minX && screen.visibleFrame.maxX >= screen.frame.maxX
        let spot = active ? DockSpot.frame(dock: dock, screen: screen.frame, visible: screen.visibleFrame) : nil
        // Im Vollbild ist das Dock weg, die Pille soll aber trotzdem nur das Cover zeigen: Hinweis bleibt, solange das Dock sonst unten steht.
        let fullscreen = !bottom && Self.dockNormallyBottom
        let hint = model.dockMusicOn && (spot != nil || fullscreen)
        if model.dockMusicHint != hint { model.dockMusicHint = hint }

        let reason = !model.dockMusicOn ? "abgeschaltet" : model.track == nil ? "keine Musik"
            : fullscreen ? "Vollbild" : spot == nil ? "Dock nicht unten oder kein Platz" : ""
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
        let state = spot != nil ? "sichtbar" + (dock == nil ? " (Ecke, ohne Dock-Rahmen)" : "") : "ausgeblendet (\(reason))"
        if state != lastReason {
            lastReason = state
            log("Dock-Musik: \(state)")
        }
        if model.dockMusicShown != (spot != nil) { model.dockMusicShown = spot != nil }
    }

    /// Steht das Dock laut Einstellung unten und wird nicht automatisch ausgeblendet?
    static var dockNormallyBottom: Bool {
        let d = UserDefaults(suiteName: "com.apple.dock")
        return (d?.string(forKey: "orientation") ?? "bottom") == "bottom" && !(d?.bool(forKey: "autohide") ?? false)
    }
}
