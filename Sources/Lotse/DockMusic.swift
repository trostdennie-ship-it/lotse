import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Musik neben dem Dock

/// Wo das Musik-Widget hinkommt: rechts neben dem Dock, gleich hoch. Reine Rechnung, damit sie sich prüfen lässt.
struct DockSpot {
    static let gap: CGFloat = 8
    static let width: CGFloat = 260

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
              CGRect(x: 1108, y: 0, width: 260, height: 70))
        check("Ersatz-Ecke", frame(dock: nil, screen: screen, visible: visible), CGRect(x: 1512 - 260 - 8, y: 0, width: 260, height: 70))
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
