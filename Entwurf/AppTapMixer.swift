import AppKit
import CoreAudio
import Darwin

/// Stufe 2 des Mixers (GERUEST, nur typgeprueft, noch nie gelaufen): echte Lautstaerke je App ueber
/// Core-Audio-Prozess-Taps (macOS 14.2+), ohne Treiber.
///
/// Je geregelter App eine unabhaengige Kette:
///   Prozessobjekte der App -> Prozess-Tap (Stereo-Mix) -> privates Aggregatgeraet (Tap + Standard-Ausgabe)
///   -> IOProc kopiert Tap-Eingang mit Gain auf den Ausgang des echten Geraets.
///
/// Leitplanken, damit nie Stille bleibt:
///  - Apps bei 100 % werden gar nicht angefasst (kein Tap).
///  - Neue Kette startet im PROBE-Zustand: Tap UNGEMUTET, IOProc schreibt Stille und misst nur. Erst wenn
///    wirklich Samples ankommen (= Berechtigung erteilt, Format passt), wird auf `mutedWhenTapped`
///    umgeschaltet und selbst wiedergegeben. Ohne Berechtigung liefert der Tap Stille -> es bleibt beim Original.
///  - `mutedWhenTapped`: macOS stummt die App nur, solange der Tap gelesen wird. Stoppt der IOProc
///    (Absturz, Beenden, Haenger), spielt die App von selbst wieder normal.
///  - HUNGER-WAECHTER: liefert ein aktiver (gemuteter) Tap `starveSeconds` lang nur Nullen, obwohl die App
///    laut CoreAudio ausgibt, geht die Kette zurueck in den ungemuteten Probe-Zustand (neuer Tap). Deckt den
///    bekannten macOS-26-Fehler ab, bei dem Taps nach Minuten nur noch Nullen liefern.
///  - Geraetewechsel/Abtastrate/Stream-Layout: der IOProc wird SOFORT auf einer eigenen Queue gestoppt
///    (auch wenn der Main-Thread haengt), danach auf Main sauber abgebaut und verzoegert neu aufgebaut.
///  - Ruhezustand, Benutzerwechsel, coreaudiod-Neustart, Call aktiv, Schalter "Mixer aus": alles abbauen.
///  - Fehlgeschlagene Ketten werden NICHT automatisch neu versucht (kein Aufbau-Schleife); erst wenn der
///    Regler wieder bewegt oder der Mixer neu eingeschaltet wird.
///  - Schleifenbremse: wird binnen 30 s mehr als `maxRebuildsPer30s`-mal wegen Geraeteereignissen abgebaut,
///    schaltet sich der Mixer selbst aus (`onAutoDisabled`).
///  - Ausgabegeraete mit eigenen Eingaengen (USB-Headset, Interface) werden vorerst abgelehnt: sonst oeffnet
///    der IOProc das Mikrofon (TCC-Abfrage, oranger Punkt) und der Tap-Stream waere nicht eindeutig.
/// Alle oeffentlichen Methoden auf dem Main-Thread.
@available(macOS 14.2, *)
final class AppTapMixer {
    enum ChainState: Equatable { case off, probing, active, failed(String) }

    /// Zustand je App-ID geaendert (fuer die Zeile: Regler aktiv / wartet / Fehler).
    var onStateChange: ((String, ChainState) -> Void)?
    /// Der Mixer hat sich wegen einer Abbau-Schleife selbst ausgeschaltet (Schalter im UI zuruecksetzen).
    var onAutoDisabled: ((String) -> Void)?
    var logger: (String) -> Void = { _ in }

    /// Globaler Schalter "Mixer aus": false baut sofort alle Taps ab, Gains bleiben gemerkt.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                blocked.removeAll(); mutedStartFailures.removeAll(); changeTimes.removeAll()
                scheduleRebuild(after: 0.1)
            } else {
                rebuildWork?.cancel(); rebuildWork = nil
                teardownAll("Mixer aus")
            }
        }
    }
    /// Apps, die nie getappt werden (Echo-Unterdrueckung/eigene Audio-Engines gehen sonst kaputt).
    var neverTap: [String] = [
        "com.apple.FaceTime", "us.zoom.", "com.microsoft.teams", "com.tinyspeck.slackmacgap", "com.cisco.webex",
        "net.whatsapp.WhatsApp", "com.hnc.Discord", "com.tdesktop.Telegram", "org.whispersystems.signal-desktop",
        "com.rogueamoeba.", "com.apple.logic10", "com.ableton.live", "com.apple.garageband10",
    ]
    /// Obergrenze fuer Verstaerkung (1 = nur leiser machen, kein Clipping moeglich).
    var maxGain: Float = 1
    /// Aktive Kette ohne ein einziges Sample ungleich Null: nach so vielen Sekunden zurueck auf Durchleitung.
    var starveSeconds: TimeInterval = 6
    /// IOProc ohne Rueckruf: nach so vielen Sekunden Kette abbauen und sperren.
    var stallSeconds: TimeInterval = 2
    var maxRebuildsPer30s = 4
    /// SIGTERM/SIGINT/SIGHUP abfangen und vor dem Ende sauber abbauen. Vor `start()` setzen.
    var handleSignals = true

    private struct RTState {
        var target: Float32 = 1      // Main schreibt, IO-Thread liest (ausgerichtete 32-Bit-Zugriffe)
        var current: Float32 = 1     // nur IO-Thread
        var engaged: UInt32 = 0      // 0 = Probe (Stille schreiben, nur messen), 1 = wiedergeben
        var heardSeq: UInt32 = 0     // IO-Thread zaehlt hoch, wenn ein Puffer Signal enthaelt
        var callbacks: UInt64 = 0    // Lebenszeichen fuer den Waechter
    }

    private final class Chain {
        let appID: String
        let objects: [AudioObjectID]
        let desc: CATapDescription
        let startedMuted: Bool
        var tap = AudioObjectID(kAudioObjectUnknown)
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        var procID: AudioDeviceIOProcID?
        var running = false
        let rt: UnsafeMutablePointer<RTState>
        var lastCallbacks: UInt64 = 0
        var lastCallbackAt: TimeInterval
        var lastHeardSeq: UInt32 = 0
        var lastHeardAt: TimeInterval
        var everHeard = false
        var state: ChainState = .off
        init(appID: String, objects: [AudioObjectID], desc: CATapDescription, startedMuted: Bool) {
            self.appID = appID; self.objects = objects; self.desc = desc; self.startedMuted = startedMuted
            rt = .allocate(capacity: 1); rt.initialize(to: RTState())
            lastCallbackAt = ProcessInfo.processInfo.systemUptime
            lastHeardAt = lastCallbackAt
        }
        deinit { rt.deinitialize(count: 1); rt.deallocate() }
    }

    /// Laufende IOProcs, von der Waechter-Queue aus stoppbar (unabhaengig vom Main-Thread).
    private struct Live { let key: ObjectIdentifier; let aggregate: AudioObjectID; let proc: AudioDeviceIOProcID }

    private let sys = AudioObjectID(kAudioObjectSystemObject)
    private var gains: [String: Float] = [:]                    // gewuenschter Gain je App-ID (fehlt = 1)
    private var known: [String: [AudioObjectID]] = [:]          // aktuell ausgebende Apps -> Prozessobjekte
    private var chains: [String: Chain] = [:]
    private var blocked: [String: String] = [:]                 // App-ID -> Grund; kein automatischer Neuversuch
    private var mutedStartFailures: [String: Int] = [:]
    private var graveyard: [Chain] = []                         // nach coreaudiod-Neustart: RT-Zeiger nie freigeben
    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var sysListeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var devListeners: [(AudioObjectPropertySelector, AudioObjectPropertyListenerBlock)] = []
    private var wsTokens: [NSObjectProtocol] = []
    private var ncTokens: [NSObjectProtocol] = []
    private var signalSources: [DispatchSourceSignal] = []
    private var watchdog: Timer?
    private var rebuildWork: DispatchWorkItem?
    private var pauseReasons: Set<String> = []                  // "sleep", "session", "call"
    private var changeTimes: [TimeInterval] = []
    private var started = false

    private let guardQueue = DispatchQueue(label: "lotse.mixer.guard", qos: .userInteractive)
    private let liveLock = NSLock()
    private var live: [Live] = []                               // nur unter liveLock

    // MARK: Lebenszyklus

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !started else { return }
        started = true
        // Geraeteereignisse kommen auf der Waechter-Queue an: erst sofort alle IOProcs stoppen (App wird
        // dadurch wieder direkt hoerbar), dann die Buchhaltung auf Main.
        let onDefault: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.emergencyStop()
            DispatchQueue.main.async { self?.outputChanged("Standard-Ausgabe gewechselt") }
        }
        let onRestart: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.serviceRestarted() }
        }
        for (sel, block) in [(kAudioHardwarePropertyDefaultOutputDevice, onDefault), (kAudioHardwarePropertyServiceRestarted, onRestart)] {
            var a = Self.addr(sel)
            if AudioObjectAddPropertyListenerBlock(sys, &a, guardQueue, block) == noErr { sysListeners.append((sel, block)) }
        }
        let ws = NSWorkspace.shared.notificationCenter
        func pause(_ name: Notification.Name, _ reason: String) {
            wsTokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setPaused(reason, true) })
        }
        func resume(_ name: Notification.Name, _ reason: String) {
            wsTokens.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.setPaused(reason, false) })
        }
        pause(NSWorkspace.willSleepNotification, "sleep"); resume(NSWorkspace.didWakeNotification, "sleep")
        pause(NSWorkspace.sessionDidResignActiveNotification, "session"); resume(NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ncTokens.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.shutdown()
        })
        // Sauberes Beenden auch bei kill/Abmelden. (Bei SIGKILL/Absturz raeumt coreaudiod Taps und private
        // Aggregate des toten Prozesses selbst ab; `mutedWhenTapped` hebt die Stummschaltung dann ohnehin auf.)
        if handleSignals {
            for sig in [SIGTERM, SIGINT, SIGHUP] {
                signal(sig, SIG_IGN)
                let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                src.setEventHandler { [weak self] in self?.shutdown(); exit(0) }
                src.resume()
                signalSources.append(src)
            }
        }
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.05
        RunLoop.main.add(t, forMode: .common)
        watchdog = t
        bindOutput()
        reconcile()                     // falls isEnabled/Gains schon vor start() gesetzt wurden
    }

    /// Alles abbauen und Listener entfernen. Synchron, darf mehrfach gerufen werden.
    func shutdown() {
        teardownAll("Beenden")
        guard started else { return }
        started = false
        watchdog?.invalidate(); watchdog = nil
        rebuildWork?.cancel(); rebuildWork = nil
        for (sel, b) in sysListeners { var a = Self.addr(sel); AudioObjectRemovePropertyListenerBlock(sys, &a, guardQueue, b) }
        sysListeners.removeAll()
        unbindOutput()
        wsTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        ncTokens.forEach { NotificationCenter.default.removeObserver($0) }
        wsTokens.removeAll(); ncTokens.removeAll()
        signalSources.forEach { $0.cancel() }; signalSources.removeAll()
    }

    // MARK: Steuerung

    /// Von SystemMixer.onChange aus fuettern: welche Apps geben gerade aus, mit welchen Prozessobjekten.
    func update(apps: [(id: String, objects: [AudioObjectID])]) {
        let next = Dictionary(apps.map { ($0.id, $0.objects.sorted()) }, uniquingKeysWith: { a, _ in a })
        guard next != known else { return }          // SystemMixer.onChange feuert auch bei Lautstaerke
        known = next
        reconcile()
    }

    /// Gain 0...maxGain fuer eine App. 1 = Kette abbauen (App spielt wieder direkt).
    /// Hebt eine Fehlersperre fuer diese App auf (bewusster neuer Versuch).
    func setGain(_ gain: Float, forApp id: String) {
        let g = max(0, min(maxGain, gain))
        gains[id] = g >= 0.999 ? nil : g
        let wasBlocked = blocked.removeValue(forKey: id) != nil
        mutedStartFailures[id] = nil
        if wasBlocked { onStateChange?(id, .off) }
        if let c = chains[id], gains[id] != nil { c.rt.pointee.target = g } else { reconcile() }
    }

    func gain(forApp id: String) -> Float { gains[id] ?? 1 }
    func state(forApp id: String) -> ChainState { chains[id]?.state ?? blocked[id].map { .failed($0) } ?? .off }

    /// Waehrend eines Calls (MeetingDetector.inCall) nichts tappen.
    func setCallActive(_ on: Bool) { setPaused("call", on) }

    private func setPaused(_ reason: String, _ on: Bool) {
        if on {
            guard pauseReasons.insert(reason).inserted else { return }
            rebuildWork?.cancel(); rebuildWork = nil
            teardownAll(reason)
        } else {
            guard pauseReasons.remove(reason) != nil, pauseReasons.isEmpty else { return }
            scheduleRebuild(after: 3)
        }
    }

    // MARK: Abgleich Soll/Ist

    private func reconcile() {
        guard started else { return }
        let allowed = isEnabled && pauseReasons.isEmpty && outputUsable()
        for (id, c) in chains {
            if !allowed || gains[id] == nil || known[id] != c.objects { teardown(c, state: .off) }
        }
        guard allowed else { return }
        for (id, g) in gains where chains[id] == nil && blocked[id] == nil {
            guard let objs = known[id], !objs.isEmpty, !neverTap.contains(where: { id.hasPrefix($0) }) else { continue }
            build(appID: id, objects: objs, gain: g, startMuted: false)
        }
    }

    private func scheduleRebuild(after delay: TimeInterval) {
        guard started else { return }
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rebuildWork = nil; self?.bindOutput(); self?.reconcile() }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Aufbau einer Kette

    private func build(appID: String, objects: [AudioObjectID], gain: Float, startMuted: Bool) {
        guard let outUID = Self.string(outputDevice, kAudioDevicePropertyDeviceUID) else { return }

        // 1. Tap: Stereo-Mix genau dieser Prozesse, privat. Probe-Phase ungemutet.
        let desc = CATapDescription(stereoMixdownOfProcesses: objects)
        desc.name = "Lotse Mixer \(appID)"
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = startMuted ? .mutedWhenTapped : .unmuted
        let chain = Chain(appID: appID, objects: objects, desc: desc, startedMuted: startMuted)
        chain.rt.pointee.target = gain
        chain.rt.pointee.current = startMuted ? 0 : gain
        chain.rt.pointee.engaged = startMuted ? 1 : 0

        var tapID = AudioObjectID(kAudioObjectUnknown)
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr, tapID != kAudioObjectUnknown else { fail(chain, "Tap anlegen (\(st))"); return }
        chain.tap = tapID

        // 2. Format pruefen: der IOProc unten kann nur Float32-PCM.
        var fmt = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var fa = Self.addr(kAudioTapPropertyFormat)
        st = AudioObjectGetPropertyData(tapID, &fa, 0, nil, &size, &fmt)
        guard st == noErr, fmt.mFormatID == kAudioFormatLinearPCM, fmt.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              fmt.mBitsPerChannel == 32 else { fail(chain, "Tap-Format"); return }

        // 3. Privates Aggregat: echtes Ausgabegeraet als Haupt-/Taktgeraet, Tap als Eingang mit Driftausgleich.
        //    Bewusst OHNE kAudioAggregateDeviceTapAutoStartKey: damit wuerde der IOProc erst laufen, wenn die
        //    App Ton liefert, und der Rueckruf-Zaehler taugte nicht mehr als Lebenszeichen.
        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Lotse Mixer \(appID)",
            kAudioAggregateDeviceUIDKey: "local.lotse.mixer." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString,
                                               kAudioSubTapDriftCompensationKey: true]],
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        st = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard st == noErr, aggID != kAudioObjectUnknown else { fail(chain, "Aggregat anlegen (\(st))"); return }
        chain.aggregate = aggID

        // 4. IOProc direkt auf dem IO-Thread (queue nil). Der Block haelt nur den rohen Zeiger, nicht self.
        let rt = chain.rt
        var procID: AudioDeviceIOProcID?
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, outData, _ in
            AppTapMixer.render(rt, inData, outData)
        }
        guard st == noErr, let procID else { fail(chain, "IOProc (\(st))"); return }
        chain.procID = procID

        // 5. Start. Hier erscheint beim allerersten Mal die Abfrage "Systemaudio aufnehmen".
        liveLock.lock(); live.append(Live(key: ObjectIdentifier(chain), aggregate: aggID, proc: procID)); liveLock.unlock()
        st = AudioDeviceStart(aggID, procID)
        guard st == noErr else { fail(chain, "Start (\(st))"); return }
        chain.running = true
        let now = ProcessInfo.processInfo.systemUptime
        chain.lastCallbackAt = now; chain.lastHeardAt = now
        chains[appID] = chain
        set(chain, startMuted ? .active : .probing)
    }

    /// Probe bestanden: Tap auf `mutedWhenTapped` umstellen und ab jetzt selbst wiedergeben.
    private func engage(_ c: Chain) {
        c.desc.muteBehavior = .mutedWhenTapped
        var ref: CATapDescription = c.desc
        var a = Self.addr(kAudioTapPropertyDescription)
        var st = withUnsafePointer(to: &ref) {
            AudioObjectSetPropertyData(c.tap, &a, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
        }
        if st == noErr {
            // Zuruecklesen: hat der Tap die Aenderung wirklich uebernommen?
            var back: Unmanaged<CATapDescription>?
            var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
            if AudioObjectGetPropertyData(c.tap, &a, 0, nil, &size, &back) == noErr, let back,
               back.takeUnretainedValue().muteBehavior != .mutedWhenTapped { st = kAudioHardwareUnspecifiedError }
        }
        if st == noErr {
            c.rt.pointee.current = 0            // weich einblenden
            c.rt.pointee.engaged = 1
            c.lastHeardAt = ProcessInfo.processInfo.systemUptime
            set(c, .active)
        } else {
            // Beschreibung nicht aenderbar: Kette neu aufbauen, diesmal gleich gemutet (Berechtigung ist ja belegt).
            // Bleibt die neue Kette stumm, holt der Hunger-Waechter sie nach `starveSeconds` zurueck.
            logger("Mixer: Tap-Beschreibung setzen fehlgeschlagen (\(st)), baue neu")
            let (id, objs, g) = (c.appID, c.objects, c.rt.pointee.target)
            teardown(c, state: .off)
            build(appID: id, objects: objs, gain: g, startMuted: true)
        }
    }

    /// Aktive Kette liefert nur Nullen: zurueck auf Durchleitung, mit frischem ungemutetem Tap neu proben.
    private func starved(_ c: Chain) {
        let (id, objs, g) = (c.appID, c.objects, c.rt.pointee.target)
        logger("Mixer: \(id) liefert keinen Ton mehr ueber den Tap, zurueck auf Durchleitung")
        if c.startedMuted && !c.everHeard {
            mutedStartFailures[id, default: 0] += 1
            if mutedStartFailures[id, default: 0] >= 2 { fail(c, "Tap liefert keinen Ton"); return }
        }
        teardown(c, state: .off)
        if isEnabled, pauseReasons.isEmpty, outputUsable(), gains[id] != nil, known[id] == objs {
            build(appID: id, objects: objs, gain: g, startMuted: false)
        }
    }

    // MARK: Abbau (Reihenfolge wichtig)

    /// `forget`: nach coreaudiod-Neustart sind alle IDs ungueltig (und evtl. neu vergeben) -> nichts zerstoeren.
    private func teardown(_ c: Chain, state: ChainState, forget: Bool = false) {
        liveLock.lock(); live.removeAll { $0.key == ObjectIdentifier(c) }; liveLock.unlock()
        if forget {
            graveyard.append(c)
        } else {
            // 1. IOProc stoppen: ab hier liest niemand mehr den Tap, `mutedWhenTapped` gibt die App wieder frei.
            if let p = c.procID, c.aggregate != kAudioObjectUnknown {
                if c.running { AudioDeviceStop(c.aggregate, p) }
                AudioDeviceDestroyIOProcID(c.aggregate, p)          // 2. IOProc entfernen
            }
            if c.aggregate != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(c.aggregate) }  // 3.
            if c.tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(c.tap) }                   // 4.
            // RT-Zeiger noch kurz am Leben halten, falls ein letzter Rueckruf unterwegs ist.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { _ = c }
        }
        c.running = false; c.procID = nil
        c.aggregate = AudioObjectID(kAudioObjectUnknown); c.tap = AudioObjectID(kAudioObjectUnknown)
        if chains[c.appID] === c { chains[c.appID] = nil }
        set(c, state)
    }

    /// Abbauen und sperren: kein automatischer Neuversuch, bis der Regler bewegt oder der Mixer neu eingeschaltet wird.
    private func fail(_ c: Chain, _ what: String) {
        logger("Mixer: \(c.appID): \(what)")
        blocked[c.appID] = what
        teardown(c, state: .failed(what))
    }

    private func teardownAll(_ reason: String, forget: Bool = false) {
        if !chains.isEmpty { logger("Mixer: alle Taps ab (\(reason))") }
        for c in Array(chains.values) { teardown(c, state: .off, forget: forget) }
    }

    /// Von jeder Queue: alle laufenden IOProcs sofort stoppen. Danach liest niemand mehr die Taps,
    /// die Apps spielen wieder direkt. Die Buchhaltung holt Main spaeter nach.
    private func emergencyStop() {
        liveLock.lock()
        for l in live { AudioDeviceStop(l.aggregate, l.proc) }
        liveLock.unlock()
    }

    private func set(_ c: Chain, _ s: ChainState) {
        guard c.state != s else { return }
        c.state = s
        onStateChange?(c.appID, s)
    }

    // MARK: Waechter

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        for c in Array(chains.values) {
            let n = c.rt.pointee.callbacks
            if n != c.lastCallbacks { c.lastCallbacks = n; c.lastCallbackAt = now }
            else if now - c.lastCallbackAt > stallSeconds { fail(c, "IOProc steht"); continue }
            let h = c.rt.pointee.heardSeq
            if h != c.lastHeardSeq { c.lastHeardSeq = h; c.lastHeardAt = now; c.everHeard = true }
            switch c.state {
            case .probing: if c.everHeard { engage(c) }
            case .active: if now - c.lastHeardAt > starveSeconds { starved(c) }
            default: break
            }
        }
    }

    // MARK: Ausgabegeraet

    private func outputChanged(_ why: String) {
        guard started else { return }
        if !chains.isEmpty {
            // Schleifenbremse: loest unser eigener Aufbau das Ereignis aus, wuerde sonst endlos auf-/abgebaut.
            let now = ProcessInfo.processInfo.systemUptime
            changeTimes = changeTimes.filter { now - $0 < 30 } + [now]
            if changeTimes.count > maxRebuildsPer30s {
                let msg = "zu viele Geraeteereignisse (\(why)), Mixer schaltet sich aus"
                logger("Mixer: \(msg)")
                isEnabled = false               // baut alles ab
                onAutoDisabled?(msg)
                return
            }
        }
        teardownAll(why)
        scheduleRebuild(after: 1.5)      // Bluetooth/AirPods brauchen einen Moment, bis das Format steht
    }

    private func serviceRestarted() {
        guard started else { return }
        teardownAll("coreaudiod neu gestartet", forget: true)
        devListeners.removeAll(); outputDevice = AudioObjectID(kAudioObjectUnknown)
        scheduleRebuild(after: 3)
    }

    private func bindOutput() {
        guard started else { return }
        unbindOutput()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = Self.addr(kAudioHardwarePropertyDefaultOutputDevice)
        guard AudioObjectGetPropertyData(sys, &a, 0, nil, &size, &id) == noErr, id != kAudioObjectUnknown else { return }
        outputDevice = id
        for sel in [kAudioDevicePropertyNominalSampleRate, kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyStreamConfiguration] {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.emergencyStop()
                DispatchQueue.main.async { self?.outputChanged("Ausgabegeraet geaendert") }
            }
            var da = Self.addr(sel, sel == kAudioDevicePropertyStreamConfiguration ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal)
            if AudioObjectAddPropertyListenerBlock(id, &da, guardQueue, block) == noErr { devListeners.append((sel, block)) }
        }
    }

    private func unbindOutput() {
        for (sel, b) in devListeners {
            var da = Self.addr(sel, sel == kAudioDevicePropertyStreamConfiguration ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal)
            AudioObjectRemovePropertyListenerBlock(outputDevice, &da, guardQueue, b)
        }
        devListeners.removeAll()
        outputDevice = AudioObjectID(kAudioObjectUnknown)
    }

    /// Nur auf "echten" reinen Ausgabegeraeten arbeiten. AirPlay (2 s Puffer), Aggregate/Mehrfachausgabe,
    /// virtuelle Geraete (BlackHole, Loopback, Teams Audio), Geraete mit eigenen Eingaengen und Geraete im
    /// Hog-Modus bleiben unangetastet.
    private func outputUsable() -> Bool {
        guard outputDevice != kAudioObjectUnknown else { return false }
        var t: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = Self.addr(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &t) == noErr else { return false }
        guard [kAudioDeviceTransportTypeBuiltIn, kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeBluetooth,
               kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort,
               kAudioDeviceTransportTypeThunderbolt, kAudioDeviceTransportTypeFireWire].contains(t) else { return false }
        // Eigene Eingangsstreams? Dann waere der Tap nicht der einzige Eingang des Aggregats.
        var ia = Self.addr(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput)
        var isize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(outputDevice, &ia, 0, nil, &isize) == noErr, isize == 0 else { return false }
        var hog: pid_t = -1
        size = UInt32(MemoryLayout<pid_t>.size)
        var ha = Self.addr(kAudioDevicePropertyHogMode)
        if AudioObjectGetPropertyData(outputDevice, &ha, 0, nil, &size, &hog) == noErr, hog != -1, hog != getpid() { return false }
        return true
    }

    // MARK: Echtzeit (IO-Thread): keine Allokation, kein Lock, kein ObjC, kein Logging

    private static func render(_ rt: UnsafeMutablePointer<RTState>,
                               _ inData: UnsafePointer<AudioBufferList>,
                               _ outData: UnsafeMutablePointer<AudioBufferList>) {
        rt.pointee.callbacks &+= 1
        let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outs = UnsafeMutableAudioBufferListPointer(outData)
        // Ausgang immer zuerst nullen: was auch passiert, wir geben nie Muell aus.
        for b in outs { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
        guard ins.count > 0, outs.count > 0 else { return }

        // Tap-Stream = letzter Eingangsstream des Aggregats (das Ausgabegeraet hat laut outputUsable() keine
        // eigenen Eingaenge). Interleaved Stereo in einem Puffer oder zwei Mono-Puffer.
        let last = ins[ins.count - 1]
        var inL: UnsafeMutablePointer<Float32>?, inR: UnsafeMutablePointer<Float32>?
        var inStride = 1, inFrames = 0
        if last.mNumberChannels >= 2, let p = last.mData {
            let ch = Int(last.mNumberChannels)
            inL = p.assumingMemoryBound(to: Float32.self); inR = inL! + 1
            inStride = ch; inFrames = Int(last.mDataByteSize) / (4 * ch)
        } else if last.mNumberChannels == 1, let p = last.mData {
            inR = p.assumingMemoryBound(to: Float32.self); inL = inR
            inFrames = Int(last.mDataByteSize) / 4
            if ins.count >= 2, ins[ins.count - 2].mNumberChannels == 1, let q = ins[ins.count - 2].mData,
               Int(ins[ins.count - 2].mDataByteSize) / 4 >= inFrames {
                inL = q.assumingMemoryBound(to: Float32.self)
            }
        }
        guard let srcL = inL, let srcR = inR, inFrames > 0 else { return }

        // Lebenszeichen "Tap liefert Signal" (Probe UND Betrieb): grob jedes 8. Frame pruefen.
        var i = 0
        while i < inFrames {
            if abs(srcL[i * inStride]) > 1e-5 || abs(srcR[i * inStride]) > 1e-5 { rt.pointee.heardSeq &+= 1; break }
            i += 8
        }
        // Probe: nur messen, nichts ausgeben (die App spielt noch selbst).
        if rt.pointee.engaged == 0 { return }

        // Ausgang: erste zwei Kanaele des Geraets (interleaved in Puffer 0 oder zwei Mono-Puffer).
        let o0 = outs[0]
        var outL: UnsafeMutablePointer<Float32>?, outR: UnsafeMutablePointer<Float32>?
        var outStride = 1, outFrames = 0
        if o0.mNumberChannels >= 2, let p = o0.mData {
            let ch = Int(o0.mNumberChannels)
            outL = p.assumingMemoryBound(to: Float32.self); outR = outL! + 1
            outStride = ch; outFrames = Int(o0.mDataByteSize) / (4 * ch)
        } else if o0.mNumberChannels == 1, let p = o0.mData {
            outL = p.assumingMemoryBound(to: Float32.self)
            outFrames = Int(o0.mDataByteSize) / 4
            if outs.count >= 2, outs[1].mNumberChannels == 1, let q = outs[1].mData,
               Int(outs[1].mDataByteSize) / 4 >= outFrames { outR = q.assumingMemoryBound(to: Float32.self) }
        }
        guard let dstL = outL, outFrames > 0 else { return }

        // Lineare Rampe ueber den Puffer (kein Knacksen bei Reglerbewegung).
        let frames = min(inFrames, outFrames)
        var g = rt.pointee.current
        let target = rt.pointee.target
        let step = (target - g) / Float32(frames)
        if let dstR = outR {
            for i in 0..<frames {
                g += step
                dstL[i * outStride] = srcL[i * inStride] * g
                dstR[i * outStride] = srcR[i * inStride] * g
            }
        } else {
            for i in 0..<frames {
                g += step
                dstL[i * outStride] = (srcL[i * inStride] + srcR[i * inStride]) * 0.5 * g
            }
        }
        rt.pointee.current = target
    }

    // MARK: Helfer

    /// PID -> CoreAudio-Prozessobjekt (kAudioObjectUnknown, wenn der Prozess kein Audio-Client ist).
    static func processObject(forPID pid: pid_t) -> AudioObjectID {
        var a = addr(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var p = pid
        var obj = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let st = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                            UInt32(MemoryLayout<pid_t>.size), &p, &size, &obj)
        return st == noErr ? obj : AudioObjectID(kAudioObjectUnknown)
    }

    private static func addr(_ sel: AudioObjectPropertySelector,
                             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func string(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var a = addr(sel)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }
}
