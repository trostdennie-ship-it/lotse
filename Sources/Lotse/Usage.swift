import Foundation

/// Nutzungsstände des Claude-Abos (5-Stunden- und Wochenlimit).
///
/// Lotse fragt dafür das von der Claude-App mitgelieferte Claude Code über dessen (experimentelle)
/// Steueranfrage `get_usage` – abgeschottet: ohne Einstellungen/Hooks, ohne Werkzeuge, ohne Transkript.
/// Lotse selbst sieht dabei keine Zugangsdaten; Claude Code meldet sich mit seiner eigenen Anmeldung.
final class UsageSource {
    private let model: IslandModel
    private var timer: Timer?
    private var lastTry = Date.distantPast
    private var pause: TimeInterval = 10 * 60
    private var running = false
    private let queue = DispatchQueue(label: "lotse.usage")

    init(model: IslandModel) { self.model = model }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.tick(force: true) }
    }

    /// Nur abfragen, solange Claude gerade genutzt wird – und höchstens alle zehn Minuten.
    private func tick(force: Bool = false) {
        let now = Date()
        // Abgelaufene Fenster nicht weiter anzeigen.
        if model.limits.contains(where: { ($0.resets ?? .distantFuture) < now }) {
            model.limits.removeAll { ($0.resets ?? .distantFuture) < now }
        }
        let active = model.sessions.contains { now.timeIntervalSince($0.updated) < 15 * 60 }
        guard !running, force || active, now.timeIntervalSince(lastTry) >= pause else { return }
        lastTry = now
        running = true
        queue.async { [weak self] in
            let result = Self.probe()
            DispatchQueue.main.async { self?.apply(result) }
        }
    }

    private enum Result {
        case limits([UsageLimit])
        case needsLogin
        case notApplicable        // z. B. API-Schlüssel statt Abo
        case failed(String)
    }

    private func apply(_ r: Result) {
        running = false
        switch r {
        case .limits(let l):
            model.limits = l
            model.limitsUpdated = Date()
            model.usageHint = ""
            pause = 10 * 60
            log("Nutzung: " + l.map { "\($0.label) \(Int($0.percent)) %" }.joined(separator: ", "))
        case .needsLogin:
            model.usageHint = "Nutzung: Claude Code im Terminal neu anmelden (claude, dann /login)."
            pause = 30 * 60
            log("Nutzung: keine Werte – Anmeldung von Claude Code im Terminal fehlt oder ist abgelaufen")
        case .notApplicable:
            model.usageHint = ""
            pause = 6 * 3600
            log("Nutzung: für dieses Konto gibt es keine Abo-Limits")
        case .failed(let why):
            pause = 30 * 60
            log("Nutzung: Abfrage fehlgeschlagen – \(why)")
        }
    }

    // MARK: Abfrage

    /// Das neueste mitgelieferte Claude Code der Desktop-App (der Pfad ändert sich mit jedem App-Update).
    private static func cli() -> URL? {
        let fm = FileManager.default
        let base = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code")
        var found: [(URL, Date)] = []
        for v in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] {
            for h in (try? fm.contentsOfDirectory(at: v, includingPropertiesForKeys: nil)) ?? [] {
                let bin = h.appendingPathComponent("claude.app/Contents/MacOS/claude")
                guard fm.isExecutableFile(atPath: bin.path) else { continue }
                let d = (try? fm.attributesOfItem(atPath: bin.path))?[.modificationDate] as? Date
                found.append((bin, d ?? .distantPast))
            }
        }
        return found.max { $0.1 < $1.1 }?.0
    }

    private static func probe() -> Result {
        guard let cli = cli() else { return .failed("Claude Code der Desktop-App nicht gefunden") }
        let fm = FileManager.default
        let cwd = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Lotse/abfrage")
        try? fm.createDirectory(at: cwd, withIntermediateDirectories: true)

        let p = Process()
        p.executableURL = cli
        p.currentDirectoryURL = cwd
        p.arguments = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--setting-sources", "", "--no-session-persistence", "--tools", "",
                       "--strict-mcp-config", "--disable-slash-commands"]
        // Bewusst karge Umgebung: nichts von Lotse oder anderen Sessions durchreichen.
        let e = ProcessInfo.processInfo.environment
        p.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                         "USER": e["USER"] ?? "", "LOGNAME": e["LOGNAME"] ?? "", "TMPDIR": e["TMPDIR"] ?? "/tmp"]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice

        var buffer = Data()
        var answer: [String: Any]?
        let done = DispatchSemaphore(value: 0)
        let lock = NSLock()
        stdout.fileHandleForReading.readabilityHandler = { h in
            let chunk = h.availableData
            lock.lock(); defer { lock.unlock() }
            guard answer == nil else { return }
            if chunk.isEmpty { done.signal(); return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                   j["type"] as? String == "control_response" {
                    answer = j; done.signal(); return
                }
            }
        }
        do { try p.run() } catch { return .failed("Start: \(error.localizedDescription)") }
        let request = #"{"type":"control_request","request_id":"lotse","request":{"subtype":"get_usage","skip_behaviors":true}}"# + "\n"
        try? stdin.fileHandleForWriting.write(contentsOf: Data(request.utf8))
        let timedOut = done.wait(timeout: .now() + 25) == .timedOut
        stdout.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { if p.isRunning { p.terminate() } }

        lock.lock(); let j = answer; lock.unlock()
        guard let j else { return .failed(timedOut ? "keine Antwort innerhalb von 25 s" : "Claude Code hat sich ohne Antwort beendet") }
        guard let outer = j["response"] as? [String: Any], outer["subtype"] as? String == "success",
              let r = outer["response"] as? [String: Any] else { return .failed("unerwartete Antwort") }
        if r["rate_limits_available"] as? Bool == false { return .notApplicable }
        guard let limits = r["rate_limits"] as? [String: Any] else { return .needsLogin }
        return .limits(parse(limits))
    }

    private static func parse(_ l: [String: Any]) -> [UsageLimit] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func window(_ any: Any?, _ label: String) -> UsageLimit? {
            guard let w = any as? [String: Any], let u = (w["utilization"] as? NSNumber)?.doubleValue else { return nil }
            // Der Zeitstempel kommt mit Mikrosekunden („…00.426501+00:00“) – die Nachkommastellen stören nur.
            let date = (w["resets_at"] as? String).flatMap { raw -> Date? in
                let trimmed = raw.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
                return plain.date(from: trimmed) ?? iso.date(from: raw)
            }
            return UsageLimit(label: label, percent: u, resets: date)
        }
        var out = [window(l["five_hour"], "5 Stunden"), window(l["seven_day"], "Woche")].compactMap { $0 }
        for m in (l["model_scoped"] as? [[String: Any]]) ?? [] {
            if let w = window(m, "Woche (nur \(m["display_name"] as? String ?? "Modell"))") { out.append(w) }
        }
        if out.count < 3 {
            for (key, name) in [("seven_day_opus", "Opus"), ("seven_day_sonnet", "Sonnet")] {
                if let w = window(l[key], "Woche (nur \(name))"), w.percent > 0 { out.append(w) }
            }
        }
        return Array(out.prefix(4))
    }
}
