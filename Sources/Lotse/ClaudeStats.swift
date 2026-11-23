import Foundation

/// Was Claude Code heute verbraucht hat – gelesen aus den Protokollen auf diesem Mac, ohne Abfrage im Netz.
struct ClaudeDay: Equatable {
    var tokens = 0          // neu verarbeitet: Eingabe + Ausgabe + neu in den Zwischenspeicher geschrieben
    var sessions = 0
    var tools = 0
    var top = ""            // Projekt mit dem größten Anteil
}

final class ClaudeStats {
    private let model: IslandModel
    private let queue = DispatchQueue(label: "lotse.stats", qos: .utility)
    private var timer: Timer?
    // Je Datei: bis wohin schon gelesen wurde. So wird ein Protokoll nur einmal ganz gelesen, danach nur der Zuwachs.
    private var offsets: [String: UInt64] = [:]
    private var day = ""
    private var seen = Set<String>()
    private var sessions = Set<String>()
    private var perProject: [String: Int] = [:]
    private var tokens = 0
    private var tools = 0

    init(model: IslandModel) { self.model = model }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.scan() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in self?.scan() }
    }

    private func scan() {
        queue.async { [weak self] in
            guard let self else { return }
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let key = ISO8601DateFormatter.string(from: start, timeZone: .current, formatOptions: [.withFullDate])
            if key != self.day {            // neuer Tag: von vorn zählen
                self.day = key; self.offsets = [:]; self.seen = []; self.sessions = []; self.perProject = [:]
                self.tokens = 0; self.tools = 0
            }
            let fm = FileManager.default
            let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
            for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                where file.pathExtension == "jsonl" {
                    let changed = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    guard changed >= start else { continue }
                    self.read(file, since: start)
                }
            }
            let top = self.perProject.max { $0.value < $1.value }?.key ?? ""
            let result = ClaudeDay(tokens: self.tokens, sessions: self.sessions.count, tools: self.tools, top: top)
            DispatchQueue.main.async { if self.model.today != result { self.model.today = result } }
        }
    }

    private func read(_ file: URL, since start: Date) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }
        let from = offsets[file.path] ?? 0
        guard (try? handle.seek(toOffset: from)) != nil else { return }
        var carry = Data()
        var position = from
        let needle = Data("\"usage\"".utf8)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            carry.append(chunk)
            var lineStart = carry.startIndex
            while let nl = carry[lineStart...].firstIndex(of: 0x0A) {
                let line = carry[lineStart..<nl]
                position += UInt64(line.count + 1)
                lineStart = carry.index(after: nl)
                guard line.range(of: needle) != nil,
                      let j = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let stamp = j["timestamp"] as? String, let date = iso.date(from: stamp), date >= start,
                      let message = j["message"] as? [String: Any], let usage = message["usage"] as? [String: Any] else { continue }
                for block in (message["content"] as? [[String: Any]]) ?? [] where block["type"] as? String == "tool_use" { tools += 1 }
                if let sid = j["sessionId"] as? String { sessions.insert(sid) }
                // Eine Antwort steht in mehreren Zeilen (je Inhaltsblock eine) – der Verbrauch zählt nur einmal.
                guard let id = message["id"] as? String, seen.insert(id).inserted else { continue }
                let n = ["input_tokens", "output_tokens", "cache_creation_input_tokens"].reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
                tokens += n
                let project = ((j["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }) ?? "Claude"
                perProject[project, default: 0] += n
            }
            carry = Data(carry[lineStart...])
        }
        offsets[file.path] = position        // eine angefangene letzte Zeile wird beim nächsten Mal noch einmal gelesen
    }
}

