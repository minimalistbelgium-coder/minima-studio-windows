import SwiftUI
import AppKit

// MARK: - Choix du thème (clair, sombre ou celui du système)

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark

    static let key = "themeMode"
    static let fallback: ThemeMode = .dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Système"
        case .light: return "Clair"
        case .dark: return "Sombre"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// Choix mémorisé (sombre tant que rien n'a été choisi, comme avant).
    static var stored: ThemeMode {
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? fallback
    }

    /// Applique le thème à toute l'app : fenêtre principale, mini-fenêtre du chrono, popovers, diagnostic.
    @MainActor
    static func apply(_ mode: ThemeMode) {
        NSApplication.shared.appearance = mode.appearance
    }
}

// MARK: - Couleurs (toutes dynamiques : elles suivent le thème clair ou sombre)

enum Theme {
    static let bg = Color(light: "F1F2F6", dark: "0B0C0E")
    static let card = Color(light: "FFFFFF", dark: "131417")
    static let card2 = Color(light: "E8EAEF", dark: "1A1B1F")
    /// Encre : blanc sur fond sombre, noir sur fond clair. À utiliser avec une opacité.
    static let ink = Color(light: "000000", dark: "FFFFFF")
    static let line = Color(light: "000000", dark: "FFFFFF", lightAlpha: 0.09, darkAlpha: 0.07)
    /// Bordure un peu plus marquée (champs, boutons).
    static let stroke = Color(light: "000000", dark: "FFFFFF", lightAlpha: 0.12, darkAlpha: 0.10)
    /// Reflet du haut des surfaces en verre.
    static let rim = Color(light: "FFFFFF", dark: "FFFFFF", lightAlpha: 0.95, darkAlpha: 0.16)
    static let text = Color(light: "15171C", dark: "EDEEF0")
    static let text2 = Color(light: "3A3E47", dark: "C9CBD1")
    static let muted = Color(light: "666A74", dark: "8B8D94")
    static let blue = Color(light: "2563EB", dark: "4C8DFF")
    static let green = Color(light: "0B8A4E", dark: "3DD68C")
    static let amber = Color(light: "B26A00", dark: "F5A524")
    static let red = Color(light: "D63333", dark: "FF6B6B")
    static let violet = Color(light: "7C4DDB", dark: "A78BFA")
    static let pink = Color(light: "D6408F", dark: "F472B6")
    /// Texte posé sur un aplat bleu.
    static let onAccent = Color(light: "FFFFFF", dark: "06101F")
    /// Texte d'un bouton « danger ».
    static let dangerText = Color(light: "C22B2B", dark: "FFA3A3")
    /// Voile posé sur la fenêtre quand une fiche est ouverte.
    static let scrim = Color(light: "1A1D26", dark: "000000", lightAlpha: 0.22, darkAlpha: 0.42)
    /// Fond du texte des initiales (toujours sombre : les couleurs de profil sont claires).
    static let avatarInk = Color(hex: "0B0C0E")

    static let palette = ["F472B6", "2DD4BF", "F5A524", "4C8DFF", "A78BFA", "34D399", "FB7185", "60A5FA", "FBBF24", "C084FC"]
}

extension NSColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }

    /// Couleur qui change selon le thème.
    init(light: String, dark: String, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        let l = NSColor(hex: light, alpha: lightAlpha)
        let d = NSColor(hex: dark, alpha: darkAlpha)
        self.init(nsColor: NSColor(name: nil) { $0.isDark ? d : l })
    }

    /// Rapproche la couleur du blanc en thème sombre et du noir en thème clair,
    /// pour qu'un texte coloré reste lisible sur son fond teinté dans les deux thèmes.
    func adaptive(lighten: Double, darken: Double) -> Color {
        let base = NSColor(self)
        return Color(nsColor: NSColor(name: nil) { appearance in
            var out = NSColor.gray
            appearance.performAsCurrentDrawingAppearance {
                let c = base.usingColorSpace(.sRGB) ?? .gray
                let dark = appearance.isDark
                let k = CGFloat(dark ? lighten : darken)
                let target: CGFloat = dark ? 1 : 0
                out = NSColor(srgbRed: c.redComponent + (target - c.redComponent) * k,
                              green: c.greenComponent + (target - c.greenComponent) * k,
                              blue: c.blueComponent + (target - c.blueComponent) * k,
                              alpha: c.alphaComponent)
            }
            return out
        })
    }

    /// Texte lisible sur un fond teinté de la même couleur.
    func mix(white amount: Double) -> Color { adaptive(lighten: amount, darken: min(0.6, amount + 0.05)) }

    /// Version lisible d'une couleur vive (statuts, clients) utilisée comme couleur de texte.
    var readable: Color { adaptive(lighten: 0.08, darken: 0.42) }
}

// MARK: - Cartes

struct CardStyle: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .transformEnvironment(\.layoutWidth) { $0 = Swift.max(0, $0 - 2 * padding) }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardStyle(padding: padding)) }
}

// MARK: - Boutons

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Surface(configuration: configuration) }

    private struct Surface: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var enabled
        @Environment(\.controlSize) private var controlSize
        @State private var hover = false

        var body: some View {
            let small = controlSize == .small || controlSize == .mini
            configuration.label
                .font(.system(size: small ? 12 : 13.5, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, small ? 12 : 16).frame(minHeight: small ? 28 : 36)
                .glassButton(tint: Theme.blue, radius: small ? 8 : 10, prominent: true)
                .brightness(hover && enabled ? 0.05 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
        }
    }
}

struct SecondaryButton: ButtonStyle {
    var danger = false
    func makeBody(configuration: Configuration) -> some View { Surface(configuration: configuration, danger: danger) }

    private struct Surface: View {
        let configuration: Configuration
        let danger: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.controlSize) private var controlSize
        @State private var hover = false

        var body: some View {
            let small = controlSize == .small || controlSize == .mini
            configuration.label
                .font(.system(size: small ? 12 : 13, weight: .medium))
                .foregroundStyle(danger ? Theme.dangerText : Theme.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, small ? 11 : 14).frame(minHeight: small ? 28 : 32)
                .glassButton(tint: danger ? Theme.red.opacity(0.14) : nil, radius: small ? 8 : 9, prominent: false, hover: hover)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
                .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hover)
        }
    }
}

// MARK: - Pastilles et avatars

struct Pill: View {
    let text: String
    var color: Color = Theme.muted
    /// Dans une colonne de largeur fixe : la pastille se tronque (…) au lieu de déborder.
    var flexible = false
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color.readable)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: !flexible, vertical: false)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 0.5))
    }
}

struct AvatarView: View {
    let name: String
    let initials: String
    let url: String?
    var color: String = "A78BFA"
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(Color(hex: color))
            Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(Theme.avatarInk)
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(name)
    }
}

extension AvatarView {
    init(profile p: Profile, size: CGFloat = 28) {
        self.init(name: p.displayName, initials: p.initials, url: p.avatar_url, color: p.color, size: size)
    }
}

// MARK: - Cartes de chiffres

/// Carte de chiffre. La ligne de pied est toujours réservée, même vide,
/// pour que toutes les cartes d'une rangée aient la même hauteur et le même alignement.
struct StatCard: View {
    let label: String
    let value: String
    var foot: String? = nil
    var footColor: Color = Theme.muted
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit().tracking(-0.4).padding(.top, 10)
                .foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(foot ?? " ").font(.system(size: 12.5)).foregroundStyle(footColor).padding(.top, 8)
                .lineLimit(2).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(foot == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .scaleEffect(hover ? 1.012 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
    }
}

// MARK: - En-tête et page

struct PageHeader<Trailing: View>: View {
    let kicker: String?
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.layoutWidth) private var width

    var body: some View {
        // Le titre prend la place restante (deux lignes au besoin), les boutons gardent leur taille.
        let stacked = width < 520
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .bottom, spacing: 16))
        layout {
            heading.frame(maxWidth: .infinity, alignment: .leading)
            trailing().layoutPriority(1)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let kicker { Text(kicker).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1) }
            Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.4).foregroundStyle(Theme.text)
                .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(kicker: String?, title: String) {
        self.init(kicker: kicker, title: title, trailing: { EmptyView() })
    }
}

struct Page<Content: View>: View {
    @Environment(\.compactLayout) private var compact
    /// Largeur de la zone de contenu (fenêtre moins la barre latérale).
    @Environment(\.layoutWidth) private var area
    @ViewBuilder var content: () -> Content

    /// Place prise par la barre de défilement quand elle est toujours visible (réglage macOS).
    /// On la retire d'office pour que la mise en page ne change pas quand elle apparaît.
    private var scrollerWidth: CGFloat {
        NSScroller.preferredScrollerStyle == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    var body: some View {
        let pad: CGFloat = compact ? 20 : 36
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content() }
                .layoutWidth(Swift.min(area - scrollerWidth, 1320) - 2 * pad)
                .padding(.horizontal, pad).padding(.top, compact ? 26 : 34).padding(.bottom, 48)
                .frame(maxWidth: 1320, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(Theme.text)
    }
}

struct EmptyHint: View {
    let text: String
    var icon: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            if let icon {
                Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.muted.opacity(0.8))
                    .frame(width: 40, height: 40).background(Theme.ink.opacity(0.05), in: Circle())
            }
            Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 26).padding(.horizontal, 16)
    }
}

struct ToastView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ZStack {
            if let t = app.toast {
                HStack(spacing: 8) {
                    Image(systemName: t.hasPrefix("Erreur") || t.hasPrefix("Impossible") ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.hasPrefix("Erreur") || t.hasPrefix("Impossible") ? Theme.red : Theme.green)
                    Text(t).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                        .lineLimit(3).multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(maxWidth: 520)
                .fixedSize(horizontal: false, vertical: true)
                .glassSurface(Capsule(), fill: Theme.card.opacity(0.7))
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: app.toast)
    }
}

enum Money {
    static func eur(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_BE")
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.rounded() == v ? 0 : 2
        f.minimumFractionDigits = v.rounded() == v ? 0 : 2
        return (f.string(from: NSNumber(value: v)) ?? "\(v)") + " €"
    }
    /// Version courte pour les axes de graphiques (1,2 k €).
    static func short(_ v: Double) -> String {
        if abs(v) >= 1000 {
            let k = (v / 100).rounded() / 10
            let s = k.rounded() == k ? String(Int(k)) : String(format: "%.1f", k).replacingOccurrences(of: ".", with: ",")
            return "\(s) k €"
        }
        return "\(Int(v.rounded())) €"
    }
    static func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: ""))
    }
}
