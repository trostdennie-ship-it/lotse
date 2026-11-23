import AppKit
import ApplicationServices
import SwiftUI

/// Chat und Cowork der Claude-App hinterlassen nichts auf der Platte und kennen keine Hooks.
/// Solange Claude dort arbeitet, zeigt das Fenster aber einen „Stopp“-Knopf – den liest Lotse über
/// die Bedienungshilfen (dieselbe Freigabe wie fürs Einrasten). Grenze: nur die Unterhaltung, die
/// gerade im Fenster zu sehen ist. Der Reiter „Code“ bleibt außen vor, den melden die Hooks.
final class ClaudeAppWatch {
    static let sessionID = "claude-fenster"

    private let model: IslandModel
    private let queue = DispatchQueue(label: "lotse.claude-fenster", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var preparedPID: pid_t = 0
    /// Laufende Unterhaltungen: Kennung → (Beginn, Runden ohne Sichtung).
    private var active: [String: (since: Date, misses: Int)] = [:]

    init(model: IslandModel) { self.model = model }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3, repeating: 2.0, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    private struct Found { var busy = false; var path = ""; var title = ""; var running: [String] = []; var cowork = 0 }

    private func poll() {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: Apps.claude).first
        else { settle([:], drop: true); return }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        if preparedPID != app.processIdentifier {
            // Electron baut seinen Bedienungshilfen-Baum erst auf, wenn ein Hilfsprogramm danach fragt.
            AXUIElementSetMessagingTimeout(el, 0.5)
            AXUIElementSetAttributeValue(el, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            preparedPID = app.processIdentifier
            return
        }
        AXUIElementSetMessagingTimeout(el, 0.5)
        var found = Found(), budget = 5000
        for w in (Self.value(el, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { walk(w, 0, &found, &budget) }

        // Im Reiter „Code“ ist von Chat und Cowork nichts zu sehen – dort melden die Hooks.
        if found.path.isEmpty || found.path.hasPrefix("/epitaxy") { settle([:], drop: true); return }
        let kind = found.cowork >= 2 ? "Cowork" : "Chat"
        var now: [String: (kind: String, title: String)] = [:]
        // Die Seitenleiste markiert jede laufende Unterhaltung mit „… Läuft“, auch wenn sie nicht offen ist.
        for t in found.running { now[Self.sessionID + ":" + t] = (kind, t) }
        if found.busy, now.isEmpty {
            let t = found.title.isEmpty || found.title == "Claude" ? "Claude antwortet" : found.title
            now[Self.sessionID] = (kind, t)
        }
        settle(now, drop: false)
    }

    /// Gleicht den Stand mit der Insel ab. `drop`: nicht mehr beobachtbar – Zeilen ohne „fertig“ entfernen.
    private func settle(_ now: [String: (kind: String, title: String)], drop: Bool) {
        for (id, v) in now {
            let first = active[id] == nil
            let since = active[id]?.since ?? Date()
            active[id] = (since, 0)
            if first { log("Claude-Fenster arbeitet: \(v.kind)") }
            DispatchQueue.main.async { self.show(id: id, kind: v.kind, title: v.title, started: since) }
        }
        for (id, a) in active where now[id] == nil {
            // Zwischen zwei Schritten fehlt die Markierung manchmal kurz – erst nach zwei Runden gilt es als fertig.
            if !drop, a.misses < 1 { active[id] = (a.since, a.misses + 1); continue }
            active[id] = nil
            let took = Int(Date().timeIntervalSince(a.since))
            log(drop ? "Claude-Fenster nicht mehr sichtbar" : "Claude-Fenster fertig nach \(took) s")
            DispatchQueue.main.async { self.finish(id: id, took: took, silent: drop) }
        }
    }

    private func walk(_ e: AXUIElement, _ depth: Int, _ found: inout Found, _ budget: inout Int) {
        budget -= 1
        guard budget > 0, depth < 70 else { return }
        let role = Self.value(e, kAXRoleAttribute) as? String ?? ""
        if role == "AXWebArea", let url = Self.value(e, "AXURL") as? URL, url.scheme?.hasPrefix("http") == true {
            found.path = url.path
            found.title = Self.value(e, kAXTitleAttribute) as? String ?? ""
        } else if role == "AXButton" {
            var labels = Set<String>()
            for a in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let s = Self.value(e, a) as? String, !s.isEmpty { labels.insert(s) }
            }
            for s in labels {
                if Self.isStop(s) { found.busy = true }
                if let t = Self.runningTitle(s), !found.running.contains(t) { found.running.append(t) }
                if ["Fortschritt", "Ausgaben", "Progress", "Outputs"].contains(s) { found.cowork += 1 }
            }
        }
        for k in (Self.value(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { walk(k, depth + 1, &found, &budget) }
    }

    /// „Titel Läuft“ → „Titel“.
    static func runningTitle(_ label: String) -> String? {
        for suffix in [" Läuft", " Running"] where label.hasSuffix(suffix) && label.count < 140 {
            let t = String(label.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
        return nil
    }

    static func isStop(_ label: String) -> Bool {
        let s = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s.range(of: "^(stopp?|stoppen|antwort (stoppen|anhalten)|stop (response|generating|claude))$",
                       options: .regularExpression) != nil
    }

    private static func value(_ e: AXUIElement, _ attribute: String) -> Any? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, attribute as CFString, &v) == .success ? v : nil
    }

    private func show(id: String, kind: String, title: String, started: Date) {
        if let i = model.sessions.firstIndex(where: { $0.id == id }) {
            var s = model.sessions[i]
            guard s.status != .working || s.project != kind || s.detail != title else { return }
            s.project = kind; s.detail = title; s.status = .working; s.updated = Date()
            s.startedAt = started; s.doneAt = nil; s.tookSeconds = nil; s.summary = ""
            withAnimation(IslandModel.spring) { model.sessions[i] = s }
        } else {
            var s = ClaudeSession(id: id, project: kind, status: .working, message: "", updated: Date())
            s.detail = title; s.startedAt = started; s.bundle = Apps.claude; s.titled = true
            withAnimation(IslandModel.spring) { model.sessions.insert(s, at: 0) }
        }
    }

    /// Kurz „fertig“ zeigen, dann die Zeile wieder entfernen.
    private func finish(id: String, took: Int, silent: Bool) {
        guard let i = model.sessions.firstIndex(where: { $0.id == id }) else { return }
        if silent { withAnimation(IslandModel.spring) { model.sessions.removeAll { $0.id == id } }; return }
        var s = model.sessions[i]
        let stamp = Date()
        s.status = .done; s.summary = s.detail; s.detail = ""; s.startedAt = nil
        s.doneAt = stamp; s.tookSeconds = took; s.updated = stamp
        withAnimation(IslandModel.spring) { model.sessions[i] = s }
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
            withAnimation(IslandModel.spring) {
                self.model.sessions.removeAll { $0.id == id && $0.status == .done && $0.doneAt == stamp }
            }
        }
    }
}
