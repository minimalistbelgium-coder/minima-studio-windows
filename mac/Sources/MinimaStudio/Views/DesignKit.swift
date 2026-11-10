import SwiftUI
import AppKit

// MARK: - Mise en page qui s'adapte à la largeur

/// Deux colonnes côte à côte quand il y a la place, l'une sous l'autre sinon.
struct Columns<Left: View, Right: View>: View {
    var minLeft: CGFloat = 480
    var rightWidth: CGFloat = 320
    var spacing: CGFloat = 16
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                VStack(alignment: .leading, spacing: spacing) { left() }
                    .frame(minWidth: minLeft, maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: spacing) { right() }
                    .frame(width: rightWidth)
            }
            VStack(alignment: .leading, spacing: spacing) {
                left()
                right()
            }
        }
    }
}

/// Grille de cartes qui passe de 4 à 2 à 1 colonne selon la largeur.
struct StatGrid<Content: View>: View {
    var min: CGFloat = 200
    @ViewBuilder var content: () -> Content
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            content()
        }
    }
}

/// Titre de carte.
struct CardTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center) {
            Text(text).font(.system(size: 15, weight: .semibold))
            Spacer(minLength: 8)
            trailing()
        }
    }
}

extension CardTitle where Trailing == EmptyView {
    init(_ text: String) { self.init(text: text, trailing: { EmptyView() }) }
}

struct Muted: View {
    let text: String
    var size: CGFloat = 12.5
    init(_ text: String, size: CGFloat = 12.5) { self.text = text; self.size = size }
    var body: some View { Text(text).font(.system(size: size)).foregroundStyle(Theme.muted) }
}

/// Pastille arrondie colorée (fond teinté, texte clair).
struct Tag: View {
    let text: String
    let color: Color
    var dot = false
    var body: some View {
        HStack(spacing: 6) {
            if dot { Circle().fill(color).frame(width: 7, height: 7) }
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(color.mix(white: 0.45))
        .padding(.horizontal, 9).padding(.vertical, 3.5)
        .background(color.opacity(0.16), in: Capsule())
    }
}

extension Color {
    /// Éclaircit une couleur pour un texte lisible sur fond teinté.
    func mix(white amount: Double) -> Color {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let r = ns.redComponent + (1 - ns.redComponent) * amount
        let g = ns.greenComponent + (1 - ns.greenComponent) * amount
        let b = ns.blueComponent + (1 - ns.blueComponent) * amount
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Barre de progression fine.
struct ThinBar: View {
    var value: Double
    var color: Color = Theme.green
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule().fill(color).frame(width: max(0, min(1, value)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Filtre client

struct ClientFilterBar: View {
    @EnvironmentObject var data: DataStore
    @Binding var selection: String
    let missions: [Mission]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(id: "", name: "Tous les clients", color: nil, count: missions.count)
                ForEach(data.clients.filter { c in missions.contains { $0.client_id == c.id } }) { c in
                    chip(id: c.id, name: c.name, color: c.color, count: missions.filter { $0.client_id == c.id }.count)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(id: String, name: String, color: String?, count: Int) -> some View {
        let on = selection == id
        let tint = color.map { Color(hex: $0) } ?? Theme.blue
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selection = id }
        } label: {
            HStack(spacing: 7) {
                if let color { Circle().fill(Color(hex: color)).frame(width: 8, height: 8) }
                else { Image(systemName: "square.grid.2x2").font(.system(size: 10.5, weight: .semibold)) }
                Text(name).font(.system(size: 12.5, weight: on ? .semibold : .medium)).lineLimit(1)
                Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(on ? Theme.text : Theme.muted)
            }
            .foregroundStyle(on ? Theme.text : Theme.text2)
            .padding(.horizontal, 12).frame(height: 32)
            .background(on ? tint.opacity(0.18) : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(on ? tint.opacity(0.55) : Theme.line))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Agenda de la semaine

struct WeekAgenda: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let missions: [Mission]
    var showPeople = true
    @State private var weekOffset = 0

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "fr_BE")
        return c
    }

    private var weekStart: Date {
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return cal.date(byAdding: .day, value: 7 * weekOffset, to: start) ?? start
    }

    var body: some View {
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let weekend = days.suffix(2).filter { d in missions.contains { $0.deadlineDate.map { cal.isDate($0, inSameDayAs: d) } ?? false } }
        let shown = Array(days.prefix(5)) + weekend
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(text: weekOffset == 0 ? "Cette semaine" : (weekOffset == 1 ? "Semaine prochaine" : "Semaine")) {
                HStack(spacing: 8) {
                    Muted(rangeLabel(days))
                    navButton("chevron.left") { weekOffset -= 1 }
                    if weekOffset != 0 {
                        Button("Aujourd'hui") { weekOffset = 0 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.blue)
                    }
                    navButton("chevron.right") { weekOffset += 1 }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10, alignment: .top)], alignment: .leading, spacing: 14) {
                ForEach(shown, id: \.self) { d in
                    dayColumn(d)
                }
            }
        }
        .card()
    }

    private func dayColumn(_ d: Date) -> some View {
        let list = missions.filter { $0.deadlineDate.map { cal.isDate($0, inSameDayAs: d) } ?? false }
            .sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
        let today = cal.isDateInToday(d)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(dayLabel(d)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(today ? Theme.blue : Theme.text)
                if today { Circle().fill(Theme.blue).frame(width: 5, height: 5) }
            }
            if list.isEmpty {
                Muted("Rien de prévu", size: 12).padding(.vertical, 8)
            }
            ForEach(list) { m in chip(m) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func chip(_ m: Mission) -> some View {
        let c = data.client(m.client_id)
        let color = Color(hex: c?.color ?? "8B8D94")
        let people = data.memberProfiles(of: m.id)
        return Button { presenter.open(.existing(m.id)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Tag(text: c?.name ?? "Sans client", color: color)
                Text(m.title).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if showPeople, !people.isEmpty { MemberStack(profiles: people, size: 18) }
                    Text(chipFoot(m)).font(.system(size: 11.5)).foregroundStyle(m.isLate ? Theme.red : Theme.muted).lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func chipFoot(_ m: Mission) -> String {
        if m.isLate { return "En retard" }
        if m.status == "assigned" && m.rushes_url == nil { return "Rushes à ajouter" }
        if m.status == "revisions" { return "Retouches" }
        if ["v1_delivered", "fix_delivered", "validated", "paid"].contains(m.status) { return MissionStatus.label(m.status) }
        guard let d = m.deadlineDate else { return "" }
        return "Livraison " + d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_BE")))
    }

    private func dayLabel(_ d: Date) -> String {
        let s = d.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private func rangeLabel(_ days: [Date]) -> String {
        guard let a = days.first, let b = days.last else { return "" }
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE"))
        return "\(a.formatted(f)) au \(b.formatted(f))"
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10.5, weight: .bold)).foregroundStyle(Theme.text2)
                .frame(width: 26, height: 26).background(Theme.card2, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Étapes de la mission

struct StepProgress: View {
    let mission: Mission
    let notes: [String: String]

    static let steps = ["assigned", "editing", "v1_delivered", "revisions", "validated", "paid"]

    var body: some View {
        let current = Self.index(of: mission.status)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { i, s in
                let done = i < current
                let now = i == current
                let color = now ? Color(hex: MissionStatus.color(mission.status)) : (done ? Theme.green : Color.white.opacity(0.08))
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(color).frame(height: 4)
                    Text(now ? MissionStatus.label(mission.status) : MissionStatus.label(s))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(now ? color.mix(white: 0.35) : (done ? Theme.text : Theme.muted))
                    Muted(notes[s] ?? (done || now ? "" : "En attente"), size: 11.5).lineLimit(1)
                }
            }
        }
    }

    static func index(of status: String) -> Int {
        if status == "fix_delivered" { return 3 }
        return steps.firstIndex(of: status) ?? 0
    }
}

// MARK: - Fenêtre déplaçable à la souris

/// Fond qui permet de déplacer la fenêtre en cliquant-glissant n'importe où dessus.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
