import SwiftUI

/// Vorführung aller Zustände des Boots mit einer Probe-Session (Menü „Boot-Zustände vorführen").
/// Die echten Sessions und Nutzungsstände bleiben unberührt und stehen danach wieder da.
extension IslandModel {
    func runTour() {
        guard !sessions.contains(where: { $0.id == "tour" }) else { return }
        let realLimits = limits
        let wasPinned = pinnedOpen
        var demo = ClaudeSession(id: "tour", project: "Vorführung", status: .working, message: "", updated: Date())
        demo.model = "Probe"
        demo.startedAt = Date()
        withAnimation(Self.spring) { sessions.insert(demo, at: 0) }
        if !pinnedOpen { togglePinned() }
        tab = .home

        func change(_ edit: (inout ClaudeSession) -> Void) {
            guard let i = sessions.firstIndex(where: { $0.id == "tour" }) else { return }
            var s = sessions.remove(at: i)
            edit(&s); s.updated = Date()
            withAnimation(Self.spring) { sessions.insert(s, at: 0) }
        }
        func limit(_ percent: Double) {
            limits = [UsageLimit(label: "5 Stunden", percent: percent, resets: Date().addingTimeInterval(3600))]
                + realLimits.filter { $0.label != "5 Stunden" }
        }
        var at = 0.0
        func step(_ pause: Double, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { action() }
            at += pause
        }

        // 1 · Arbeiten ohne Plan: das Boot segelt auf der Stelle
        step(4) { limit(12); change { $0.detail = "1 von 6 · Claude arbeitet – das Boot segelt" } }
        // 2 · Strecke: fünf Schritte bis zum Hafen
        for done in 0...5 {
            step(done == 5 ? 3 : 1.8) {
                change {
                    $0.planTotal = 5; $0.planDone = done
                    $0.planStep = done < 5 ? "Schritt \(done + 1) von 5" : "im Hafen"
                    $0.detail = "2 von 6 · Mit Plan fährt das Boot die Strecke ab"
                }
            }
        }
        // 3 · Warten: Leuchtturm
        step(5) { change { $0.planTotal = 0; $0.planDone = 0; $0.planStep = ""; $0.status = .waiting
                           $0.message = "3 von 6 · Claude braucht dich – der Leuchtturm blinkt" } }
        // 4 · Limit ab 70 %: höhere Wellen
        step(5) { limit(76); change { $0.status = .working; $0.message = ""; $0.detail = "4 von 6 · Limit bei 76 % – höherer Seegang" } }
        // 5 · Limit ab 90 %: Gewitter
        step(6) { limit(94); change { $0.detail = "5 von 6 · Limit bei 94 % – Gewitter zieht auf" } }
        // 6 · Fertig: das Boot fährt hinaus und legt wieder an
        step(5) {
            self.limits = realLimits
            change { $0.status = .done; $0.detail = ""; $0.summary = "6 von 6 · Claude ist fertig – das Boot legt an."
                     $0.tookSeconds = 42; $0.doneAt = Date(); $0.startedAt = nil }
        }
        step(0) {
            withAnimation(Self.spring) { self.sessions.removeAll { $0.id == "tour" } }
            self.limits = realLimits
            if !wasPinned, self.pinnedOpen { self.togglePinned() }
        }
    }
}

/// Probedurchlauf „mehrere Sessions zugleich": drei Probe-Sessions arbeiten nebeneinander, eine braucht
/// dich zwischendurch, nacheinander werden sie fertig. Erst zugeklappt (die Pille), dann aufgeklappt.
/// Auslöser: Ereignis `LotseFleet`. Echte Sessions bleiben unberührt.
extension IslandModel {
    func runFleet() {
        guard !sessions.contains(where: { $0.id.hasPrefix("fleet-") }) else { return }
        let wasPinned = pinnedOpen
        if pinnedOpen { togglePinned() }
        mode = .compact
        tab = .home
        let start = Date()
        func make(_ n: Int, _ project: String, _ detail: String, _ model: String, _ total: Int, ago: Double) -> ClaudeSession {
            var s = ClaudeSession(id: "fleet-\(n)", project: project, status: .working, message: "", updated: start)
            s.detail = detail; s.model = model; s.planTotal = total; s.startedAt = start.addingTimeInterval(-ago)
            if total > 0 { s.planStep = "Schritt 1 von \(total)" }
            return s
        }
        func change(_ n: Int, _ edit: (inout ClaudeSession) -> Void) {
            guard let i = sessions.firstIndex(where: { $0.id == "fleet-\(n)" }) else { return }
            var s = sessions[i]
            edit(&s); s.updated = Date()
            withAnimation(Self.spring) { sessions[i] = s }
        }
        var at = 0.0
        func step(_ pause: Double, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { action() }
            at += pause
        }

        // Zugeklappt: erst eine, dann zwei, dann drei Sessions – die Pille zählt mit.
        step(3) { withAnimation(Self.spring) { self.sessions.insert(make(1, "Probe · Website", "Baut die Startseite um", "Fable 5.2", 5, ago: 190), at: 0) } }
        step(3) { withAnimation(Self.spring) { self.sessions.insert(make(2, "Probe · Video", "Rendert die Untertitel neu", "Opus 5.5", 4, ago: 75), at: 1) } }
        step(4) { withAnimation(Self.spring) { self.sessions.insert(make(3, "Probe · Auswertung", "Liest die Zahlen der Woche ein", "Sonnet 5.5", 0, ago: 5), at: 2) } }
        // Aufklappen: jede Session hat ihre Zeile, die Schritte laufen weiter.
        step(2.5) { if !self.pinnedOpen { self.togglePinned() } }
        step(2) { change(1) { $0.planDone = 1; $0.planStep = "Schritt 2 von 5" }; change(2) { $0.planDone = 1; $0.planStep = "Schritt 2 von 4" } }
        step(2) { change(1) { $0.planDone = 2; $0.planStep = "Schritt 3 von 5" }; change(3) { $0.detail = "Vergleicht mit der Vorwoche" } }
        // Eine braucht dich: sie rückt nach oben, der Leuchtturm blinkt.
        step(5) { change(2) { $0.status = .waiting; $0.message = "Braucht dich – die anderen arbeiten weiter" } }
        step(2.5) { change(2) { $0.status = .working; $0.message = ""; $0.planDone = 2; $0.planStep = "Schritt 3 von 4" }
                    change(1) { $0.planDone = 3; $0.planStep = "Schritt 4 von 5" } }
        // Nacheinander fertig.
        step(3) { change(3) { $0.status = .done; $0.detail = ""; $0.startedAt = nil; $0.doneAt = Date(); $0.tookSeconds = 31 } }
        step(3) { change(2) { $0.status = .done; $0.detail = ""; $0.planStep = ""; $0.startedAt = nil; $0.doneAt = Date(); $0.tookSeconds = 96 }
                  change(1) { $0.planDone = 4; $0.planStep = "Schritt 5 von 5" } }
        step(3.5) { change(1) { $0.status = .done; $0.detail = ""; $0.planStep = ""; $0.startedAt = nil; $0.doneAt = Date(); $0.tookSeconds = 214 } }
        step(0) {
            withAnimation(Self.spring) { self.sessions.removeAll { $0.id.hasPrefix("fleet-") } }
            if self.pinnedOpen != wasPinned { self.togglePinned() }
        }
    }
}
