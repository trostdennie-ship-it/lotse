import AppKit
import SwiftUI

// MARK: - „Während du weg warst"

/// Was passiert ist, während der Bildschirm aus oder gesperrt war.
struct AwaySummary {
    struct Group: Identifiable {
        var id: String { appID ?? name }
        var appID: String?
        var name: String
        var notices: [Notice]
        var last: Date { notices.map(\.date).max() ?? .distantPast }
    }
    var since: Date
    var groups: [Group]
    var done: [ClaudeSession]
    var waiting: [ClaudeSession]
    var first: CalEvent?

    var isEmpty: Bool { groups.isEmpty && done.isEmpty && waiting.isEmpty }

    static func collect(_ model: IslandModel, since: Date) -> AwaySummary {
        let fresh = model.notices.filter { $0.kind == .system && $0.date >= since }
        var order: [String] = [], byApp: [String: Group] = [:]
        for n in fresh {
            let key = n.appID?.lowercased() ?? n.appName
            if byApp[key] == nil { order.append(key); byApp[key] = Group(appID: n.appID, name: n.appName, notices: []) }
            byApp[key]?.notices.append(n)
        }
        let groups = order.compactMap { byApp[$0] }.sorted { $0.notices.count > $1.notices.count }
        let done = model.sessions.filter { $0.status == .done && ($0.doneAt ?? .distantPast) >= since }
        let waiting = model.sessions.filter { $0.status == .waiting }
        let first = model.events.first { $0.start > Date() && Calendar.current.isDateInToday($0.start) }
        return AwaySummary(since: since, groups: groups, done: done, waiting: waiting, first: first)
    }
}

/// Merkt sich, wann der Bildschirm ausging oder gesperrt wurde, und zeigt nach längerer Pause die Bilanz.
final class AwayWatcher {
    private let model: IslandModel
    private var since: Date?
    private var locked = false
    private var again: DispatchWorkItem?
    /// Ab dieser Pause gibt es eine Bilanz (Sekunden).
    static var threshold: TimeInterval { UserDefaults.standard.object(forKey: "awayMinutes").map { ($0 as? Double ?? 120) * 60 } ?? 2 * 3600 }

    init(model: IslandModel) { self.model = model }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.began("Bildschirm aus") }
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.began("Ruhezustand") }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.back() }
        let dn = DistributedNotificationCenter.default()
        dn.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = true; self?.began("gesperrt")
        }
        dn.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.locked = false; self?.back()
        }
    }

    private func began(_ why: String) {
        guard since == nil else { return }
        since = Date()
        again?.cancel()
        log("Weg: \(why)")
    }

    /// Erst wenn der Bildschirm an und entsperrt ist. Die Mitteilungen aus der Pause laufen danach noch ein paar Sekunden ein.
    private func back() {
        guard let s = since, !locked else { return }
        since = nil
        let gap = Date().timeIntervalSince(s)
        log("Zurück nach \(Int(gap / 60)) Min")
        guard gap >= Self.threshold else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.show(since: s) }
    }

    /// Auch für die Vorführung (Ereignis `LotseAway`).
    func show(since: Date) {
        let summary = AwaySummary.collect(model, since: since)
        guard !summary.isEmpty else { log("Weg-Bilanz: nichts passiert"); return }
        log("Weg-Bilanz: \(summary.groups.reduce(0) { $0 + $1.notices.count }) Mitteilungen, \(summary.done.count) fertig, \(summary.waiting.count) wartet")
        model.away = summary
        model.post(Notice(kind: .info, appName: "Willkommen zurück", title: "Willkommen zurück", body: "", card: "away", hold: 45))
        // „Später": Die Bilanz kommt nach 20 Minuten noch einmal, solange sie nicht als gesehen markiert ist.
        model.awayLater = { [weak self] in
            guard let self else { return }
            let w = DispatchWorkItem { [weak self] in
                guard let self, self.model.away != nil else { return }
                self.model.post(Notice(kind: .info, appName: "Willkommen zurück", title: "Willkommen zurück", body: "", card: "away", hold: 45))
            }
            self.again?.cancel(); self.again = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 20 * 60, execute: w)
        }
    }
}

// MARK: - Die Karte

struct AwayView: View {
    @ObservedObject var model: IslandModel
    let summary: AwaySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.kicker(summary.since, now: model.now)).font(Theme.font(10, .semibold)).tracking(0.7)
                .monospacedDigit().foregroundStyle(Theme.accent)
            Text("Das ist passiert").font(Theme.font(18, .semibold)).foregroundStyle(Theme.text)
            VStack(spacing: 0) {
                let rows = Array(rowsList.enumerated())
                ForEach(rows, id: \.offset) { i, r in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 38) }
                    r
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
            HStack(spacing: 8) {
                Spacer()
                Button("Später") { model.awayLater?(); model.dismissPeek() }.buttonStyle(CapsuleStyle(compact: true))
                Button("Alles gesehen") {
                    let ids = Set(summary.groups.flatMap { $0.notices.map(\.id) })
                    withAnimation(IslandModel.spring) { model.notices.removeAll { ids.contains($0.id) } }
                    model.away = nil
                    model.dismissPeek()
                }
                .buttonStyle(CapsuleStyle(primary: true, compact: true))
            }
        }
        .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 16)
    }

    private var rowsList: [AnyView] {
        var out: [AnyView] = []
        let hide = model.discreet
        for g in summary.groups.prefix(3) {
            let n = g.notices.count
            let isMail = g.notices.first?.card == "mail" || ["com.apple.mail", "com.microsoft.outlook"].contains(g.appID?.lowercased() ?? "")
            let isCal = ["com.apple.ical", "com.apple.reminders"].contains(g.appID?.lowercased() ?? "")
            let title = isMail ? (n == 1 ? "1 neue Mail" : "\(n) neue Mails")
                : isCal ? (n == 1 ? "1 Erinnerung" : "\(n) Erinnerungen")
                : (n == 1 ? "1 Nachricht" : "\(n) Nachrichten")
            let names = Self.unique(g.notices.map(\.title))
            let detail = hide ? g.name : names.count == 1 && !isMail
                ? "\(names[0]): \(g.notices.first?.body ?? "")"
                : names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " · \(names.count - 2) weitere" : "")
            let sample = g.notices.first
            out.append(AnyView(row(icon: AnyView(AppIcon(id: g.appID, size: 26)), title: isMail ? title : "\(title) · \(g.name)", detail: detail,
                                   meta: Fmt.time.string(from: g.last)) {
                if let u = sample?.url { NSWorkspace.shared.open(u) } else if let id = g.appID { Apps.activate(id) }
            }))
        }
        if !summary.done.isEmpty || !summary.waiting.isEmpty {
            var parts: [String] = []
            if !summary.done.isEmpty { parts.append(summary.done.map(\.project).prefix(2).joined(separator: ", ") + (summary.done.count == 1 ? " ist fertig" : " sind fertig")) }
            if !summary.waiting.isEmpty { parts.append(summary.waiting.map(\.project).prefix(2).joined(separator: ", ") + " wartet auf dich") }
            let target = summary.waiting.first ?? summary.done.first
            out.append(AnyView(row(icon: AnyView(Mascot(size: 26, state: summary.waiting.isEmpty ? .idle : .waiting, lit: true)),
                                   title: "Claude", detail: hide ? "\(summary.done.count + summary.waiting.count) Sessions" : parts.joined(separator: " · "),
                                   meta: summary.waiting.isEmpty ? "" : "\(summary.waiting.count) wartet", accent: !summary.waiting.isEmpty) {
                if let s = target { model.openSession?(s) }
            }))
        }
        if let e = summary.first {
            out.append(AnyView(row(icon: AnyView(Image(systemName: "calendar").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                                    .frame(width: 26, height: 26).background(Circle().fill(Theme.raised))),
                                   title: "Nächster Termin \(Fmt.time.string(from: e.start))",
                                   detail: (hide ? "Termin" : e.label(discreet: false)) + " · " + Fmt.until(e.start, now: model.now), meta: "") {}))
        }
        return out
    }

    private func row(icon: AnyView, title: String, detail: String, meta: String, accent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Theme.font(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(detail).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(meta).font(Theme.font(11, accent ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(accent ? Theme.accent : Theme.faint)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    static func unique(_ list: [String]) -> [String] {
        var seen = Set<String>(); return list.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func kicker(_ since: Date, now: Date) -> String {
        let cal = Calendar.current
        let day = cal.isDate(since, inSameDayAs: now) ? "" : cal.isDateInYesterday(since) ? "GESTERN " : {
            let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EE "; return f.string(from: since).uppercased().replacingOccurrences(of: ".", with: "")
        }()
        let mins = max(0, Int(now.timeIntervalSince(since) / 60))
        let span = mins >= 60 ? "\(mins / 60) STD \(mins % 60) MIN" : "\(mins) MIN"
        return "WEG SEIT \(day)\(Fmt.time.string(from: since)) · \(span)"
    }
}
