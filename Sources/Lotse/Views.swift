import SwiftUI
import AppKit

// MARK: - Gestaltung: dunkler Schiefer, ruhige Typo, ein einziger eisblauer Akzent.

enum Theme {
    static let tile = Color.white.opacity(0.075)
    static let raised = Color.white.opacity(0.16)                       // Felder, ruhende Knöpfe
    static let line = Color.white.opacity(0.12)
    static let text = Color.white
    static let soft = Color.white.opacity(0.82)
    static let muted = Color.white.opacity(0.68)
    static let faint = Color.white.opacity(0.60)
    /// Das gewählte Farbschema (Einstellungen → Aussehen). Alle Farbtöne unten richten sich danach.
    static var palette = Palette(rawValue: UserDefaults.standard.string(forKey: "palette") ?? "") ?? .ice
    static var tones: Tones { palette.tones }
    static var accent: Color { tones.accent }                            // Punkt, Balken, Countdown
    static var ice: Color { tones.light }                                // helle Fläche gewählter Knöpfe
    static var warn: Color { tones.warn }                                // Warnung: fast volles Limit, riskanter Befehl
    /// macOS-Einstellung „Bewegung reduzieren": dann stehen Boot und Punkte still.
    static var calm: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static var onIce: Color { tones.onLight }                            // dunkle Schrift auf hellen Knöpfen

    /// Exakt die Schrift der Menüleiste („Datei, Bearbeiten …“): Systemschrift, 13 pt, normal.
    static let bar = Font(NSFont.menuBarFont(ofSize: 0))
    /// Schrift der Insel: Geist (OFL, liegt im App-Paket). Fehlt sie, bleibt es bei der Systemschrift.
    /// Die Flügel neben der Notch nutzen bewusst die Menüleistenschrift (`bar`, `system`).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        geistLoaded ? Font.custom("Geist", size: size).weight(weight) : system(size, weight)
    }
    static func system(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    private static let geistLoaded: Bool = {
        let url = Bundle.main.url(forResource: "Geist", withExtension: "woff2")
            ?? URL(fileURLWithPath: "Resources/Geist.woff2")   // Probebilder aus .build heraus
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return NSFont(name: "Geist", size: 12) != nil || NSFontManager.shared.availableMembers(ofFontFamily: "Geist") != nil
    }()
    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

/// Farbschema: kühles Eisblau auf Schiefer oder warmer Bernstein auf Graphit.
enum Palette: String, CaseIterable {
    case ice, amber, deep, lime
    var title: String {
        switch self {
        case .ice: return "Eisblau auf Schiefer"
        case .amber: return "Bernstein auf Graphit"
        case .deep: return "Türkis auf Tiefsee"
        case .lime: return "Limette auf Kohle"
        }
    }
    var tones: Tones {
        switch self {
        case .ice: return .ice
        case .amber: return .amber
        case .deep: return .deep
        case .lime: return .lime
        }
    }
}

/// Alle Farbtöne eines Schemas an einem Ort.
struct Tones {
    var accent: Color
    var light: Color
    var onLight: Color
    var warn: Color
    var tile: [Color]            // Kachel-Verlauf: oben links → Mitte → unten rechts
    var button: [Color]          // Hauptknopf
    var buttonRest: [Color]      // ruhender Knopf
    var surface: [Color]         // dunkle Fläche der Insel
    var tint: Color
    var cover: [Color]           // Platzhalter ohne Albumbild
    var dots: Color              // Punktgrafik der Geräte-Karten
    var wave: [Color]            // Arbeitsanzeige
    var chosen: [Color]          // gewählte Fläche (Hover-Kacheln der Ablage)

    private static func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let ice = Tones(
        accent: c(0.66, 0.82, 1.0), light: c(0.80, 0.89, 0.99), onLight: c(0.10, 0.16, 0.26), warn: c(1.0, 0.80, 0.52),
        tile: [c(0.33, 0.38, 0.48).opacity(0.62), c(0.22, 0.26, 0.34).opacity(0.58), c(0.15, 0.18, 0.24).opacity(0.60)],
        button: [c(0.90, 0.95, 1.0), c(0.70, 0.83, 0.98)],
        buttonRest: [c(0.50, 0.57, 0.70).opacity(0.55), c(0.34, 0.40, 0.52).opacity(0.50)],
        surface: [c(0.02, 0.025, 0.035), c(0.075, 0.09, 0.125)], tint: c(0.07, 0.085, 0.12),
        cover: [c(0.30, 0.47, 0.68), c(0.18, 0.28, 0.44)], dots: c(0.86, 0.93, 1.0),
        wave: [c(0.66, 0.82, 1.0), c(0.70, 0.62, 1.0), c(1.0, 0.66, 0.84), c(0.66, 0.82, 1.0)],
        chosen: [c(0.32, 0.44, 0.62), c(0.25, 0.36, 0.53)])

    /// Abgegriffen vom warmen Lichtstreifen eines dunklen Beton-Hintergrunds: ein einziger Akzent, neutrale Flächen.
    static let amber = Tones(
        accent: c(1.0, 0.72, 0.42), light: c(1.0, 0.87, 0.68), onLight: c(0.22, 0.14, 0.06), warn: c(1.0, 0.50, 0.44),
        tile: [c(0.40, 0.375, 0.35).opacity(0.62), c(0.27, 0.25, 0.235).opacity(0.58), c(0.185, 0.17, 0.16).opacity(0.60)],
        button: [c(1.0, 0.93, 0.80), c(0.98, 0.79, 0.54)],
        buttonRest: [c(0.60, 0.555, 0.51).opacity(0.55), c(0.42, 0.385, 0.35).opacity(0.50)],
        surface: [c(0.028, 0.025, 0.022), c(0.10, 0.09, 0.08)], tint: c(0.10, 0.09, 0.08),
        cover: [c(0.62, 0.43, 0.24), c(0.36, 0.24, 0.13)], dots: c(1.0, 0.94, 0.85),
        wave: [c(1.0, 0.72, 0.42), c(1.0, 0.88, 0.66), c(0.94, 0.55, 0.26), c(1.0, 0.72, 0.42)],
        chosen: [c(0.60, 0.43, 0.24), c(0.50, 0.35, 0.19)])

    /// Die Farben des App-Symbols: Nachtblau bis Petrol, Türkis als Akzent, ein warmer Ton nur für Warnungen.
    static let deep = Tones(
        accent: c(0.40, 0.90, 0.84), light: c(0.76, 0.96, 0.93), onLight: c(0.03, 0.17, 0.22), warn: c(1.0, 0.70, 0.40),
        tile: [c(0.20, 0.36, 0.50).opacity(0.62), c(0.12, 0.24, 0.37).opacity(0.58), c(0.08, 0.16, 0.27).opacity(0.60)],
        button: [c(0.86, 0.99, 0.97), c(0.50, 0.90, 0.85)],
        buttonRest: [c(0.34, 0.52, 0.66).opacity(0.55), c(0.22, 0.36, 0.50).opacity(0.50)],
        surface: [c(0.012, 0.022, 0.05), c(0.04, 0.085, 0.14)], tint: c(0.035, 0.075, 0.13),
        cover: [c(0.12, 0.50, 0.58), c(0.10, 0.22, 0.45)], dots: c(0.86, 0.98, 0.97),
        wave: [c(0.40, 0.90, 0.84), c(0.42, 0.66, 1.0), c(0.62, 0.52, 1.0), c(0.40, 0.90, 0.84)],
        chosen: [c(0.14, 0.44, 0.52), c(0.11, 0.34, 0.44)])

    /// Fast schwarze, neutrale Flächen und ein einziger greller Akzent.
    static let lime = Tones(
        accent: c(0.78, 0.96, 0.36), light: c(0.88, 0.98, 0.62), onLight: c(0.09, 0.13, 0.02), warn: c(1.0, 0.55, 0.36),
        tile: [c(0.34, 0.35, 0.33).opacity(0.62), c(0.23, 0.24, 0.225).opacity(0.58), c(0.155, 0.16, 0.15).opacity(0.60)],
        button: [c(0.93, 1.0, 0.72), c(0.76, 0.94, 0.36)],
        buttonRest: [c(0.52, 0.54, 0.50).opacity(0.55), c(0.36, 0.37, 0.345).opacity(0.50)],
        surface: [c(0.02, 0.022, 0.02), c(0.075, 0.08, 0.072)], tint: c(0.07, 0.075, 0.068),
        cover: [c(0.42, 0.56, 0.18), c(0.20, 0.28, 0.10)], dots: c(0.94, 1.0, 0.82),
        wave: [c(0.78, 0.96, 0.36), c(0.94, 1.0, 0.70), c(0.36, 0.86, 0.56), c(0.78, 0.96, 0.36)],
        chosen: [c(0.40, 0.52, 0.18), c(0.32, 0.42, 0.14)])
}

private struct GlassKey: EnvironmentKey { static let defaultValue = GlassStyle.solid }
extension EnvironmentValues {
    var glass: GlassStyle {
        get { self[GlassKey.self] }
        set { self[GlassKey.self] = newValue }
    }
}

/// Seegang um das Boot: 0 = ruhig, 1 = höhere Wellen (5-Stunden-Limit ab 70 %), 2 = Gewitter (ab 90 %).
enum Probe {
    static let frame: Int? = ProcessInfo.processInfo.environment["LOTSE_FRAME"].flatMap { Int($0) }
    static let time: Double? = ProcessInfo.processInfo.environment["LOTSE_T"].flatMap { Double($0) }
    /// Startseite des Einrichtungsassistenten (nur für Probebilder).
    nonisolated(unsafe) static var setupStep = 0
}

private struct TrailWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SeaKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var sea: Int {
        get { self[SeaKey.self] }
        set { self[SeaKey.self] = newValue }
    }
}

/// Ein eigenständiges Stück Glas (Kachel, Reiterleiste, Uhr). Inhalt darin ist nie selbst Glas.
struct GlassPiece<S: InsettableShape>: ViewModifier {
    @Environment(\.glass) private var style
    var shape: S
    var dim: Double = 0.0       // zusätzliche Abdunklung hinter klarem Glas, damit weiße Schrift lesbar bleibt

    func body(content: Content) -> some View {
        if style == .liquid {
            // Weicher Schiefer-Verlauf: heller oben links, dunkler unten rechts, dazu eine kaum sichtbare Lichtkante.
            // (Echtes Glas wirkt auf der dunklen Fläche nur flach grau – der Verlauf gibt den Kacheln Tiefe.)
            content
                .background(shape.fill(LinearGradient(
                    stops: [.init(color: Theme.tones.tile[0], location: 0),
                            .init(color: Theme.tones.tile[1], location: 0.55),
                            .init(color: Theme.tones.tile[2], location: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        } else {
            content
                .background(shape.fill(LinearGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0.05)],
                                                      startPoint: .top, endPoint: .bottom)))
                .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0.03)],
                                                           startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
    }
}

/// Notch-Form: oben bündig mit kleinen Ohren, unten weich abgerundet.
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var ear: CGFloat = 7
    /// Schultern: Um so viel ist der Bereich unter der Kopfzeile auf jeder Seite schmaler als die Kopfzeile.
    /// 0 = schlichte Insel. Größer 0 = die Kopfzeile bleibt eine breite Leiste, der Inhalt hängt schmaler darunter.
    var shoulder: CGFloat = 0
    /// Höhe der Kopfzeile (nur mit Schultern von Belang).
    var head: CGFloat = 34

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(bottomRadius, shoulder) }
        set { bottomRadius = newValue.first; shoulder = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        let br = min(bottomRadius, r.height / 2)
        let left = r.minX + ear, right = r.maxX - ear
        let s = r.height > head + 2 * br ? max(0, min(shoulder, (r.width - 2 * ear) / 2 - br - 4)) : 0
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: left, y: r.minY + ear), control: CGPoint(x: left, y: r.minY))
        if s < 0.5 {
            p.addLine(to: CGPoint(x: left, y: r.maxY - br))
            p.addQuadCurve(to: CGPoint(x: left + br, y: r.maxY), control: CGPoint(x: left, y: r.maxY))
            p.addLine(to: CGPoint(x: right - br, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: right, y: r.maxY - br), control: CGPoint(x: right, y: r.maxY))
        } else {
            let h = r.minY + head
            let hr = min(11, s / 2), j = min(9, s / 2)      // Rundung der Leiste außen, Kehle zum Inhalt hin
            let bl = left + s, bR = right - s
            p.addLine(to: CGPoint(x: left, y: h - hr))
            p.addQuadCurve(to: CGPoint(x: left + hr, y: h), control: CGPoint(x: left, y: h))
            p.addLine(to: CGPoint(x: bl - j, y: h))
            p.addQuadCurve(to: CGPoint(x: bl, y: h + j), control: CGPoint(x: bl, y: h))
            p.addLine(to: CGPoint(x: bl, y: r.maxY - br))
            p.addQuadCurve(to: CGPoint(x: bl + br, y: r.maxY), control: CGPoint(x: bl, y: r.maxY))
            p.addLine(to: CGPoint(x: bR - br, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: bR, y: r.maxY - br), control: CGPoint(x: bR, y: r.maxY))
            p.addLine(to: CGPoint(x: bR, y: h + j))
            p.addQuadCurve(to: CGPoint(x: bR + j, y: h), control: CGPoint(x: bR, y: h))
            p.addLine(to: CGPoint(x: right - hr, y: h))
            p.addQuadCurve(to: CGPoint(x: right, y: h - hr), control: CGPoint(x: right, y: h))
        }
        p.addLine(to: CGPoint(x: right, y: r.minY + ear))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: right, y: r.minY))
        p.closeSubpath()
        return p
    }
}

private struct Blur: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

private extension AnyTransition {
    /// Inhalt taucht weich aus der Insel auf statt hart einzublenden.
    static var emerge: AnyTransition {
        .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.16)),
                    removal: .opacity.animation(.easeOut(duration: 0.09)))
    }
}

// MARK: - Bausteine

struct Dot: View {
    var color: Color = Theme.accent
    var pulsing = false
    @State private var on = false

    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
            .background(Circle().fill(color.opacity(0.35)).scaleEffect(pulsing && on ? 2.6 : 1).opacity(pulsing && on ? 0 : 1))
            .onAppear {
                guard pulsing, !Theme.calm else { return }
                withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

/// Knöpfe liegen als schlichte Flächen auf dem Glas: weißlich im Ruhezustand, sattes Blau für die Hauptaktion.
struct GlassFill<S: InsettableShape>: View {
    var shape: S
    var primary = false
    var body: some View {
        // Auch Knöpfe tragen einen weichen Verlauf statt einer flachen Farbe.
        shape.fill(LinearGradient(
            colors: primary ? Theme.tones.button : Theme.tones.buttonRest,
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(shape.strokeBorder(Color.white.opacity(primary ? 0.35 : 0.08), lineWidth: 1))
    }
}

struct CapsuleStyle: ButtonStyle {
    var primary = false
    var compact = false
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(12, primary ? .medium : .regular))
            .foregroundStyle(primary ? Theme.onIce : Color.white)
            .padding(.horizontal, compact ? 14 : 17)
            .frame(height: compact ? 26 : 30)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(GlassFill(shape: Capsule(), primary: primary))
            .modifier(HoverGlow())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}

struct RoundStyle: ButtonStyle {
    var primary = false
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.38, weight: .medium))
            .foregroundStyle(primary ? Theme.onIce : Color.white)
            .frame(width: size, height: size)
            .background(GlassFill(shape: Circle(), primary: primary))
            .modifier(HoverGlow())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .contentShape(Circle())
    }
}

/// Kacheln erscheinen nacheinander: kurz verzögert, mit einem kleinen Weg von unten.
struct Rise: ViewModifier {
    var index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 7)
            .onAppear {
                if Theme.calm { shown = true; return }
                withAnimation(.easeOut(duration: 0.3).delay(0.12 + 0.045 * Double(index))) { shown = true }
            }
    }
}

/// Knöpfe hellen sich leicht auf, wenn die Maus darüber liegt.
struct HoverGlow: ViewModifier {
    @State private var over = false
    func body(content: Content) -> some View {
        content
            .brightness(over ? 0.07 : 0)
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { over = h } }
    }
}

/// Kachel mit Symbol + Titel links und leiser Angabe rechts.
private struct Tile<Content: View>: View {
    var icon: String
    var title: String
    var info: String = ""
    var trailing: AnyView? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                Text(title).font(Theme.font(12, .medium)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
                Spacer(minLength: 4)
                if let trailing { trailing } else {
                    Text(info).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            content
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }
}

struct Cover: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fill) }
            else {
                LinearGradient(colors: Theme.tones.cover,
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct AppIcon: View {
    var id: String?
    var size: CGFloat
    var body: some View {
        if let id, Apps.url(id) == nil {
            Image(systemName: "gearshape.fill").font(.system(size: size * 0.5, weight: .regular)).foregroundStyle(Theme.soft)
                .frame(width: size, height: size).background(Circle().fill(Theme.raised))
        } else if id == nil {
            Image(systemName: "timer").font(.system(size: size * 0.5, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: size, height: size).background(Circle().fill(Theme.raised))
        } else {
            Image(nsImage: Apps.icon(id)).resizable().interpolation(.high).frame(width: size, height: size)
        }
    }
}

/// Lotses kleines Pixel-Segelboot. Es zeigt, was Claude gerade tut:
/// segelt (wippt, Wellen laufen) = arbeitet · Signalflagge blinkt = wartet auf dich ·
/// fährt einmal hinaus und legt wieder an = gerade fertig geworden · liegt still = ruht.
struct Mascot: View {
    enum State: Equatable { case sailing, waiting, idle, arriving(since: Date) }
    var size: CGFloat = 44
    var state: State = .idle
    /// Für den Aufbau einer Karte: Anteil der schon gedruckten Zeilen (nil = fertig gezeichnet).
    var printing: Double? = nil
    /// Solange nicht „an", erscheinen die Punkte in gedämpftem Grau.
    var lit = true
    @SwiftUI.State private var settled = false
    @Environment(\.sea) private var sea
    @Environment(\.displayScale) private var scale

    /// Wartet Claude auf dich, steht statt des Boots ein Leuchtturm da – sein Licht schwenkt hin und her.
    private static let tower = [
        ".....LL.....",
        "....HHHH....",
        ".....SS.....",
        ".....ss.....",
        ".....SS.....",
        ".....ss.....",
        "....SSSS....",
        "....ssss....",
        "...HHHHHH...",
        "..hhhhhhhh..",
    ]

    /// Auch die Menüleiste zeichnet dieses Muster – so bleiben beide Boote gleich.
    static let boat = [
        ".....MS.....",
        ".....MSS....",
        "....sMSS....",
        "...ssMSSS...",
        "..sssMSSSS..",
        ".ssssMSSSSS.",
        ".....M......",
        "HHHHHHHHHHHH",
        ".HHHHHHHHHH.",
        "...hhhhhh...",
    ]
    private static let waves = ["w.ww.ww.ww.w", ".ww.ww.ww.ww", "ww.ww.ww.ww."]

    /// Große Boote (ab etwa 36 Punkt auf Retina) bekommen das Feinraster des App-Symbols: doppelt so viele Punkte je Richtung.
    private static let fineBoat: [String] = {
        var g = Array(repeating: Array(repeating: Character("."), count: 24), count: 20)
        for r in 1...12 {                                             // Großsegel rechts vom Mast
            let w = max(1, Int((Double(r) * 8 / 12).rounded()))
            for c in 12..<(12 + w) { g[r + 2][c] = "S" }
        }
        for r in 5...12 { for c in (11 - min(6, r - 4))..<11 { g[r + 2][c] = "s" } }     // Vorsegel links
        for r in 2...15 { g[r][11] = "M" }                                             // Mast
        for (i, span) in [(2, 21), (3, 20), (4, 19), (6, 17)].enumerated() {           // Rumpf
            for c in span.0...span.1 { g[16 + i][c] = i == 3 ? "h" : "H" }
        }
        return g.map { String($0) }
    }()

    private static let fineTower: [String] = {
        var g = Array(repeating: Array(repeating: Character("."), count: 24), count: 20)
        func fill(_ r: Int, _ a: Int, _ b: Int, _ ch: Character) { for c in a...b { g[r][c] = ch } }
        fill(0, 11, 12, "H"); fill(1, 10, 13, "H")                    // Dach
        fill(2, 10, 13, "L"); fill(3, 10, 13, "L")                    // Laterne
        fill(4, 8, 15, "H"); fill(5, 9, 14, "h")                      // Galerie
        for r in 6...17 {                                             // Schaft, nach unten breiter, quer gestreift
            let half = r < 10 ? 2 : r < 14 ? 3 : 4
            fill(r, 12 - half, 11 + half, ((r - 6) / 2) % 2 == 0 ? "S" : "s")
        }
        fill(18, 6, 17, "H"); fill(19, 5, 18, "h")                    // Sockel
        return g.map { String($0) }
    }()
    /// Bilder pro Sekunde für Segeln und Leuchtturm (`defaults write local.lotse.app boatFPS 20`).
    private static let fps: Double = { let v = UserDefaults.standard.double(forKey: "boatFPS"); return v >= 2 ? min(v, 60) : 30 }()
    /// Zum Ausprobieren: LOTSE_FINE=1 erzwingt das Feinraster auch für kleine Boote, =0 schaltet es ab.
    private static let fineOverride: Bool? = ProcessInfo.processInfo.environment["LOTSE_FINE"].map { $0 == "1" }

    var body: some View {
        switch state {
        case .idle:
            canvas(frame: 0)
        case .arriving(let since):
            // Einmalige Sequenz (gut 1,6 s): hinausfahren, kurz weg sein, wieder anlegen.
            if let t = Probe.time {
                canvas(frame: 0, bright: true, shift: Self.glide(t) == nil ? 99 : 0, time: t, slide: Self.glide(t))
            } else if Theme.calm || settled || Date().timeIntervalSince(since) > 1.7 {
                canvas(frame: 0, bright: true)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    let t = ctx.date.timeIntervalSince(since)
                    canvas(frame: 0, bright: true, shift: Self.glide(t) == nil ? 99 : 0,
                           time: ctx.date.timeIntervalSinceReferenceDate, slide: Self.glide(t))
                }
                .task(id: since) {
                    try? await Task.sleep(nanoseconds: UInt64(max(0, 1.75 - Date().timeIntervalSince(since)) * 1_000_000_000))
                    settled = true
                }
            }
        case .sailing, .waiting:
            if let f = Probe.frame {
                canvas(frame: f)
            } else if let t = Probe.time {
                canvas(frame: Int(t / (state == .sailing ? 0.28 : 0.5)), time: t)
            } else if Theme.calm {
                canvas(frame: 0)
            } else {
                // Fließend: Das Boot wiegt sich, die Wellen laufen durch, der Lichtkegel blendet über.
                let step = state == .sailing ? 0.28 : 0.5
                TimelineView(.animation(minimumInterval: 1.0 / Self.fps)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    canvas(frame: Int(t / step), time: t)
                }
            }
        }
    }

    /// Seitlicher Versatz in Bildpunkten: beschleunigt nach rechts hinaus (0,73 s), bleibt weg (0,63 s),
    /// kommt von links zurück und bremst ab (0,25 s).
    private static func voyage(_ t: Double) -> Int {
        let span = 14.0
        if t < 0.73 { let k = t / 0.73; return Int((span * k * k).rounded()) }
        if t < 1.36 { return 99 }
        if t < 1.61 { let k = (t - 1.36) / 0.25; return -Int((span * (1 - k) * (1 - k)).rounded()) }
        return 0
    }

    /// Dasselbe wie `voyage`, aber stufenlos und in Rasterschritten mit Nachkommastellen; nil = gerade außer Sicht.
    private static func glide(_ t: Double) -> Double? {
        let span = 14.0
        if t < 0.73 { let k = t / 0.73; return span * k * k }
        if t < 1.36 { return nil }
        if t < 1.61 { let k = (t - 1.36) / 0.25; return -span * (1 - k) * (1 - k) }
        return 0
    }

    /// `time` (Sekunden) schaltet auf fließende Bewegung; ohne sie springt alles in ganzen Rasterschritten (Probebilder).
    private func canvas(frame: Int, bright: Bool = false, shift: Int = 0, time: Double? = nil, slide: Double? = nil) -> some View {
        Canvas { ctx, sz in
            // Feinraster nur, wenn ein Punkt wenigstens drei Bildschirmpixel bekommt – sonst verschwimmt es.
            let fine = Self.fineOverride ?? (min(sz.width, sz.height) * scale / 24 >= 3)
            let k = fine ? 2 : 1
            let art = fine ? (state == .waiting ? Self.fineTower : Self.fineBoat) : (state == .waiting ? Self.tower : Self.boat)
            let cols = CGFloat(Self.boat[0].count * k), rows = CGFloat((Self.boat.count + 2) * k)
            // Kleine Boote dürfen halbe Schritte nehmen (1,5 Punkt je Kästchen): Die Kästchen rasten dann einzeln auf
            // ganze Punkte ein und bleiben auch auf einem Bildschirm ohne Retina scharf.
            let px = fine ? (min(sz.width / cols, sz.height / rows) * scale).rounded(.down) / scale
                          : min(sz.width / cols, sz.height / rows).rounded(.down)
            // Zwischen den Kästchen bleibt ein schmaler Spalt – so sieht das Boot aus wie im App-Symbol.
            // Der Spalt ist ein Bildschirmpixel breit; bei ganz kleinen Booten ohne Retina wird er nur abgedunkelt,
            // sonst bliebe vom Kästchen zu wenig übrig.
            let hair = 1 / max(1, scale)
            let soft = px - hair < 1.4 && scale < 2
            let gap = fine ? hair : px < 2 ? 0 : (px >= 5 ? (px * 0.16 * scale).rounded() / scale : hair)
            let snap = { (v: CGFloat) in fine ? (v * scale).rounded() / scale : v.rounded() }
            let ox = snap((sz.width - px * cols) / 2)
            let oy = snap((sz.height - px * rows) / 2 + px * CGFloat(k))
            var bob = 0
            if state == .sailing { bob = [0, -1, 0, 1][frame % 4] }
            /// Ein Punkt des gezeichneten Rasters (im Feinraster halb so groß).
            /// `dx`/`dy` verschieben den Punkt stufenlos (in Punkt) – das Raster selbst bleibt eingerastet.
            func cell(_ x: Int, _ y: Int, _ color: Color, dx: CGFloat = 0, dy: CGFloat = 0) {
                let x0 = snap(ox + CGFloat(x) * px) + dx, x1 = snap(ox + CGFloat(x + 1) * px) + dx
                let y0 = snap(oy + CGFloat(y) * px) + dy, y1 = snap(oy + CGFloat(y + 1) * px) + dy
                if soft, gap > 0 { ctx.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)), with: .color(color.opacity(0.42))) }
                ctx.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0 - gap, height: y1 - y0 - gap)), with: .color(color))
            }
            /// Ein Punkt im groben Zwölfer-Raster – im Feinraster ein Block aus vier Punkten.
            func dot(_ x: Int, _ y: Int, _ color: Color) {
                for dy in 0..<k { for dx in 0..<k { cell(x * k + dx, y * k + dy, color) } }
            }
            let unit = px * CGFloat(k)                                    // ein Schritt im Zwölfer-Raster
            let moveX = CGFloat(slide ?? Double(shift)) * unit
            // Wiegen: fließend eine knappe halbe Rasterhöhe auf und ab, sonst ganze Schritte.
            let bobY: CGFloat = state != .sailing ? 0
                : time.map { CGFloat(sin($0 * 2 * .pi / 1.12)) * unit * 0.45 } ?? CGFloat(bob) * px
            let fade = state == .idle && !bright ? 0.82 : 1.0
            if shift != 99 {
                for (y, row) in art.enumerated() {
                    if let p = printing, Double(y) >= p * Double(art.count) { continue }
                    for (x, c) in row.enumerated() {
                        if !lit { if c != "." { cell(x, y, Color.white.opacity(0.35)) }; continue }
                        switch c {
                        case "L": cell(x, y, Color.white.opacity(Theme.calm ? 1 : time.map { 0.78 + 0.22 * cos($0 * 2 * .pi) } ?? (frame % 2 == 0 ? 1 : 0.55)), dx: moveX, dy: bobY)
                        case "S": cell(x, y, Color.white.opacity(0.96 * fade), dx: moveX, dy: bobY)
                        case "s": cell(x, y, Color.white.opacity(0.70 * fade), dx: moveX, dy: bobY)
                        case "M": cell(x, y, Color.white.opacity(0.80 * fade), dx: moveX, dy: bobY)
                        case "H": cell(x, y, Theme.accent.opacity(fade), dx: moveX, dy: bobY)
                        case "h": cell(x, y, Theme.accent.opacity(0.65 * fade), dx: moveX, dy: bobY)
                        default: break
                        }
                    }
                }
                // Kielwasser hinter dem Rumpf, solange das Boot Fahrt macht.
                let out = slide ?? Double(shift)
                if out > 0.5 {
                    for i in 1...min(4, Int(out.rounded(.up))) {
                        for d in 0..<(k * k) { cell(-i * k + d % k, 9 * k + d / k, Color.white.opacity(0.45 - 0.09 * Double(i)), dx: moveX) }
                    }
                }
            }
            // Der Lichtkegel des Leuchtturms: schwenkt abwechselnd nach rechts und links.
            if state == .waiting, lit, (printing ?? 1) >= 1, !Theme.calm {
                let side = frame % 4
                let by = fine ? 1 : 0     // im Feinraster sitzt die Laterne eine Zeile tiefer
                // Fließend blendet der Kegel im Zwei-Sekunden-Takt von rechts nach links über.
                let swing = time.map { cos($0 * .pi) }
                let right = swing.map { max(0, $0) } ?? (side == 0 ? 1 : 0), left = swing.map { max(0, -$0) } ?? (side == 2 ? 1 : 0)
                for (i, a) in [0.85, 0.55, 0.3, 0.15].enumerated() {
                    if right > 0.02 { dot(7 + i, by, .white.opacity(a * right)) }
                    if left > 0.02 { dot(4 - i, by, .white.opacity(a * left)) }
                }
            }
            // Wetter: Ab 90 % des Limits zieht eine Gewitterwolke auf, gelegentlich blitzt es.
            if sea >= 2, lit, (printing ?? 1) >= 1, shift == 0 {
                let cloud = Color.white.opacity(0.5)
                for x in 1...3 { dot(x, -1, cloud) }
                for x in 0...4 { dot(x, 0, cloud) }
                if frame % 7 == 0, state != .idle { dot(2, 1, Theme.warn); dot(1, 2, Theme.warn); dot(2, 3, Theme.warn) }
            }
            let moving = state == .sailing || shift != 0
            let wave = Self.waves[moving ? frame % 3 : 0]
            let sea0 = Color.white.opacity(state == .idle && !bright ? 0.22 : 0.42)
            if let time, lit, (printing ?? 1) >= 1 {
                // Die Wellen wandern stufenlos nach links (ein Rasterschritt je 0,28 s); an den Rändern blenden sie aus.
                // Steht das Boot oder der Leuchtturm, bleiben sie am Ort. In beiden Fällen plätschert das Wasser leicht:
                // Jeder Punkt hebt und senkt sich ein wenig, versetzt zu seinen Nachbarn.
                let n = 12 * k, base = Array(Self.waves[0])
                let phase = moving ? (time / (0.28 / Double(k))).truncatingRemainder(dividingBy: 3) : 0
                func lap(_ x: Int) -> CGFloat { CGFloat(sin(time * 2 * .pi / 2.6 + Double(x) * 1.9 / Double(k))) * unit * 0.11 }
                let whole = Int(phase), frac = CGFloat(phase - Double(whole))
                for x in 0...n {
                    let src = (x + whole) % 12
                    let pos = CGFloat(x) - frac
                    let edge = min(1, max(0, min(pos + 1, CGFloat(n) - pos)))
                    guard edge > 0 else { continue }
                    if fine {
                        cell(x, Self.boat.count * 2 + (base[src] == "w" ? 1 : 0), sea0.opacity(Double(edge)), dx: -frac * px, dy: lap(x + whole))
                    } else if base[src] == "w" {
                        cell(x, Self.boat.count, sea0.opacity(Double(edge)), dx: -frac * px, dy: lap(x + whole))
                    }
                }
            } else if fine, lit, (printing ?? 1) >= 1 {
                // Wie im App-Symbol: zwei versetzte Reihen, die zusammen eine Wellenlinie ergeben.
                let w = Array(wave)
                for x in 0..<24 { cell(x, Self.boat.count * 2 + (w[x % 12] == "w" ? 1 : 0), sea0) }
            } else {
                for (x, c) in wave.enumerated() where c == "w" && lit && (printing ?? 1) >= 1 { dot(x, Self.boat.count, sea0) }
            }
            // Höherer Seegang ab 70 % des Limits: eine zweite, versetzte Wellenreihe schlägt am Rumpf hoch.
            if sea >= 1, lit, (printing ?? 1) >= 1, state != .waiting {
                let crest = Self.waves[(moving ? frame + 1 : 1) % 3]
                if fine {
                    let w = Array(crest)
                    for x in 0..<24 where w[x % 12] == "w" && (x + frame) % 3 == 0 { cell(x, Self.boat.count * 2 - 1, Color.white.opacity(0.5)) }
                } else {
                    for (x, c) in crest.enumerated() where c == "w" && (x + frame) % 3 == 0 {
                        dot(x, Self.boat.count + 1, Color.white.opacity(0.5))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

// MARK: - Insel

struct IslandView: View {
    @ObservedObject var model: IslandModel

    /// Breite der zugeklappten Pille – sie richtet sich nach dem Statustext.
    private var compactWidth: CGFloat { Self.compactWidth(model) }

    /// Auch die Maus-Prüfung rechnet hiermit – sie darf sich nicht auf die zuletzt gemessene Größe verlassen.
    static func compactWidth(_ model: IslandModel) -> CGFloat {
        let wings = model.hasNotch ? model.notchWidth + 240 : 0
        do {
            if model.hasNotch { return wings }
            let s = TopRow.status(for: model)
            let w = ceil((s.text as NSString).size(withAttributes: [.font: NSFont.menuBarFont(ofSize: 0)]).width)
            let trail = TopRow.hasTrail(model)
            if s.text.isEmpty, !trail { return 80 }                                     // nur das Boot
            var chrome: CGFloat = 79                                                    // Ränder 44, Boot 25, Abstand 8, 2 Luft
            // Rechts genau so viel Platz, wie Laufzeit, Zähler oder Timer wirklich brauchen (gemessen) – so ist der
            // Abstand zwischen Text und Laufzeit derselbe wie zwischen Boot und Text.
            if trail { chrome += 8 + (model.trailWidth > 0 ? model.trailWidth : (model.focusRunning && model.unread == 0 && !model.discreet ? 52 : 30)) }
            if s.text.isEmpty { chrome -= 8 }
            return min(max(120, ceil(w + chrome)), 520)
        }
    }

    private var width: CGFloat {
        let wings = model.hasNotch ? model.notchWidth + 240 : 0
        switch model.mode {
        case .compact: return compactWidth
        case .peek:
            return max(peekWidth(wings), headerNeed)
        case .drop: return max(380, wings, headerNeed)
        case .expanded:
            // Eine Breite für alle Reiter: So bleiben die Symbole der Kopfzeile beim Wechsel an ihrem Platz,
            // nur die Höhe und der Inhalt darunter ändern sich.
            return max(760, wings)
        }
    }

    /// Am Notch: so breit, dass der Text der Kopfzeile ganz in den linken Flügel passt – gekürzt wird erst ab 200 Punkten.
    private var headerNeed: CGFloat {
        guard model.hasNotch else { return 0 }
        let s = TopRow.status(for: model)
        let w = ceil(((s.short.isEmpty ? s.text : s.short) as NSString).size(withAttributes: [.font: NSFont.menuBarFont(ofSize: 0)]).width)
        return model.notchWidth + 12 + 44 + 2 * (min(w, 200) + 20)      // Aussparung mit Luft, Ränder, je Flügel Punkt + Text
    }

    private func peekWidth(_ wings: CGFloat) -> CGFloat {
        do {
            if model.peekAsk != nil { return max(560, wings) }
            // Kurze Bestätigungen bleiben eine schmale Pille; alles andere wird eine Karte.
            if let n = model.peekNotice, n.bigCard { return max(540, wings) }
            if let n = model.peekNotice, let c = n.card { return max(c == "mail" ? 430 : 344, compactWidth) }
            if let n = model.peekNotice, n.brief {
                let font = NSFont(name: "Geist-Medium", size: 13) ?? NSFont.systemFont(ofSize: 12, weight: .semibold)
                let w = ((n.title + "  " + n.body) as NSString).size(withAttributes: [.font: font]).width
                // Die Pille behält die Breite der Kopfzeile: Der Notch bekommt nur ein „Kinn".
                return max(min(ceil(w) + 84, 470), compactWidth)
            }
            return max(470, wings)
        }
    }

    /// Das Wetter um das Boot folgt dem 5-Stunden-Limit.
    private var sea: Int {
        guard let p = model.limits.first(where: { $0.label == "5 Stunden" })?.percent else { return 0 }
        return p >= 90 ? 2 : p >= 70 ? 1 : 0
    }

    /// Breite des Bereichs unter der Kopfzeile: je Reiter so breit, wie sein Inhalt es braucht.
    private var contentWidth: CGFloat {
        guard model.mode == .expanded else { return width }
        switch model.tab {
        case .home, .work: return width
        case .mix: return 600
        case .stow: return model.stowFiles.isEmpty && model.shelf.isEmpty ? 540 : 640
        }
    }

    /// Um so viel ist der Inhalt je Seite schmaler als die Kopfzeile (abzüglich der „Ohren" der Form).
    private var shoulder: CGFloat { max(0, (width - contentWidth) / 2) }

    private var radius: CGFloat {
        switch model.mode {
        case .compact: return 11
        case .peek, .drop: return model.peekNotice?.small == true && model.mode == .peek ? 13 : 20
        case .expanded: return 22
        }
    }

    /// Am Notch liegt die Leuchtlinie so viel tiefer: Die Aussparung reicht bis zur Unterkante der Menüleiste
    /// und würde sie sonst verdecken. Die Pille selbst bleibt so hoch wie die Menüleiste und verdeckt nichts.
    static let chin: CGFloat = 2.5

    var body: some View {
        VStack(spacing: 0) {
            TopRow(model: model).frame(height: model.topInset)
            switch model.mode {
            case .compact: EmptyView()
            case .peek:
                if let n = model.peekNotice { PeekView(model: model, notice: n).id(n.id).transition(.emerge) }
            case .drop:
                DropHint().transition(.emerge)
            case .expanded:
                Group {
                    switch model.tab {
                    case .home: HomeView(model: model)
                    case .work: WorkView(model: model)
                    case .mix: MixerView(model: model)
                    case .stow: StowView(model: model)
                    }
                }
                .padding(.horizontal, 12).padding(.top, shoulder > 0 ? 14 : 6).padding(.bottom, 12)
                .frame(width: shoulder > 0 ? contentWidth - 14 : nil)
                .frame(maxWidth: .infinity)
                .id(model.tab)
                .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.easeOut(duration: 0.09))))
            }
        }
        .frame(width: width)
        .animation(IslandModel.spring, value: width)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(GlassGroup(style: model.glass))
        .modifier(IslandSurface(style: model.glass, compact: model.mode == .compact, expanded: model.mode == .expanded,
                                notch: model.hasNotch, topInset: model.topInset, radius: radius, shoulder: shoulder))
        // Arbeitet Claude, zeigt die Ruhe-Pille das mit einer Lichtspur am Rand.
        .overlay(alignment: .bottom) {
            if model.mode == .compact, !model.discreet, model.wave != .off,
               model.sessions.contains(where: { $0.status == .working }) || model.now < model.wavePreviewUntil {
                Group {
                    if model.wave == .outline {
                        OutlineGlow(radius: radius)
                    } else {
                        WorkWave(style: model.wave).frame(height: 22).padding(.horizontal, 10).offset(y: 19 + (model.hasNotch ? IslandView.chin : 0))
                    }
                }
                .allowsHitTesting(false).transition(.opacity)
            }
        }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { model.pillSize = g.size }
                .onChange(of: g.size) { _, s in model.pillSize = s }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.glass, model.glass)
        .environment(\.sea, sea)
        .id(model.palette)
        .environment(\.colorScheme, .dark)
    }
}

/// Bündelt die Glasstücke der Insel, damit macOS sie gemeinsam zeichnet.
struct GlassGroup: ViewModifier {
    var style: GlassStyle
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), style == .liquid {
            GlassEffectContainer(spacing: 4) { content }
        } else {
            content
        }
    }
}

// MARK: - Glas

enum GlassStyle: String, CaseIterable {
    case liquid, frosted, solid, preview
    var title: String {
        switch self {
        case .liquid: return "Schiefer mit Verlauf (Standard)"
        case .frosted: return "Milchglas"
        case .solid: return "Dunkel, undurchsichtig"
        case .preview: return "Vorschau"
        }
    }
}

/// Klassische Unschärfe des Hintergrunds hinter dem Fenster.
struct BehindBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .vibrantDark)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

/// Die Fläche der Insel. Im Liquid-Glass-Stil gilt: zugeklappt und beim Kurz-Hinweis ist die Insel EIN Stück
/// klares Glas; aufgeklappt gibt es keinen Kasten mehr – jede Kachel ist ihr eigenes Glasstück.
/// Die Arbeitswelle am unteren Rand der Pille, in mehreren Spielarten.
struct WorkWave: View {
    var style: WaveStyle = .fine
    @Environment(\.accessibilityReduceMotion) private var still

    static var colors: [Color] { Theme.tones.wave }

    var body: some View {
        // Das langsame Glimmen kommt mit halb so vielen Bildern aus – das spart über Stunden spürbar Strom.
        TimelineView(.animation(minimumInterval: style == .breath ? 1.0 / 15 : 1.0 / 30, paused: still)) { ctx in
            let t = Probe.time ?? (still ? 0.8 : ctx.date.timeIntervalSinceReferenceDate)
            Canvas { g, size in
                let w = size.width
                let shift = CGFloat((t * 0.12).truncatingRemainder(dividingBy: 1)) * w
                let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: Self.colors + Self.colors),
                                                                   startPoint: CGPoint(x: -w + shift, y: 0), endPoint: CGPoint(x: w + shift, y: 0))
                switch style {
                case .comet:
                    // Ein heller Punkt mit Schweif pendelt am Rand entlang.
                    let u = 0.5 + 0.46 * sin(t * 1.1)
                    let dir: CGFloat = cos(t * 1.1) >= 0 ? 1 : -1
                    let x = w * CGFloat(u)
                    var line = Path(); line.move(to: CGPoint(x: 0, y: 3)); line.addLine(to: CGPoint(x: w, y: 3))
                    g.stroke(line, with: .color(Theme.accent.opacity(0.18)), lineWidth: 1)
                    let tail = Path { p in p.move(to: CGPoint(x: x - dir * 70, y: 3)); p.addLine(to: CGPoint(x: x, y: 3)) }
                    let fade = GraphicsContext.Shading.linearGradient(Gradient(colors: [.clear, Self.colors[1], .white]),
                                                                      startPoint: CGPoint(x: x - dir * 70, y: 3), endPoint: CGPoint(x: x, y: 3))
                    var glow = g; glow.addFilter(.blur(radius: 5))
                    glow.stroke(tail, with: fade, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    g.stroke(tail, with: fade, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                case .breath:
                    // Der ganze Rand glimmt langsam auf und ab.
                    let k = 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 1.6))
                    var line = Path(); line.move(to: CGPoint(x: 0, y: 3)); line.addLine(to: CGPoint(x: w, y: 3))
                    var glow = g; glow.addFilter(.blur(radius: 7)); glow.opacity = k
                    glow.stroke(line, with: shade, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    var sharp = g; sharp.opacity = 0.4 + 0.6 * k
                    sharp.stroke(line, with: shade, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                default:
                    let bold = style == .bold
                    var path = Path()
                    let steps = max(2, Int(w / 2))
                    for i in 0...steps {
                        let x = w * CGFloat(i) / CGFloat(steps)
                        let u = Double(x / w)
                        // Zwei gegenläufige Wellenberge plus ein feines Kräuseln; zu den Enden hin flach.
                        let a = exp(-pow((u - (0.5 + 0.42 * sin(t * 0.9))) / 0.09, 2))
                        let b = exp(-pow((u - (0.5 + 0.36 * sin(t * 0.6 + 2.1))) / 0.13, 2)) * 0.6
                        let ripple = sin(u * 26 - t * 3.2) * 0.12
                        let y = 3 + CGFloat((a + b + ripple) * sin(u * .pi)) * (bold ? 11 : 6)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    var glow = g; glow.addFilter(.blur(radius: bold ? 8 : 5))
                    glow.stroke(path, with: shade, style: StrokeStyle(lineWidth: bold ? 8 : 5, lineCap: .round))
                    g.stroke(path, with: shade, style: StrokeStyle(lineWidth: bold ? 2.2 : 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        // Zu den Rändern hin ausblenden, damit die Linie aus der Pille herauswächst.
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                     .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .accessibilityHidden(true)
    }
}

/// Spielart „Umriss": Ein Lichtband läuft um Seiten und Unterkante der Pille.
struct OutlineGlow: View {
    var radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { ctx in
            let t = still ? 0.0 : ctx.date.timeIntervalSinceReferenceDate
            let shape = NotchShape(bottomRadius: radius)
            let paint = AngularGradient(colors: [.clear, Theme.tones.wave[0], Theme.tones.wave[1], Theme.tones.wave[2], .clear],
                                        center: .center, angle: .degrees((t * 80).truncatingRemainder(dividingBy: 360)))
            ZStack {
                shape.stroke(paint, lineWidth: 5).blur(radius: 5)
                shape.stroke(paint, lineWidth: 1.5)
            }
            // Die Oberkante liegt am Bildschirmrand – dort kein Licht.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.45)],
                                 startPoint: .top, endPoint: .bottom).padding(-12))
        }
        .accessibilityHidden(true)
    }
}

struct IslandSurface: ViewModifier {
    var style: GlassStyle
    var compact: Bool
    var expanded: Bool
    var notch: Bool
    var topInset: CGFloat
    var radius: CGFloat

    var shoulder: CGFloat = 0
    private var shape: NotchShape { NotchShape(bottomRadius: radius, shoulder: shoulder, head: topInset + 5) }
    private static var tint: Color { Theme.tones.tint }

    /// Am echten Notch bleibt der obere Streifen schwarz, damit die Insel aus dem Notch herauswächst.
    @ViewBuilder private var notchBand: some View {
        if notch {
            VStack(spacing: 0) {
                Color.black.frame(height: topInset)
                Spacer(minLength: 0)
            }
        }
    }

    private var rim: some View {
        shape.stroke(LinearGradient(colors: [.white.opacity(0.05), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
    }

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), style == .liquid {
            if notch && compact {
                content.background(Color.black).clipShape(shape)      // der Notch selbst ist Hardware, kein Glas
            } else {
                // Dunkle Fläche um alles (bewusst so), die Kacheln darauf sind eigene Glasstücke.
                // Die Fläche ist bewusst kein Glas und kein Elternteil mit Maske – sonst würden die Kacheln matt.
                content
                    .background(notchBand)
                    .clipShape(shape)
                    .background(
                        shape.fill(LinearGradient(colors: Theme.tones.surface,
                                                  startPoint: .top, endPoint: .bottom))
                            .opacity(1)
                            .shadow(color: .black.opacity(compact ? 0 : 0.45), radius: 24, y: 10)
                    )
                    .overlay(rim)      // feine Kante: ohne sie verschwindet die Fläche vor dunklen Fenstern
            }
        } else if style == .frosted || style == .liquid {
            painted(content, blur: true, opacity: 0.38)
        } else {
            painted(content, blur: false, opacity: style == .solid ? 1 : 0.45)
        }
    }

    private func painted(_ content: Content, blur: Bool, opacity: Double) -> some View {
        content
            .background(ZStack {
                if blur { BehindBlur() }
                Self.tint.opacity(opacity)
                LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
                notchBand
            })
            .clipShape(shape)
            .overlay(rim)
            .shadow(color: .black.opacity(compact ? 0.1 : 0.4), radius: compact ? 6 : 26, y: compact ? 2 : 12)
    }
}

// MARK: - Kopfzeile (immer sichtbar, in Höhe der Menüleiste)

struct TopRow: View {
    @ObservedObject var model: IslandModel
    @Namespace private var ns

    struct Status {
        var text: String
        var short: String = ""
        var color: Color = Theme.faint
        var pulsing = false
    }

    private var status: Status { Self.status(for: model) }

    static func status(for model: IslandModel) -> Status {
        if model.mode == .peek, let n = model.peekNotice, !n.small {
            if n.kind == .calendar, n.event != nil {
                return Status(text: "Termin", color: Theme.accent, pulsing: true)
            }
            // Am Notch steht in der Kopfzeile nur, von wem der Hinweis kommt – der Titel steht ohnehin in der Karte darunter.
            let from = n.appName.components(separatedBy: " · ").first ?? ""
            return Status(text: n.kind == .system ? n.appName : n.title, short: from.isEmpty ? n.title : from, color: Theme.accent, pulsing: true)
        }
        if model.mode == .drop { return Status(text: "Ablage", color: Theme.accent, pulsing: true) }
        // Im Besprechungsmodus nennt die Pille keine Projekt- oder Terminnamen.
        let hide = model.discreet
        if let a = model.asks.first, a.isQuestion {
            return Status(text: hide ? "Claude hat eine Frage" : "Claude hat eine Frage · \(a.project)", short: "Frage", color: Theme.accent, pulsing: true)
        }
        if let a = model.asks.first {
            return Status(text: hide ? "Claude wartet auf dein OK" : "Claude wartet auf dein OK · \(a.project)", short: "OK?", color: Theme.accent, pulsing: true)
        }
        if let s = model.sessions.first(where: { $0.status == .waiting }) {
            return Status(text: hide ? "Claude braucht dich" : "Claude braucht dich · \(s.project)", short: "Claude", color: Theme.accent, pulsing: true)
        }
        let busy = model.sessions.contains { $0.status == .working }
        // Arbeitet Claude, zeigt die Pille, woran – der nächste Termin drängt sich erst fünf Minuten vorher vor.
        // Steht der Termin unten neben dem Dock, nennt ihn die Laufschrift nicht noch einmal.
        if !model.dockEventHint, let e = model.nextEvent, e.start.timeIntervalSince(model.now) < (busy ? 300 : 3600),
           !busy || e.start.timeIntervalSince(model.now) > -60 {
            // Läuft der Termin schon, sagt die Pille, welcher es ist und bis wann – „läuft" allein erklärt nichts.
            if e.start <= model.now {
                let end = "bis " + Fmt.time.string(from: e.end)
                return Status(text: (hide ? "Termin" : e.title) + " · " + end, short: "Termin", color: Theme.accent)
            }
            let t = Fmt.until(e.start, now: model.now)
            return Status(text: hide ? "Termin \(t)" : "\(e.title) \(t)", short: t, color: Theme.accent, pulsing: e.start.timeIntervalSince(model.now) < 300)
        }
        let working = model.sessions.filter { $0.status == .working }
        if working.count > 1 {
            // Mehrere Sessions zugleich: die Pille nennt die Zahl und die Projekte, Einzelheiten stehen aufgeklappt.
            var names: [String] = []
            for s in working where !names.contains(s.project) { names.append(s.project) }
            let list = names.prefix(2).joined(separator: ", ") + (names.count > 2 ? " +\(names.count - 2)" : "")
            return Status(text: hide ? "\(working.count) Sessions arbeiten" : "\(working.count) Sessions arbeiten · \(list)",
                          short: "\(working.count)×", color: Theme.accent, pulsing: true)
        }
        if let s = model.sessions.first(where: { $0.status == .working }) {
            let what = s.planStep.isEmpty ? s.detail : s.planStep
            let text = what.isEmpty ? "Claude arbeitet · \(s.project)" : "\(s.project) · \(what)"
            return Status(text: hide ? "Claude arbeitet" : text, short: "Claude", color: Theme.accent, pulsing: true)
        }
        // Läuft die Musik unten neben dem Dock, bleibt oben nur das Cover: die Flügel gehören dann Claude, Terminen und Mitteilungen.
        if let t = model.track, t.isPlaying { return Status(text: model.dockMusicHint ? "" : "\(t.title) · \(t.artist)") }
        if !model.dockEventHint, let e = model.nextEvent, e.start.timeIntervalSince(model.now) < 8 * 3600 {
            let time = Fmt.time.string(from: e.start)
            return Status(text: hide ? "Termin · \(time)" : "\(e.title) · \(time)", short: time)
        }
        // Nichts los: Datum und Uhr stehen schon in der Menüleiste – die Pille zeigt dann nur das Boot.
        return Status(text: "")
    }

    /// Der Statustext, aufgeteilt auf die beiden Flügel am Notch: vor und nach dem ersten „ · ".
    static func halves(_ s: Status) -> (String, String) {
        guard let r = s.text.range(of: " · ") else { return (s.text, "") }
        return (String(s.text[..<r.lowerBound]), String(s.text[r.upperBound...]))
    }

    /// Ob rechts in der Ruhe-Pille etwas steht (Zähler, Timer, Arbeitsdauer, Besprechungsmodus).
    static func hasTrail(_ model: IslandModel) -> Bool {
        if case .recording = model.recState { return true }
        return model.discreet || model.unread > 0 || model.focusRunning
            || model.sessions.contains { $0.status == .working && ($0.startedAt != nil || $0.planTotal > 0) }
    }

    var body: some View {
        HStack(spacing: 8) {
            if model.mode == .compact, !model.hasNotch, status.text.isEmpty, !Self.hasTrail(model) {
                // Nichts zu melden: nur das Boot, mittig.
                Mascot(size: 25, state: boat).frame(maxWidth: .infinity)
            } else {
                if model.hasNotch {
                    // Am Notch: zwei gleich breite Flügel, dazwischen die Aussparung. Was nicht in einen Flügel
                    // passt, wird gekürzt – hinter der Aussparung könnte es niemand lesen.
                    HStack(spacing: 8) { if model.mode == .expanded { tabs } else { lead } }
                        .frame(maxWidth: .infinity, alignment: .leading).clipped()
                    Color.clear.frame(width: max(0, model.notchWidth + 12 - 16))      // 6 Punkte Luft je Seite, abzüglich der Abstände
                    HStack(spacing: 8) {
                        if model.mode == .compact, case .recording = model.recState { trail }      // der Mitschnitt bleibt immer sichtbar
                        else if model.mode == .compact { Ticker(full: Self.halves(status).1, alignment: .trailing, stay: !Self.hasTrail(model), color: Theme.soft) { trail } }
                        else { trail }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing).clipped()
                } else {
                if model.mode == .expanded { tabs } else { lead }
                if model.mode == .compact {
                    // Zugeklappt ohne Notch: Die Laufzeit rückt bis auf denselben Abstand an den Text heran,
                    // den auch das Boot zum Text hat. Der Text darf sich zuerst ausbreiten.
                    trail.fixedSize()
                        .background(GeometryReader { g in Color.clear.preference(key: TrailWidthKey.self, value: g.size.width) })
                        .onPreferenceChange(TrailWidthKey.self) { w in
                            if abs(w - model.trailWidth) > 0.5 { DispatchQueue.main.async { model.trailWidth = w } }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Spacer(minLength: 10)
                    trail
                }
                }
            }
        }
        .padding(.horizontal, model.mode == .expanded ? 18 : 22)
    }

    @ViewBuilder private var lead: some View {
        let s = status
        if model.mode == .compact, let t = model.track, t.isPlaying, !s.pulsing {
            Cover(image: t.artwork, size: 16, radius: 4)
        } else if model.mode == .compact {
            // Das Boot ist die Statusanzeige der Ruhe-Pille: segelt = Claude arbeitet, Flagge = wartet auf dich.
            Mascot(size: 25, state: boat)
        } else {
            Dot(color: s.color, pulsing: s.pulsing).id("\(s.pulsing)-\(model.mode == .peek)")
        }
        if model.hasNotch, model.mode == .compact {
            // Zugeklappt am Notch: links, worum es geht (danach das Kurzwort), rechts die Einzelheit (danach Laufzeit oder Zähler).
            Ticker(full: Self.halves(s).0) {
                Text(s.short).font(Theme.bar).foregroundStyle(Theme.text).lineLimit(1)
            }
        } else {
            Text(model.hasNotch && !(s.short.isEmpty && model.mode == .peek) ? s.short : s.text)
                .font(Theme.bar).foregroundStyle(Theme.text).lineLimit(1)
                .layoutPriority(1)
        }
    }

    private var boat: Mascot.State {
        if !model.asks.isEmpty || model.sessions.contains(where: { $0.status == .waiting }) { return .waiting }
        if model.sessions.contains(where: { $0.status == .working }) { return .sailing }
        return .idle
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            tab(.home, "house.fill", "Überblick")
            if model.shows("tab.work") { tab(.work, "timer", "Fokus, Zwischenablage, Termine") }
            if model.shows("tab.mix") { tab(.mix, "slider.horizontal.3", "Lautstärke") }
            if model.shows("tab.stow") { tab(.stow, "tray.and.arrow.down.fill", "Ablage") }
        }
    }

    private func tab(_ t: Tab, _ icon: String, _ name: String) -> some View {
        Button { withAnimation(IslandModel.spring) { model.tab = t } } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(model.tab == t ? Theme.text : Theme.faint)
                .frame(width: 30, height: 26)
                .background {
                    // Ein einziger Kreis, der zum gewählten Reiter hinübergleitet.
                    if model.tab == t {
                        Circle().fill(Color.white.opacity(0.16)).frame(width: 24, height: 24)
                            .matchedGeometryEffect(id: "tab", in: ns)
                    }
                }
                .contentShape(Rectangle())
        }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(model.tab == t ? .isSelected : [])
        .buttonStyle(.plain)
    }

    private func tool(_ icon: String, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.faint)
                .frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).modifier(HoverGlow()).help(name).accessibilityLabel(name)
    }

    /// Was rechts oben als leiser Status steht.
    private var note: String {
        if model.discreet { return "" }
        if let a = model.asks.first { return a.isQuestion ? "hat eine Frage" : "wartet auf dein OK" }
        if model.tab == .home, !model.sessions.contains(where: { $0.status == .working }),
           let s = model.sessions.first(where: { $0.status == .done }), let at = s.doneAt, let took = s.tookSeconds,
           model.now.timeIntervalSince(at) < 120 {
            return "\(s.project) fertig in " + (took < 90 ? "\(took) s" : "\(took / 60) Min")
        }
        return ""
    }

    /// Die arbeitende Session für den rechten Flügel: zuerst eine mit Plan, sonst eine mit Startzeit.
    private var workingForTrail: ClaudeSession? {
        let w = model.sessions.filter { $0.status == .working }
        return w.first { $0.planTotal > 0 } ?? w.first { $0.startedAt != nil }
    }

    @ViewBuilder private var trail: some View {
        if model.mode == .expanded {
            if !note.isEmpty {
                // Passt der Projektname nicht in den Flügel, bleibt nur „fertig in …" – die Session steht darunter.
                ViewThatFits(in: .horizontal) {
                    Text(note).fixedSize()
                    Text(note.range(of: "fertig in ").map { String(note[$0.lowerBound...]) } ?? note).fixedSize()
                    Text(note)
                }
                .font(Theme.system(12)).foregroundStyle(Theme.faint).lineLimit(1).padding(.trailing, 6)
            }
            tool("wifi", "WLAN-Einstellungen öffnen") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!)
            }
            tool("folder", "Schnellzugriff auf deine Ordner") { model.showFolders?() }
        } else if case .recording(let since) = model.recState, model.mode == .compact {
            // Ein laufender Mitschnitt hat Vorrang vor allem anderen – er darf nie unbemerkt weiterlaufen.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 5) {
                    Circle().fill(RecordTile.red).frame(width: 7, height: 7)
                    Text(Fmt.elapsed(ctx.date.timeIntervalSince(since))).font(Theme.bar).monospacedDigit().foregroundStyle(Theme.text)
                }
                .accessibilityLabel("Mitschnitt läuft")
            }
        } else if model.discreet, model.unread == 0, model.mode == .compact {
            // Zeigt, dass der Besprechungsmodus gerade Inhalte zurückhält.
            Image(systemName: "eye.slash.fill").font(.system(size: 10)).foregroundStyle(Theme.muted)
                .help("Besprechungsmodus: Inhalte von Hinweisen sind ausgeblendet")
                .accessibilityLabel("Besprechungsmodus aktiv")
        } else if model.unread > 0, model.mode == .compact {
            Text("\(min(model.unread, 99))")
                .font(Theme.system(11, .semibold)).monospacedDigit().foregroundStyle(Theme.onIce)
                .padding(.horizontal, 5).frame(minWidth: 17, minHeight: 17)
                .background(Capsule().fill(Theme.ice))
        } else if model.focusRunning, model.mode == .compact {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 4) {
                    Image(systemName: "timer").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(Fmt.clock(model.focusRemaining(at: ctx.date)))
                        .font(Theme.bar).monospacedDigit().foregroundStyle(Theme.text)
                }
            }
        } else if model.mode == .compact, let s = workingForTrail {
            HStack(spacing: 7) {
                // Hat Claude einen Plan, füllt sich mit jedem erledigten Schritt ein schmaler Balken.
                if s.planTotal > 0 {
                    PlanFill(done: s.planDone, total: s.planTotal)
                        .help("Schritt \(min(s.planDone + 1, s.planTotal)) von \(s.planTotal)")
                        .accessibilityLabel("Claude hat \(s.planDone) von \(s.planTotal) Schritten erledigt")
                }
                // Statt der Uhr (die steht schon in der Menüleiste): wie lange Claude am laufenden Auftrag arbeitet.
                if let since = s.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Fmt.elapsed(ctx.date.timeIntervalSince(since)))
                            .font(Theme.bar).monospacedDigit().foregroundStyle(Theme.muted)
                            .accessibilityLabel("Claude arbeitet seit \(Int(ctx.date.timeIntervalSince(since)) / 60) Minuten")
                    }
                }
            }
        }
    }
}

/// Fortschritt für die Ruhe-Pille im Pixelraster des Boots: drei Reihen quadratischer Punkte,
/// erledigte Schritte leuchten in der Akzentfarbe, der laufende Schritt glimmt, der Rest bleibt blass.
struct PlanFill: View {
    let done: Int
    let total: Int
    static let cell: CGFloat = 1.5, gap: CGFloat = 0.5, cols = 20, rows = 3      // dasselbe Raster wie das Boot: 2 pt Schritt, 0,5 pt Spalt
    static var size: CGSize { CGSize(width: CGFloat(cols) * (cell + gap) - gap, height: CGFloat(rows) * (cell + gap) - gap) }
    @State private var glow = false

    /// Welche Spalten erledigt sind und bis wohin der laufende Schritt reicht.
    static func columns(done: Int, total: Int) -> (filled: Int, current: Int) {
        let n = max(total, 1), d = min(max(done, 0), n)
        let filled = Int((Double(d) / Double(n) * Double(cols)).rounded())
        let current = d >= n ? filled : max(filled + 1, Int((Double(d + 1) / Double(n) * Double(cols)).rounded()))
        return (filled, min(current, cols))
    }

    var body: some View {
        let c = Self.columns(done: done, total: total)
        ZStack {
            grid { col in col < c.filled ? Theme.accent : col < c.current ? nil : Color.white.opacity(0.16) }
            grid { col in col >= c.filled && col < c.current ? Theme.accent : nil }
                .opacity(glow ? 0.75 : 0.25)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true } }
    }

    private func grid(_ color: @escaping (Int) -> Color?) -> some View {
        Canvas { g, _ in
            for col in 0..<Self.cols {
                guard let fill = color(col) else { continue }
                for row in 0..<Self.rows {
                    let r = CGRect(x: CGFloat(col) * (Self.cell + Self.gap), y: CGFloat(row) * (Self.cell + Self.gap), width: Self.cell, height: Self.cell)
                    g.fill(Path(r), with: .color(fill))
                }
            }
        }
    }
}

/// Laufschrift in einem Flügel neben der Aussparung: Ändert sich der Text, läuft er einmal durch
/// (Anfang kurz stehen lassen, dann bis zum Ende schieben), danach steht wieder der Ruhe-Inhalt (`rest`):
/// links das Kurzwort, rechts Laufzeit oder Zähler. Zwischen zwei Läufen liegen mindestens 12 Sekunden Ruhe –
/// sonst liefe sie bei jeder kleinen Änderung los und würde ständig am Blickrand zappeln.
struct Ticker<Rest: View>: View {
    let full: String
    var alignment: Alignment = .leading
    /// Passt der Text ganz in den Flügel: bleibt er stehen, oder macht er nach ein paar Sekunden Platz (rechts, wenn dort
    /// sonst Laufzeit oder Zähler stehen)?
    var stay = true
    var color: Color = Theme.text
    @ViewBuilder var rest: Rest
    @State private var latest = ""          // der aktuelle Text, für die Schleife unten
    @State private var shown = ""           // der Text, der gerade durchläuft
    @State private var start: Date?
    @State private var wing: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var still

    private static var speed: Double { 34 }
    private static var lead: Double { 0.9 }
    private static var hold: Double { 1.1 }
    private static var pause: Double { 12 }
    private static func width(_ s: String) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: NSFont.menuBarFont(ofSize: 0)]).width)
    }

    var body: some View {
        GeometryReader { g in
            Group {
                if let start, !shown.isEmpty {
                    let over = max(0, Self.width(shown) - g.size.width)
                    TimelineView(.animation(paused: over == 0)) { ctx in
                        let t = ctx.date.timeIntervalSince(start)
                        label(shown).fixedSize().offset(x: -min(max(0, (t - Self.lead) * Self.speed), over))
                    }
                    .frame(width: g.size.width, alignment: over > 0 ? .leading : alignment).clipped()
                    .mask(LinearGradient(stops: [.init(color: over > 0 ? .clear : .black, location: 0), .init(color: .black, location: 0.08),
                                                 .init(color: .black, location: 0.9), .init(color: over > 0 ? .clear : .black, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .transition(.opacity)
                } else if stay, !full.isEmpty, Self.width(full) <= g.size.width {
                    label(full).transition(.opacity)         // passt ganz: dann steht einfach der volle Text da
                } else {
                    rest.transition(.opacity)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: alignment)
            .onChange(of: g.size.width, initial: true) { _, w in wing = w }
        }
        .onChange(of: full, initial: true) { _, f in latest = f }
        // Eine Schleife statt eines Laufs je Änderung: Ein laufender Text wird zu Ende gezeigt, auch wenn inzwischen
        // ein neuer da ist – sonst käme bei schnellen Wechseln nie einer durch.
        .task {
            var done = ""
            while !Task.isCancelled {
                let text = latest
                let fits = Self.width(text) <= wing
                if text == done || text.isEmpty || wing <= 0 || (fits && stay) || (!fits && still) {
                    if text.isEmpty { done = "" }
                    try? await Task.sleep(for: .seconds(0.3)); continue
                }
                shown = text; done = text
                withAnimation(.easeInOut(duration: 0.3)) { start = Date() }
                let over = max(0, Self.width(text) - wing)
                try? await Task.sleep(for: .seconds(fits ? 4 : Self.lead + over / Self.speed + Self.hold))
                withAnimation(.easeInOut(duration: 0.3)) { start = nil }
                try? await Task.sleep(for: .seconds(Self.pause))
            }
        }
        .accessibilityLabel(full)
    }

    private func label(_ s: String) -> some View {
        Text(s).font(Theme.bar).foregroundStyle(color).lineLimit(1)
    }
}

// MARK: - Kurz-Hinweis

struct PeekView: View {
    @ObservedObject var model: IslandModel
    let notice: Notice

    private var doneSession: ClaudeSession? {
        guard notice.kind == .claude, !model.discreet, let sid = notice.sessionID else { return nil }
        return model.sessions.first { $0.id == sid && $0.status == .done && !$0.summary.isEmpty }
    }

    var body: some View {
        if notice.card == "away", let a = model.away {
            AwayView(model: model, summary: a)
        } else if notice.card == "leave" {
            if let c = model.leave, c.event.id == notice.event?.id { LeaveView(model: model, card: c) }
        } else if notice.card == "leave-ask" {
            LeaveAskView(model: model)
        } else if let card = notice.card {
            // Ein Klick auf die Karte öffnet, worum es geht (z. B. die Mail-App).
            Button { model.open(notice); model.dismissPeek() } label: {
                DeviceCard(kind: card, title: notice.title, subtitle: notice.body).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else if notice.brief {
            // Kleine Meldung: eine Zeile direkt unter der Kopfzeile.
            HStack(spacing: 8) {
                Image(systemName: notice.symbol ?? (notice.title == "Abgelehnt" ? "xmark.circle.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(notice.title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text)
                if !notice.body.isEmpty {
                    Text(notice.body).font(Theme.font(13)).monospacedDigit().foregroundStyle(Theme.muted)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.horizontal, 18).padding(.top, 5).padding(.bottom, 13)
        } else {
            Group {
                if let ask = model.peekAsk {
                    AskScene(model: model, ask: ask, staged: true)
                } else if notice.kind == .calendar, let e = notice.event {
                    CalendarPeek(model: model, notice: notice, event: e)
                } else if let s = doneSession {
                    VStack(alignment: .leading, spacing: 11) {
                        DoneScene(model: model, session: s, staged: true)
                        buttons.padding(.leading, 62).modifier(SlideIn(delay: 0.95))
                    }
                } else {
                    plain
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        }
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("Später") { model.dismissPeek() }.buttonStyle(CapsuleStyle(compact: true))
            if notice.kind != .info {
                Button(notice.kind == .calendar ? (notice.url != nil ? "Beitreten" : "OK") : "Öffnen") {
                    model.open(notice); model.dismissPeek()
                }
                .buttonStyle(CapsuleStyle(primary: true, compact: true))
            }
        }
    }

    private var plain: some View {
        HStack(alignment: .top, spacing: 12) {
            if notice.kind == .claude {
                // „Claude braucht dich" / „hat eine Frage": Boot mit blinkender Signalflagge.
                StagedMascot(size: 42) { _ in notice.title.contains("braucht") ? .waiting : .idle }
            } else {
                AppIcon(id: notice.appID, size: 34)
            }
            VStack(alignment: .leading, spacing: 9) {
                VStack(alignment: .leading, spacing: 2) {
                    if model.hasNotch || notice.kind == .system {
                        Text(notice.title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    } else {
                        Text(notice.appName).font(Theme.font(11)).foregroundStyle(Theme.faint)
                    }
                    if !notice.body.isEmpty {
                        Text(notice.body).font(Theme.font(12)).foregroundStyle(Theme.soft)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                buttons
            }
            .modifier(SlideIn(delay: 0.78, active: notice.kind == .claude))
            Spacer(minLength: 0)
        }
    }
}

/// Die Terminkarte einer Erinnerung: Man soll sofort sehen, welcher Termin gemeint ist.
struct CalendarPeek: View {
    @ObservedObject var model: IslandModel
    let notice: Notice
    let event: CalEvent

    private var title: String { event.label(discreet: model.discreet) }
    private var span: String { "\(Fmt.time.string(from: event.start)) – \(Fmt.time.string(from: event.end))" }
    private var minutes: Int { max(0, Int(ceil(event.start.timeIntervalSince(model.now) / 60))) }
    private var started: Bool { event.start <= model.now }
    private var duration: String {
        let m = Int(event.end.timeIntervalSince(event.start) / 60)
        return m >= 60 && m % 60 == 0 ? "\(m / 60) Std" : m > 60 ? "\(m / 60) Std \(m % 60) Min" : "\(m) Min"
    }
    private var place: String { model.discreet && event.role == .personal ? "" : event.whereLabel }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button("Später") { model.dismissPeek() }.buttonStyle(CapsuleStyle(compact: true))
            Button(notice.url != nil ? "Beitreten" : "OK") { model.open(notice); model.dismissPeek() }
                .buttonStyle(CapsuleStyle(primary: true, compact: true))
        }
        .fixedSize().layoutPriority(1)      // die Knöpfe bleiben ganz, bei Platzmangel kürzen die Marken
    }

    /// Eine Kennzeile (wie bald, von wann bis wann), der Titel groß, Eckdaten als Marken, Knöpfe rechts.
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(event.color).frame(width: 7, height: 7)
                Text((started ? "BEGINNT JETZT" : "IN \(minutes) MIN") + " · " + span)
                    .font(Theme.font(10, .semibold)).tracking(0.7).monospacedDigit().foregroundStyle(Theme.accent)
            }
            Text(title).font(Theme.font(18, .semibold)).foregroundStyle(Theme.text)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 6) {
                if let s = event.role.symbol { chip(s, event.role.title) }
                if !place.isEmpty { chip(event.joinURL != nil ? "video.fill" : "mappin.and.ellipse", place) }
                chip("clock", duration)
                Spacer(minLength: 8)
                buttons
            }
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .medium))
            Text(text).font(Theme.font(11)).lineLimit(1)
        }
        .foregroundStyle(Theme.soft)
        .padding(.horizontal, 8).frame(height: 22)
        .background(Capsule().fill(Theme.tile))
    }
}

/// Das Boot baut sich auf wie die Grafik einer Geräte-Karte: Zeile für Zeile gedruckt, dann leuchtet es auf –
/// erst danach übernimmt die normale Zustands-Animation (segeln, Flagge, anlegen).
struct StagedMascot: View {
    var size: CGFloat
    /// Der Zustand nach dem Aufbau; bekommt den Zeitpunkt, zu dem der Aufbau fertig ist.
    var then: (Date) -> Mascot.State
    @State private var start = Date()
    @State private var built = false
    /// Für Probebilder: sofort fertig zeigen.
    static var instant = false

    var body: some View {
        if built || Theme.calm || Self.instant {
            Mascot(size: size, state: then(start.addingTimeInterval(1.0)))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                let t = ctx.date.timeIntervalSince(start) - 0.28            // erst, wenn die Form fast steht
                Mascot(size: size, state: .idle, printing: min(1, max(0, t / 0.4)), lit: t >= 0.5)
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                built = true
            }
            .onAppear { start = Date() }
        }
    }
}

/// Text gleitet nach dem Aufleuchten von links herein.
struct SlideIn: ViewModifier {
    var delay: Double
    var active = true
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || !active ? 1 : 0)
            .offset(x: shown || !active ? 0 : -7)
            .onAppear {
                guard active else { return }
                if Theme.calm || StagedMascot.instant { shown = true; return }
                withAnimation(.easeOut(duration: 0.5).delay(delay)) { shown = true }
            }
    }
}

/// Geräte-Karte (Kopfhörer verbunden). Der Aufbau folgt einer festen Abfolge:
/// Die Punktgrafik wird zeilenweise „gedruckt" (erst links, dann rechts), leuchtet dann auf,
/// das Funkzeichen rechts geht an, der Text gleitet herein, das Funkzeichen ebbt wieder ab.
struct DeviceCard: View {
    var kind = "headphones"
    var title: String
    var subtitle: String
    @State private var start = Date()
    /// Für Probebilder: einen festen Zeitpunkt der Abfolge zeigen.
    static var freeze: Double?

    // Briefumschlag als Punktraster.
    private static let mail = [
        "#################",
        "##.............##",
        "#.##.........##.#",
        "#...##.....##...#",
        "#.....##.##.....#",
        "#.......#.......#",
        "#...............#",
        "#...............#",
        "#...............#",
        "#################",
    ]
    private var glyph: [String] { kind == "mail" ? Self.mail : Self.phones }

    // Kopfhörer als Punktraster (eigene Zeichnung).
    private static let phones = [
        "....#########....",
        "..###.......###..",
        ".##...........##.",
        ".#.............#.",
        "##.............##",
        "###...........###",
        "###...........###",
        "###...........###",
        "###...........###",
        ".##...........##.",
    ]

    var body: some View {
        Group {
            if let f = Self.freeze {
                content(t: f)
            } else if Theme.calm {
                content(t: 9)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    content(t: ctx.date.timeIntervalSince(start) - 0.28)      // erst, wenn die Form fast steht
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 18)
        .onAppear { start = Date() }
    }

    private func ramp(_ t: Double, _ from: Double, _ to: Double) -> Double { min(1, max(0, (t - from) / (to - from))) }

    private func content(t: Double) -> some View {
        let lit = t >= 0.50 && t < 2.6                       // „verbunden": alles leuchtet auf
        let text = ramp(t, 0.55, 1.05)
        let ease = 1 - (1 - text) * (1 - text)
        return HStack(spacing: 16) {
            Canvas { ctx, sz in
                let rows = glyph.count, cols = glyph[0].count
                let pitch = min(sz.width / CGFloat(cols), sz.height / CGFloat(rows))
                let d = pitch * 0.74
                let left = ramp(t, 0.0, 0.25), right = ramp(t, 0.25, 0.45)
                for (y, row) in glyph.enumerated() {
                    for (x, c) in row.enumerated() where c == "#" {
                        let progress = x < cols / 2 ? left : right
                        guard Double(y) < progress * Double(rows) else { continue }
                        var color = lit ? Theme.tones.dots : Color.white.opacity(0.35)
                        // Ein einzelner Punkt blinkt als Lebenszeichen.
                        if kind != "mail", x == 1, y == 6, Int(max(0, t) / 0.2) % 2 == 0 { color = Color(red: 1.0, green: 0.42, blue: 0.40) }
                        let r = CGRect(x: CGFloat(x) * pitch + (pitch - d) / 2, y: CGFloat(y) * pitch + (pitch - d) / 2, width: d, height: d)
                        ctx.fill(Path(ellipseIn: r), with: .color(color))
                    }
                }
            }
            .frame(width: 62, height: 37)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(subtitle).font(Theme.font(12)).foregroundStyle(kind == "mail" ? Theme.soft : Theme.accent).lineLimit(1)
            }
            .opacity(ease)
            .offset(x: -7 * (1 - ease))

            Spacer(minLength: 6)

            // Funkzeichen aus gepunkteten Bögen: geht mit dem Aufleuchten an und ebbt von außen nach innen ab.
            if kind != "mail" { Canvas { ctx, sz in
                let centre = CGPoint(x: 1.5, y: sz.height / 2)
                for (i, radius) in [6.0, 12.5, 19.0].enumerated() {
                    var alpha = t < 0.50 ? 0.15 : 1.0
                    if i > 0 { alpha *= 1 - ramp(t, 0.9 + (i == 2 ? 0 : 0.18), 1.3 + (i == 2 ? 0 : 0.18)) * 0.9 }
                    let count = 4 + i * 3
                    for k in 0..<count {
                        let angle = (-0.78 + 1.56 * Double(k) / Double(count - 1))
                        let p = CGPoint(x: centre.x + CGFloat(cos(angle) * radius), y: centre.y + CGFloat(sin(angle) * radius))
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.1, y: p.y - 1.1, width: 2.2, height: 2.2)),
                                 with: .color(Theme.tones.dots.opacity(alpha)))
                    }
                }
            }
            .frame(width: 23, height: 34) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(subtitle)")
    }
}

/// „Claude ist fertig": Das Boot legt an, daneben steht in einem Satz, was erreicht wurde.
struct DoneScene: View {
    @ObservedObject var model: IslandModel
    let session: ClaudeSession
    var staged = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if staged {
                // Erst wird das Boot gedruckt, dann fährt es einmal hinaus und legt wieder an.
                StagedMascot(size: 46) { ready in .arriving(since: ready) }
            } else {
                Mascot(size: 46, state: .arriving(since: session.doneAt ?? .distantPast))
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Dot(color: Theme.accent)
                    Text(session.project).font(Theme.font(12, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(took).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                // Der Ergebnissatz ist die Hauptsache, nicht die Statuszeile.
                Text(session.summary).font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .modifier(SlideIn(delay: 0.78, active: staged))
            Spacer(minLength: 0)
        }
    }

    private var took: String {
        guard let t = session.tookSeconds else { return "Claude ist fertig" }
        return t < 90 ? "Claude fertig in \(t) s" : "Claude fertig in \(t / 60) Min"
    }
}

/// „Claude möchte einen Befehl ausführen“ – direkt aus der Insel beantworten.
struct AskScene: View {
    @ObservedObject var model: IslandModel
    let ask: PermissionAsk
    /// Im Kurz-Hinweis baut sich die Szene Schritt für Schritt auf.
    var staged = false

    private var risky: Bool { !ask.risk.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if staged { StagedMascot(size: 60) { _ in .waiting } } else { Mascot(size: 60, state: .waiting) }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Dot(pulsing: true)
                    Text(ask.project).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(sentence).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                .modifier(SlideIn(delay: 0.78, active: staged))
                if ask.isQuestion {
                    questions.modifier(SlideIn(delay: 0.86, active: staged))
                    HStack(spacing: 10) {
                        Button("In Claude beantworten") { openInClaude() }
                            .buttonStyle(CapsuleStyle(primary: true, compact: true))
                        Text("⌃⌥J").font(Theme.font(11)).foregroundStyle(Theme.faint)
                    }
                    .modifier(SlideIn(delay: 0.98, active: staged))
                }
                if !ask.isQuestion, !ask.summary.isEmpty {
                    Text(ask.summary).font(Theme.font(13)).foregroundStyle(Theme.text)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .modifier(SlideIn(delay: 0.84, active: staged))
                }
                if !ask.isQuestion, !ask.detail.isEmpty { command.modifier(SlideIn(delay: 0.9, active: staged)) }
                if risky {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11))
                        Text("Vorsicht: \(ask.tool == "Bash" ? "Dieser Befehl" : "Diese Aktion") \(ask.risk). Bitte erst lesen.")
                            .font(Theme.font(12)).fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.warn)
                }
                if !ask.isQuestion {
                HStack(spacing: 8) {
                    Button { model.answer?(ask, "deny") } label: { keyed("Ablehnen", "⌃⌥N") }
                        .buttonStyle(CapsuleStyle(compact: true))
                    // Bei riskanten Befehlen gibt es kein Kürzel und keine hervorgehobene Voreinstellung.
                    Button { model.answer?(ask, "allow") } label: { keyed("Erlauben", risky ? "" : "⌃⌥Y") }
                        .buttonStyle(CapsuleStyle(primary: !risky, compact: true))
                    Button("In Claude ansehen") {
                        model.answer?(ask, "pass")
                        if let s = model.sessions.first(where: { $0.id == ask.sessionID }) { model.openSession?(s) }
                    }
                    .buttonStyle(.plain).font(Theme.font(11)).foregroundStyle(Theme.muted).padding(.leading, 4)
                }
                .modifier(SlideIn(delay: 0.98, active: staged))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func openInClaude() {
        model.answer?(ask, "pass")
        if let s = model.sessions.first(where: { $0.id == ask.sessionID }) { model.openSession?(s) }
    }

    /// Claudes Fragen im Wortlaut, darunter die Antwortmöglichkeiten – bewusst als schlichte Liste ohne
    /// Auswahlzeichen: Beantwortet wird in Claude, weil Lotse die Auswahl nicht zurückgeben kann.
    private var questions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ask.questions.prefix(3).enumerated()), id: \.element.id) { i, q in
                VStack(alignment: .leading, spacing: 6) {
                    Text(q.text).font(Theme.font(13, .medium)).foregroundStyle(Theme.text)
                        .lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    if !q.options.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(q.options.prefix(4).enumerated()), id: \.offset) { _, o in
                                HStack(alignment: .firstTextBaseline, spacing: 7) {
                                    Text("–").font(Theme.font(12)).foregroundStyle(Theme.faint)
                                    Text(o).font(Theme.font(12)).foregroundStyle(Theme.soft).lineLimit(1)
                                }
                            }
                            if q.options.count > 4 {
                                Text("und \(q.options.count - 4) weitere").font(Theme.font(11)).foregroundStyle(Theme.faint)
                            }
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Frage \(i + 1): \(q.text). Antworten: \(q.options.joined(separator: ", "))")
            }
            if ask.questions.count > 3 {
                Text("und \(ask.questions.count - 3) weitere").font(Theme.font(11)).foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 11).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
    }

    /// Der Befehl steht immer vollständig da – kurze direkt, lange in einem scrollbaren Feld.
    @ViewBuilder private var command: some View {
        let long = ask.detail.count > 260 || ask.detail.filter { $0 == "\n" }.count > 3
        let text = Text(ask.detail).font(Theme.mono(12)).foregroundStyle(Theme.soft)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        Group {
            if long {
                ScrollView { text.padding(.horizontal, 10).padding(.vertical, 7) }.frame(height: 104)
            } else {
                text.fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.vertical, 7)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Theme.warn.opacity(risky ? 0.55 : 0), lineWidth: 1))
        .accessibilityLabel("Befehl: \(ask.detail)")
    }

    /// Knopftext mit leise danebengestelltem Tastenkürzel.
    private func keyed(_ title: String, _ keys: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if !keys.isEmpty { Text(keys).font(Theme.font(11)).opacity(0.6) }
        }
    }

    private var sentence: String {
        if ask.isQuestion { return ask.questions.count == 1 ? "Claude hat eine Frage" : "Claude hat \(ask.questions.count) Fragen" }
        switch ask.tool {
        case "Bash": return "Claude möchte einen Befehl ausführen"
        case "Edit", "Write", "MultiEdit", "NotebookEdit": return "Claude möchte eine Datei ändern"
        case "WebFetch", "WebSearch": return "Claude möchte ins Web"
        default:
            return ask.tool.hasPrefix("mcp__")
                ? "Claude möchte \(ClaudeSource.readable(ask.tool)) nutzen (externes Werkzeug)"
                : "Claude möchte \(ask.tool) nutzen"
        }
    }
}

struct DropHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.accent)
            Text("Hier loslassen, um zu parken").font(Theme.font(13, .medium)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity).frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 17, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
    }
}

// MARK: - Reiter „Überblick“

struct HomeView: View {
    @ObservedObject var model: IslandModel

    /// Drei Kacheln mit dem Wetter in der Mitte, und oben ist eine Aussparung: Dann steht das Wetter genau darunter.
    private var weatherUnderNotch: Bool {
        model.hasNotch && model.notchWidth > 0 && model.track != nil && model.shows("home.music") && model.shows("home.date")
            && !(model.focusRunning || model.focusPaused != nil)
    }

    /// Sind alle Kacheln der Leiste abgeschaltet oder leer?
    private var stripEmpty: Bool {
        !(model.track != nil && model.shows("home.music")) && !model.shows("home.weather") && !model.shows("home.date")
            && !(model.focusRunning || model.focusPaused != nil)
    }

    var body: some View {
        VStack(spacing: 10) {
            // Die Kachelleiste: das Wichtigste des Tages in einer flachen Reihe.
            HStack(spacing: 9) {
                if model.track != nil, model.shows("home.music") { StripMusic(model: model).frame(maxWidth: .infinity).modifier(Rise(index: 0)) }
                if model.shows("home.weather") {
                    // Steht das Wetter in der Mitte, ist es genau so breit wie die Aussparung darüber.
                    StripWeather(model: model).frame(maxWidth: weatherUnderNotch ? model.notchWidth : .infinity).modifier(Rise(index: 1))
                }
                if model.shows("home.date") { StripDate(model: model).frame(maxWidth: .infinity).modifier(Rise(index: 2)) }
                // Der Timer steht im Überblick nur, solange er gebraucht wird – gestartet wird er im Reiter „Fokus, Zwischenablage, Termine".
                if model.focusRunning || model.focusPaused != nil {
                    StripTimer(model: model).frame(width: 96).modifier(Rise(index: 3))
                }
            }
            .frame(height: stripEmpty ? 0 : 92)
            if model.showForecast, model.shows("home.weather"), !model.forecast.isEmpty {
                ForecastRow(model: model).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if model.showWeek, model.shows("home.date") {
                WeekRow(model: model).transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !model.sessions.isEmpty || !model.asks.isEmpty || !model.limits.isEmpty || !model.usageHint.isEmpty {
                ClaudeTile(model: model).modifier(Rise(index: 4))
            }
            // Leere Mitteilungen bekommen keine Kachel.
            if model.shows("home.notices"), !model.notices.isEmpty || !model.cleared.isEmpty || model.notificationsDenied {
                NotificationsTile(model: model).modifier(Rise(index: 5))
            }
        }
    }
}

/// Gemeinsame Hülle der flachen Leisten-Kacheln.
private struct StripTile<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 13).padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }
}

struct StripMusic: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        StripTile {
            if let t = model.track {
                HStack(spacing: 11) {
                    Cover(image: t.artwork, size: 52, radius: 9)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(t.artist).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                        HStack(spacing: 2) {
                            control(t.isPlaying ? "pause.fill" : "play.fill", "playpause", t.isPlaying ? "Pause" : "Wiedergabe")
                            control("forward.fill", "next track", "Nächster Titel")
                        }
                        .padding(.leading, -7).padding(.top, 1)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
    private func control(_ icon: String, _ command: String, _ name: String) -> some View {
        Button { model.musicAction?(command) } label: {
            Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.text).frame(width: 28, height: 26).contentShape(Rectangle())
        }
        .buttonStyle(.plain).modifier(HoverGlow()).help(name).accessibilityLabel(name)
    }
}

struct StripWeather: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        StripTile {
            if let w = model.weather {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("\(w.temperature)°").font(Theme.font(30, .light)).foregroundStyle(Theme.text)
                        Spacer()
                        Image(systemName: w.symbol).symbolRenderingMode(.multicolor).font(.system(size: 22))
                    }
                    Text(w.city).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("H \(w.high)°  T \(w.low)°").font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(w.city): \(w.temperature) Grad, Höchstwert \(w.high), Tiefstwert \(w.low)")
                .accessibilityAddTraits(.isButton)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(IslandModel.spring) { model.showForecast.toggle(); if model.showForecast { model.showWeek = false } }
                }
                .help(model.showForecast ? "Vorschau schließen" : "Die nächsten Stunden zeigen")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.weatherCity.isEmpty ? "Wetter" : "Wetter wird geladen …").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    if model.weatherCity.isEmpty {
                        Button("Ort festlegen") { model.askWeatherCity?() }.buttonStyle(CapsuleStyle(compact: true))
                    }
                }
            }
        }
    }
}

/// Die nächsten Stunden: Uhrzeit, Wetter, Temperatur, Regenwahrscheinlichkeit.
struct ForecastRow: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(model.forecast.prefix(8).enumerated()), id: \.element.id) { i, h in
                VStack(spacing: 5) {
                    Text(i == 0 ? "jetzt" : Fmt.time.string(from: h.time).prefix(2) + " Uhr")
                        .font(Theme.font(11)).foregroundStyle(i == 0 ? Theme.text : Theme.muted)
                    Image(systemName: h.symbol).symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(height: 18)
                    Text("\(h.temperature)°").font(Theme.font(13, .medium)).monospacedDigit().foregroundStyle(Theme.text)
                    Text(h.rain >= 20 ? "\(h.rain) %" : " ").font(Theme.font(10)).monospacedDigit().foregroundStyle(Theme.accent)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Fmt.time.string(from: h.time)): \(h.temperature) Grad, Regen \(h.rain) Prozent")
            }
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Weather.app")) } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).modifier(HoverGlow()).help("Wetter-App öffnen").accessibilityLabel("Wetter-App öffnen")
        }
        .padding(.horizontal, 10).padding(.vertical, 11)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }
}

/// Die Woche: heute und die sechs Tage danach, je Tag eine Spalte mit allen Terminen.
struct WeekRow: View {
    @ObservedObject var model: IslandModel
    private static let head: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EE d."; return f
    }()

    private var days: [Date] {
        let cal = Calendar.current, start = cal.startOfDay(for: model.now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private func events(on day: Date) -> [CalEvent] {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: 1, to: day) else { return [] }
        // Ganztägiges zuerst; mehrtägige Termine erscheinen an jedem ihrer Tage.
        return model.week.filter { $0.start < next && $0.end > day && (model.weekRole == .none || $0.role == model.weekRole) }.sorted { ($0.allDay ? 0 : 1, $0.start) < ($1.allDay ? 0 : 1, $1.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                Text("Die nächsten sieben Tage").font(Theme.font(12, .medium)).foregroundStyle(Theme.text)
                Spacer()
                // Nur anbieten, wenn überhaupt ein Kalender als Arbeit oder privat markiert ist.
                if model.week.contains(where: { $0.role != .none }) {
                    HStack(spacing: 2) {
                        ForEach([CalRole.none, .work, .personal], id: \.self) { r in
                            Button { withAnimation(IslandModel.spring) { model.weekRole = r } } label: {
                                Text(r == .none ? "Alle" : r.title).font(Theme.font(10, .medium))
                                    .foregroundStyle(model.weekRole == r ? Theme.text : Theme.muted)
                                    .padding(.horizontal, 8).frame(height: 22)
                                    .background(Capsule().fill(model.weekRole == r ? Theme.text.opacity(0.14) : .clear))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) } label: {
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain).modifier(HoverGlow()).help("Kalender öffnen").accessibilityLabel("Kalender öffnen")
            }
            if model.calendarDenied {
                Text("Kein Kalenderzugriff.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.element) { i, day in column(day, today: i == 0) }
                }
            }
        }
        .padding(13)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }

    private func column(_ day: Date, today: Bool) -> some View {
        // Heute zählt, was noch kommt: Vorbei ist nur ein Vermerk am Ende, sonst schieben die Termine vom Vormittag
        // die anstehenden unter „weitere“.
        let all = events(on: day)
        let list = today ? all.filter { $0.allDay || $0.end > model.now } : all
        let gone = all.count - list.count
        return VStack(alignment: .leading, spacing: 6) {
            Text(Self.head.string(from: day).replacingOccurrences(of: ".", with: "", options: [], range: nil).uppercased() + ".")
                .font(Theme.font(10, .semibold)).foregroundStyle(today ? Theme.accent : Theme.muted)
            Rectangle().fill(today ? Theme.accent.opacity(0.6) : Theme.line).frame(height: 1)
            if list.isEmpty {
                Text(gone > 0 ? "nichts mehr" : "frei").font(Theme.font(11)).foregroundStyle(Theme.faint)
            }
            ForEach(list.prefix(6)) { e in
                let past = e.end < model.now
                // Läuft gerade: hervorgehoben mit Endzeit. Vorbei: ausgegraut. Ganztägiges bleibt neutral.
                let running = !e.allDay && e.start <= model.now && e.end > model.now
                VStack(alignment: .leading, spacing: 0) {
                    // Das Rollen-Symbol steht in der Zeitzeile, damit es bei langen Titeln nicht allein umbricht.
                    HStack(spacing: 4) {
                        Text(e.allDay ? "ganztägig" : running ? "jetzt · bis \(Fmt.time.string(from: e.end))" : Fmt.time.string(from: e.start))
                            .font(Theme.font(10, running ? .semibold : .regular)).monospacedDigit()
                        if !running, let sym = e.role.symbol { Image(systemName: sym).font(.system(size: 8.5, weight: .semibold)) }
                    }
                    .foregroundStyle(past ? Theme.faint : Theme.accent).lineLimit(1)
                    // Ein einzelnes langes Wort wird leicht verkleinert statt mitten im Wort umzubrechen.
                    Text(e.label(discreet: model.discreet)).font(Theme.font(11, running ? .semibold : .medium))
                        .minimumScaleFactor(0.8).allowsTightening(true)
                        .foregroundStyle(past ? Theme.faint : Theme.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, running ? 6 : 0).padding(.vertical, running ? 4 : 0)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accent.opacity(running ? 0.18 : 0)))
                .overlay(alignment: .leading) {
                    if running { RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 2).padding(.vertical, 4) }
                }
                .opacity(past ? 0.45 : 1)
                .accessibilityElement(children: .combine)
                .help("\(e.label(discreet: model.discreet))\(e.role == .none ? "" : " (" + e.role.title + ")") · \(e.allDay ? "ganztägig" : Fmt.time.string(from: e.start) + " – " + Fmt.time.string(from: e.end))")
            }
            let more = [list.count > 6 ? "+ \(list.count - 6) weitere" : nil, gone > 0 ? "\(gone) vorbei" : nil].compactMap { $0 }
            if !more.isEmpty {
                Text(more.joined(separator: " · ")).font(Theme.font(10)).foregroundStyle(Theme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct StripDate: View {
    @ObservedObject var model: IslandModel
    private static let weekday: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EE"; return f
    }()
    var body: some View {
        StripTile {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(Self.weekday.string(from: model.now).uppercased().replacingOccurrences(of: ".", with: ""))
                        .font(Theme.font(11, .medium)).foregroundStyle(Theme.muted)
                    Text("\(Calendar.current.component(.day, from: model.now))")
                        .font(Theme.font(30, .light)).monospacedDigit().foregroundStyle(Theme.text)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let e = model.nextEvent {
                        e.marked(discreet: model.discreet).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(2)
                        Text(when(e)).font(Theme.font(11)).monospacedDigit()
                            .foregroundStyle(e.start.timeIntervalSince(model.now) < 3600 ? Theme.accent : Theme.muted).lineLimit(1)
                        if let url = e.joinURL, e.start.timeIntervalSince(model.now) < 15 * 60 {
                            // Erst in den letzten fünf Minuten wird er zum hellsten Knopf.
                            Button("Beitreten") { NSWorkspace.shared.open(url) }
                                .buttonStyle(CapsuleStyle(primary: e.start.timeIntervalSince(model.now) < 5 * 60, compact: true)).padding(.top, 3)
                        }
                    } else {
                        Text(model.calendarDenied ? "Kein Kalenderzugriff" : "Nichts geplant").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(IslandModel.spring) { model.showWeek.toggle(); if model.showWeek { model.showForecast = false } }
            }
            .help(model.showWeek ? "Woche schließen" : "Alle Termine der Woche zeigen")
        }
    }
    private func when(_ e: CalEvent) -> String {
        let range = "\(Fmt.time.string(from: e.start)) – \(Fmt.time.string(from: e.end))"
        if !Calendar.current.isDate(e.start, inSameDayAs: model.now) { return "morgen, \(range)" }
        // Kurz vor Beginn zählt der Abstand; das Ende steht im Reiter „Fokus, Zwischenablage, Termine".
        return e.start.timeIntervalSince(model.now) < 3600 ? "\(Fmt.until(e.start, now: model.now)) · \(Fmt.time.string(from: e.start))" : range
    }
}

struct StripTimer: View {
    @ObservedObject var model: IslandModel
    var body: some View {
        StripTile {
            VStack(spacing: 7) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Fmt.clock(model.focusRemaining(at: ctx.date)))
                        .font(Theme.font(18, .light)).monospacedDigit().foregroundStyle(Theme.text)
                }
                Button { model.focusToggle() } label: { Image(systemName: model.focusRunning ? "pause.fill" : "play.fill") }
                    .buttonStyle(RoundStyle(size: 28))
                    .help(model.focusRunning ? "Fokus pausieren" : "Fokus starten")
                    .accessibilityLabel(model.focusRunning ? "Fokus pausieren" : "Fokus starten")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct Hint: View {
    var text: String
    var button: String
    var url: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text).font(Theme.font(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Button(button) { NSWorkspace.shared.open(URL(string: url)!) }.buttonStyle(CapsuleStyle(compact: true))
        }
    }
}

struct ClaudeTile: View {
    @ObservedObject var model: IslandModel

    /// Die Session, die gerade am meisten Aufmerksamkeit verdient.
    private var lead: ClaudeSession? {
        model.sessions.first { $0.status == .waiting } ?? model.sessions.first { $0.status == .working } ?? model.sessions.first
    }

    var body: some View {
        Tile(icon: "sparkle", title: "Claude", info: info) {
            VStack(alignment: .leading, spacing: 12) {
                if let ask = model.asks.first {
                    AskScene(model: model, ask: ask)
                } else if model.sessions.count > 1 {
                    // Mehrere Sessions: jede bekommt dieselbe Bahn – Status, woran sie arbeitet, Strecke und Laufzeit.
                    ForEach(Array(lanes.prefix(5).enumerated()), id: \.element.id) { i, s in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        Button { model.openSession?(s) } label: { lane(s) }.buttonStyle(.plain)
                    }
                    if lanes.count > 5 {
                        Text(lanes.count == 6 ? "und 1 weitere Session" : "und \(lanes.count - 5) weitere Sessions")
                            .font(Theme.font(11)).foregroundStyle(Theme.faint)
                    }
                } else if let s = lead {
                    Button { model.openSession?(s) } label: {
                        if s.status == .done, !s.summary.isEmpty, !model.silent {
                            DoneScene(model: model, session: s).contentShape(Rectangle())
                        } else {
                            scene(s)
                        }
                    }
                    .buttonStyle(.plain)
                }
                let shown = model.asks.first?.sessionID ?? lead?.id
                // Solange eine Freigabe zu sehen ist, bleibt die Kachel kompakt.
                let rest = model.asks.isEmpty && model.sessions.count > 1 ? [] : Array(model.sessions.filter { $0.id != shown }.prefix(model.asks.isEmpty ? 4 : 1))
                if !rest.isEmpty {
                    Rectangle().fill(Theme.line).frame(height: 1)
                    ForEach(rest) { s in
                        Button { model.openSession?(s) } label: { row(s) }.buttonStyle(.plain)
                    }
                    let hidden = model.sessions.count - 1 - rest.count
                    if hidden > 0 {
                        Text(hidden == 1 ? "und 1 weitere Session" : "und \(hidden) weitere Sessions")
                            .font(Theme.font(11)).foregroundStyle(Theme.faint)
                    }
                }
                if !model.limits.isEmpty {
                    if !model.sessions.isEmpty { Rectangle().fill(Theme.line).frame(height: 1) }
                    HStack(spacing: 18) {
                        ForEach(model.limits) { l in Meter(limit: l, now: model.now) }
                    }
                }
                if let d = model.today, d.tokens > 0, !model.silent {
                    Text(Self.day(d)).font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint).lineLimit(1)
                }
                if model.limits.isEmpty, !model.usageHint.isEmpty {
                    Text(model.usageHint).font(Theme.font(11)).foregroundStyle(Theme.faint)
                } else if let u = model.limitsUpdated, !model.limits.isEmpty, model.now.timeIntervalSince(u) > 20 * 60 {
                    Text("Nutzung: Stand \(Fmt.ago(u, now: model.now))").font(Theme.font(11)).foregroundStyle(Theme.faint)
                }
            }
        }
    }

    /// Reihenfolge der Bahnen: erst wer dich braucht, dann wer arbeitet, zuletzt Fertiges.
    private var lanes: [ClaudeSession] {
        func rank(_ s: ClaudeSession) -> Int { s.status == .waiting ? 0 : s.status == .working ? 1 : 2 }
        return model.sessions.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// Eine Bahn: links das Boot als Status, in der Mitte Projekt und Tätigkeit, rechts Strecke, Schritt und Laufzeit.
    private func lane(_ s: ClaudeSession) -> some View {
        let waiting = s.status == .waiting
        let second = waiting ? (s.message.isEmpty ? "Wartet auf deine Eingabe." : s.message)
            : s.status == .working ? s.detail : (s.summary.isEmpty ? "" : s.summary)
        return HStack(alignment: .center, spacing: 11) {
            Mascot(size: 25, state: s.status == .working ? .sailing : waiting ? .waiting : .idle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(s.project).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(sentence(s)).font(Theme.font(12)).foregroundStyle(waiting ? Theme.accent : Theme.muted).lineLimit(1)
                }
                if !second.isEmpty {
                    Text(second).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.tail)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            if s.status == .working {
                if s.planTotal > 1 {
                    Course(done: s.planDone, total: s.planTotal).frame(width: 78, height: 12)
                    Text("\(min(s.planDone + 1, s.planTotal))/\(s.planTotal)").font(Theme.font(11)).monospacedDigit()
                        .foregroundStyle(Theme.muted).frame(width: 30, alignment: .trailing)
                }
                if let since = s.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Fmt.elapsed(ctx.date.timeIntervalSince(since))).font(Theme.font(11)).monospacedDigit()
                            .foregroundStyle(Theme.soft).frame(width: 44, alignment: .trailing)
                    }
                }
            } else {
                Text(Fmt.ago(s.updated, now: model.now)).font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint)
            }
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .opacity(s.status == .done ? 0.78 : 1)
    }

    /// „Heute: 4,3 Mio. Tokens · 6 Sessions · 812 Werkzeug-Aufrufe · am meisten in Lotse"
    static func day(_ d: ClaudeDay) -> String {
        let n = Double(d.tokens)
        let tokens = n >= 1_000_000 ? String(format: "%.1f Mio.", n / 1_000_000).replacingOccurrences(of: ".", with: ",", options: [], range: nil)
            .replacingOccurrences(of: "Mio,", with: "Mio.")
            : n >= 1_000 ? "\(Int(n / 1_000)) Tsd." : "\(d.tokens)"
        var parts = ["Heute: \(tokens) Tokens", d.sessions == 1 ? "1 Session" : "\(d.sessions) Sessions"]
        if d.tools > 0 { parts.append("\(d.tools) Werkzeug-Aufrufe") }
        if !d.top.isEmpty, d.sessions > 1 { parts.append("am meisten in \(d.top)") }
        return parts.joined(separator: " · ")
    }

    private var info: String {
        // Den Zustand zeigen Boot und Satz – hier steht nur, wie viele Sessions es gibt.
        return model.sessions.count > 1 ? "\(model.sessions.count) Sessions" : ""
    }

    private func sentence(_ s: ClaudeSession) -> String {
        switch s.status {
        case .working: return s.planStep.isEmpty ? "Claude arbeitet" : s.planStep
        case .waiting: return "Claude braucht dich"
        case .done: return "Claude ist fertig"
        }
    }

    /// Große Szene: Boot links, rechts Projekt + Satz, darunter was gerade läuft.
    private func scene(_ s: ClaudeSession) -> some View {
        sceneRow(s, boat: true)
    }

    private func sceneRow(_ s: ClaudeSession, boat: Bool) -> some View {
        HStack(alignment: .center, spacing: 16) {
            if boat { Mascot(size: 54, state: s.status == .working ? .sailing : s.status == .waiting ? .waiting : .idle) }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Dot(color: s.status == .done ? Theme.faint : Theme.accent, pulsing: s.status != .done).id("\(s.id)-\(s.status)")
                    Text(s.project).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(sentence(s)).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                let chip = s.status == .waiting ? s.message : s.status == .working ? s.detail : ""
                if !chip.isEmpty {
                    Text(chip).font(Theme.font(12)).foregroundStyle(Theme.soft)
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
                }
                Text(meta(s)).font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint).lineLimit(1)
                // Mit Plan fährt ein kleines Boot die Strecke ab: Jeder erledigte Schritt bringt es dem Hafen näher.
                if s.status == .working, s.planTotal > 1 {
                    Voyage(done: s.planDone, total: s.planTotal).frame(width: 300)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func meta(_ s: ClaudeSession) -> String {
        var parts: [String] = []
        if !s.model.isEmpty { parts.append(s.model) }
        if s.planTotal > 0, s.status != .done { parts.append("Schritt \(min(s.planDone + 1, s.planTotal)) von \(s.planTotal)") }
        if let c = s.contextPercent { parts.append("Kontext \(c) %") }
        parts.append(Fmt.ago(s.updated, now: model.now))
        return parts.joined(separator: " · ")
    }

    /// Weitere Sessions: eine Zeile mit kleinem Boot.
    private func row(_ s: ClaudeSession) -> some View {
        HStack(spacing: 9) {
            Mascot(size: 25, state: s.status == .working ? .sailing : s.status == .waiting ? .waiting : .idle)
            Text(s.project).font(Theme.font(12, .medium)).foregroundStyle(Theme.text).lineLimit(1)
            Text(s.status == .working && !s.detail.isEmpty ? s.detail : sentence(s))
                .font(Theme.font(12)).foregroundStyle(s.status == .waiting ? Theme.accent : Theme.muted).lineLimit(1)
            Spacer(minLength: 6)
            // Bei arbeitenden Sessions zählt, wie weit sie sind und wie lange sie schon laufen.
            if s.status == .working {
                if s.planTotal > 0 {
                    Text("\(min(s.planDone + 1, s.planTotal))/\(s.planTotal)").font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint)
                }
                if let since = s.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Fmt.elapsed(ctx.date.timeIntervalSince(since))).font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                }
            } else {
                Text(Fmt.ago(s.updated, now: model.now)).font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Die Strecke in klein, für die Bahnen: gestrichelte Wasserlinie, eine Boje je Schritt, ein heller Punkt für die Position.
struct Course: View {
    var done: Int
    var total: Int

    var body: some View {
        Canvas { g, size in
            let u: CGFloat = 2, y = (size.height - u).rounded()
            let w = size.width - u
            func dot(_ x: CGFloat, _ yy: CGFloat, _ c: Color, _ s: CGFloat = 2) {
                g.fill(Path(CGRect(x: (x / u).rounded() * u, y: yy, width: s, height: s)), with: .color(c))
            }
            var x: CGFloat = 0
            while x <= w { dot(x, y, Color.white.opacity(0.20)); x += 2 * u }
            let n = max(total, 1)
            if total <= 12 {
                for step in 0...n {
                    let bx = w * CGFloat(step) / CGFloat(n)
                    let reached = step <= done
                    dot(bx, y - u, reached ? Theme.accent : Color.white.opacity(0.38))
                    dot(bx, y - 2 * u, reached ? Theme.accent : Color.white.opacity(0.38))
                }
            }
            // Zurückgelegtes Stück und Position: mitten im laufenden Schritt.
            let p = min(1, (CGFloat(min(done, total)) + (done >= total ? 0 : 0.5)) / CGFloat(n))
            var fx: CGFloat = 0
            while fx <= w * p { dot(fx, y, Theme.accent.opacity(0.85)); fx += u }
            dot(w * p - u, y - 3 * u, Theme.text, 4); dot(w * p - u, y - u, Theme.text, 4)
        }
        .accessibilityLabel("Schritt \(min(done + 1, max(total, 1))) von \(total)")
    }
}

/// Die Strecke eines Plans: Wasserlinie mit einer Boje je Schritt, rechts der Hafen. Das Boot steht dort,
/// wo Claude gerade ist – mit jedem erledigten Schritt segelt es ein Stück weiter.
struct Voyage: View {
    var done: Int
    var total: Int

    private static let harbor = [
        "..F....",
        "..FF...",
        "..M....",
        "..M..B.",
        "PPPPPPP",
        "P.P.P.P",
    ]

    var body: some View {
        GeometryReader { geo in
            let u: CGFloat = 2, boat: CGFloat = 24
            let hu: CGFloat = 2
            let harborW = CGFloat(Self.harbor[0].count) * hu
            let track = max(1, geo.size.width - boat - harborW - 6)
            // Mitten im laufenden Schritt; nach dem letzten liegt das Boot am Hafen.
            let progress = min(1, (CGFloat(min(done, total)) + (done >= total ? 0 : 0.5)) / CGFloat(max(total, 1)))
            ZStack(alignment: .topLeading) {
                TimelineView(.periodic(from: .now, by: 0.28)) { ctx in
                    let frame = Probe.frame ?? (Theme.calm ? 0 : Int(ctx.date.timeIntervalSinceReferenceDate / 0.28))
                    Canvas { g, size in
                        let water = size.height - 3 * u
                        func dot(_ x: CGFloat, _ y: CGFloat, _ c: Color) {
                            g.fill(Path(CGRect(x: (x / u).rounded() * u, y: (y / u).rounded() * u, width: u, height: u)), with: .color(c))
                        }
                        // Wasserlinie: wandernde Punkte
                        var x: CGFloat = 0
                        var i = 0
                        while x < size.width - harborW - 2 {
                            if (i + frame) % 3 != 0 { dot(x, water, Color.white.opacity(0.22)) }
                            x += u; i += 1
                        }
                        // Bojen: eine je Schritt, erledigte in Eisblau
                        if total <= 14 {
                            for step in 1..<total {
                                let bx = boat / 2 + track * CGFloat(step) / CGFloat(total)
                                let reached = step <= done
                                dot(bx, water - u, reached ? Theme.accent : Color.white.opacity(0.4))
                                dot(bx, water - 2 * u, reached ? Theme.accent : Color.white.opacity(0.4))
                            }
                        }
                        // Hafen: Steg mit Mast und Fähnchen
                        let hx = size.width - harborW, hy = water + u - CGFloat(Self.harbor.count - 1) * hu
                        func block(_ x: CGFloat, _ y: CGFloat, _ c: Color) {
                            g.fill(Path(CGRect(x: x, y: y, width: hu, height: hu)), with: .color(c))
                        }
                        for (r, row) in Self.harbor.enumerated() {
                            for (c, ch) in row.enumerated() {
                                let px = hx + CGFloat(c) * hu, py = hy + CGFloat(r) * hu
                                switch ch {
                                case "F": block(px, py, Theme.accent)
                                case "M": block(px, py, Color.white.opacity(0.8))
                                case "B": block(px, py, Color.white.opacity(0.6))
                                case "P": block(px, py, Color.white.opacity(0.45))
                                default: break
                                }
                            }
                        }
                    }
                }
                Mascot(size: boat, state: .sailing)
                    .offset(x: track * progress, y: geo.size.height - boat - 1)
                    .animation(.spring(response: 0.9, dampingFraction: 0.85), value: done)
            }
        }
        .frame(height: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt \(min(done + 1, total)) von \(total)")
    }
}

/// Nutzungsstand eines Limits als schmale Leiste. Ab 80 % wird er zur Warnung.
struct Meter: View {
    var limit: UsageLimit
    var now: Date

    private var high: Bool { limit.percent >= 80 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(limit.label).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(Int(limit.percent.rounded())) %").font(Theme.font(11, .semibold)).monospacedDigit()
                    .foregroundStyle(high ? Theme.warn : Theme.soft)
                if let r = limit.resets, r > now {
                    Text(reset(r)).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.raised)
                    Capsule().fill(high ? Theme.warn : Theme.accent).frame(width: max(3, g.size.width * min(1, limit.percent / 100)))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(limit.label): \(Int(limit.percent.rounded())) Prozent verbraucht\(high ? ", fast aufgebraucht" : "")")
    }

    private func reset(_ d: Date) -> String {
        let h = d.timeIntervalSince(now) / 3600
        if h < 1 { return "neu in \(max(1, Int(h * 60))) Min." }
        if h < 24 { return "neu in \(Int(h.rounded())) Std." }
        let days = Int((h / 24).rounded())
        return days == 1 ? "neu morgen" : "neu in \(days) Tagen"
    }
}

struct CalendarTile: View {
    @ObservedObject var model: IslandModel
    var compact = false

    /// Der Tag, um den es geht: heute, solange noch etwas ansteht – sonst morgen.
    private var day: (label: String, date: Date, events: [CalEvent]) {
        let cal = Calendar.current
        let today = model.events.filter { cal.isDate($0.start, inSameDayAs: model.now) }
        if today.contains(where: { $0.end > model.now }) { return ("Heute", model.now, today) }
        let next = cal.date(byAdding: .day, value: 1, to: model.now) ?? model.now
        let tomorrow = model.events.filter { cal.isDate($0.start, inSameDayAs: next) }
        if !tomorrow.isEmpty { return ("Morgen", next, tomorrow) }
        return ("Heute", model.now, today)
    }

    var body: some View {
        let d = day
        let open = d.events.filter { $0.end > model.now }
        Tile(icon: "calendar", title: compact ? "Termine" : d.label, info: info(d.label, d.events.count)) {
            if model.calendarDenied {
                Hint(text: "Lotse darf deinen Kalender noch nicht lesen.", button: "Zugriff erlauben",
                     url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
            } else if d.events.isEmpty {
                Text("Heute und morgen steht nichts an.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else if compact {
                list(d.events, lead: open.first)
                // Ist heute wenig los, füllt der nächste Tag die Spalte, statt sie leer zu lassen.
                let cal = Calendar.current
                let next = cal.date(byAdding: .day, value: 1, to: d.date) ?? d.date
                let later = model.events.filter { cal.isDate($0.start, inSameDayAs: next) }
                if d.events.count < 5, !later.isEmpty {
                    Text(d.label == "Heute" ? "MORGEN" : "ÜBERMORGEN").font(Theme.font(10, .semibold)).tracking(0.6)
                        .foregroundStyle(Theme.faint).padding(.top, 6)
                    list(Array(later.prefix(6 - d.events.count)), lead: nil)
                }
            } else {
                if let e = open.first { lead(e) }
                let rest = d.events.filter { $0.id != open.first?.id }
                if !rest.isEmpty {
                    if open.first != nil { Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 1) }
                    list(rest, lead: nil)
                }
            }
        }
    }

    private func info(_ label: String, _ count: Int) -> String {
        if count == 0 { return "" }
        let n = count == 1 ? "1 Termin" : "\(count) Termine"
        return compact ? "\(label.lowercased()) · \(n)" : n
    }

    /// Der nächste Termin groß, mit Countdown und – kurz vorher – dem Knopf zum Beitreten.
    private func lead(_ e: CalEvent) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(Fmt.time.string(from: e.start)) bis \(Fmt.time.string(from: e.end))")
                    .font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.faint)
                e.marked(discreet: model.discreet).font(Theme.font(15)).foregroundStyle(Theme.text).lineLimit(1)
                // Steht der Termin erst morgen an, sagt die Überschrift schon alles.
                if Calendar.current.isDate(e.start, inSameDayAs: model.now) {
                    Text(Fmt.until(e.start, now: model.now))
                        .font(Theme.font(12, .medium)).monospacedDigit()
                        .foregroundStyle(e.start.timeIntervalSince(model.now) < 3600 ? Theme.accent : Theme.muted)
                }
            }
            Spacer()
            // Der Knopf erscheint erst, wenn der Termin wirklich ansteht – vorher lenkt er nur ab.
            // Erst in den letzten fünf Minuten wird er zum hellsten Knopf.
            if let url = e.joinURL, e.start.timeIntervalSince(model.now) < 15 * 60 {
                Button("Beitreten") { NSWorkspace.shared.open(url) }
                    .buttonStyle(CapsuleStyle(primary: e.start.timeIntervalSince(model.now) < 5 * 60, compact: true))
            }
        }
    }

    /// Alle Termine des Tages in Reihenfolge; Vergangenes tritt zurück. Bei vielen Terminen scrollbar.
    @ViewBuilder private func list(_ events: [CalEvent], lead: CalEvent?) -> some View {
        let rows = VStack(alignment: .leading, spacing: 7) {
            ForEach(events) { e in
                let past = e.end <= model.now
                HStack(spacing: 8) {
                    Text(Fmt.time.string(from: e.start)).font(Theme.font(11)).monospacedDigit()
                        .foregroundStyle(e.id == lead?.id ? Theme.accent : Theme.faint)
                        .frame(width: 38, alignment: .leading)
                    e.marked(discreet: model.discreet).font(Theme.font(12, e.id == lead?.id ? .medium : .regular))
                        .foregroundStyle(past ? Theme.faint : (e.id == lead?.id ? Theme.text : Theme.soft)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .opacity(past ? 0.75 : 1)
            }
        }
        let limit = compact ? 7 : 6
        if events.count > limit {
            ScrollView { rows }.scrollIndicators(.never).frame(height: CGFloat(limit) * 21.5)
        } else {
            rows
        }
    }
}

/// Musik als eine ruhige Zeile: Cover, Titel, drei Knöpfe.
struct MusicTile: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        if let t = model.track {
            HStack(spacing: 11) {
                Cover(image: t.artwork, size: 34, radius: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(t.title).font(Theme.font(13)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(t.artist).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    control("backward.fill", "previous track", "Vorheriger Titel")
                    control(t.isPlaying ? "pause.fill" : "play.fill", "playpause", t.isPlaying ? "Pause" : "Wiedergabe", size: 30)
                    control("forward.fill", "next track", "Nächster Titel")
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 9)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
            .accessibilityElement(children: .contain)
        }
    }

    private func control(_ icon: String, _ command: String, _ name: String, size: CGFloat = 26) -> some View {
        Button { model.musicAction?(command) } label: { Image(systemName: icon) }
            .buttonStyle(RoundStyle(size: size))
            .help(name)
            .accessibilityLabel(name)
    }
}

struct NotificationsTile: View {
    @ObservedObject var model: IslandModel
    @State private var all = false

    var body: some View {
        Tile(icon: "bell.fill", title: "Mitteilungen",
             trailing: model.notices.isEmpty ? nil : AnyView(
                Button(model.cleared.isEmpty ? "Leeren" : "Rückgängig") {
                    if model.cleared.isEmpty { model.clearNotices() } else { model.restoreNotices() }
                }
                    .buttonStyle(.plain).font(Theme.font(11, .medium)).foregroundStyle(Theme.muted))) {
            if model.notificationsDenied {
                Hint(text: "Damit Lotse die Mitteilungen anderer Apps zeigen kann, braucht es Festplattenvollzugriff.",
                     button: "Einstellungen öffnen",
                     url: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
            } else if model.notices.isEmpty {
                HStack(spacing: 10) {
                    Text(model.cleared.isEmpty ? "Alles ruhig." : "Mitteilungen geleert.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    if !model.cleared.isEmpty {
                        Button("Rückgängig") { model.restoreNotices() }.buttonStyle(CapsuleStyle(compact: true))
                    }
                }
            } else {
                VStack(spacing: 0) {
                    let items = Array(model.notices.prefix(all ? 8 : 3))
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, n in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 34).padding(.vertical, 7) }
                        // Die Zeile selbst tut nichts – rechts stehen zwei kleine Knöpfe: öffnen oder abhaken.
                        HStack(spacing: 6) {
                            HStack(spacing: 10) {
                                if n.card == "mail" {
                                    Image(systemName: "envelope.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.accent)
                                        .frame(width: 24, height: 24).background(Circle().fill(Theme.raised))
                                } else {
                                    AppIcon(id: n.appID, size: 24)
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    // Absender und Zeit stehen auf der Grundlinie des Titels, nicht mittig daneben.
                                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                                        Text(model.silent ? n.appName : n.title).font(Theme.font(13, .medium)).foregroundStyle(Theme.text).lineLimit(1)
                                        Spacer(minLength: 6)
                                        Text("\(n.appName) · \(Fmt.ago(n.date, now: model.now))")
                                            .font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                                    }
                                    if !n.body.isEmpty {
                                        // Solange der Bildschirm geteilt wird, bleibt der Inhalt auch hier verborgen.
                                        Text(model.silent ? "Inhalt ausgeblendet (Besprechungsmodus)" : n.body)
                                            .font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                                    }
                                }
                            }
                            Button { model.open(n) } label: {
                                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                                    .frame(width: 30, height: 24).background(Capsule().fill(Theme.raised))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).modifier(HoverGlow()).help("In \(n.appName) öffnen").accessibilityLabel("Öffnen")
                            Button { withAnimation(IslandModel.spring) { model.notices.removeAll { $0.id == n.id } } } label: {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                                    .frame(width: 30, height: 24).background(Capsule().fill(Theme.raised))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).modifier(HoverGlow()).help("Abhaken").accessibilityLabel("Abhaken")
                        }
                    }
                    if model.notices.count > 3 {
                        Button {
                            withAnimation(IslandModel.spring) { all.toggle() }
                        } label: {
                            Text(all ? "Weniger zeigen" : "\(min(model.notices.count, 8) - 3) weitere zeigen")
                                .font(Theme.font(11, .medium)).foregroundStyle(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 34).padding(.top, 9)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Die Ablage: geparkte Dateien als Kacheln. Jede lässt sich herausziehen; Lotse merkt sich nur den Ort der Datei.
struct ShelfView: View {
    @ObservedObject var model: IslandModel
    @State private var hovered: String?

    private var note: String {
        model.shelfMinutes == 0 ? "bleibt, bis du sie entfernst"
            : model.shelfMinutes < 60 ? "verschwindet nach \(model.shelfMinutes) Min aus der Ablage"
            : "verschwindet nach \(model.shelfMinutes / 60) Std aus der Ablage"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                Text("Ablage").font(Theme.font(12, .medium)).foregroundStyle(Theme.text)
                Text(note).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                Spacer(minLength: 6)
                Button { withAnimation(IslandModel.spring) { model.claudeFiles = Array(model.shelf.prefix(10).map(\.url)) } } label: {
                    Label(model.shelf.count == 1 ? "An Claude" : "Alle an Claude", systemImage: "sparkle")
                }
                .buttonStyle(CapsuleStyle(compact: true))
                .help("Neue Claude-Session mit diesen Dateien vorbereiten")
                if model.shelf.contains(where: { Stow.isImage($0.url) }) {
                    Button("Bilder umwandeln") { model.convertShelfImages() }.buttonStyle(CapsuleStyle(compact: true))
                }
                Button("Leeren") { withAnimation(IslandModel.spring) { model.shelf = [] } }
                    .buttonStyle(.plain).font(Theme.font(11, .medium)).foregroundStyle(Theme.muted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(model.shelf.prefix(12)) { item in tile(item) }
            }
            if model.shelf.count > 12 {
                Text("und \(model.shelf.count - 12) weitere").font(Theme.font(11)).foregroundStyle(Theme.faint)
            }
        }
        .padding(13)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }

    private func tile(_ item: ShelfItem) -> some View {
        let on = hovered == item.id
        return VStack(spacing: 5) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if Stow.isImage(item.url), let img = Stow.thumbnail(item.url, size: 160) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 52, height: 52)
                            .frame(width: 60, height: 60)
                    }
                }
                if on {
                    Button { withAnimation(IslandModel.spring) { model.shelf.removeAll { $0.id == item.id } } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.onIce)
                            .frame(width: 18, height: 18).background(Circle().fill(Theme.ice))
                    }
                    .buttonStyle(.plain).offset(x: 6, y: -6)
                    .help("Aus der Ablage nehmen (die Datei bleibt)").accessibilityLabel("\(item.url.lastPathComponent) aus der Ablage nehmen")
                }
                if on {
                    Button { withAnimation(IslandModel.spring) { model.claudeFiles = [item.url] } } label: {
                        Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onIce)
                            .frame(width: 18, height: 18).background(Circle().fill(Theme.ice))
                    }
                    .buttonStyle(.plain).offset(x: 6, y: 48)
                    .help("An Claude geben").accessibilityLabel("\(item.url.lastPathComponent) an Claude geben")
                }
            }
            Text(item.url.lastPathComponent).font(Theme.font(10)).foregroundStyle(Theme.soft)
                .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity)
        }
        .padding(.vertical, 7).padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(on ? 0.10 : 0)))
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? item.id : (hovered == item.id ? nil : hovered) }
        // Herausziehen in jede andere App; ein Doppelklick öffnet die Datei.
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .help("\(item.url.lastPathComponent) – herausziehen oder doppelklicken zum Öffnen")
    }
}

// MARK: - Reiter „Arbeitsplatz“

struct WorkView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 10) {
                FocusTile(model: model)
                RecordTile(model: model).frame(height: 112)
            }
            .frame(width: 190).modifier(Rise(index: 0))
            ClipTile(model: model).modifier(Rise(index: 1))
            CalendarTile(model: model, compact: true).frame(width: 240).modifier(Rise(index: 2))
        }
        .frame(height: 308)
    }
}

/// Verlauf der Zwischenablage: Ein Klick legt den Eintrag wieder in die Zwischenablage, danach wie gewohnt einfügen.
struct ClipTile: View {
    @ObservedObject var model: IslandModel
    @State private var copied: UUID?
    @State private var hovered: UUID?
    @State private var query = ""

    private var found: [Clip] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.clips : model.clips.filter { $0.text.localizedCaseInsensitiveContains(q) || $0.app.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Tile(icon: "doc.on.clipboard", title: "Zwischenablage",
             trailing: model.clips.isEmpty ? nil : AnyView(
                Button("Leeren") { withAnimation(IslandModel.spring) { model.clips = []; query = "" } }
                    .buttonStyle(.plain).font(Theme.font(11, .medium)).foregroundStyle(Theme.muted))) {
            // Die Suche erscheint erst, wenn es etwas zu durchsuchen gibt.
            if model.clipboardOn, model.clips.count > 4 {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.faint)
                    TextField("Suchen", text: $query).textFieldStyle(.plain).font(Theme.font(12)).foregroundStyle(Theme.text)
                        .accessibilityLabel("Zwischenablage durchsuchen")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.faint) }
                            .buttonStyle(.plain).accessibilityLabel("Suche leeren")
                    }
                }
                .padding(.horizontal, 8).frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
            }
            if !model.clipboardOn {
                Text("Der Verlauf ist in den Einstellungen abgeschaltet.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else if model.clips.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Noch nichts kopiert.").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    Text("Was du ab jetzt kopierst – Text, Bilder, Dateien –, steht hier zum erneuten Einfügen bereit.")
                        .font(Theme.font(11)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
            } else if found.isEmpty {
                Text("Nichts gefunden für „\(query)“.").font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else {
                // Bis acht Einträge passen ohne Rollen; erst darüber wird die Liste rollbar.
                Group {
                    if found.count <= 7 {
                        VStack(spacing: 2) { ForEach(found) { clip in row(clip) } }
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 2) { ForEach(found) { clip in row(clip) } }
                        }
                    }
                }
                .padding(.horizontal, -6)
            }
        }
    }

    private func row(_ clip: Clip) -> some View {
        Button {
            model.copyClip?(clip)
            copied = clip.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if copied == clip.id { copied = nil } }
        } label: {
            HStack(spacing: 8) {
                switch clip.kind {
                case .image:
                    if let img = clip.thumbnail {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 28, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                case .files:
                    Image(systemName: "doc.fill").font(.system(size: 10)).foregroundStyle(Theme.accent).frame(width: 14)
                case .text:
                    EmptyView()
                }
                Text(Self.line(clip.text)).font(Theme.font(12)).foregroundStyle(Theme.text).lineLimit(1).truncationMode(.tail).layoutPriority(1)
                Spacer(minLength: 6)
                if copied == clip.id {
                    Label("kopiert", systemImage: "checkmark").font(Theme.font(11, .medium)).foregroundStyle(Theme.accent)
                } else {
                    // Nur die Zeit – der Text selbst braucht den Platz; die Herkunft steht im Hinweis beim Darüberfahren.
                    Text(Fmt.ago(clip.date, now: model.now)).font(Theme.font(11)).foregroundStyle(Theme.faint).fixedSize()
                }
            }
            .padding(.horizontal, 6).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(hovered == clip.id ? 0.10 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? clip.id : (hovered == clip.id ? nil : hovered) }
        .help((clip.app.isEmpty ? "" : "Kopiert in \(clip.app)\n\n") + String(clip.text.prefix(600)))
        .accessibilityLabel("Kopieren: \(Self.line(clip.text))")
    }

    /// Erste nichtleere Zeile, ohne Einrückung – mehrzeiliges bekommt ein Auslassungszeichen.
    private static func line(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        return lines.count > 1 ? first + " …" : first
    }
}

/// Mitschnitt eines Calls: ein Knopf startet und stoppt, die Tondatei landet im Ordner „Lotse Mitschnitte".
struct RecordTile: View {
    @ObservedObject var model: IslandModel
    static let red = Color(red: 1.0, green: 0.45, blue: 0.42)

    private var info: String {
        switch model.recState {
        case .recording: return "läuft"
        case .starting: return "startet"
        case .saving: return "speichert"
        default: return ""
        }
    }

    var body: some View {
        Tile(icon: "waveform", title: "Mitschnitt", info: info) {
            switch model.recState {
            case .recording(let since):
                HStack(spacing: 9) {
                    Dot(color: Self.red, pulsing: true)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(Fmt.elapsed(ctx.date.timeIntervalSince(since)))
                            .font(Theme.font(20, .light)).monospacedDigit().foregroundStyle(Theme.text)
                    }
                    Spacer(minLength: 0)
                    Button("Stopp") { model.toggleRecording?() }.buttonStyle(CapsuleStyle(primary: true, compact: true))
                }
                .frame(maxHeight: .infinity)
            case .starting, .saving:
                Text(model.recState == .saving ? "Wird gespeichert …" : "Startet …")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted).frame(maxHeight: .infinity)
            case .done(let url):
                VStack(alignment: .leading, spacing: 7) {
                    switch model.transcript {
                    case .working(let step):
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 12, height: 12)
                            Text(step).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                    case .ready(let text):
                        HStack(spacing: 6) {
                            Button("Text") { NSWorkspace.shared.open(text) }.buttonStyle(CapsuleStyle(compact: true)).fixedSize()
                                .help("Das Transkript öffnen")
                            Button("An Claude") { model.askClaude?(text) }.buttonStyle(CapsuleStyle(primary: true, compact: true)).fixedSize()
                                .help("Kopiert einen Auftrag zur Zusammenfassung samt Transkript und öffnet Claude")
                        }
                    case .failed(let why):
                        Text(why).font(Theme.font(11)).foregroundStyle(Theme.warn).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    case .none:
                        Button("Mitschreiben") { model.transcribe?(url) }.buttonStyle(CapsuleStyle(compact: true))
                            .help("Schreibt den Mitschnitt auf diesem Mac mit")
                    }
                    HStack(spacing: 6) {
                        Button("Zeigen") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.buttonStyle(CapsuleStyle(compact: true))
                        Button("Neu") { model.toggleRecording?() }.buttonStyle(CapsuleStyle(compact: true))
                    }
                }
            case .failed(let why):
                VStack(alignment: .leading, spacing: 6) {
                    Text(why).font(Theme.font(11)).foregroundStyle(Theme.warn).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Button("Nochmal") { model.toggleRecording?() }.buttonStyle(CapsuleStyle(compact: true))
                }
            case .idle:
                VStack(alignment: .leading, spacing: 7) {
                    Button { model.toggleRecording?() } label: {
                        HStack(spacing: 6) { Circle().fill(Self.red).frame(width: 7, height: 7); Text("Ton aufnehmen") }
                    }
                    .buttonStyle(CapsuleStyle(compact: true))
                    .help("Nimmt den Ton des Macs und dein Mikrofon auf – kein Bild")
                    Text("Nur mit Einverständnis aller.").font(Theme.font(11)).foregroundStyle(Theme.faint)
                }
            }
        }
    }
}

struct FocusTile: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        Tile(icon: "timer", title: "Fokus", info: model.focusRunning ? "läuft" : model.focusPaused != nil ? "pausiert" : "bereit") {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let left = model.focusRemaining(at: ctx.date)
                let total = TimeInterval(model.focusMinutes * 60)
                VStack(spacing: 10) {
                    Text(Fmt.clock(left)).font(Theme.font(34, .light)).monospacedDigit().foregroundStyle(Theme.text)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.raised)
                            Capsule().fill(Theme.accent).frame(width: g.size.width * max(0, min(1, 1 - left / total)))
                        }
                    }
                    .frame(height: 3)
                }
                // Uhr, Balken und Knöpfe bilden einen Block in der Mitte statt oben und unten zu kleben.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            HStack(spacing: 7) {
                if model.focusRunning || model.focusPaused != nil {
                    Button { model.focusReset() } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(RoundStyle(size: 26))
                        .help("Zurücksetzen").accessibilityLabel("Fokus zurücksetzen")
                } else {
                    Button { model.focusAdjust(-5) } label: { Image(systemName: "minus") }.buttonStyle(RoundStyle(size: 26))
                        .help("5 Minuten weniger").accessibilityLabel("5 Minuten weniger")
                }
                Button(model.focusRunning ? "Pause" : model.focusPaused != nil ? "Weiter" : "Start") { model.focusToggle() }
                    .buttonStyle(CapsuleStyle(primary: true, compact: true))
                if !(model.focusRunning || model.focusPaused != nil) {
                    Button { model.focusAdjust(5) } label: { Image(systemName: "plus") }.buttonStyle(RoundStyle(size: 26))
                        .help("5 Minuten mehr").accessibilityLabel("5 Minuten mehr")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Reiter „Ablage“

struct StowView: View {
    @ObservedObject var model: IslandModel
    @State private var hovered: String?

    var body: some View {
        if !model.claudeFiles.isEmpty {
            ToClaudeView(model: model)
        } else if model.stowFiles.isEmpty, model.shelf.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.accent)
                Text("Zieh Dateien auf die Insel, um sie hier zu parken.").font(Theme.font(13)).foregroundStyle(Theme.soft)
                Text("Von dort ziehst du sie in jede App. Bilder lassen sich umwandeln.")
                    .font(Theme.font(11)).foregroundStyle(Theme.faint)
            }
            .frame(maxWidth: .infinity).frame(height: 120)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
        } else if model.stowFiles.isEmpty {
            ShelfView(model: model)
        } else {
            HStack(alignment: .top, spacing: 8) {
                stack.frame(width: 150)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        big("globe", "Web", "JPEG, 2000 px") { model.runStow(.web) }
                        big("paperplane.fill", "Senden", "JPEG, 1280 px") { model.runStow(.send) }
                        big("printer.fill", "Drucken", "PDF, A4") { model.runStow(.print) }
                    }
                    HStack(spacing: 6) {
                        ForEach(Stow.formats, id: \.ext) { f in
                            Button(f.label) { model.runStow(.format(f.ext)) }.buttonStyle(CapsuleStyle(compact: true, fill: true))
                        }
                    }
                    HStack(spacing: 8) {
                        if model.stowBusy {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                            Text("Wandle um …").font(Theme.font(11)).foregroundStyle(Theme.muted)
                        } else {
                            Text(model.stowMessage.isEmpty ? "Wähle, was daraus werden soll." : model.stowMessage)
                                .font(Theme.font(11)).foregroundStyle(model.stowResult.isEmpty ? Theme.faint : Theme.soft).lineLimit(1)
                        }
                        Spacer()
                        if !model.stowResult.isEmpty {
                            Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting(model.stowResult) }
                                .buttonStyle(CapsuleStyle(primary: true, compact: true))
                        }
                        Button(model.stowResult.isEmpty ? "Abbrechen" : "Fertig") { model.closeStow() }.buttonStyle(CapsuleStyle(compact: true))
                    }
                }
            }
            .disabled(model.stowBusy)
        }
    }

    private var stack: some View {
        VStack(spacing: 9) {
            ZStack {
                ForEach(Array(model.stowFiles.prefix(3).enumerated().reversed()), id: \.offset) { i, url in
                    Group {
                        if let img = Stow.thumbnail(url) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) }
                        else { Theme.raised }
                    }
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    .rotationEffect(.degrees(Double(i) * -5))
                    .offset(x: CGFloat(i) * -5, y: CGFloat(i) * -3)
                }
            }
            .frame(height: 92)
            Text(model.stowFiles.count == 1 ? model.stowFiles[0].lastPathComponent : "\(model.stowFiles.count) Bilder")
                .font(Theme.font(11, .medium)).foregroundStyle(Theme.soft).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(Theme.raised))
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
    }

    private func big(_ icon: String, _ title: String, _ result: String, _ action: @escaping () -> Void) -> some View {
        let on = hovered == title
        let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
        return Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(on ? Theme.onIce : Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(on ? Color.white.opacity(0.92) : Theme.raised))
                // Im Ruhezustand nur der Name; unter der Maus das konkrete Ergebnis – an derselben Stelle.
                ZStack {
                    Text(title).font(Theme.font(13)).foregroundStyle(Theme.muted).opacity(on ? 0 : 1)
                    Text(result).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).opacity(on ? 1 : 0)
                }
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background {
                if on {
                    shape.fill(LinearGradient(colors: Theme.tones.chosen,
                                              startPoint: .top, endPoint: .bottom))
                }
            }
            .modifier(GlassPiece(shape: shape))
            .scaleEffect(on ? 1.035 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { if h { hovered = title } else if hovered == title { hovered = nil } }
        }
        .accessibilityLabel("\(title): \(result)")
    }
}


// MARK: - Reiter „Lautstärke“

/// Schlanker Regler: dünne Spur, helle Füllung, kleiner Knopf. Ziehen oder klicken setzt den Wert.
struct LevelSlider: View {
    var value: Double
    var enabled = true
    var onChange: (Double) -> Void

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: 2)
                Capsule().fill(Color.white.opacity(enabled ? 0.92 : 0.3)).frame(width: max(0, w * value), height: 2)
                Circle().fill(Color.white.opacity(enabled ? 1 : 0.4)).frame(width: 9, height: 9)
                    .offset(x: min(max(0, w * value - 4.5), w - 9))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                guard enabled, w > 0 else { return }
                onChange(min(1, max(0, d.location.x / w)))
            })
        }
        .frame(height: 16)
        .accessibilityValue("\(Int((value * 100).rounded())) Prozent")
    }
}

/// Drehscheibe mit Strichkranz und Zahl in der Mitte: die Gesamtlautstärke.
struct VolumeDial: View {
    var value: Double
    var muted: Bool
    var enabled = true
    var onChange: (Double) -> Void = { _ in }

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let outer = min(sz.width, sz.height) / 2 - 1
                let lit = Int((value * 60).rounded())
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * Double.pi - Double.pi / 2
                    let on = i < lit && !muted
                    let len: CGFloat = i % 5 == 0 ? 7 : 5
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + CGFloat(cos(a)) * (outer - len), y: c.y + CGFloat(sin(a)) * (outer - len)))
                    p.addLine(to: CGPoint(x: c.x + CGFloat(cos(a)) * outer, y: c.y + CGFloat(sin(a)) * outer))
                    ctx.stroke(p, with: .color(on ? Color.white.opacity(0.9) : Color.white.opacity(0.16)),
                               style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                }
            }
            VStack(spacing: 0) {
                Text(muted ? "–" : "\(Int((value * 100).rounded()))")
                    .font(Theme.font(26, .light)).monospacedDigit().foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(muted ? "stumm" : "gesamt").font(Theme.font(10, .medium)).foregroundStyle(Theme.faint)
            }
        }
        .frame(width: 104, height: 104)
        .contentShape(Circle())
        // Am Strichkranz drehen: oben ist 0, im Uhrzeigersinn bis 100.
        .gesture(DragGesture(minimumDistance: 0).onChanged { d in
            guard enabled else { return }
            let a = atan2(Double(d.location.x - 52), Double(52 - d.location.y))
            var v = (a < 0 ? a + 2 * Double.pi : a) / (2 * Double.pi)
            if value < 0.15 && v > 0.85 { v = 0 } else if value > 0.85 && v < 0.15 { v = 1 }  // nicht über die Null springen
            onChange(min(1, max(0, v)))
        })
        .help(enabled ? "Am Kranz drehen, um die Lautstärke zu ändern" : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(muted ? "Ton aus" : "Gesamtlautstärke \(Int((value * 100).rounded())) Prozent")
        .accessibilityAdjustableAction { dir in
            guard enabled else { return }
            onChange(min(1, max(0, value + (dir == .increment ? 0.05 : -0.05))))
        }
    }
}

struct MixerView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Links: die Gesamtlautstärke
            // Die Scheibe selbst ist der Regler, ein zweiter Schieber wäre doppelt.
            VStack(spacing: 14) {
                Spacer(minLength: 0)
                VolumeDial(value: model.volume, muted: model.muted, enabled: model.volumeAdjustable) { model.setVolume?($0) }
                Button { model.setMuted?(!model.muted) } label: {
                    Image(systemName: model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .buttonStyle(RoundStyle(primary: model.muted, size: 28))
                .help(model.muted ? "Ton einschalten" : "Ton ausschalten")
                .accessibilityLabel(model.muted ? "Ton einschalten" : "Ton ausschalten")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxHeight: .infinity)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
            .modifier(Rise(index: 0))

            // Rechts: was gerade Ton ausgibt
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                    Text("Apps").font(Theme.font(12, .medium)).foregroundStyle(Theme.text)
                    Spacer()
                    // Steht unten die Geräteauswahl, wäre der Name hier doppelt.
                    if model.outputs.count <= 1 {
                        Text(model.outputName).font(Theme.font(11)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
                if !model.volumeAdjustable {
                    Text("Dieses Ausgabegerät lässt sich nicht vom Mac aus regeln (z. B. ein Monitor über HDMI).")
                        .font(Theme.font(11)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                if model.mixApps.isEmpty {
                    Text("Gerade gibt keine App Ton aus.").font(Theme.font(12)).foregroundStyle(Theme.muted)
                } else {
                    ForEach(model.mixApps.prefix(4)) { app in row(app) }
                }
                Spacer(minLength: 4)
                if let t = model.track { playing(t) }
                if model.outputs.count > 1 { outputs }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .modifier(GlassPiece(shape: RoundedRectangle(cornerRadius: 17, style: .continuous)))
            .modifier(Rise(index: 1))
        }
        .frame(minHeight: 216)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Was gerade läuft – mit Cover und Steuerung.
    private func playing(_ t: Track) -> some View {
        HStack(spacing: 11) {
            Cover(image: t.artwork, size: 40, radius: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(t.title).font(Theme.font(13, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(t.artist).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                control("backward.fill", "previous track", "Vorheriger Titel")
                control(t.isPlaying ? "pause.fill" : "play.fill", "playpause", t.isPlaying ? "Pause" : "Wiedergabe", big: true)
                control("forward.fill", "next track", "Nächster Titel")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.raised))
    }

    private func control(_ icon: String, _ command: String, _ name: String, big: Bool = false) -> some View {
        Button { model.musicAction?(command) } label: {
            Image(systemName: icon).font(.system(size: big ? 14 : 11)).foregroundStyle(Theme.text)
                .frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.plain).modifier(HoverGlow()).help(name).accessibilityLabel(name)
    }

    /// Wohin der Ton geht – ein Klick schaltet um.
    private var outputs: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "hifispeaker.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.soft)
                Text("Ausgabe").font(Theme.font(12, .medium)).foregroundStyle(Theme.text)
            }
            // Eine Zeile je Gerät, damit auch lange Namen ganz zu lesen sind.
            VStack(spacing: 5) {
                ForEach(model.outputs.prefix(4)) { o in
                    Button { model.setOutput?(o) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: o.symbol).font(.system(size: 10, weight: .medium)).frame(width: 14)
                            Text(o.name).font(Theme.font(11, o.current ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 0)
                            if o.current { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        }
                        .foregroundStyle(o.current ? Theme.onIce : Theme.soft)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(o.current ? AnyShapeStyle(Theme.ice) : AnyShapeStyle(Theme.raised)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(o.current ? "\(o.name) ist das aktuelle Ausgabegerät" : "Ton auf \(o.name) ausgeben")
                    .accessibilityLabel(o.current ? "\(o.name), aktuelles Ausgabegerät" : "Ton auf \(o.name) ausgeben")
                }
            }
        }
    }

    private func row(_ app: MixApp) -> some View {
        HStack(spacing: 10) {
            Group {
                if let url = app.url { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable() }
                else { Image(systemName: "app.fill").resizable().foregroundStyle(Theme.faint) }
            }
            .frame(width: 22, height: 22)
            Text(app.name).font(Theme.font(12)).foregroundStyle(Theme.text).lineLimit(1).frame(width: 104, alignment: .leading)
            if app.scriptable, let level = app.level {
                LevelSlider(value: level) { model.setAppLevel?(app.id, $0) }
                Text("\(Int((level * 100).rounded())) %").font(Theme.font(11)).monospacedDigit().foregroundStyle(Theme.soft)
                    .frame(width: 40, alignment: .trailing)
            } else {
                // Ohne eigenen Regler: Lotse zeigt die App, kann sie aber (noch) nicht einzeln leiser machen.
                LevelSlider(value: 1, enabled: false) { _ in }
                Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
                    .frame(width: 40, alignment: .trailing)
                    .help("\(app.name) lässt sich nicht einzeln regeln und folgt der Gesamtlautstärke")
                    .accessibilityLabel("folgt der Gesamtlautstärke")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
