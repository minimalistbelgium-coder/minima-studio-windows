import SwiftUI

enum Theme {
    static let bg = Color(hex: "0B0C0E")
    static let card = Color(hex: "131417")
    static let card2 = Color(hex: "1A1B1F")
    static let line = Color.white.opacity(0.07)
    static let text = Color(hex: "EDEEF0")
    static let text2 = Color(hex: "C9CBD1")
    static let muted = Color(hex: "8B8D94")
    static let blue = Color(hex: "4C8DFF")
    static let green = Color(hex: "3DD68C")
    static let amber = Color(hex: "F5A524")
    static let red = Color(hex: "FF6B6B")

    static let palette = ["F472B6", "2DD4BF", "F5A524", "4C8DFF", "A78BFA", "34D399", "FB7185", "60A5FA", "FBBF24", "C084FC"]
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
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardStyle(padding: padding)) }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Color(hex: "06101F"))
            .padding(.horizontal, 16).frame(minHeight: 36)
            .background(Theme.blue.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
    }
}

struct SecondaryButton: ButtonStyle {
    var danger = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(danger ? Color(hex: "FFA3A3") : Theme.text)
            .padding(.horizontal, 14).frame(minHeight: 32)
            .background(Theme.card2.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.white.opacity(0.1)))
            .contentShape(Rectangle())
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.muted
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
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
            Text(initials).font(.system(size: size * 0.38, weight: .semibold)).foregroundStyle(Theme.bg)
            if let url, let u = URL(string: url) {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }
}

extension AvatarView {
    init(profile p: Profile, size: CGFloat = 28) {
        self.init(name: p.displayName, initials: p.initials, url: p.avatar_url, color: p.color, size: size)
    }
}

struct StatCard: View {
    let label: String
    let value: String
    var foot: String? = nil
    var footColor: Color = Theme.muted
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit().tracking(-0.4).padding(.top, 10)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let foot { Text(foot).font(.system(size: 12.5)).foregroundStyle(footColor).padding(.top, 8) }
        }
        .card()
    }
}

struct PageHeader<Trailing: View>: View {
    let kicker: String?
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom) {
                heading
                Spacer(minLength: 16)
                trailing()
            }
            VStack(alignment: .leading, spacing: 14) {
                heading
                trailing()
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let kicker { Text(kicker).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
            Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.4)
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
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) { content() }
                .padding(.horizontal, compact ? 20 : 36).padding(.top, compact ? 26 : 34).padding(.bottom, 48)
                .frame(maxWidth: 1320, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }
}

struct EmptyHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 26)
    }
}

struct ToastView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        if let t = app.toast {
            Text(t).font(.system(size: 13.5))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(Color(hex: "1F2025"), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
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
    static func parse(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "€", with: ""))
    }
}
