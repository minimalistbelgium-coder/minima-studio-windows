import SwiftUI
import AppKit

// MARK: - Liquid Glass (macOS 26) avec repli propre pour macOS 13 à 15
//
// Tout le verre de l'app passe par ce fichier :
//   .glassCard()            carte translucide
//   .glassSurface(forme)    surface en verre quelconque (barre latérale, toast, fiche)
//   .glassButton(...)       fond d'un bouton
//   GlassGroup { ... }      regroupe plusieurs verres voisins (GlassEffectContainer)
// Sur macOS 26 on utilise les vraies API (glassEffect). Avant, un matériau flou,
// une bordure fine et un reflet léger donnent un rendu proche.

private struct GlassDepthKey: EnvironmentKey { static let defaultValue = 0 }

extension EnvironmentValues {
    /// Nombre de surfaces en verre déjà traversées. À l'intérieur d'un verre,
    /// les cartes deviennent de simples aplats translucides (pas de verre sur du verre).
    var glassDepth: Int {
        get { self[GlassDepthKey.self] }
        set { self[GlassDepthKey.self] = newValue }
    }
}

/// Fond en verre d'une forme donnée.
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    var tint: Color? = nil
    /// Voile de couleur posé dans le repli (et sous le verre quand on veut plus d'opacité).
    var fill: Color = Theme.card.opacity(0.55)
    var shadow = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(tint.map { Glass.regular.tint($0) } ?? Glass.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(fill))
                .overlay(shape.fill(tint ?? Color.clear))
                .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
                .overlay(shape.strokeBorder(
                    LinearGradient(colors: [Theme.rim, Theme.rim.opacity(0)], startPoint: .top, endPoint: .center),
                    lineWidth: 1).blendMode(.plusLighter).opacity(scheme == .dark ? 1 : 0.6))
                .shadow(color: .black.opacity(shadow ? (scheme == .dark ? 0.30 : 0.07) : 0), radius: 16, y: 8)
        }
    }
}

/// Aplat translucide utilisé pour les cartes posées sur une surface déjà en verre.
struct InsetBackground<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        shape.fill(Theme.ink.opacity(0.045))
            .overlay(shape.strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension View {
    /// Surface en verre de la forme voulue. Le contenu est marqué comme « dans du verre ».
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, fill: Color = Theme.card.opacity(0.55), shadow: Bool = true) -> some View {
        self
            .environment(\.glassDepth, 1)
            .background { GlassBackground(shape: shape, tint: tint, fill: fill, shadow: shadow) }
    }

    /// Carte : verre au premier niveau, aplat discret à l'intérieur d'un autre verre.
    func glassCard(radius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(GlassCardModifier(radius: radius, tint: tint))
    }

    /// Fond d'un bouton. `prominent` : bouton principal teinté.
    @ViewBuilder
    func glassButton(tint: Color?, radius: CGFloat, prominent: Bool, hover: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.glassEffect((tint.map { Glass.regular.tint($0) } ?? Glass.regular).interactive(), in: shape)
        } else if prominent {
            self
                .background(tint ?? Theme.blue, in: shape)
                .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)], startPoint: .top, endPoint: .center)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .shadow(color: (tint ?? Theme.blue).opacity(0.28), radius: 8, y: 3)
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .background(Theme.card2.opacity(hover ? 1 : 0.75), in: shape)
                .overlay(shape.fill(tint ?? Color.clear))
                .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    /// Survol d'une ligne cliquable : léger voile.
    func hoverRow(radius: CGFloat = 0) -> some View { modifier(HoverRow(radius: radius)) }
}

private struct GlassCardModifier: ViewModifier {
    let radius: CGFloat
    let tint: Color?
    @Environment(\.glassDepth) private var depth

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .environment(\.glassDepth, depth + 1)
            .clipShape(shape)
            .background {
                if depth > 0 {
                    InsetBackground(shape: shape).overlay(shape.fill(tint ?? Color.clear))
                } else {
                    GlassBackground(shape: shape, tint: tint)
                }
            }
    }
}

private struct HoverRow: ViewModifier {
    let radius: CGFloat
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .background(Theme.ink.opacity(hover ? 0.045 : 0), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.12), value: hover)
    }
}

/// Regroupe des verres voisins pour qu'ils soient rendus ensemble (macOS 26). Sans effet avant.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}

/// Flou natif de ce qu'il y a derrière la fenêtre (mini-fenêtre du chrono).
struct BehindWindowBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.state = .active
        v.material = material
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Verre de la mini-fenêtre : flou de ce qui est derrière la fenêtre, puis verre par-dessus.
struct MiniGlass<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        ZStack {
            BehindWindowBlur().clipShape(shape)
            GlassBackground(shape: shape, fill: Theme.card.opacity(0.5), shadow: false)
        }
    }
}

// MARK: - Fond d'ambiance (donne de la matière au verre)

struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.blue.opacity(dark ? 0.20 : 0.16), Theme.blue.opacity(0)],
                           center: UnitPoint(x: 0.88, y: -0.05), startRadius: 0, endRadius: 620)
            RadialGradient(colors: [Theme.violet.opacity(dark ? 0.13 : 0.12), Theme.violet.opacity(0)],
                           center: UnitPoint(x: 0.12, y: 1.05), startRadius: 0, endRadius: 560)
            RadialGradient(colors: [Theme.green.opacity(dark ? 0.06 : 0.07), Theme.green.opacity(0)],
                           center: UnitPoint(x: 0.55, y: 0.6), startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Bascule du thème (pastille en verre, soleil et lune animés)

struct ThemeToggle: View {
    /// Version réduite : un seul bouton rond qui alterne clair et sombre.
    var compact = false
    @AppStorage(ThemeMode.key) private var raw = ThemeMode.fallback.rawValue
    @Environment(\.colorScheme) private var scheme
    @Namespace private var ns

    private var mode: ThemeMode { ThemeMode(rawValue: raw) ?? ThemeMode.fallback }

    var body: some View {
        Group {
            if compact { single } else { segmented }
        }
        .onChange(of: raw) { v in ThemeMode.apply(ThemeMode(rawValue: v) ?? ThemeMode.fallback) }
    }

    private func choose(_ m: ThemeMode) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.72)) { raw = m.rawValue }
    }

    private var single: some View {
        let dark = scheme == .dark
        return Button { choose(dark ? .light : .dark) } label: {
            ZStack {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(Theme.amber)
                    .rotationEffect(.degrees(dark ? -90 : 0))
                    .scaleEffect(dark ? 0.3 : 1)
                    .opacity(dark ? 0 : 1)
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(Theme.violet)
                    .rotationEffect(.degrees(dark ? 0 : 90))
                    .scaleEffect(dark ? 1 : 0.3)
                    .opacity(dark ? 1 : 0)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 34, height: 34)
            .glassButton(tint: nil, radius: 17, prominent: false)
            .contentShape(Circle())
            .animation(.spring(response: 0.45, dampingFraction: 0.65), value: dark)
        }
        .buttonStyle(.plain)
        .help(dark ? "Passer au thème clair" : "Passer au thème sombre")
        .accessibilityLabel("Changer de thème")
    }

    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(ThemeMode.allCases) { m in
                let on = m == mode
                Button { choose(m) } label: {
                    Image(systemName: m.icon)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(on ? tint(m) : Theme.muted)
                        .rotationEffect(.degrees(on ? 0 : (m == .light ? -70 : (m == .dark ? 30 : 0))))
                        .scaleEffect(on ? 1.08 : 0.9)
                        .frame(maxWidth: .infinity).frame(height: 26)
                        .background {
                            if on {
                                Capsule().fill(Theme.ink.opacity(0.10))
                                    .overlay(Capsule().strokeBorder(Theme.rim.opacity(0.5), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "knob", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Thème : \(m.label.lowercased())")
                .accessibilityLabel("Thème \(m.label.lowercased())")
            }
        }
        .padding(3)
        .background { GlassBackground(shape: Capsule(), fill: Theme.card2.opacity(0.6), shadow: false) }
    }

    private func tint(_ m: ThemeMode) -> Color {
        switch m {
        case .light: return Theme.amber
        case .dark: return Theme.violet
        case .system: return Theme.text
        }
    }
}
