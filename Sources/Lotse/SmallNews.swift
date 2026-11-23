import Foundation
import CoreAudio
import IOKit.ps

/// Kleine Meldungen direkt am Notch: Ladekabel angesteckt oder abgezogen, Akku fast leer,
/// Kopfhörer verbunden. Sie erscheinen als schmale Pille und verschwinden nach gut zwei Sekunden.
final class SmallNews {
    private let model: IslandModel
    private var power: (ac: Bool, percent: Int)?
    private var output: AudioDeviceID = 0

    init(model: IslandModel) { self.model = model }

    func start() {
        // Stromversorgung: macOS meldet jede Änderung.
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<SmallNews>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
        }, me)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        power = readPower()

        // Tonausgabe: wechselt das Ausgabegerät auf ein Bluetooth-Gerät, haben sich Kopfhörer verbunden.
        output = defaultOutput()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.outputChanged()
        }
    }

    private func say(_ title: String, _ detail: String, _ symbol: String) {
        model.post(Notice(kind: .info, appID: nil, appName: "", title: title, body: detail, brief: true, symbol: symbol))
    }

    // MARK: Strom

    private func readPower() -> (ac: Bool, percent: Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let now = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let full = d[kIOPSMaxCapacityKey] as? Int ?? 100
            return (d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue, full > 0 ? now * 100 / full : now)
        }
        return nil      // kein Akku (Desktop-Mac)
    }

    private func powerChanged() {
        guard let now = readPower() else { return }
        defer { power = now }
        guard let before = power else { return }
        if now.ac != before.ac {
            say(now.ac ? "Lädt" : "Akkubetrieb", "\(now.percent) %", now.ac ? "bolt.fill" : "battery.75percent")
        } else if !now.ac, now.percent <= 15, before.percent > 15 {
            say("Akku fast leer", "\(now.percent) %", "battery.25percent")
        }
    }

    // MARK: Ton

    private func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private func name(of id: AudioDeviceID) -> String {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr, let name else { return "" }
        return name.takeRetainedValue() as String
    }

    private func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var type = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &type) == noErr else { return false }
        return type == kAudioDeviceTransportTypeBluetooth || type == kAudioDeviceTransportTypeBluetoothLE
    }

    private func outputChanged() {
        let now = defaultOutput()
        guard now != output else { return }
        output = now
        guard isBluetooth(now) else { return }
        let device = name(of: now)
        model.post(Notice(kind: .info, appID: nil, appName: "", title: device.isEmpty ? "Kopfhörer" : device,
                          body: "Verbunden", card: "headphones"))
    }
}

/// Verbindet den Mixer-Baustein mit der Insel: Gesamtlautstärke, Stummschalten und die Liste der Apps,
/// die gerade Ton ausgeben. Eigene Regler gibt es nur für Apps, die das selbst anbieten (Spotify, Musik).
final class MixerBridge {
    private let model: IslandModel
    private let mixer = SystemMixer()
    private var levels: [String: Double] = [:]
    private var lastSend: [String: Date] = [:]
    private var trailing: [String: DispatchWorkItem] = [:]

    init(model: IslandModel) { self.model = model }

    func start() {
        mixer.logger = { log("Mixer: \($0)") }
        mixer.onChange = { [weak self] in self?.sync() }
        model.setVolume = { [weak self] v in
            guard let self else { return }
            if self.mixer.muted { _ = self.mixer.setMuted(false) }
            _ = self.mixer.setVolume(Float(v))
        }
        model.setMuted = { [weak self] on in _ = self?.mixer.setMuted(on) }
        model.setAppLevel = { [weak self] id, v in self?.setLevel(id, v) }
        model.setOutput = { [weak self] out in
            AudioOutputs.select(out.id)
            self?.mixer.refresh()
            self?.sync()
        }
        mixer.start()
        sync()
        // macOS meldet nicht zuverlässig, wenn eine App zu spielen beginnt. Deshalb sieht der Mixer selbst nach:
        // alle paar Sekunden im Hintergrund und in kurzem Takt, solange der Reiter „Lautstärke" offen ist.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.ticks += 1
            let watching = self.model.mode == .expanded && self.model.tab == .mix
            if watching || self.ticks % 5 == 0 { self.mixer.refresh() }
            // Angesteckte oder verbundene Geräte tauchen so auch ohne eigene Meldung auf.
            if watching, self.ticks % 2 == 0 {
                let outs = AudioOutputs.list()
                if outs != self.model.outputs { self.model.outputs = outs }
            }
        }
    }

    private var timer: Timer?
    private var ticks = 0
    private var logged = ""

    private func sync() {
        model.volume = Double(mixer.volume)
        model.muted = mixer.muted
        model.volumeAdjustable = mixer.canSetVolume
        model.outputName = mixer.outputName
        let outs = AudioOutputs.list()
        if outs != model.outputs { model.outputs = outs }
        let apps = mixer.apps.map { a in
            MixApp(id: a.id, name: a.name, url: a.bundleURL, scriptable: a.scriptable, level: levels[a.id])
        }
        if apps != model.mixApps { model.mixApps = apps }
        let names = apps.map(\.name).joined(separator: ", ")
        if names != logged { logged = names; log("Mixer: Ton von \(names.isEmpty ? "keiner App" : names)") }
        // Den Stand der App-eigenen Regler nachlesen, sobald eine solche App auftaucht.
        for a in mixer.apps where a.scriptable && levels[a.id] == nil {
            mixer.playerVolume(bundleID: a.id) { [weak self] v in
                guard let self, let v else { return }
                self.levels[a.id] = Double(v)
                if let i = self.model.mixApps.firstIndex(where: { $0.id == a.id }) { self.model.mixApps[i].level = Double(v) }
            }
        }
    }

    private func setLevel(_ id: String, _ value: Double) {
        levels[id] = value
        if let i = model.mixApps.firstIndex(where: { $0.id == id }) { model.mixApps[i].level = value }
        // Beim Ziehen höchstens zehn Befehle pro Sekunde an die App schicken.
        trailing[id]?.cancel()
        if let last = lastSend[id], Date().timeIntervalSince(last) < 0.1 {
            // Den letzten Wert einer Ziehbewegung auf jeden Fall noch nachreichen.
            let work = DispatchWorkItem { [weak self] in
                guard let self, let v = self.levels[id] else { return }
                self.lastSend[id] = Date()
                self.mixer.setPlayerVolume(bundleID: id, Float(v))
            }
            trailing[id] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            return
        }
        lastSend[id] = Date()
        mixer.setPlayerVolume(bundleID: id, Float(value))
    }
}
