import AppKit
import Carbon.HIToolbox
import Combine

/// Tastenkürzel, die aus jeder App funktionieren (ohne Sonderfreigabe):
///   ⌃⌥Y  Claude-Freigabe erlauben      – nur aktiv, solange eine Freigabe wartet
///   ⌃⌥N  Claude-Freigabe ablehnen      – nur aktiv, solange eine Freigabe wartet
///   ⌃⌥J  zur Claude-Session springen, die dich braucht (sonst zur zuletzt aktiven)
///   ⌃⌥I  Insel öffnen und offen halten / wieder schließen;  Esc schließt sie, solange sie so geöffnet ist
/// Bei riskanten Befehlen bleibt ⌃⌥Y gesperrt – die muss man in der Insel ansehen und dort bestätigen.
final class Hotkeys {
    private let model: IslandModel
    private var handler: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var watch: AnyCancellable?
    private var watchPinned: AnyCancellable?
    /// Welche Freigabe seit wann wirklich zu sehen ist – nur die darf per Kürzel beantwortet werden.
    private var seen: (id: String, since: Date)?
    private var seenTimer: Timer?
    private static var actions: [UInt32: () -> Void] = [:]
    private static let signature: OSType = 0x4C4F5453   // "LOTS"

    init(model: IslandModel) { self.model = model }

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let n = id.id
            DispatchQueue.main.async { Hotkeys.actions[n]?() }
            return noErr
        }, 1, &spec, nil, &handler)

        Self.actions[1] = { [weak self] in self?.answer("allow") }
        Self.actions[2] = { [weak self] in self?.answer("deny") }
        Self.actions[3] = { [weak self] in self?.jump() }
        Self.actions[4] = { [weak self] in self?.model.togglePinned() }
        Self.actions[5] = { [weak self] in if self?.model.pinnedOpen == true { self?.model.togglePinned() } }
        register(3, kVK_ANSI_J)
        register(4, kVK_ANSI_I)

        // Y/N nur belegen, solange wirklich eine Freigabe wartet – sonst bleiben die Tasten frei für andere Apps.
        // 0 = nichts wartet, 1 = unauffällige Freigabe, 2 = riskanter Befehl (dann kein ⌃⌥Y).
        // Y und N bleiben belegt, solange irgendeine Freigabe wartet. Beantwortet wird aber nur die sichtbare.
        watch = model.$asks.map { !$0.isEmpty }.removeDuplicates().sink { [weak self] waiting in
            guard let self else { return }
            if waiting {
                self.register(1, kVK_ANSI_Y); self.register(2, kVK_ANSI_N)
                self.seenTimer?.invalidate()
                self.seenTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in self?.track() }
            } else {
                self.unregister(1); self.unregister(2)
                self.seenTimer?.invalidate(); self.seenTimer = nil; self.seen = nil
            }
        }
        // Esc nur abfangen, solange die Insel per Kürzel offen gehalten wird UND zu sehen ist.
        watchPinned = model.$pinnedOpen.combineLatest(model.$islandVisible).map { $0 && $1 }.removeDuplicates().sink { [weak self] open in
            if open { self?.register(5, kVK_Escape, mods: 0) } else { self?.unregister(5) }
        }
    }

    private func track() {
        let id = model.visibleAsk?.id
        if id != seen?.id { seen = id.map { ($0, Date()) } }
    }

    private func register(_ id: UInt32, _ key: Int, mods: Int = controlKey | optionKey) {
        guard refs[id] == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(key), UInt32(mods),
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs[id] = ref } else { log("Tastenkürzel \(id) nicht belegbar (Status \(status))") }
    }

    private func unregister(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }

    private func answer(_ reply: String) {
        track()
        // Ist gerade keine Freigabe zu sehen, holt das Kürzel sie nur hervor – beantwortet wird nichts Ungesehenes.
        guard let ask = model.visibleAsk else { model.resurfaceAsk(); return }
        // Fragen lassen sich nicht per Kürzel beantworten – ⌃⌥Y springt stattdessen zur Session.
        if ask.isQuestion {
            if reply == "allow" { jump() }
            return
        }
        // Eine Freigabe muss knapp eine Sekunde zu sehen gewesen sein (schützt vor Wechsel im letzten Moment und Doppeltipper).
        guard let s = seen, s.id == ask.id, Date().timeIntervalSince(s.since) > 0.8 else { return }
        if reply == "allow", !ask.risk.isEmpty { return }
        model.answer?(ask, reply)
    }

    private func jump() {
        let target = model.sessions.first { $0.status == .waiting } ?? model.sessions.first
        if let target { model.openSession?(target) } else { Apps.activate(Apps.claude) }
    }
}
