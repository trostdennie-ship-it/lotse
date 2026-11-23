import AppKit
import AVFoundation
import ScreenCaptureKit

/// Zustand des Mitschnitts.
enum RecState: Equatable {
    case idle
    case starting
    case recording(since: Date)
    case saving
    case done(URL)
    case failed(String)

    var busy: Bool { if case .recording = self { return true }; return self == .starting || self == .saving }
}

/// Schneidet den Ton eines Videocalls mit: den Ton des Macs (die anderen) und dein Mikrofon – kein Bild.
/// Beides wird während der Aufnahme in zwei Spuren geschrieben und danach zu einer Tondatei (.m4a) gemischt.
/// macOS verlangt dafür die Freigaben „Bildschirm- und Systemaudioaufnahme" und „Mikrofon" und zeigt
/// während der Aufnahme sein eigenes Aufnahme-Symbol in der Menüleiste.
@available(macOS 15.0, *)
final class CallRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let model: IslandModel
    private let queue = DispatchQueue(label: "lotse.mitschnitt")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var system: AVAssetWriterInput?
    private var mic: AVAssetWriterInput?
    private var sessionStarted = false
    private var raw: URL?
    private var target: URL?

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Lotse Mitschnitte")
    }

    init(model: IslandModel) { self.model = model }

    func start() {
        model.toggleRecording = { [weak self] in self?.toggle() }
    }

    private func toggle() {
        switch model.recState {
        case .recording: Task { await self.finish() }
        case .starting, .saving: break
        default: Task { await self.begin() }
        }
    }

    private func set(_ s: RecState) { DispatchQueue.main.async { self.model.recState = s } }

    // MARK: Start

    private func begin() async {
        set(.starting)
        do {
            // Mikrofon: einmal fragen; ohne Mikrofon nimmt Lotse nur die anderen auf.
            let micOK = await AVCaptureDevice.requestAccess(for: .audio)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let display = content.displays.first else { throw Fail("Kein Bildschirm gefunden.") }

            let cfg = SCStreamConfiguration()
            cfg.capturesAudio = true
            cfg.excludesCurrentProcessAudio = true
            cfg.sampleRate = 48_000
            cfg.channelCount = 2
            cfg.captureMicrophone = micOK
            // Bild wird nicht gebraucht: so klein und selten wie möglich, es wird verworfen.
            cfg.width = 2; cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let fm = FileManager.default
            try fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let name = Self.fileName(event: await MainActor.run { self.model.nextEvent })
            let rawURL = fm.temporaryDirectory.appendingPathComponent("lotse-\(UUID().uuidString).mov")
            let w = try AVAssetWriter(outputURL: rawURL, fileType: .mov)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000,
                                           AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 128_000]
            let sys = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
            sys.expectsMediaDataInRealTime = true
            guard w.canAdd(sys) else { throw Fail("Tonspur lässt sich nicht anlegen.") }
            w.add(sys)
            var micInput: AVAssetWriterInput?
            if micOK {
                let m = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                m.expectsMediaDataInRealTime = true
                if w.canAdd(m) { w.add(m); micInput = m }
            }
            guard w.startWriting() else { throw w.error ?? Fail("Die Datei lässt sich nicht anlegen.") }

            let s = SCStream(filter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []),
                             configuration: cfg, delegate: self)
            try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)       // sonst meldet macOS verworfene Bilder
            try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            if micInput != nil { try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }

            queue.sync {
                self.writer = w; self.system = sys; self.mic = micInput
                self.sessionStarted = false; self.raw = rawURL
                self.target = Self.folder.appendingPathComponent(name)
            }
            try await s.startCapture()
            stream = s
            log("Mitschnitt gestartet (Mikrofon \(micInput != nil ? "an" : "aus")): \(name)")
            set(.recording(since: Date()))
        } catch {
            log("Mitschnitt: Start fehlgeschlagen – \(error)")
            let denied = (error as NSError).domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && (error as NSError).code == -3801
            set(.failed(denied ? "Freigabe „Bildschirm- und Systemaudioaufnahme“ fehlt." : Self.text(error)))
        }
    }

    // MARK: Ton entgegennehmen

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type != .screen, buffer.isValid, buffer.numSamples > 0, let writer, writer.status == .writing else { return }
        let input = type == .audio ? system : mic
        guard let input else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData { input.append(buffer) }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        log("Mitschnitt: von macOS beendet – \(error)")
        Task { await self.finish() }
    }

    // MARK: Stopp und Abmischen

    private func finish() async {
        guard let s = stream else { return }
        stream = nil
        set(.saving)
        try? await s.stopCapture()
        let (w, rawURL, out): (AVAssetWriter?, URL?, URL?) = queue.sync {
            system?.markAsFinished(); mic?.markAsFinished()
            let r = (writer, raw, target)
            writer = nil; system = nil; mic = nil
            return r
        }
        guard let w, let rawURL, let out else { set(.failed("Nichts aufgenommen.")); return }
        guard sessionStarted else {
            w.cancelWriting()
            set(.failed("Es kam kein Ton an – war der Call schon vorbei?"))
            return
        }
        await w.finishWriting()
        do {
            try await Self.mixdown(from: rawURL, to: out)
            try? FileManager.default.removeItem(at: rawURL)
            log("Mitschnitt gespeichert: \(out.lastPathComponent)")
            set(.done(out))
        } catch {
            // Abmischen misslungen: die Rohdatei mit zwei Spuren behalten, damit nichts verloren geht.
            let keep = out.deletingPathExtension().appendingPathExtension("mov")
            try? FileManager.default.moveItem(at: rawURL, to: keep)
            log("Mitschnitt: Abmischen fehlgeschlagen – \(error); Rohdatei behalten")
            set(FileManager.default.fileExists(atPath: keep.path) ? .done(keep) : .failed(Self.text(error)))
        }
    }

    /// Mischt alle Tonspuren der Rohdatei zu einer .m4a-Datei.
    private static func mixdown(from source: URL, to target: URL) async throws {
        let asset = AVURLAsset(url: source)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw Fail("Die Aufnahme enthält keinen Ton.") }
        let duration = try await asset.load(.duration)
        let mix = AVMutableComposition()
        var parts: [(track: AVMutableCompositionTrack, level: Float)] = []
        for t in tracks {
            guard let c = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let range = try await t.load(.timeRange)
            try c.insertTimeRange(range, of: t, at: range.start)
            parts.append((c, loudness(of: t, in: asset)))
        }
        // Pegel angleichen: Die lautere Spur (meist der Mac-Ton) wird auf die Lautstärke der leiseren abgesenkt,
        // damit deine Stimme nicht untergeht. Anheben über 100 % erlaubt macOS beim Abmischen nicht.
        let audible = parts.map(\.level).filter { $0 > 0 }
        let audioMix = AVMutableAudioMix()
        if parts.count > 1, let quiet = audible.min() {
            audioMix.inputParameters = parts.map { part in
                let p = AVMutableAudioMixInputParameters(track: part.track)
                let gain = part.level > 0 ? max(0.12, min(1, quiet / part.level)) : 1
                p.setVolume(gain, at: .zero)
                log("Mitschnitt: Spur mit Pegel \(String(format: "%.3f", part.level)) → Lautstärke \(Int(gain * 100)) %")
                return p
            }
        }
        guard let export = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetAppleM4A) else {
            throw Fail("Abmischen nicht möglich.")
        }
        export.audioMix = audioMix
        export.timeRange = CMTimeRange(start: .zero, duration: duration)
        try? FileManager.default.removeItem(at: target)
        try await export.export(to: target, as: .m4a)
    }

    /// Mittlere Lautstärke der hörbaren Stellen einer Spur (Stille zählt nicht mit). 0 = nichts zu hören.
    private static func loudness(of track: AVAssetTrack, in asset: AVAsset) -> Float {
        guard let reader = try? AVAssetReader(asset: asset) else { return 0 }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false])
        guard reader.canAdd(out) else { return 0 }
        reader.add(out)
        guard reader.startReading() else { return 0 }
        var sum = 0.0, count = 0.0
        while let buffer = out.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<Int8>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                                              dataPointerOut: &pointer) == kCMBlockBufferNoErr, let pointer else { continue }
            let n = length / MemoryLayout<Float>.size
            pointer.withMemoryRebound(to: Float.self, capacity: n) { samples in
                for i in 0..<n {
                    let v = Double(samples[i])
                    if abs(v) > 0.004 { sum += v * v; count += 1 }      // nur hörbare Stellen
                }
            }
        }
        return count > 2_000 ? Float((sum / count).squareRoot()) : 0
    }

    // MARK: Hilfen

    private struct Fail: LocalizedError {
        var text: String
        init(_ t: String) { text = t }
        var errorDescription: String? { text }
    }

    private static func text(_ error: Error) -> String {
        let s = error.localizedDescription
        return s.count > 90 ? String(s.prefix(90)) + "…" : s
    }

    /// „Mitschnitt 2026-11-22 21.50 – Jour fixe.m4a": Läuft gerade ein Termin (±10 Min), steht sein Titel dabei.
    private static func fileName(event: CalEvent?) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        var name = "Mitschnitt \(f.string(from: Date()))"
        if let e = event, e.start.timeIntervalSinceNow < 600, e.end.timeIntervalSinceNow > -600 {
            let clean = e.title.components(separatedBy: CharacterSet(charactersIn: "/:\\?%*|\"<>")).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !clean.isEmpty { name += " – " + String(clean.prefix(60)) }
        }
        return name + ".m4a"
    }
}
