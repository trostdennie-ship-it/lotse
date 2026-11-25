import AppKit
import SwiftUI

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

enum Leave {
    /// Wie weit voraus Lotse Termine betrachtet.
    static let horizon: TimeInterval = 3 * 3600

    /// Orte, die keine Anfahrt bedeuten: Räume, Etagen, Videocalls, Verweise.
    private static let notAPlace = try! NSRegularExpression(
        pattern: #"^\s*(raum|room|besprechungsraum|meeting ?room)\b|\b(\d+\.\s*og|og\b|etage|stock(werk)?|floor)\b|teams|zoom|google meet|webex|skype|online|virtuell|virtual|telefon|anruf|call\b|siehe|see invite|tbd|tba"#,
        options: [.caseInsensitive])

    static func isCandidate(_ e: CalEvent, now: Date) -> Bool {
        guard !e.allDay, e.joinURL == nil else { return false }
        let place = e.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !place.isEmpty else { return false }
        let secs = e.start.timeIntervalSince(now)
        guard secs > 0, secs <= horizon else { return false }
        return notAPlace.firstMatch(in: place, range: NSRange(place.startIndex..., in: place)) == nil
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
