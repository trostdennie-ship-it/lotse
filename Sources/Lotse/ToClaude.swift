import AppKit
import SwiftUI

// MARK: - „An Claude geben"

/// Startet aus der Ablage eine neue Claude-Code-Session: Auftrag, Ordner und Dateien sind schon eingetragen,
/// in der Claude-App fehlt nur noch Enter. Die Claude-App reicht beim Link `claude://code/new` nur Auftrag und
/// Ordner weiter, die Dateien stehen deshalb als Pfade im Auftrag.
enum ToClaude {
    enum Preset: String, CaseIterable {
        case summary = "Zusammenfassen", check = "Prüfen", compare = "Vergleichen"
        var symbol: String { self == .summary ? "text.alignleft" : self == .check ? "checklist" : "arrow.left.arrow.right" }
        func text(_ count: Int) -> String {
            switch self {
            case .summary: return count == 1 ? "Fass mir das Wichtigste aus der Datei kurz zusammen." : "Fass mir das Wichtigste aus den Dateien kurz zusammen."
            case .check: return count == 1 ? "Prüf die Datei auf Fehler, Unklarheiten und Risiken und sag mir, was ich ändern sollte."
                : "Prüf die Dateien auf Fehler, Unklarheiten und Risiken und sag mir, was ich ändern sollte."
            case .compare: return "Vergleich die Dateien und zeig mir die wichtigsten Unterschiede."
            }
        }
    }

    /// Ordner, in denen zuletzt gearbeitet wurde: zuletzt gewählt, dann laufende Sessions, dann der Ordner der Datei.
    static func folders(_ model: IslandModel, files: [URL]) -> [String] {
        var out: [String] = []
        func add(_ p: String) { if !p.isEmpty, !out.contains(p), FileManager.default.fileExists(atPath: p) { out.append(p) } }
        (UserDefaults.standard.stringArray(forKey: "claudeFolders") ?? []).forEach(add)
        model.sessions.sorted { $0.updated > $1.updated }.map(\.cwd).forEach(add)
        files.map { $0.deletingLastPathComponent().path }.forEach(add)
        return Array(out.prefix(8))
    }

    static func remember(_ folder: String) {
        var list = UserDefaults.standard.stringArray(forKey: "claudeFolders") ?? []
        list.removeAll { $0 == folder }; list.insert(folder, at: 0)
        UserDefaults.standard.set(Array(list.prefix(6)), forKey: "claudeFolders")
    }

    static func prompt(_ task: String, files: [URL]) -> String {
        let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = files.map { "- \($0.path)" }.joined(separator: "\n")
        return (t.isEmpty ? "" : t + "\n\n") + (files.count == 1 ? "Datei:\n" : "Dateien:\n") + list
    }

    static func link(task: String, folder: String?, files: [URL]) -> URL? {
        var c = URLComponents(); c.scheme = "claude"; c.host = "code"; c.path = "/new"
        var q = [URLQueryItem(name: "q", value: prompt(task, files: files))]
        if let f = folder { q.append(URLQueryItem(name: "folder", value: f)) }
        c.queryItems = q
        // „+“ bleibt sonst stehen und wird als Leerzeichen gelesen.
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url
    }

    static func start(_ model: IslandModel, task: String, folder: String?, files: [URL]) {
        guard let url = link(task: task, folder: folder, files: files) else { return }
        if let f = folder { remember(f) }
        log("An Claude: \(files.count) Datei(en), Ordner \(folder.map { ($0 as NSString).lastPathComponent } ?? "–")")
        NSWorkspace.shared.open(url)
        withAnimation(IslandModel.spring) { model.claudeFiles = []; model.mode = .compact }
    }

    static func detail(_ url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        if url.pathExtension.lowercased() == "pdf", let doc = CGPDFDocument(url as CFURL) {
            return "PDF · \(doc.numberOfPages) \(doc.numberOfPages == 1 ? "Seite" : "Seiten")"
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { $0 }
        let s = size.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) }
        return [ext.isEmpty ? nil : ext, s].compactMap { $0 }.joined(separator: " · ")
    }
}

struct ToClaudeView: View {
    @ObservedObject var model: IslandModel
    @State private var task = ""
    @State private var folder: String?
    @State private var hovered: String?
    @FocusState private var typing: Bool

    private var files: [URL] { model.claudeFiles }
    private var presets: [ToClaude.Preset] { files.count > 1 ? ToClaude.Preset.allCases : [.summary, .check] }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            fileColumn.frame(width: 150)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text("An Claude geben").font(Theme.font(13, .semibold)).foregroundStyle(Theme.text)
                }
                ZStack(alignment: .topLeading) {
                    if task.isEmpty {
                        Text("Was soll Claude damit machen?").font(Theme.font(13)).foregroundStyle(Theme.faint)
                            .padding(.horizontal, 11).padding(.vertical, 9).allowsHitTesting(false)
                    }
                    TextField("", text: $task, axis: .vertical).textFieldStyle(.plain)
                        .font(Theme.font(13)).foregroundStyle(Theme.text).lineLimit(3...4)
                        .focused($typing)
                        .padding(.horizontal, 11).padding(.vertical, 9)
                        .accessibilityLabel("Auftrag an Claude")
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
                HStack(spacing: 4) {
                    ForEach(presets, id: \.self) { p in
                        let on = task == p.text(files.count)
                        Button { task = p.text(files.count) } label: {
                            HStack(spacing: 4) {
                                Image(systemName: p.symbol).font(.system(size: 10, weight: .semibold))
                                Text(p.rawValue).font(Theme.font(12, .medium))
                            }
                            .foregroundStyle(on ? Theme.onIce : Theme.soft)
                            .lineLimit(1).fixedSize()
                            .padding(.horizontal, 8).frame(height: 24)
                            .background(Capsule().fill(on ? Theme.ice : Theme.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack(spacing: 8) {
                    folderMenu
                    Spacer(minLength: 6)
                    Button("Abbrechen") { withAnimation(IslandModel.spring) { model.claudeFiles = [] } }
                        .buttonStyle(CapsuleStyle(compact: true))
                    Button("Starten") { ToClaude.start(model, task: task, folder: folder, files: files) }
                        .buttonStyle(CapsuleStyle(primary: true, compact: true))
                        .keyboardShortcut(.return, modifiers: .command)
                        .help("Öffnet eine neue Session in der Claude-App (⌘↩)")
                }
            }
            .padding(13)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
        }
        .onAppear {
            if folder == nil { folder = ToClaude.folders(model, files: files).first }
            if task.isEmpty { task = presets[0].text(files.count) }
        }
    }

    private var fileColumn: some View {
        VStack(spacing: 8) {
            if files.count == 1, let f = files.first {
                Spacer(minLength: 0)
                icon(f, size: 56)
                Text(f.lastPathComponent).font(Theme.font(12, .medium)).foregroundStyle(Theme.text)
                    .lineLimit(2).multilineTextAlignment(.center).truncationMode(.middle)
                Text(ToClaude.detail(f)).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                ForEach(files.prefix(5), id: \.path) { f in
                    HStack(spacing: 8) {
                        icon(f, size: 24)
                        Text(f.lastPathComponent).font(Theme.font(11)).foregroundStyle(Theme.soft)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                        if hovered == f.path {
                            Button { withAnimation(IslandModel.spring) { model.claudeFiles.removeAll { $0 == f } } } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.muted)
                            }
                            .buttonStyle(.plain).accessibilityLabel("\(f.lastPathComponent) weglassen")
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { h in hovered = h ? f.path : (hovered == f.path ? nil : hovered) }
                }
                if files.count > 5 {
                    Text("und \(files.count - 5) weitere").font(Theme.font(11)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }

    private func icon(_ url: URL, size: CGFloat) -> some View {
        Group {
            if Stow.isImage(url), let img = Stow.thumbnail(url, size: 160) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size > 30 ? 9 : 4, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: size, height: size)
            }
        }
    }

    private var folderMenu: some View {
        Menu {
            ForEach(ToClaude.folders(model, files: files), id: \.self) { p in
                Button((p as NSString).abbreviatingWithTildeInPath) { folder = p }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Ordner:").foregroundStyle(Theme.faint)
                Text(folder.map { ($0 as NSString).lastPathComponent } ?? "wählen").foregroundStyle(Theme.soft)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.faint)
            }
            .font(Theme.font(11))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(folder.map { "Claude arbeitet in \(($0 as NSString).abbreviatingWithTildeInPath)" } ?? "Ordner für die Session")
    }
}
