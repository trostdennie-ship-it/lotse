import AppKit
import Combine
import SwiftUI

// MARK: - Ablage neben dem Dock

/// Glasfeld links neben dem Dock mit den zuletzt geparkten Dateien. Nur sichtbar, wenn etwas in der Ablage liegt
/// oder gerade eine Datei gezogen wird. Es ist dieselbe Ablage wie im Reiter oben.
enum DockShelfLayout {
    static let tile: CGFloat = 44
    static let spacing: CGFloat = 6
    static let padding: CGFloat = 12
    static let shown = 5

    static func selfTest() -> [String] {
        let url = URL(fileURLWithPath: "/System/Library/Desktop Pictures/Solid Colors/Teal.png")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return picture(url) === picture(url) ? [] : ["Ablage am Dock: Vorschau wird jedes Mal neu gelesen"]
    }

    /// Vorschau oder Symbol, einmal gelesen und gemerkt: Das Feld steht oft stundenlang da und wird ständig neu gezeichnet.
    private static let pictures = NSCache<NSString, NSImage>()
    static func picture(_ url: URL) -> NSImage {
        if let hit = pictures.object(forKey: url.path as NSString) { return hit }
        let img = (Stow.isImage(url) ? Stow.thumbnail(url, size: 120) : nil) ?? NSWorkspace.shared.icon(forFile: url.path)
        pictures.setObject(img, forKey: url.path as NSString)
        return img
    }

    static func width(count: Int) -> CGFloat {
        guard count > 0 else { return 170 }
        let n = CGFloat(min(count, shown))
        let more: CGFloat = count > shown ? spacing + 30 : 0
        return padding * 2 + n * tile + (n - 1) * spacing + more
    }
}

struct DockShelfView: View {
    @ObservedObject var model: IslandModel
    @State private var hovered: String?

    var body: some View {
        let items = Array(model.shelf.prefix(DockShelfLayout.shown))
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        HStack(spacing: DockShelfLayout.spacing) {
            if items.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text("Hier ablegen").font(Theme.font(12, .medium)).foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity)
            } else {
                ForEach(items) { tile($0) }
                if model.shelf.count > DockShelfLayout.shown {
                    Text("+\(model.shelf.count - DockShelfLayout.shown)").font(Theme.font(12, .medium)).monospacedDigit()
                        .foregroundStyle(Theme.muted).frame(width: 30)
                }
            }
        }
        .padding(.horizontal, DockShelfLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassPiece(shape: shape))
        .overlay(shape.strokeBorder(Theme.accent.opacity(model.filesDragging ? 0.7 : 0), lineWidth: 1.5))
        .animation(.easeOut(duration: 0.2), value: model.filesDragging)
    }

    private func tile(_ item: ShelfItem) -> some View {
        let on = hovered == item.id
        return ZStack {
            Group {
                if Stow.isImage(item.url) {
                    Image(nsImage: DockShelfLayout.picture(item.url)).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: DockShelfLayout.tile, height: DockShelfLayout.tile)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(nsImage: DockShelfLayout.picture(item.url)).resizable()
                        .frame(width: DockShelfLayout.tile - 4, height: DockShelfLayout.tile - 4)
                }
            }
            .frame(width: DockShelfLayout.tile, height: DockShelfLayout.tile)
            .scaleEffect(on ? 1.06 : 1)
            if on {
                badge("xmark", "\(item.url.lastPathComponent) aus der Ablage nehmen") {
                    withAnimation(IslandModel.spring) { model.shelf.removeAll { $0.id == item.id } }
                }
                .offset(x: DockShelfLayout.tile / 2 - 3, y: -DockShelfLayout.tile / 2 + 3)
                badge("sparkle", "\(item.url.lastPathComponent) an Claude geben") {
                    withAnimation(IslandModel.spring) { model.claudeFiles = [item.url]; model.tab = .stow; model.mode = .expanded }
                }
                .offset(x: DockShelfLayout.tile / 2 - 3, y: DockShelfLayout.tile / 2 - 3)
            }
        }
        .frame(width: DockShelfLayout.tile, height: DockShelfLayout.tile)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h ? item.id : (hovered == item.id ? nil : hovered) } }
        // Herausziehen in jede App; ein Doppelklick öffnet die Datei.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .help(item.url.lastPathComponent)
    }

    private func badge(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.onIce)
                .frame(width: 16, height: 16).background(Circle().fill(Theme.ice))
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

/// Nimmt gezogene Dateien an und legt sie in die Ablage, ohne die Insel aufzuklappen.
private final class DockShelfHost: NSHostingView<DockShelfView> {
    weak var model: IslandModel?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func files(_ sender: NSDraggingInfo) -> [URL] {
        (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { files(sender).isEmpty ? [] : .copy }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = files(sender)
        guard !urls.isEmpty else { return false }
        model?.acceptDrop(urls, open: false)
        log("Ablage am Dock: \(urls.count) Datei(en) abgelegt")
        return true
    }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DockShelfWindow {
    private let model: IslandModel
    private let panel: ShelfPanel
    private var timer: Timer?
    private var bag: [Any] = []
    private var lastState = ""

    init(model: IslandModel) {
        self.model = model
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        let host = DockShelfHost(rootView: DockShelfView(model: model))
        host.model = model
        host.registerForDraggedTypes([.fileURL])
        panel.contentView = host
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.activeSpaceDidChangeNotification] {
            bag.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.update() }
            })
        }
        bag.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.update() })
        bag.append(model.$shelf.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.update() } })
        bag.append(model.$filesDragging.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.update() } })
        bag.append(model.$dockShelfOn.receive(on: RunLoop.main).sink { [weak self] _ in DispatchQueue.main.async { self?.update() } })
        update()
    }

    func update() {
        // Beim Ziehen über die volle Ablage bleibt das Feld so, wie es ist; leer zeigt es „Hier ablegen“.
        let active = model.dockShelfOn && (!model.shelf.isEmpty || model.filesDragging)
        if active, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
        } else if !active { timer?.invalidate(); timer = nil }

        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }
        var spot: CGRect?
        var covers = false
        if active, DockMusicWindow.dockNormallyBottom {
            let dock = DockReader.frame()
            if let i = DockSpot.pick(dock: dock, screens: screens.map { ($0.frame, $0.visibleFrame) }) {
                let w = DockShelfLayout.width(count: model.shelf.count)
                let (screen, visible) = (screens[i].frame, screens[i].visibleFrame)
                // Steht links schon der Termin, setzt sich die Ablage außen daneben. Reicht der Platz nicht,
                // liegt sie solange an seiner Stelle.
                if let ev = DockEventWindow.current, let d = dock,
                   let outer = DockSpot.left(dock: CGRect(x: ev.minX, y: d.minY, width: d.maxX - ev.minX, height: d.height),
                                             screen: screen, visible: visible, width: w) {
                    spot = outer
                } else {
                    spot = DockSpot.left(dock: dock, screen: screen, visible: visible, width: w)
                    covers = DockEventWindow.current != nil && spot != nil
                }
            }
        }
        if model.dockShelfCovers != covers { model.dockShelfCovers = covers }
        if let r = spot {
            if panel.frame != r { panel.setFrame(r, display: true, animate: panel.isVisible) }
            if !panel.isVisible {
                panel.alphaValue = 0
                panel.orderFrontRegardless()
                NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
            }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
        let state = spot == nil ? (active ? "ausgeblendet (Dock nicht unten oder kein Platz)" : "ausgeblendet") : "sichtbar"
        if state != lastState { lastState = state; log("Ablage am Dock: \(state)") }
    }

    deinit {
        timer?.invalidate()
        bag.forEach { if !($0 is AnyCancellable) { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) } }
    }
}
