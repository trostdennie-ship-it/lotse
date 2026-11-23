import Foundation

/// Trägt Lotses Hooks in die Einstellungen von Claude Code ein (`~/.claude/settings.json`).
///
/// Über diese Hooks erfährt die Insel, woran Claude arbeitet, wann eine Session fertig ist und wann
/// eine Freigabe wartet. Fremde Einträge bleiben unberührt; vor der ersten Änderung entsteht eine Sicherung.
enum ClaudeHooks {
    enum State: Equatable {
        case connected            // alle Einträge vorhanden
        case partial              // einige fehlen (z. B. nach einem Update von Lotse)
        case missing              // nichts eingetragen
        case unreadable           // settings.json ist kein gültiges JSON – Lotse fasst sie nicht an
    }

    enum Problem: LocalizedError {
        case unreadable
        var errorDescription: String? {
            "Die Datei ~/.claude/settings.json lässt sich nicht lesen. Lotse hat sie nicht verändert – bitte Claude bitten, sie zu reparieren."
        }
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// Ereignis → (Skript, Wartezeit in Sekunden, im Hintergrund).
    private static let wanted: [(event: String, ask: Bool, timeout: Int, async: Bool)] = [
        ("SessionStart", false, 5, false), ("SessionEnd", false, 5, false), ("UserPromptSubmit", false, 5, false),
        ("Stop", false, 5, false), ("Notification", false, 5, false),
        ("PreToolUse", false, 5, true), ("PostToolUse", false, 5, true), ("PostToolUseFailure", false, 5, true),
        ("PermissionRequest", true, 60, false),
    ]

    /// Der Befehl prüft erst, ob das Skript noch da ist – so stört ein gelöschtes Lotse Claude nie.
    private static func command(ask: Bool) -> String {
        let path = (ask ? ClaudeSource.askHook : ClaudeSource.hook).path
        return "[ ! -x '\(path)' ] || '\(path)'"
    }

    private static func marker(ask: Bool) -> String { ask ? "Lotse/claude-ask.sh" : "Lotse/claude-hook.sh" }

    private static func read(_ url: URL) -> [String: Any]?? {
        guard FileManager.default.fileExists(atPath: url.path) else { return .some(nil) }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 || $0 == 0x0D }) { return .some(nil) }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return .some(json)
    }

    private static func has(_ hooks: [String: Any], _ event: String, ask: Bool) -> Bool {
        for group in hooks[event] as? [[String: Any]] ?? [] {
            for h in group["hooks"] as? [[String: Any]] ?? [] where (h["command"] as? String ?? "").contains(marker(ask: ask)) {
                return true
            }
        }
        return false
    }

    static func state(at url: URL = settingsURL) -> State {
        guard let file = read(url) else { return .unreadable }
        let hooks = file?["hooks"] as? [String: Any] ?? [:]
        let found = wanted.filter { has(hooks, $0.event, ask: $0.ask) }.count
        return found == wanted.count ? .connected : found == 0 ? .missing : .partial
    }

    /// Ergänzt fehlende Einträge. Vorhandenes – auch von anderen Werkzeugen – bleibt stehen.
    static func install(at url: URL = settingsURL) throws {
        guard let file = read(url) else { throw Problem.unreadable }
        var root = file ?? [:]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var changed = false
        for w in wanted where !has(hooks, w.event, ask: w.ask) {
            var entry: [String: Any] = ["type": "command", "command": command(ask: w.ask), "timeout": w.timeout]
            if w.async { entry["async"] = true }
            var groups = hooks[w.event] as? [[String: Any]] ?? []
            groups.append(["hooks": [entry]])
            hooks[w.event] = groups
            changed = true
        }
        guard changed else { return }
        root["hooks"] = hooks
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Einmalige Sicherung des Standes vor Lotse.
        let backup = url.deletingLastPathComponent().appendingPathComponent("settings.json.vor-lotse")
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Nimmt Lotses Einträge wieder heraus (für die Deinstallation).
    static func remove(at url: URL = settingsURL) throws {
        guard let file = read(url) else { throw Problem.unreadable }
        guard var root = file, var hooks = root["hooks"] as? [String: Any] else { return }
        for (event, value) in hooks {
            guard var groups = value as? [[String: Any]] else { continue }
            groups = groups.compactMap { group in
                var g = group
                let rest = (g["hooks"] as? [[String: Any]] ?? []).filter {
                    let c = $0["command"] as? String ?? ""
                    return !c.contains(marker(ask: false)) && !c.contains(marker(ask: true))
                }
                if rest.isEmpty { return nil }
                g["hooks"] = rest
                return g
            }
            if groups.isEmpty { hooks[event] = nil } else { hooks[event] = groups }
        }
        if hooks.isEmpty { root["hooks"] = nil } else { root["hooks"] = hooks }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }

    /// Selbsttest an einer Wegwerf-Datei: fremde Einträge überleben, zweimal eintragen verdoppelt nichts.
    static func selfTest() -> [String] {
        var out: [String] = []
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lotse-hooktest-\(ProcessInfo.processInfo.processIdentifier)")
        let url = dir.appendingPathComponent("settings.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let foreign = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo fremd"}]}]}}"#
        try? foreign.write(to: url, atomically: true, encoding: .utf8)
        if state(at: url) != .missing { out.append("HOOKS: fremde Datei nicht als „fehlt“ erkannt") }
        do {
            try install(at: url); try install(at: url)
            if state(at: url) != .connected { out.append("HOOKS: nach dem Eintragen nicht verbunden") }
            let j = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
            let stop = (j["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
            if stop.count != 2 { out.append("HOOKS: Stop hat \(stop.count) statt 2 Einträge (fremd + Lotse)") }
            if j["model"] as? String != "opus" { out.append("HOOKS: fremder Schlüssel verloren") }
            try remove(at: url)
            if state(at: url) != .missing { out.append("HOOKS: nach dem Entfernen noch Einträge da") }
            let k = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]) ?? [:]
            if ((k["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count != 1 { out.append("HOOKS: fremder Hook beim Entfernen verloren") }
        } catch { out.append("HOOKS: \(error.localizedDescription)") }
        try? "{ kaputt".write(to: url, atomically: true, encoding: .utf8)
        if state(at: url) != .unreadable { out.append("HOOKS: kaputte Datei nicht erkannt") }
        if (try? install(at: url)) != nil { out.append("HOOKS: kaputte Datei wurde überschrieben") }
        return out
    }
}
