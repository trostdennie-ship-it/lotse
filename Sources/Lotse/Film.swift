import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation

enum FilmState { nonisolated(unsafe) static var active = false }

/// Film-Aufnahme (`Lotse --film <ordner>`): Die echte Insel spielt am Notch eine Vorführung mit Beispieldaten ab,
/// und Lotse schneidet dabei nur das eigene Insel-Fenster mit – mit durchsichtigem Hintergrund, ohne Mauszeiger.
/// So zeigt ein Film das tatsächliche Verhalten (Federn, gestaffelte Kacheln, segelndes Boot) statt einer Nachbildung.
/// Ergebnis: `insel.mov` (ProRes 4444 mit Alpha) und `ablauf.json` (wann was passiert ist, in Sekunden ab erstem Bild).
@available(macOS 15.0, *)
final class Film: NSObject, SCStreamOutput, SCStreamDelegate {
    private let model: IslandModel
    private let panel: NSWindow
    private let dir: URL
    private let fleet: [ClaudeSession]
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "lotse.film")
    private var first: Double?
    private var marks: [[String: Any]] = []
    private var frames = 0

    init(model: IslandModel, panel: NSWindow, dir: URL, fleet: [ClaudeSession]) {
        self.model = model; self.panel = panel; self.dir = dir; self.fleet = fleet
    }

    func start() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { @MainActor in
            do { try await begin() } catch { log("Film: \(error.localizedDescription)"); print("FEHLER:", error); exit(1) }
        }
    }

    @MainActor private func begin() async throws {
        try await Task.sleep(nanoseconds: 1_200_000_000)        // die Insel steht
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(panel.windowNumber) }) else {
            throw NSError(domain: "Lotse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Insel-Fenster nicht gefunden"])
        }
        let scale = panel.screen?.backingScaleFactor ?? 2
        let w = Int(panel.frame.width * scale), h = Int(panel.frame.height * scale)
        let cfg = SCStreamConfiguration()
        cfg.width = w; cfg.height = h
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        cfg.showsCursor = false
        cfg.backgroundColor = .clear
        cfg.shouldBeOpaque = false
        cfg.ignoreShadowsSingleWindow = true
        cfg.queueDepth = 8
        let out = dir.appendingPathComponent("insel.mov")
        try? FileManager.default.removeItem(at: out)
        let wr = try AVAssetWriter(outputURL: out, fileType: .mov)
        let inp = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: w, AVVideoHeightKey: h])
        inp.expectsMediaDataInRealTime = true
        wr.add(inp); writer = wr; input = inp
        let st = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: cfg, delegate: self)
        try st.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await st.startCapture()
        stream = st
        log("Film: Aufnahme läuft, \(w)×\(h) px, Maßstab \(scale), Notch \(model.hasNotch ? "ja" : "nein")")
        script()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sb.isValid, let writer, let input,
              let info = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        if first == nil {
            first = pts.seconds
            writer.startWriting(); writer.startSession(atSourceTime: pts)
        }
        if input.isReadyForMoreMediaData, input.append(sb) { frames += 1 }
    }

    /// Zeit seit dem ersten Bild – dieselbe Uhr wie die Bildzeiten der Aufnahme.
    private func mark(_ name: String) {
        let t = CACurrentMediaTime() - (queue.sync { first } ?? CACurrentMediaTime())
        marks.append(["t": (t * 1000).rounded() / 1000, "n": name])
    }

    // MARK: Drehbuch

    @MainActor private func script() {
        let m = model
        var at = 1.0
        func step(_ name: String, after pause: Double, _ action: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in self?.mark(name); action() }
            at += pause
        }
        let spring = IslandModel.spring
        let working = fleet.filter { $0.status == .working }
        func fresh(_ s: ClaudeSession, ago: Double) -> ClaudeSession { var c = s; c.startedAt = Date().addingTimeInterval(-ago); c.updated = Date(); return c }

        step("ruhe", after: 2.2) {}
        step("arbeitet", after: 3.2) { withAnimation(spring) { m.sessions = [fresh(working[0], ago: 247)] } }
        step("mehrere", after: 2.6) { withAnimation(spring) { m.sessions = [fresh(working[0], ago: 250), fresh(working[1], ago: 912), fresh(working[2], ago: 64)] } }
        step("auf", after: 4.6) { m.setHover(true) }
        step("woche", after: 4.6) { withAnimation(spring) { m.showWeek = true } }
        step("woche-zu", after: 1.0) { withAnimation(spring) { m.showWeek = false } }
        step("reiter-arbeit", after: 3.0) { withAnimation(spring) { m.tab = .work } }
        step("reiter-ablage", after: 2.2) { withAnimation(spring) { m.tab = .stow } }
        step("reiter-ueberblick", after: 1.6) { withAnimation(spring) { m.tab = .home } }
        step("zu", after: 2.2) { m.setHover(false) }
        step("freigabe", after: 4.2) {
            let ask = PermissionAsk(id: "film", sessionID: working[0].id, project: working[0].project, tool: "Bash",
                                    detail: "npm test", summary: "Führt die Tests des Projekts aus")
            m.asks.insert(ask, at: 0)
            m.post(Notice(kind: .claude, appID: Apps.claude, appName: "Claude · \(ask.project)", title: "Claude wartet auf dein OK",
                          body: ask.summary, sessionID: ask.sessionID))
        }
        step("erlaubt", after: 3.0) {
            m.asks.removeAll(); m.dismissPeek()
            m.post(Notice(kind: .info, appID: Apps.claude, appName: working[0].project, title: "Erlaubt",
                          body: "Führt die Tests des Projekts aus", brief: true))
        }
        step("termin", after: 6.2) {
            m.post(Notice(kind: .calendar, appID: "com.apple.iCal", appName: "Kalender · Arbeit", title: "Jour fixe",
                          body: "Beginnt in 1 Min · klicken zum Beitreten", url: URL(string: "https://meet.google.com/abc"), hold: 5))
        }
        step("mail", after: 6.0) {
            m.post(Notice(kind: .system, appID: "com.apple.mail", appName: "Mail", title: "Anna Berger",
                          body: "Angebot Q1 – überarbeitete Fassung", card: "mail"))
        }
        step("fertig", after: 7.5) {
            withAnimation(spring) {
                var done = working[1]; done.status = .done; done.detail = ""; done.planStep = ""; done.startedAt = nil
                done.summary = "Der Schnitt steht, der Export liegt im Ordner."; done.doneAt = Date(); done.tookSeconds = 912; done.updated = Date()
                m.sessions = [done, fresh(working[0], ago: 300)]
            }
            m.post(Notice(kind: .claude, appID: Apps.claude, appName: "Claude", title: "Claude ist fertig",
                          body: "Der Schnitt steht, der Export liegt im Ordner.", sessionID: working[1].id))
        }
        step("ende", after: 0.5) { [weak self] in self?.finish() }
    }

    private func finish() {
        Task { @MainActor in
            try? await stream?.stopCapture()
            queue.sync { input?.markAsFinished() }
            await writer?.finishWriting()
            let screen = panel.screen
            let meta: [String: Any] = [
                "marks": marks, "frames": frames, "scale": screen?.backingScaleFactor ?? 0,
                "panel": [panel.frame.width, panel.frame.height], "notch": model.hasNotch, "notchWidth": model.notchWidth,
                "screen": [screen?.frame.width ?? 0, screen?.frame.height ?? 0], "safeTop": screen?.safeAreaInsets.top ?? 0,
            ]
            if let data = try? JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: dir.appendingPathComponent("ablauf.json"))
            }
            log("Film: fertig, \(frames) Bilder")
            NSApp.terminate(nil)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { log("Film: Aufnahme abgebrochen – \(error.localizedDescription)") }
}
