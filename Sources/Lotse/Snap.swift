import AppKit
import ApplicationServices
import SwiftUI

/// Fenster an den Bildschirmrand ziehen (wie Magnet): Beim Ziehen an Rand oder Ecke zeigt eine Vorschau
/// die Zielfläche, beim Loslassen rastet das Fenster dort ein.
///   links / rechts  → Hälfte          oben → ganzer Bildschirm
///   Ecken           → Viertel         unten → Drittel (links, Mitte, rechts – je nach Stelle)
/// Braucht die Freigabe „Bedienungshilfen", weil Lotse dafür Fenster anderer Apps verschiebt.
final class WindowSnap {
    /// Während ein Fenster gezogen wird, klappt die Insel nicht auf.
    static var dragging = false

    private var monitors: [Any] = []
    private let system = AXUIElementCreateSystemWide()
    private var window: AXUIElement?
    private var startPos = CGPoint.zero
    private var startSize = CGSize.zero
    private var moved = false
    private var lastCheck = Date.distantPast
    private var target: NSRect?
    private lazy var preview = SnapPreview()

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "snapEnabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "snapEnabled")
            if newValue { askPermission() } else { reset() }
        }
    }

    var trusted: Bool { AXIsProcessTrusted() }

    func start() {
        AXUIElementSetMessagingTimeout(system, 0.25)
        monitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in self?.down() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in self?.drag() },
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in self?.up() },
        ].compactMap { $0 }
        // Beim ersten Start einmal um die Freigabe bitten – danach nicht bei jedem Start erneut.
        if enabled, !trusted, OnboardingWindow.done, !UserDefaults.standard.bool(forKey: "snapAsked") {
            UserDefaults.standard.set(true, forKey: "snapAsked")
            askPermission()
        }
        log("Fenster einrasten: \(enabled ? "an" : "aus"), Bedienungshilfen \(trusted ? "freigegeben" : "nicht freigegeben")")
    }

    func askPermission() {
        guard !trusted else { return }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // MARK: Maus

    private func down() {
        reset()
        guard enabled, trusted else { return }
        let p = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(primary.frame.height - p.y), &hit) == .success,
              let hit, let w = Self.window(of: hit) else { return }
        var pid: pid_t = 0
        AXUIElementGetPid(w, &pid)
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }
        AXUIElementSetMessagingTimeout(w, 0.25)
        guard Self.string(w, kAXSubroleAttribute) == (kAXStandardWindowSubrole as String),
              Self.bool(w, "AXFullScreen") != true,
              let pos = Self.point(w), let size = Self.size(w) else { return }
        // Nur Fenster, deren Größe sich ändern lässt.
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(w, kAXSizeAttribute as CFString, &settable)
        guard settable.boolValue else { return }
        window = w; startPos = pos; startSize = size
    }

    private func drag() {
        guard let w = window else { return }
        if !moved {
            // Wird wirklich das Fenster verschoben (und nicht etwa darin markiert oder seine Größe geändert)?
            guard Date().timeIntervalSince(lastCheck) > 0.05 else { return }
            lastCheck = Date()
            guard let pos = Self.point(w), let size = Self.size(w) else { reset(); return }
            if abs(size.width - startSize.width) > 1 || abs(size.height - startSize.height) > 1 { reset(); return }
            guard hypot(pos.x - startPos.x, pos.y - startPos.y) > 3 else { return }
            moved = true
            Self.dragging = true
        }
        let zone = Self.zone(at: NSEvent.mouseLocation)
        if zone != target {
            target = zone
            preview.show(zone)
        }
    }

    private func up() {
        guard moved, let w = window, let rect = target, let primary = NSScreen.screens.first else { reset(); return }
        reset()
        // Einen Wimpernschlag warten, bis die App ihr eigenes Ziehen beendet hat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            var pos = CGPoint(x: rect.minX, y: primary.frame.height - rect.maxY)
            var size = rect.size
            guard let p = AXValueCreate(.cgPoint, &pos), let s = AXValueCreate(.cgSize, &size) else { return }
            // Größe – Position – Größe: So landet das Fenster auch dann richtig, wenn es am alten Platz nicht größer werden durfte.
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
            AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, p)
            AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, s)
            log("Fenster eingerastet: \(Int(rect.width))×\(Int(rect.height)) bei \(Int(rect.minX)),\(Int(rect.minY))")
        }
    }

    private func reset() {
        window = nil; moved = false; target = nil; lastCheck = .distantPast
        Self.dragging = false
        preview.show(nil)
    }

    // MARK: Zonen

    /// Zielfläche für die Zeigerposition (Bildschirmkoordinaten, Ursprung unten links) – oder nil, wenn kein Rand berührt ist.
    static func zone(at p: NSPoint) -> NSRect? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return nil }
        return zone(at: p, frame: screen.frame, visible: screen.visibleFrame)
    }

    static func zone(at p: NSPoint, frame f: NSRect, visible v: NSRect) -> NSRect? {
        let edge: CGFloat = 5, corner: CGFloat = 110
        let left = p.x <= f.minX + edge, right = p.x >= f.maxX - edge - 1
        let top = p.y >= f.maxY - edge - 1, bottom = p.y <= f.minY + edge
        let nearTop = p.y >= f.maxY - corner, nearBottom = p.y <= f.minY + corner
        let nearLeft = p.x <= f.minX + corner, nearRight = p.x >= f.maxX - corner
        let halfW = (v.width / 2).rounded(), halfH = (v.height / 2).rounded()
        func quarter(_ leftSide: Bool, _ upper: Bool) -> NSRect {
            NSRect(x: leftSide ? v.minX : v.minX + halfW, y: upper ? v.minY + halfH : v.minY,
                   width: leftSide ? halfW : v.width - halfW, height: upper ? v.height - halfH : halfH)
        }
        if left || right {
            if nearTop { return quarter(left, true) }
            if nearBottom { return quarter(left, false) }
            return NSRect(x: left ? v.minX : v.minX + halfW, y: v.minY, width: left ? halfW : v.width - halfW, height: v.height)
        }
        if top {
            if nearLeft { return quarter(true, true) }
            if nearRight { return quarter(false, true) }
            return v
        }
        if bottom {
            let third = (v.width / 3).rounded()
            let i = min(2, max(0, Int((p.x - f.minX) / (f.width / 3))))
            return NSRect(x: v.minX + CGFloat(i) * third, y: v.minY, width: i == 2 ? v.width - 2 * third : third, height: v.height)
        }
        return nil
    }

    // MARK: Bedienungshilfen

    private static func window(of element: AXUIElement) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == (kAXWindowRole as String) { return element }
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    private static func string(_ e: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private static func bool(_ e: AXUIElement, _ attr: String) -> Bool? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success else { return nil }
        return v as? Bool
    }

    private static func value(_ e: AXUIElement, _ attr: String) -> AXValue? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, attr as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        return (v as! AXValue)
    }

    private static func point(_ e: AXUIElement) -> CGPoint? {
        guard let v = value(e, kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v, .cgPoint, &p) ? p : nil
    }

    private static func size(_ e: AXUIElement) -> CGSize? {
        guard let v = value(e, kAXSizeAttribute) else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v, .cgSize, &s) ? s : nil
    }

    /// Kleiner Selbsttest der Zonen (`Lotse --selftest`).
    static func selfTest() -> [String] {
        let f = NSRect(x: 0, y: 0, width: 3440, height: 1440), v = NSRect(x: 0, y: 0, width: 3440, height: 1410)
        let cases: [(NSPoint, NSRect?, String)] = [
            (NSPoint(x: 0, y: 700), NSRect(x: 0, y: 0, width: 1720, height: 1410), "links → linke Hälfte"),
            (NSPoint(x: 3439, y: 700), NSRect(x: 1720, y: 0, width: 1720, height: 1410), "rechts → rechte Hälfte"),
            (NSPoint(x: 1700, y: 1439), v, "oben → ganzer Bildschirm"),
            (NSPoint(x: 0, y: 1430), NSRect(x: 0, y: 705, width: 1720, height: 705), "Ecke oben links → Viertel"),
            (NSPoint(x: 3439, y: 3), NSRect(x: 1720, y: 0, width: 1720, height: 705), "Ecke unten rechts → Viertel"),
            (NSPoint(x: 1700, y: 0), NSRect(x: 1147, y: 0, width: 1147, height: 1410), "unten Mitte → mittleres Drittel"),
            (NSPoint(x: 3000, y: 0), NSRect(x: 2294, y: 0, width: 1146, height: 1410), "unten rechts → rechtes Drittel"),
            (NSPoint(x: 1700, y: 700), nil, "Mitte → nichts"),
        ]
        return cases.compactMap { p, want, name in
            let got = zone(at: p, frame: f, visible: v)
            return got == want ? nil : "ZONE FALSCH (\(name)): \(String(describing: got))"
        }
    }
}

/// Die Vorschau der Zielfläche: ein halbdurchsichtiges, abgerundetes Feld in Lotses Eisblau.
final class SnapPreview {
    private var panel: NSPanel?

    func show(_ rect: NSRect?) {
        guard let rect else {
            guard let panel, panel.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; panel.animator().alphaValue = 0 },
                                                 completionHandler: { [weak panel] in if panel?.alphaValue == 0 { panel?.orderOut(nil) } })
            return
        }
        let frame = rect.insetBy(dx: 6, dy: 6)
        let p = panel ?? make()
        tint(p.contentView)
        if !p.isVisible || p.alphaValue == 0 {
            // Aus der Mitte der Zielfläche heraus aufgehen.
            p.setFrame(frame.insetBy(dx: frame.width * 0.06, dy: frame.height * 0.06), display: true)
            p.alphaValue = 0
            p.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup {
            $0.duration = 0.16
            $0.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().setFrame(frame, display: true)
            p.animator().alphaValue = 1
        }
    }

    /// Die Vorschau trägt die Akzentfarbe des gewählten Farbschemas.
    private func tint(_ view: NSView?) {
        let accent = NSColor(Theme.accent)
        view?.layer?.backgroundColor = accent.withAlphaComponent(0.20).cgColor
        view?.layer?.borderColor = accent.withAlphaComponent(0.70).cgColor
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.cornerCurve = .continuous
        tint(view)
        view.layer?.borderWidth = 1.5
        p.contentView = view
        panel = p
        return p
    }
}
