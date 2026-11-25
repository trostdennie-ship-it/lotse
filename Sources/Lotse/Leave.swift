import AppKit
import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - „Losgehen": rechtzeitig zum Aufbruch erinnern

enum TravelMode: String, CaseIterable {
    case driving, transit, walking
    var symbol: String { self == .driving ? "car.fill" : self == .transit ? "tram.fill" : "figure.walk" }
    var title: String { self == .driving ? "Auto" : self == .transit ? "ÖPNV" : "zu Fuß" }
    var mapsParam: String { rawValue }
}

/// Ein aufgelöster Termin-Ort. `short` ist die Kurzform für die Karte (Stadtteil oder Ort), nie die volle Adresse.
struct LeavePlace {
    var address: String
    var short: String
    var hasStreet: Bool
    var isPOI: Bool
    var metersAway: Double
}

/// Fahrzeiten und Losgehzeit für einen Termin.
struct LeavePlan: Equatable {
    var eventID: String
    var leaveAt: Date
    var times: [TravelMode: TimeInterval]
    var meters: Double
    var mode: TravelMode
}

/// Was die Losgehen-Karte zeigt.
struct LeaveCard {
    var event: CalEvent
    var plan: LeavePlan
    var place: LeavePlace
}

enum Leave {
    /// Wie weit voraus Lotse Termine betrachtet.
    static let horizon: TimeInterval = 3 * 3600

    /// Orte, die keine Anfahrt bedeuten: Räume, Etagen, Videocalls, Verweise.
    private static let notAPlace = try! NSRegularExpression(
        pattern: #"^\s*(raum|room|besprechungsraum|meeting ?room)\b|\b(\d+\.\s*og|og|etage|stock(werk)?|floor|teams|zoom|google meet|webex|skype|online|virtuell|virtual|telefon|anruf|call|siehe|see invite|tbd|tba)\b"#,
        options: [.caseInsensitive])

    static func isCandidate(_ e: CalEvent, now: Date) -> Bool {
        guard !e.allDay, e.joinURL == nil else { return false }
        let place = e.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return false }
        let secs = e.start.timeIntervalSince(now)
        guard secs > 0, secs <= horizon else { return false }
        return notAPlace.firstMatch(in: place, range: NSRange(place.startIndex..., in: place)) == nil
    }

    /// Ob eine Losgehen-Karte noch gezeigt werden darf: Sie gehört zum Termin der Meldung, und der hat noch nicht begonnen.
    static func cardValid(_ card: LeaveCard?, eventID: String?, now: Date) -> Bool {
        guard let card, card.event.id == eventID else { return false }
        return now < card.event.start
    }

    static func isRealPlace(_ p: LeavePlace) -> Bool { p.hasStreet || p.isPOI }

    static func tooClose(meters: Double, travel: TimeInterval) -> Bool { meters < 500 || travel < 600 }

    static func leaveAt(start: Date, travel: TimeInterval) -> Date { start.addingTimeInterval(-travel) }

    static func cardAt(_ plan: LeavePlan) -> Date { plan.leaveAt.addingTimeInterval(-300) }

    static func shouldShow(_ plan: LeavePlan, start: Date, now: Date, shown: Bool) -> Bool {
        !shown && now >= cardAt(plan) && now < start
    }

    static func headline(leaveAt: Date, start: Date, end: Date, now: Date) -> String {
        let secs = leaveAt.timeIntervalSince(now)
        if secs > 0 {
            let mins = Int((secs / 60).rounded(.up))
            return "LOSGEHEN IN \(mins) MIN · TERMIN \(Fmt.time.string(from: start)) – \(Fmt.time.string(from: end))"
        }
        let late = Int((-secs / 60).rounded(.down))
        return late < 1 ? "JETZT LOSGEHEN" : "DU BIST \(late) MIN SPÄT DRAN"
    }

    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        let km = (meters / 100).rounded() / 10
        return String(format: "%.1f km", km).replacingOccurrences(of: ".", with: ",")
    }

    static func duration(_ t: TimeInterval) -> String {
        let mins = Int((t / 60).rounded())
        return mins < 60 ? "\(mins) Min" : mins % 60 == 0 ? "\(mins / 60) Std" : "\(mins / 60) Std \(mins % 60) Min"
    }

    static func mapsURL(address: String, mode: TravelMode) -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/dir/")
        c?.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: address),
                         URLQueryItem(name: "travelmode", value: mode.mapsParam)]
        let q = c?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        c?.percentEncodedQuery = q
        return c?.url
    }

    /// Ob jetzt die Erlaubnis-Karte kommen darf: nach dem Assistenten, mit Anlass, höchstens einmal am Tag, nie nach Ablehnung.
    static func askDue(now: Date, lastAsked: Date?, denied: Bool, onboarded: Bool, hasCandidate: Bool) -> Bool {
        guard onboarded, !denied, hasCandidate else { return false }
        guard let lastAsked else { return true }
        return !Calendar.current.isDate(lastAsked, inSameDayAs: now)
    }
}

extension Leave {
    static func selfTest() -> [String] {
        var bad: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { bad.append("Losgehen: \(what)") } }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .current
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 13, minute: 30))!
        func at(_ h: Int, _ m: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: h, minute: m))! }
        func ev(_ place: String, start: Date, join: URL? = nil, allDay: Bool = false) -> CalEvent {
            CalEvent(id: "t", title: "Kundentermin", start: start, end: start.addingTimeInterval(3600), color: .clear,
                     joinURL: join, allDay: allDay, place: place)
        }
        let street = "Musterstraße 1, Hamburg"
        check(isCandidate(ev(street, start: now.addingTimeInterval(7200)), now: now), "Adresse in 2 Std ist ein Fall")
        check(!isCandidate(ev(street, start: now.addingTimeInterval(7200), join: URL(string: "https://zoom.us/j/1")), now: now), "mit Meeting-Link kein Fall")
        check(!isCandidate(ev(street, start: now.addingTimeInterval(7200), allDay: true), now: now), "ganztägig kein Fall")
        check(!isCandidate(ev(street, start: now.addingTimeInterval(4 * 3600)), now: now), "in 4 Std noch kein Fall")
        check(!isCandidate(ev(street, start: now.addingTimeInterval(-60)), now: now), "schon begonnen kein Fall")
        check(!isCandidate(ev("Raum Elbe, 3. OG", start: now.addingTimeInterval(7200)), now: now), "Raumangabe kein Fall")
        check(!isCandidate(ev("Microsoft Teams-Besprechung", start: now.addingTimeInterval(7200)), now: now), "Teams kein Fall")
        check(!isCandidate(ev("", start: now.addingTimeInterval(7200)), now: now), "ohne Ort kein Fall")
        check(isCandidate(ev("Hamburg Hauptbahnhof", start: now.addingTimeInterval(7200)), now: now), "Hauptbahnhof ist ein Fall")
        check(isCandidate(ev("Ostbahnhof Berlin", start: now.addingTimeInterval(7200)), now: now), "Ostbahnhof ist ein Fall")
        check(!isCandidate(ev("Zoom", start: now.addingTimeInterval(7200)), now: now), "Zoom kein Fall")

        let demo = LeaveCard.demo(now: now, minutesToLeave: 5)
        check(cardValid(demo, eventID: demo.event.id, now: now), "gültige Karte")
        check(!cardValid(nil, eventID: demo.event.id, now: now), "ohne Karte nicht gültig")
        check(!cardValid(demo, eventID: "anderer", now: now), "andere Termin-ID nicht gültig")
        check(!cardValid(demo, eventID: demo.event.id, now: demo.event.start), "nach Beginn nicht gültig")

        func place(street: Bool, poi: Bool) -> LeavePlace { LeavePlace(address: "x", short: "x", hasStreet: street, isPOI: poi, metersAway: 1000) }
        check(isRealPlace(place(street: true, poi: false)), "Straße zählt")
        check(isRealPlace(place(street: false, poi: true)), "benannter Ort zählt")
        check(!isRealPlace(place(street: false, poi: false)), "reine Stadt zählt nicht")

        check(tooClose(meters: 400, travel: 1200), "unter 500 m zu nah")
        check(tooClose(meters: 800, travel: 540), "unter 10 Min zu nah")
        check(!tooClose(meters: 800, travel: 900), "800 m / 15 Min nicht zu nah")

        let start = at(14, 0)
        check(leaveAt(start: start, travel: 25 * 60) == at(13, 35), "Losgehzeit 13:35")
        let plan = LeavePlan(eventID: "t", leaveAt: at(13, 35), times: [.driving: 1500], meters: 7400, mode: .driving)
        check(cardAt(plan) == at(13, 30), "Karte um 13:30")
        check(!shouldShow(plan, start: start, now: at(13, 29), shown: false), "13:29 noch keine Karte")
        check(shouldShow(plan, start: start, now: at(13, 30), shown: false), "13:30 Karte")
        check(shouldShow(plan, start: start, now: at(13, 50), shown: false), "spät noch Karte")
        check(!shouldShow(plan, start: start, now: at(14, 0), shown: false), "nach Beginn keine Karte")
        check(!shouldShow(plan, start: start, now: at(13, 30), shown: true), "nur einmal")

        let end = at(15, 0)
        check(headline(leaveAt: at(13, 35), start: start, end: end, now: at(13, 30)) == "LOSGEHEN IN 5 MIN · TERMIN 14:00 – 15:00", "Kennzeile vorher")
        check(headline(leaveAt: at(13, 35), start: start, end: end, now: at(13, 35)) == "JETZT LOSGEHEN", "Kennzeile jetzt")
        check(headline(leaveAt: at(13, 35), start: start, end: end, now: at(13, 42)) == "DU BIST 7 MIN SPÄT DRAN", "Kennzeile spät")

        check(distance(7400) == "7,4 km", "Entfernung km: \(distance(7400))")
        check(distance(850) == "850 m", "Entfernung m: \(distance(850))")
        check(duration(1080) == "18 Min", "Dauer Min")
        check(duration(3900) == "1 Std 5 Min", "Dauer Std")

        let addr = "Musterstraße 1, 20357 Hamburg"
        if let u = mapsURL(address: addr, mode: .transit), let c = URLComponents(url: u, resolvingAgainstBaseURL: false) {
            let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            check(c.host == "www.google.com" && c.path == "/maps/dir/", "Maps-Link Adresse")
            check(q["api"] == "1" && q["destination"] == addr && q["travelmode"] == "transit", "Maps-Link Werte")
        } else { check(false, "Maps-Link fehlt") }

        let yesterday = now.addingTimeInterval(-86400)
        check(!askDue(now: now, lastAsked: nil, denied: false, onboarded: false, hasCandidate: true), "nie vor dem Assistenten")
        check(!askDue(now: now, lastAsked: nil, denied: true, onboarded: true, hasCandidate: true), "nach Ablehnung nie")
        check(!askDue(now: now, lastAsked: nil, denied: false, onboarded: true, hasCandidate: false), "ohne Anlass nie")
        check(!askDue(now: now, lastAsked: now.addingTimeInterval(-7200), denied: false, onboarded: true, hasCandidate: true), "heute schon gefragt")
        check(askDue(now: now, lastAsked: yesterday, denied: false, onboarded: true, hasCandidate: true), "gestern gefragt → wieder")
        check(askDue(now: now, lastAsked: nil, denied: false, onboarded: true, hasCandidate: true), "nie gefragt → fragen")
        return bad
    }
}

// MARK: - Wächter: Standort, Fahrzeiten, Zeitpunkt der Karte

final class LeaveWatcher: NSObject, CLLocationManagerDelegate {
    private let model: IslandModel
    private let manager = CLLocationManager()
    private var location: CLLocation?
    private var locatedAt: Date?
    private var locating = false
    /// Ortstext → aufgelöster Ort (nil = kein echter Ort; Fehlschläge werden auch gemerkt).
    private var places: [String: LeavePlace?] = [:]
    private var resolving = Set<String>()
    private var plans: [String: LeavePlan] = [:]
    private var distances: [String: [TravelMode: Double]] = [:]
    private var asked: [String: Date] = [:]
    private var shown = Set<String>()
    /// „Später": Termin-ID → Zeitpunkt, zu dem die Karte noch einmal kommt.
    private var again: [String: Date] = [:]
    private var timer: Timer?
    private var exact: Timer?
    private var bag: AnyCancellable?

    init(model: IslandModel) { self.model = model }

    private var chosenMode: TravelMode {
        TravelMode(rawValue: UserDefaults.standard.string(forKey: "leaveMode") ?? "") ?? .driving
    }

    private var authorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedAlways || s == .authorized
    }

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        model.locationDenied = manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        bag = model.$events.dropFirst().debounce(for: .seconds(1), scheduler: RunLoop.main).sink { [weak self] _ in self?.tick() }
        model.leaveLater = { [weak self] in self?.later() }
        model.leavePick = { [weak self] m in self?.pick(m) }
        model.leaveAllow = { [weak self] in
            guard let self else { return }
            self.model.dismissPeek()
            log("Losgehen: Standort angefragt")
            self.manager.requestWhenInUseAuthorization()
        }
        model.leaveNotNow = { [weak self] in self?.model.dismissPeek() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.tick() }
    }

    func tick() {
        let now = Date()
        guard model.leaveOn else { forget(); return }
        let cands = model.events.filter { Leave.isCandidate($0, now: now) }
        let ids = Set(cands.map(\.id))
        // Termine, die keine mehr sind (verschoben, gelöscht, begonnen), vergessen.
        plans = plans.filter { ids.contains($0.key) }
        again = again.filter { ids.contains($0.key) }
        model.leaveSuppressed = model.leaveSuppressed.intersection(ids)
        if let c = model.leave, !ids.contains(c.event.id) {
            model.leave = nil
            if model.peekNotice?.card == "leave" { model.dismissPeek() }
        }
        guard !cands.isEmpty else { exact?.invalidate(); return }

        switch manager.authorizationStatus {
        case .notDetermined:
            let last = UserDefaults.standard.object(forKey: "leaveAskedAt") as? Date
            if Leave.askDue(now: now, lastAsked: last, denied: false, onboarded: OnboardingWindow.done, hasCandidate: true) {
                UserDefaults.standard.set(now, forKey: "leaveAskedAt")
                log("Losgehen: frage nach dem Standort")
                model.post(Notice(kind: .info, appName: "Losgehen", title: "Standort für „Losgehen“", body: "", card: "leave-ask", hold: 60))
            }
            return
        case .denied, .restricted:
            model.locationDenied = true; return
        default: break
        }
        model.locationDenied = false
        guard authorized else { return }
        if location == nil || now.timeIntervalSince(locatedAt ?? .distantPast) > 600 {
            if !locating { locating = true; manager.requestLocation() }
            if location == nil { return }
        }
        for e in cands {
            let key = e.place.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let resolved = places[key] else { resolve(key); continue }
            guard let place = resolved else { continue }
            if now.timeIntervalSince(asked[e.id] ?? .distantPast) > 600 { route(e, place) }
        }
        evaluate()
    }

    // MARK: Ort und Fahrzeiten

    private func resolve(_ text: String) {
        guard !resolving.contains(text) else { return }
        resolving.insert(text)
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        if let l = location { req.region = MKCoordinateRegion(center: l.coordinate, latitudinalMeters: 200_000, longitudinalMeters: 200_000) }
        MKLocalSearch(request: req).start { [weak self] resp, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.resolving.remove(text)
                // Ohne Antwort (kein Netz) nicht merken – beim nächsten Durchgang neu versuchen.
                guard let resp else { if error == nil { self.places[text] = .some(nil) }; return }
                guard let item = resp.mapItems.first else { self.places[text] = .some(nil); return }
                let pm = item.placemark
                let meters = self.location.map { $0.distance(from: CLLocation(latitude: pm.coordinate.latitude, longitude: pm.coordinate.longitude)) } ?? .infinity
                let place = LeavePlace(address: text,
                                       short: pm.subLocality ?? pm.locality ?? item.name ?? "",
                                       hasStreet: pm.thoroughfare != nil,
                                       isPOI: item.pointOfInterestCategory != nil,
                                       metersAway: meters)
                self.coords[text] = pm.coordinate
                self.places[text] = Leave.isRealPlace(place) ? .some(place) : .some(nil)
                self.tick()
            }
        }
    }

    private func route(_ e: CalEvent, _ place: LeavePlace) {
        guard let here = location, let to = placeCoordinate(place) else { return }
        asked[e.id] = Date()
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: to))
        let from = MKMapItem(placemark: MKPlacemark(coordinate: here.coordinate))
        var times: [TravelMode: TimeInterval] = [:], meters: [TravelMode: Double] = [:]
        let group = DispatchGroup()
        for mode in TravelMode.allCases {
            let r = MKDirections.Request()
            r.source = from; r.destination = dest; r.arrivalDate = e.start
            r.transportType = mode == .driving ? .automobile : mode == .transit ? .transit : .walking
            group.enter()
            MKDirections(request: r).calculateETA { resp, _ in
                DispatchQueue.main.async {
                    if let resp, resp.expectedTravelTime > 0 { times[mode] = resp.expectedTravelTime; meters[mode] = resp.distance }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in self?.planned(e, place, times, meters) }
    }

    /// Koordinate des Ziels (aus dem Zwischenspeicher der Suche).
    private var coords: [String: CLLocationCoordinate2D] = [:]
    private func placeCoordinate(_ p: LeavePlace) -> CLLocationCoordinate2D? { coords[p.address] }

    private func planned(_ e: CalEvent, _ place: LeavePlace, _ times: [TravelMode: TimeInterval], _ meters: [TravelMode: Double]) {
        let mode = times[chosenMode] != nil ? chosenMode : TravelMode.allCases.first { times[$0] != nil }
        guard let mode, let travel = times[mode], travel <= Leave.horizon,
              !Leave.tooClose(meters: place.metersAway, travel: travel) else {
            plans[e.id] = nil; model.leaveSuppressed.remove(e.id); return
        }
        let plan = LeavePlan(eventID: e.id, leaveAt: Leave.leaveAt(start: e.start, travel: travel), times: times,
                             meters: meters[mode] ?? place.metersAway, mode: mode)
        distances[e.id] = meters
        if plans[e.id] == nil {
            log("Losgehen: Termin in \(Int(e.start.timeIntervalSinceNow / 60)) Min, Fahrzeit \(Int(travel / 60)) Min")
        }
        plans[e.id] = plan
        model.leaveSuppressed.insert(e.id)
        if model.leave?.event.id == e.id { model.leave = LeaveCard(event: e, plan: plan, place: place) }
        evaluate()
    }

    // MARK: Karte zeigen

    private func evaluate() {
        let now = Date()
        for (id, plan) in plans {
            guard let e = model.events.first(where: { $0.id == id }),
                  let place = places[e.place.trimmingCharacters(in: .whitespacesAndNewlines)] ?? nil else { continue }
            let due = again[id].map { now >= $0 && now < e.start } ?? false
            // Kam die normale Erinnerung fünf Minuten vorher schon (Plan zu spät fertig), keine zweite Karte.
            if !shown.contains(id), model.remindedEarly.contains(id) { shown.insert(id); continue }
            if due || Leave.shouldShow(plan, start: e.start, now: now, shown: shown.contains(id)) {
                again[id] = nil
                shown.insert(id)
                show(e, plan, place)
            }
        }
        schedule()
    }

    private func show(_ e: CalEvent, _ plan: LeavePlan, _ place: LeavePlace) {
        model.leave = LeaveCard(event: e, plan: plan, place: place)
        log("Losgehen: Karte für Termin in \(Int(e.start.timeIntervalSinceNow / 60)) Min")
        model.post(Notice(kind: .info, appName: "Losgehen", title: e.title, body: "", card: "leave", hold: 120, event: e))
    }

    /// Weckt genau dann, wenn die nächste Karte fällig ist.
    private func schedule() {
        let now = Date()
        let times = plans.values.filter { !shown.contains($0.eventID) }.map(Leave.cardAt) + Array(again.values)
        exact?.invalidate()
        guard let next = times.filter({ $0 > now }).min(), next.timeIntervalSince(now) < 3 * 3600 else { return }
        exact = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.3, repeats: false) { [weak self] _ in self?.evaluate() }
    }

    private func later() {
        model.dismissPeek()
        guard let c = model.leave else { return }
        if Date() < c.plan.leaveAt { again[c.event.id] = c.plan.leaveAt; schedule() }
    }

    private func pick(_ mode: TravelMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "leaveMode")
        guard var c = model.leave, let travel = c.plan.times[mode] else { return }
        c.plan.mode = mode
        c.plan.leaveAt = Leave.leaveAt(start: c.event.start, travel: travel)
        c.plan.meters = distances[c.event.id]?[mode] ?? c.plan.meters
        plans[c.event.id] = c.plan
        model.leave = c
        schedule()
    }

    private func forget() {
        plans = [:]; again = [:]; model.leaveSuppressed = []; exact?.invalidate()
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.locationDenied = m.authorizationStatus == .denied || m.authorizationStatus == .restricted
            if self.authorized { log("Losgehen: Standort erlaubt"); self.tick() }
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let l = locs.last else { return }
            self.locating = false; self.location = l; self.locatedAt = Date(); self.tick()
        }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in self?.locating = false }
    }
}

// MARK: - Die Karten

struct LeaveView: View {
    @ObservedObject var model: IslandModel
    let card: LeaveCard

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let now = FilmState.active ? model.now : ctx.date
            let late = now >= card.plan.leaveAt
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text(Leave.headline(leaveAt: card.plan.leaveAt, start: card.event.start, end: card.event.end, now: now))
                        .font(Theme.font(10, .semibold)).tracking(0.7).monospacedDigit().foregroundStyle(Theme.accent)
                }
                Text(card.event.label(discreet: model.discreet)).font(Theme.font(18, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                HStack(spacing: 8) {
                    ForEach(TravelMode.allCases.filter { card.plan.times[$0] != nil }, id: \.self) { m in
                        Button { model.leavePick?(m) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: m.symbol).font(.system(size: 11, weight: .semibold))
                                Text(Leave.duration(card.plan.times[m] ?? 0)).monospacedDigit()
                            }
                        }
                        .buttonStyle(CapsuleStyle(primary: m == card.plan.mode, compact: true))
                        .help("Mit \(m.title) – als Verkehrsmittel wählen")
                        .accessibilityLabel("\(m.title), \(Leave.duration(card.plan.times[m] ?? 0))")
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11)).foregroundStyle(Theme.faint)
                    Text([card.place.short, Leave.distance(card.plan.meters)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("Später") { model.leaveLater?() }.buttonStyle(CapsuleStyle(compact: true))
                        .help(late ? "Karte schließen" : "Zur Losgehzeit noch einmal erinnern")
                    Button("Route in Google Maps") {
                        if let u = Leave.mapsURL(address: card.place.address, mode: card.plan.mode) { NSWorkspace.shared.open(u) }
                        model.dismissPeek()
                    }
                    .buttonStyle(CapsuleStyle(primary: true, compact: true))
                }
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 16)
        }
    }
}

struct LeaveAskView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text("LOSGEHEN").font(Theme.font(10, .semibold)).tracking(0.7).foregroundStyle(Theme.accent)
            }
            Text("Für „Losgehen“ braucht Lotse deinen Standort").font(Theme.font(16, .semibold)).foregroundStyle(Theme.text)
            HStack(alignment: .bottom, spacing: 8) {
                Text("Damit rechnet Lotse aus, wann du zu Terminen mit Adresse los musst. Der Standort geht nur an Apple Karten.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Nicht jetzt") { model.leaveNotNow?() }.buttonStyle(CapsuleStyle(compact: true))
                Button("Erlauben") { model.leaveAllow?() }.buttonStyle(CapsuleStyle(primary: true, compact: true))
            }
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 16)
    }
}

extension LeaveCard {
    /// Erfundene Daten für Probebilder und Vorführung.
    static func demo(now: Date, minutesToLeave: Double) -> LeaveCard {
        let leave = now.addingTimeInterval(minutesToLeave * 60)
        let drive: TimeInterval = 25 * 60
        let start = leave.addingTimeInterval(drive)
        let e = CalEvent(id: "leave-demo", title: "Kundentermin", start: start, end: start.addingTimeInterval(3600),
                         color: .blue, place: "Musterstraße 1, 20357 Hamburg")
        let plan = LeavePlan(eventID: e.id, leaveAt: leave, times: [.driving: drive, .transit: 31 * 60, .walking: 88 * 60],
                             meters: 7400, mode: .driving)
        return LeaveCard(event: e, plan: plan,
                         place: LeavePlace(address: e.place, short: "Schanzenviertel", hasStreet: true, isPOI: false, metersAway: 6100))
    }
}
