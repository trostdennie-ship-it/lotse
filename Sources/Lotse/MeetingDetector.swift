import AppKit
import CoreAudio
import CoreMediaIO

/// Erkennt ohne zusaetzliche Berechtigung, ob der Nutzer (1) in einem Call ist und (2) vermutlich den
/// Bildschirm teilt. Alle Callbacks und Zustaende laufen auf dem Main-Thread.
///  - inCall: CoreAudio-Prozessobjekte (macOS 14+): "Prozess X nimmt gerade Audio auf" je Bundle-ID,
///    dazu Kamera-in-Benutzung (CoreMediaIO). Reine Property-Listener, kein Polling, kein TCC-Prompt.
///  - sharingScreen: Best effort. Fenster-Heuristik (Besitzer + Layer + Groesse, ohne Fenstertitel) und
///    optional die private Funktion CGSIsScreenWatcherPresent. Fenster-Scan nur waehrend eines Calls.
final class MeetingDetector {
    /// (inCall, sharingScreen), nur bei Aenderung, auf dem Main-Thread.
    var onChange: ((Bool, Bool) -> Void)?
    /// Weiches Signal von aussen, z. B. "Kalendertermin mit Meeting-Link laeuft gerade".
    var calendarHint: () -> Bool = { false }
    /// Private SkyLight-Funktion zusaetzlich abfragen (per dlsym, fehlt sie, passiert nichts).
    var usePrivateScreenWatcherAPI = true

    private(set) var inCall = false
    private(set) var sharingScreen = false
    /// Bundle-IDs, die gerade aufnehmen (fuer Diagnose/Feintuning; leer = niemand).
    private(set) var micUsers: Set<String> = []

    /// Prefix-Treffer => Mikrofon-Nutzung zaehlt sofort als Call.
    var callApps: [String] = [
        "us.zoom.", "com.microsoft.teams", "com.tinyspeck.slackmacgap", "com.apple.FaceTime",
        "com.apple.avconferenced", "com.cisco.webex", "Cisco-Systems.Spark", "net.whatsapp.WhatsApp",
        "com.hnc.Discord", "com.tdesktop.Telegram", "org.whispersystems.signal-desktop",
    ]
    /// Browser: Mikrofon zaehlt erst nach `browserGrace` Sekunden oder sofort mit Kalender-Hinweis/Kamera.
    var browserApps: [String] = [
        "com.google.Chrome", "com.apple.Safari", "com.apple.WebKit", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "org.mozilla.firefox", "com.brave.Browser",
    ]
    var browserGrace: TimeInterval = 8
    /// Abfall-Verzoegerung, damit Geraetewechsel/Stummschalten nicht flackern.
    var releaseDelay: TimeInterval = 4
    /// Fenster-Scan nur waehrend eines Calls (alle `scanInterval` s). Ausserhalb eines Calls wird hoechstens
    /// die private Screen-Watcher-Funktion gefragt (alle `idleScanInterval` s, nil = gar nicht).
    var scanInterval: TimeInterval = 2
    var idleScanInterval: TimeInterval? = 10

    private let sys = AudioObjectID(kAudioObjectSystemObject)
    private var sysBlocks: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var procBlocks: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var procBundle: [AudioObjectID: String] = [:]
    private var camBlocks: [CMIOObjectID: CMIOObjectPropertyListenerBlock] = [:]
    private var camSysBlock: CMIOObjectPropertyListenerBlock?
    private var wsTokens: [NSObjectProtocol] = []
    private var shareTimer: Timer?
    private var shareTimerInterval: TimeInterval = 0
    private var browserSince: Date?
    private var graceWork: DispatchWorkItem?
    private var releaseWork: DispatchWorkItem?
    private var rawCall = false
    private var started = false

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true
        for sel in [kAudioHardwarePropertyProcessObjectList] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebuildProcesses() }
            var a = Self.addr(sel)
            if AudioObjectAddPropertyListenerBlock(sys, &a, .main, block) == noErr { sysBlocks.append((sel, block)) }
        }
        rebuildProcesses()

        let cb: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebuildCameras() }
        var ca = Self.cmioAddr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        if CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &ca, .main, cb) == noErr { camSysBlock = cb }
        rebuildCameras()

        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            wsTokens.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.evaluate() })
        }
        evaluate()
    }

    func stop() {
        guard started else { return }
        started = false
        for (sel, block) in sysBlocks { var a = Self.addr(sel); AudioObjectRemovePropertyListenerBlock(sys, &a, .main, block) }
        sysBlocks.removeAll()
        for (id, block) in procBlocks { var a = Self.addr(kAudioProcessPropertyIsRunningInput); AudioObjectRemovePropertyListenerBlock(id, &a, .main, block) }
        procBlocks.removeAll(); procBundle.removeAll()
        var ra = Self.cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for (id, block) in camBlocks { CMIOObjectRemovePropertyListenerBlock(id, &ra, .main, block) }
        camBlocks.removeAll()
        if let b = camSysBlock {
            var ca = Self.cmioAddr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            CMIOObjectRemovePropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &ca, .main, b)
        }
        camSysBlock = nil
        wsTokens.forEach(NSWorkspace.shared.notificationCenter.removeObserver); wsTokens.removeAll()
        shareTimer?.invalidate(); shareTimer = nil; shareTimerInterval = 0
        graceWork?.cancel(); graceWork = nil
        releaseWork?.cancel(); releaseWork = nil   // sonst bleibt inCall nach stop()/start() haengen
        browserSince = nil; rawCall = false; micUsers = []
        set(inCall: false, sharing: false)
    }

    // MARK: Mikrofon je Prozess (CoreAudio, macOS 14+)

    private func rebuildProcesses() {
        let current = Set(Self.objectList(sys, kAudioHardwarePropertyProcessObjectList))
        for id in procBlocks.keys where !current.contains(id) {
            // Objekt existiert nicht mehr; Listener ist damit hinfaellig.
            procBlocks[id] = nil; procBundle[id] = nil
        }
        for id in current where procBlocks[id] == nil {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            var a = Self.addr(kAudioProcessPropertyIsRunningInput)
            guard AudioObjectAddPropertyListenerBlock(id, &a, .main, block) == noErr else { continue }
            procBlocks[id] = block
        }
        // Objekt-IDs koennen wiederverwendet werden: Bundle-ID bei jeder Listenaenderung neu lesen.
        for id in procBlocks.keys { procBundle[id] = Self.bundleID(ofProcessObject: id) }
        evaluate()
    }

    private static func bundleID(ofProcessObject id: AudioObjectID) -> String {
        var a = addr(kAudioProcessPropertyBundleID)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &s) == noErr, let s {
            let str = s.takeRetainedValue() as String
            if !str.isEmpty { return str }
        }
        // Kommandozeilen-Prozesse haben keine Bundle-ID: ueber die PID nachschlagen.
        var pa = addr(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        var psize = UInt32(MemoryLayout<pid_t>.size)
        if AudioObjectGetPropertyData(id, &pa, 0, nil, &psize, &pid) == noErr,
           let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier { return b }
        return "pid:\(pid)"
    }

    // MARK: Kamera (CoreMediaIO)

    private func rebuildCameras() {
        let current = Set(Self.cameraIDs())
        for id in camBlocks.keys where !current.contains(id) { camBlocks[id] = nil }
        var ra = Self.cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for id in current where camBlocks[id] == nil {
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.evaluate() }
            if CMIOObjectAddPropertyListenerBlock(id, &ra, .main, block) == noErr { camBlocks[id] = block }
        }
        evaluate()
    }

    private static func cameraIDs() -> [CMIOObjectID] {
        var a = cmioAddr(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &a, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private func cameraRunning() -> Bool {
        var a = Self.cmioAddr(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
        for id in camBlocks.keys {
            var v: UInt32 = 0, used: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &v) == noErr, v != 0 { return true }
        }
        return false
    }

    // MARK: Auswertung

    private func evaluate() {
        guard started else { return }
        var users = Set<String>()
        var a = Self.addr(kAudioProcessPropertyIsRunningInput)
        for (id, bundle) in procBundle {
            var v: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &v) == noErr, v != 0 { users.insert(bundle) }
        }
        micUsers = users

        let callMic = users.contains { Self.matches($0, callApps) }
        let browserMic = users.contains { Self.matches($0, browserApps) }
        let cam = cameraRunning()
        let apps = runningCallApps()

        var browserCounts = false
        graceWork?.cancel(); graceWork = nil
        if browserMic {
            let since = browserSince ?? Date()
            browserSince = since
            let waited = Date().timeIntervalSince(since)
            if cam || calendarHint() || waited >= browserGrace {
                browserCounts = true
            } else {
                let work = DispatchWorkItem { [weak self] in self?.evaluate() }
                graceWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (browserGrace - waited) + 0.05, execute: work)
            }
        } else {
            browserSince = nil
        }

        // Kamera allein zaehlt nur, wenn ueberhaupt eine Call-App oder ein Browser laeuft (nicht Photo Booth).
        rawCall = callMic || browserCounts || (cam && !apps.isEmpty)

        if rawCall {
            releaseWork?.cancel(); releaseWork = nil
            set(inCall: true, sharing: sharingScreen)
        } else if !inCall {
            releaseWork?.cancel(); releaseWork = nil
        } else if inCall, releaseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.releaseWork = nil
                if !self.rawCall { self.set(inCall: false, sharing: self.sharingScreen); self.updateShareTimer() }
            }
            releaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay, execute: work)
        }

        updateShareTimer()
    }

    /// Im Call: voller Scan alle `scanInterval` s. Sonst nur der billige private Aufruf alle `idleScanInterval` s.
    /// (Browser, WhatsApp, Telegram, Slack laufen praktisch immer; "App laeuft" taugt nicht als Schalter.)
    private func updateShareTimer() {
        let want: TimeInterval = inCall ? scanInterval
            : (usePrivateScreenWatcherAPI && Self.screenWatcher != nil ? (idleScanInterval ?? 0) : 0)
        guard want != shareTimerInterval else { return }
        shareTimer?.invalidate(); shareTimer = nil
        shareTimerInterval = want
        guard want > 0 else { set(inCall: inCall, sharing: false); return }
        let t = Timer(timeInterval: want, repeats: true) { [weak self] _ in self?.scanSharing() }
        t.tolerance = want * 0.25
        RunLoop.main.add(t, forMode: .common)
        shareTimer = t
        scanSharing()
    }

    private func set(inCall newCall: Bool, sharing newShare: Bool) {
        guard newCall != inCall || newShare != sharingScreen else { return }
        inCall = newCall; sharingScreen = newShare
        onChange?(newCall, newShare)
    }

    private func runningCallApps() -> [pid_t: String] {
        var out: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications {
            guard let b = app.bundleIdentifier, Self.matches(b, callApps) || Self.matches(b, browserApps) else { continue }
            out[app.processIdentifier] = b
        }
        return out
    }

    // MARK: Bildschirmfreigabe (Heuristik, ohne Screen-Recording-Berechtigung)

    private typealias WatcherFn = @convention(c) () -> Bool
    private static let screenWatcher: WatcherFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(p, to: WatcherFn.self)
    }()

    private func scanSharing() {
        var sharing = false
        if usePrivateScreenWatcherAPI, let fn = Self.screenWatcher, fn() { sharing = true }
        if !sharing, inCall { sharing = overlayWindowPresent() }
        set(inCall: inCall, sharing: sharing)
    }

    /// Ohne Screen-Recording-Berechtigung liefert CGWindowListCopyWindowInfo Besitzer-PID, Layer und
    /// Bounds, aber keine Fenstertitel. Zoom und Teams legen beim Teilen einen Rahmen bzw. ein Overlay
    /// ueber den ganzen Bildschirm: ein Fenster einer Call-App oberhalb der normalen Ebene (Layer > 0),
    /// das einen Bildschirm (fast) vollstaendig abdeckt, oder mehrere duenne Rahmenstreifen.
    private func overlayWindowPresent() -> Bool {
        let apps = runningCallApps()
        guard !apps.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        var strips = 0
        for w in list {
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let bundle = apps[pid] ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  Self.matches(bundle, callApps) || Self.matches(bundle, browserApps),
                  let layer = w[kCGWindowLayer as String] as? Int, layer > 0,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd as CFDictionary)
            else { continue }
            for s in screens {
                let fullW = r.width >= s.width * 0.95, fullH = r.height >= s.height * 0.9
                if fullW && fullH { return true }
                if (fullW && r.height <= 12) || (fullH && r.width <= 12) { strips += 1 }
            }
        }
        return strips >= 2
    }

    // MARK: Helfer

    private static func matches(_ bundle: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { bundle.hasPrefix($0) }
    }

    private static func addr(_ sel: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func cmioAddr(_ sel: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: sel, mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func objectList(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = addr(sel)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}
