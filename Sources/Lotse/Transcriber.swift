import AppKit
import AVFoundation
import Speech

/// Stand des Transkripts zum letzten Mitschnitt.
enum TranscriptState: Equatable {
    case none
    case working(String)        // was gerade geschieht
    case ready(URL)
    case failed(String)
}

/// Schreibt einen Mitschnitt mit – mit der Spracherkennung von macOS, vollständig auf diesem Mac.
/// Der Ton verlässt den Rechner nicht. Beim ersten Mal lädt macOS einmalig das Sprachmodell von Apple.
@available(macOS 26.0, *)
enum Transcriber {
    struct Fail: LocalizedError {
        var text: String
        init(_ t: String) { text = t }
        var errorDescription: String? { text }
    }

    /// Liefert den Text mit Zeitmarken je Absatz („[03:12] …").
    static func transcribe(_ audio: URL, language: String, progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> String {
        guard SpeechTranscriber.isAvailable else { throw Fail("Die Spracherkennung steht auf diesem Mac nicht zur Verfügung.") }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language)) else {
            throw Fail("Für diese Sprache gibt es keine Spracherkennung.")
        }
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            progress("Lädt das Sprachmodell …")
            try await request.downloadAndInstall()
        }
        progress("Schreibt mit …")
        let file = try AVAudioFile(forReading: audio)
        let analyzer = try await SpeechAnalyzer(inputAudioFile: file, modules: [transcriber], finishAfterFile: true)
        _ = analyzer                         // muss leben, bis alle Ergebnisse da sind
        var parts: [(start: Double, text: String)] = []
        for try await result in transcriber.results where result.isFinal {
            let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append((result.range.start.seconds, text)) }
        }
        return layout(parts)
    }

    /// Fasst die erkannten Stücke zu Absätzen zusammen: neuer Absatz nach gut einer halben Minute oder einer längeren Pause.
    private static func layout(_ parts: [(start: Double, text: String)]) -> String {
        var out: [String] = []
        var current = "", began = 0.0, last = 0.0
        func stamp(_ s: Double) -> String {
            let t = Int(max(0, s))
            return t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%02d:%02d", t / 60, t % 60)
        }
        for p in parts {
            if current.isEmpty { began = p.start }
            else if p.start - began > 40 || p.start - last > 6 {
                out.append("[\(stamp(began))] \(current)"); current = ""; began = p.start
            }
            current += (current.isEmpty ? "" : " ") + p.text
            last = p.start
        }
        if !current.isEmpty { out.append("[\(stamp(began))] \(current)") }
        return out.joined(separator: "\n\n")
    }

    /// Schreibt das Transkript als Textdatei neben die Aufnahme.
    static func write(_ text: String, for audio: URL) throws -> URL {
        let url = audio.deletingPathExtension().appendingPathExtension("txt")
        let head = "Transkript: \(audio.deletingPathExtension().lastPathComponent)\nAutomatisch mitgeschrieben – bitte vor der Weitergabe gegenlesen.\n\n"
        try (head + (text.isEmpty ? "(Keine Sprache erkannt.)" : text)).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

/// Verbindet das Mitschreiben mit der Insel: startet nach einem Mitschnitt (auf Wunsch von selbst) und reicht das Ergebnis weiter.
final class TranscriptBridge {
    private let model: IslandModel
    private var watch: Any?

    init(model: IslandModel) { self.model = model }

    func start() {
        model.transcribe = { [weak self] url in self?.run(url) }
        model.askClaude = { [weak self] url in self?.hand(url) }
    }

    private func run(_ audio: URL) {
        guard #available(macOS 26.0, *) else { model.transcript = .failed("Braucht macOS 26 oder neuer."); return }
        if case .working = model.transcript { return }
        model.transcript = .working("Startet …")
        let language = model.transcriptLanguage
        Task {
            do {
                let text = try await Transcriber.transcribe(audio, language: language) { step in
                    DispatchQueue.main.async { self.model.transcript = .working(step) }
                }
                let file = try Transcriber.write(text, for: audio)
                log("Transkript geschrieben: \(file.lastPathComponent) (\(text.count) Zeichen)")
                await MainActor.run { self.model.transcript = .ready(file) }
            } catch {
                log("Transkript fehlgeschlagen – \(error)")
                let why = error.localizedDescription
                await MainActor.run { self.model.transcript = .failed(why.count > 90 ? String(why.prefix(90)) + "…" : why) }
            }
        }
    }

    /// Legt Auftrag und Transkript in die Zwischenablage und holt Claude nach vorn – dort nur noch einfügen.
    private func hand(_ transcript: URL) {
        guard let text = try? String(contentsOf: transcript, encoding: .utf8) else { return }
        let prompt = """
        Fasse diesen Call zusammen: 1. worum es ging (zwei Sätze), 2. Beschlüsse, 3. offene Punkte mit Verantwortlichen und Terminen, \
        4. nächste Schritte für mich. Das Transkript ist automatisch erstellt – Namen und Zahlen können falsch erkannt sein, markiere Unsicheres.

        \(text)
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(prompt, forType: .string)
        Apps.activate(Apps.claude)
        model.post(Notice(kind: .info, appID: Apps.claude, appName: "Lotse", title: "Auftrag kopiert",
                          body: "In Claude einfügen (⌘V)", brief: true, symbol: "doc.on.clipboard"))
    }
}
