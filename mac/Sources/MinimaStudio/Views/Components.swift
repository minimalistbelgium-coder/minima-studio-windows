import SwiftUI
import AppKit

// MARK: - Champs de formulaire

struct FormField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            content()
            if let hint { Text(hint).font(.system(size: 11.5)).foregroundStyle(Theme.muted.opacity(0.8)) }
        }
    }
}

struct InputStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .padding(.horizontal, 11).frame(minHeight: 34)
            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08)))
    }
}

extension View {
    func input() -> some View { modifier(InputStyle()) }
}

struct MultilineInput: View {
    @Binding var text: String
    var placeholder: String = ""
    var height: CGFloat = 90
    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).font(.system(size: 13.5)).foregroundStyle(Theme.muted.opacity(0.7))
                    .padding(.horizontal, 11).padding(.vertical, 9)
            }
            TextEditor(text: $text)
                .font(.system(size: 13.5))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6).padding(.vertical, 6)
        }
        .frame(height: height)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.08)))
    }
}

// MARK: - Petits éléments

struct ClientDot: View {
    let color: String?
    var size: CGFloat = 8
    var body: some View { Circle().fill(Color(hex: color ?? "8B8D94")).frame(width: size, height: size) }
}

struct StatusPill: View {
    let status: String
    var body: some View { Pill(text: MissionStatus.label(status), color: Color(hex: MissionStatus.color(status))) }
}

struct MemberStack: View {
    let profiles: [Profile]
    var size: CGFloat = 24
    var body: some View {
        HStack(spacing: -7) {
            ForEach(profiles) { p in
                AvatarView(profile: p, size: size)
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
                    .help(p.displayName)
            }
        }
    }
}

struct SectionTitle: View {
    let text: String
    var trailing: String? = nil
    var body: some View {
        HStack {
            Text(text).font(.system(size: 15, weight: .semibold))
            Spacer()
            if let trailing { Text(trailing).font(.system(size: 12.5)).foregroundStyle(Theme.muted) }
        }
    }
}

// MARK: - Ligne de mission

struct MissionRow: View {
    @EnvironmentObject var data: DataStore
    let mission: Mission
    var showMoney = false
    var onOpen: () -> Void

    var body: some View {
        let client = data.client(mission.client_id)
        Button(action: onOpen) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: client?.color ?? "8B8D94")).frame(width: 3, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(mission.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    HStack(spacing: 6) {
                        Text(client?.name ?? "Sans client")
                        if mission.rushes_url != nil {
                            Text("·")
                            Image(systemName: "link").font(.system(size: 10))
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 12)
                MemberStack(profiles: data.memberProfiles(of: mission.id))
                if showMoney, let b = mission.editor_budget {
                    Text(Money.eur(b)).font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.text2)
                        .frame(width: 80, alignment: .trailing)
                }
                VStack(alignment: .trailing, spacing: 3) {
                    Text(DateFmt.relative(mission.deadlineDate).isEmpty ? "Sans deadline" : DateFmt.relative(mission.deadlineDate))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(mission.isLate ? Theme.red : Theme.text2)
                    if let d = mission.deadlineDate {
                        Text(d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_BE"))))
                            .font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                }
                .frame(width: 110, alignment: .trailing)
                StatusPill(status: mission.status).frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct MissionList: View {
    let missions: [Mission]
    var showMoney = false
    var empty = "Aucune mission."
    var onOpen: (Mission) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if missions.isEmpty {
                EmptyHint(text: empty)
            } else {
                ForEach(Array(missions.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    MissionRow(mission: m, showMoney: showMoney) { onOpen(m) }
                }
            }
        }
        .card(padding: 0)
    }
}

enum Links {
    static func open(_ s: String?) {
        guard var s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
        if !s.lowercased().hasPrefix("http") { s = "https://" + s }
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}

/// Cible d'ouverture de la fiche mission.
enum MissionTarget: Identifiable, Hashable {
    case new
    case existing(String)
    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let id): return id
        }
    }
}

// MARK: - Sélecteur à pastilles (remplace le segmented control système)

struct ChipPicker<T: Hashable>: View {
    struct Option: Identifiable {
        let value: T
        let label: String
        var count: Int? = nil
        var id: String { label }
    }
    @Binding var selection: T
    let options: [Option]
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { o in
                let on = o.value == selection
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) { selection = o.value }
                } label: {
                    HStack(spacing: 6) {
                        Text(o.label).font(.system(size: 12.5, weight: on ? .semibold : .medium))
                        if let c = o.count {
                            Text("\(c)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                                .padding(.horizontal, 6).frame(height: 17)
                                .background((on ? Theme.blue : Color.white).opacity(on ? 0.25 : 0.07), in: Capsule())
                        }
                    }
                    .foregroundStyle(on ? Theme.text : Theme.muted)
                    .padding(.horizontal, 13).frame(height: 30)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.card2)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1)))
                                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                                .matchedGeometryEffect(id: "chip", in: ns)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line))
    }
}
