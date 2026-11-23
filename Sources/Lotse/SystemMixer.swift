import AppKit
import AudioToolbox
import CoreAudio
import Darwin

/// Stufe 1 des Mixers: liest und setzt nur, was macOS ohne Zusatzberechtigung hergibt.
///  - Regler: Lautstaerke + Stumm des Standard-Ausgabegeraets (VirtualMainVolume, wie die Lautstaerketasten).
///  - Liste: Apps, deren Prozesse gerade Audio-Ausgabe laufen haben (CoreAudio-Prozessobjekte, macOS 14+),
///    Helferprozesse (Browser-Renderer, WebKit-GPU) unter ihrer App zusammengefasst. Nur Anzeige.
///  - Echte Regler nur fuer skriptbare Player (Music, Spotify) ueber AppleScript "sound volume".
/// Reine Property-Listener, kein Polling, kein Tap, kein TCC-Prompt (ausser Automation fuer AppleScript).
/// Alle oeffentlichen Methoden, Zustaende und Callbacks laufen auf dem Main-Thread.
final class SystemMixer {
    struct SoundingApp: Equatable, Identifiable {
        /// Bundle-ID der App (bei Prozessen ohne Bundle "pid:123").
        let id: String
        let name: String
        let bundleURL: URL?
        /// PID der zugeordneten App (nicht des Helfers), 0 wenn unbekannt.
        let appPID: pid_t
        /// CoreAudio-Prozessobjekte, die gerade ausgeben (Stufe 2 braucht genau diese fuer den Tap).
        let processObjects: [AudioObjectID]
        /// true = eigener Lautstaerkeregler per AppleScript moeglich.
        let scriptable: Bool
    }

    /// Wird bei jeder Aenderung von volume/muted/outputName/apps gerufen (Main-Thread).
    var onChange: (() -> Void)?
    var logger: (String) -> Void = { _ in }

    private(set) var volume: Float = 0          // 0...1
    private(set) var muted = false
    private(set) var canSetVolume = false
    private(set) var canMute = false
    private(set) var outputName = ""
    private(set) var apps: [SoundingApp] = []

    /// Skriptbare Player: Bundle-ID -> AppleScript-Name. Beide kennen "sound volume" (0...100).
    var scriptablePlayers: [String: String] = ["com.apple.Music": "Music", "com.spotify.client": "Spotify"]
    /// Prozesse, die nie als Zeile erscheinen sollen (Systemtoene, Lotse selbst kommt automatisch dazu).
    var hiddenBundlePrefixes: [String] = [
        "com.apple.systemsoundserverd", "systemsoundserverd", "com.apple.audio.", "com.apple.coreaudio", "com.apple.controlcenter",
        "com.apple.CoreSpeech", "com.apple.accessibility", "com.apple.audiomxd", "com.apple.mediaremoted",
        "com.apple.loginwindow", "com.apple.notificationcenterui", "com.apple.cmio", "com.apple.avconferenced",
        "com.apple.PowerChime", "com.apple.universalaccessd", "com.apple.corespeechd", "com.apple.TelephonyUtilities",
    ]

    private let sys = AudioObjectID(kAudioObjectSystemObject)
    private var started = false
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var sysListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var devListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var procListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var procInfo: [AudioObjectID: (pid: pid_t, bundle: String)] = [:]
    private var pending = false
    private let scriptQueue = DispatchQueue(label: "lotse.mixer.applescript", qos: .userInitiated)

    // MARK: Lebenszyklus

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true
        listenSystem(kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in self?.bindDevice() }
        listenSystem(kAudioHardwarePropertyProcessObjectList) { [weak self] in self?.rebuildProcesses() }
        // coreaudiod wurde neu gestartet: alle Objekt-IDs sind ungueltig, alles neu aufbauen.
        listenSystem(kAudioHardwarePropertyServiceRestarted) { [weak self] in
            self?.procListeners.removeAll(); self?.procInfo.removeAll()
            self?.bindDevice(); self?.rebuildProcesses()
        }
        bindDevice()
        rebuildProcesses()
    }

    func stop() {
        guard started else { return }
        started = false
        for (a, b) in sysListeners { var a = a; AudioObjectRemovePropertyListenerBlock(sys, &a, .main, b) }
        sysListeners.removeAll()
        unbindDevice()
        var a = Self.addr(kAudioProcessPropertyIsRunningOutput)
        for (id, b) in procListeners { AudioObjectRemovePropertyListenerBlock(id, &a, .main, b) }
        procListeners.removeAll(); procInfo.removeAll()
        apps = []
    }

    /// Alles einmal frisch lesen (z. B. beim Oeffnen des Mixer-Panels), falls ein Listener ausgeblieben ist.
    /// Kein Dauer-Polling; nur lesend.
    func refresh() {
        guard started else { return }
        readDevice()
        rebuildProcesses()
    }

    // MARK: Regler (Standard-Ausgabegeraet)

    /// Setzt die Lautstaerke des Standard-Ausgabegeraets (0...1). false = Geraet hat keinen Regler
    /// (HDMI/DisplayPort, manche USB-DACs, Mehrfachausgabegeraete).
    @discardableResult
    func setVolume(_ value: Float) -> Bool {
        guard device != kAudioObjectUnknown, canSetVolume else { return false }
        var v = Float32(max(0, min(1, value)))
        var a = Self.addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        let st = AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if st != noErr { logger("Mixer: Lautstaerke setzen fehlgeschlagen (\(st))") }
        return st == noErr
    }

    @discardableResult
    func setMuted(_ on: Bool) -> Bool {
        guard device != kAudioObjectUnknown, canMute else { return false }
        var v: UInt32 = on ? 1 : 0
        var a = Self.addr(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        return AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    private func bindDevice() {
        unbindDevice()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else {
            canSetVolume = false; canMute = false; outputName = ""; changed(); return
        }
        device = id
        let out = kAudioDevicePropertyScopeOutput
        // Virtuelle Hauptlautstaerke, dazu die echten Kanalregler: je nach Treiber meldet nur einer von beiden.
        var watch = [Self.addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, out),
                     Self.addr(kAudioDevicePropertyMute, out),
                     Self.addr(kAudioDevicePropertyVolumeScalar, out, kAudioObjectPropertyElementMain),
                     Self.addr(kAudioDevicePropertyVolumeScalar, out, 1),
                     Self.addr(kAudioDevicePropertyVolumeScalar, out, 2),
                     // Kopfhoerer rein/raus am selben Geraet (eingebauter Ausgang wechselt nur die Datenquelle).
                     Self.addr(kAudioDevicePropertyDataSource, out)]
        watch = watch.filter { var a = $0; return AudioObjectHasProperty(id, &a) }
        for w in watch {
            var a = w
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.readDevice() }
            if AudioObjectAddPropertyListenerBlock(id, &a, .main, block) == noErr { devListeners.append((w, block)) }
        }
        readDevice()
    }

    private func unbindDevice() {
        for (a, b) in devListeners { var a = a; AudioObjectRemovePropertyListenerBlock(device, &a, .main, b) }
        devListeners.removeAll()
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func readDevice() {
        guard device != kAudioObjectUnknown else { return }
        let out = kAudioDevicePropertyScopeOutput
        var va = Self.addr(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, out)
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        let hasVol = AudioObjectHasProperty(device, &va)
        if hasVol, AudioObjectGetPropertyData(device, &va, 0, nil, &size, &v) == noErr { volume = v }
        var settable: DarwinBoolean = false
        canSetVolume = hasVol && AudioObjectIsPropertySettable(device, &va, &settable) == noErr && settable.boolValue

        var ma = Self.addr(kAudioDevicePropertyMute, out)
        var m: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        let hasMute = AudioObjectHasProperty(device, &ma)
        if hasMute, AudioObjectGetPropertyData(device, &ma, 0, nil, &size, &m) == noErr { muted = m != 0 } else { muted = false }
        settable = false
        canMute = hasMute && AudioObjectIsPropertySettable(device, &ma, &settable) == noErr && settable.boolValue

        outputName = Self.string(device, kAudioObjectPropertyName) ?? ""
        changed()
    }

    // MARK: Apps mit laufender Ausgabe

    private func rebuildProcesses() {
        guard started else { return }
        let current = Set(Self.objectList(sys, kAudioHardwarePropertyProcessObjectList))
        for id in procListeners.keys where !current.contains(id) { procListeners[id] = nil; procInfo[id] = nil }
        var a = Self.addr(kAudioProcessPropertyIsRunningOutput)
        for id in current where procListeners[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleEvaluate() }
            guard AudioObjectAddPropertyListenerBlock(id, &a, .main, block) == noErr else { continue }
            procListeners[id] = block
        }
        // Objekt-IDs koennen wiederverwendet werden: PID/Bundle bei jeder Listenaenderung neu lesen.
        for id in procListeners.keys {
            var pid: pid_t = 0
            var size = UInt32(MemoryLayout<pid_t>.size)
            var pa = Self.addr(kAudioProcessPropertyPID)
            _ = AudioObjectGetPropertyData(id, &pa, 0, nil, &size, &pid)
            procInfo[id] = (pid, Self.string(id, kAudioProcessPropertyBundleID) ?? "")
        }
        scheduleEvaluate()
    }

    /// Mehrere Listener feuern oft im selben Moment: einmal pro Runloop-Durchlauf auswerten.
    private func scheduleEvaluate() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in self?.pending = false; self?.evaluate() }
    }

    private func evaluate() {
        guard started else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        var groups: [String: (name: String, url: URL?, pid: pid_t, objs: [AudioObjectID])] = [:]
        var a = Self.addr(kAudioProcessPropertyIsRunningOutput)
        for (obj, info) in procInfo {
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &running) == noErr, running != 0 else { continue }
            guard info.pid != me, !hiddenBundlePrefixes.contains(where: { info.bundle.hasPrefix($0) }) else { continue }
            let owner = Self.owner(ofPID: info.pid, audioBundleID: info.bundle)
            guard owner.pid != me, !hiddenBundlePrefixes.contains(where: { owner.id.hasPrefix($0) }) else { continue }
            var g = groups[owner.id] ?? (owner.name, owner.url, owner.pid, [])
            g.objs.append(obj)
            groups[owner.id] = g
        }
        let list = groups.map { key, g in
            SoundingApp(id: key, name: g.name, bundleURL: g.url, appPID: g.pid, processObjects: g.objs.sorted(),
                        scriptable: scriptablePlayers[key] != nil)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard list != apps else { return }
        apps = list
        changed()
    }

    private func changed() { onChange?() }

    // MARK: Helferprozess -> App

    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t
    /// Private libsystem-Funktion (dieselbe Zuordnung, die TCC und die Aktivitaetsanzeige benutzen).
    /// Fehlt sie, greifen die oeffentlichen Wege darunter.
    private static let responsiblePID: ResponsibleFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(p, to: ResponsibleFn.self)
    }()

    /// Ordnet einen (Helfer-)Prozess seiner App zu:
    /// 1. verantwortlicher Prozess (deckt XPC-Dienste wie com.apple.WebKit.GPU -> Safari ab),
    /// 2. aeusserstes .app-Buendel im Programmpfad (Chrome/Electron-Helfer liegen im App-Buendel),
    /// 3. Elternkette bis zu einer normalen App.
    static func owner(ofPID pid: pid_t, audioBundleID: String) -> (id: String, name: String, url: URL?, pid: pid_t) {
        func describe(_ app: NSRunningApplication) -> (id: String, name: String, url: URL?, pid: pid_t)? {
            guard let id = app.bundleIdentifier else { return nil }
            return (id, app.localizedName ?? id, app.bundleURL, app.processIdentifier)
        }
        func isRealApp(_ app: NSRunningApplication) -> Bool {
            // Helfer-Buendel liegen in einem anderen .app; eine "echte" App nicht.
            guard let url = app.bundleURL, url.pathExtension == "app" else { return false }
            return !url.deletingLastPathComponent().path.contains(".app/")
        }
        /// Aeusserstes .app-Buendel im Programmpfad (auch fuer Hintergrund-Apps, die LaunchServices nicht kennt).
        func fromPath(_ q: pid_t) -> (id: String, name: String, url: URL?, pid: pid_t)? {
            guard let path = executablePath(q), let r = path.range(of: ".app/") else { return nil }
            let url = URL(fileURLWithPath: String(path[..<r.lowerBound]) + ".app")
            guard let b = Bundle(url: url), let id = b.bundleIdentifier else { return nil }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
            let name = running?.localizedName
                ?? (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return (id, name, url, running?.processIdentifier ?? q)
        }
        var candidates: [pid_t] = []
        if let fn = responsiblePID { let r = fn(pid); if r > 1 { candidates.append(r) } }
        if !candidates.contains(pid) { candidates.append(pid) }
        for q in candidates {
            if let app = NSRunningApplication(processIdentifier: q), isRealApp(app), let d = describe(app) { return d }
            if let d = fromPath(q) { return d }
        }
        var p = parentPID(pid), hops = 0
        while p > 1, hops < 8 {
            if let app = NSRunningApplication(processIdentifier: p), isRealApp(app), let d = describe(app) { return d }
            p = parentPID(p); hops += 1
        }
        if !audioBundleID.isEmpty {
            let name = executablePath(pid).map { URL(fileURLWithPath: $0).lastPathComponent } ?? audioBundleID
            return (audioBundleID, name, nil, pid)
        }
        let name = executablePath(pid).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "PID \(pid)"
        return ("pid:\(pid)", name, nil, pid)
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : nil
    }

    private static func parentPID(_ pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : 0
    }

    // MARK: Skriptbare Player (AppleScript)

    /// Lautstaerke eines skriptbaren Players lesen (0...1). nil = nicht skriptbar, laeuft nicht oder
    /// Automations-Freigabe fehlt. Loest beim ersten Mal die Automations-Abfrage aus.
    func playerVolume(bundleID: String, done: @escaping (Float?) -> Void) {
        guard let name = runningPlayerName(bundleID) else { done(nil); return }
        runScript("tell application \"\(name)\" to get sound volume") { out in
            done(out.flatMap { Float($0) }.map { max(0, min(1, $0 / 100)) })
        }
    }

    /// Lautstaerke eines skriptbaren Players setzen (0...1). Bewegt den Regler in der App selbst.
    func setPlayerVolume(bundleID: String, _ value: Float, done: ((Bool) -> Void)? = nil) {
        guard let name = runningPlayerName(bundleID) else { done?(false); return }
        let pct = Int((max(0, min(1, value)) * 100).rounded())
        runScript("tell application \"\(name)\" to set sound volume to \(pct)\nreturn \"ok\"") { done?($0 != nil) }
    }

    /// Nur laufende Apps ansprechen: "tell application" wuerde sie sonst starten.
    private func runningPlayerName(_ bundleID: String) -> String? {
        guard let name = scriptablePlayers[bundleID],
              !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else { return nil }
        return name
    }

    private func runScript(_ source: String, done: @escaping (String?) -> Void) {
        scriptQueue.async { [logger] in
            var err: NSDictionary?
            let out = NSAppleScript(source: source)?.executeAndReturnError(&err).stringValue
            if let err { logger("Mixer AppleScript: \(err[NSAppleScript.errorMessage] ?? err)") }
            DispatchQueue.main.async { done(err == nil ? (out ?? "") : nil) }
        }
    }

    // MARK: Helfer

    private func listenSystem(_ sel: AudioObjectPropertySelector, _ body: @escaping () -> Void) {
        var a = Self.addr(sel)
        let block: AudioObjectPropertyListenerBlock = { _, _ in body() }
        if AudioObjectAddPropertyListenerBlock(sys, &a, .main, block) == noErr { sysListeners.append((Self.addr(sel), block)) }
    }

    static func addr(_ sel: AudioObjectPropertySelector,
                     _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
    }

    static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        let str = s.takeRetainedValue() as String
        return str.isEmpty ? nil : str
    }

    static func objectList(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = addr(sel)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
