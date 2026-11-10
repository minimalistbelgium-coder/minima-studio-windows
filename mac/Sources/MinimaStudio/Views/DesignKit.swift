import SwiftUI
import AppKit

// MARK: - Mise en page qui s'adapte à la largeur

// Règle de l'app : aucune disposition ne dépend de la taille du contenu (pas de ViewThatFits).
// La largeur utile est calculée à partir de la largeur de la fenêtre, puis transmise
// de conteneur en conteneur (page, colonnes, cartes, fiche). Les seuils sont donc stables :
// pas de bascule pendant un survol, ni quand la barre de défilement apparaît.

private struct LayoutWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 1000 }

extension EnvironmentValues {
    /// Largeur utile du conteneur courant, déduite de la largeur de la fenêtre.
    var layoutWidth: CGFloat {
        get { self[LayoutWidthKey.self] }
        set { self[LayoutWidthKey.self] = newValue }
    }
}

extension View {
    /// Annonce au contenu la largeur dont il dispose.
    func layoutWidth(_ width: CGFloat) -> some View { environment(\.layoutWidth, Swift.max(0, width)) }
}

/// Donne la largeur utile du conteneur à son contenu.
struct WidthReader<Content: View>: View {
    @Environment(\.layoutWidth) private var width
    @ViewBuilder var content: (CGFloat) -> Content
    var body: some View { content(width) }
}

/// Deux colonnes côte à côte quand il y a la place, l'une sous l'autre sinon.
/// Les deux dispositions gardent les mêmes vues (l'état des cartes est conservé).
struct Columns<Left: View, Right: View>: View {
    var minLeft: CGFloat = 480
    var rightWidth: CGFloat = 320
    var spacing: CGFloat = 16
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right
    @Environment(\.layoutWidth) private var width

    var body: some View {
        let wide = width >= minLeft + rightWidth + spacing
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: spacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
        layout {
            VStack(alignment: .leading, spacing: spacing) { left() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutWidth(wide ? width - rightWidth - spacing : width)
            VStack(alignment: .leading, spacing: spacing) { right() }
                .frame(maxWidth: wide ? rightWidth : .infinity, alignment: .leading)
                .layoutWidth(wide ? rightWidth : width)
        }
    }
}

/// Éléments placés à la suite, avec retour à la ligne quand la largeur manque.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: s.width, height: s.height))
            x += s.width + spacing
            rowHeight = Swift.max(rowHeight, s.height)
            maxX = Swift.max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowHeight), frames)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(width: width.isFinite ? width : .greatestFiniteMagnitude, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(width: bounds.width, subviews: subviews).frames
        for (i, v) in subviews.enumerated() {
            let f = frames[i]
            v.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: f.width, height: f.height))
        }
    }
}

/// Grille de cartes qui passe de 4 à 2 à 1 colonne selon la largeur.
/// Toutes les cartes ont exactement la même largeur et la même hauteur (celle de la plus haute),
/// alignées en haut.
struct StatGrid<Content: View>: View {
    var min: CGFloat = 220
    @ViewBuilder var content: () -> Content
    var body: some View {
        // Pas de GlassEffectContainer (GlassGroup) ici : il dessine le verre par-dessus le contenu
        // des cartes (chiffres floutés). Chaque carte garde son propre verre en fond.
        EqualGrid(minWidth: min, spacing: 14) { content() }
    }
}

/// Mise en page en colonnes égales : chaque case reçoit la même taille.
struct EqualGrid: Layout {
    var minWidth: CGFloat = 200
    var spacing: CGFloat = 14

    private struct Metrics { let cols: Int; let rows: Int; let cell: CGSize; let width: CGFloat }

    private func metrics(_ proposal: ProposedViewSize, _ subviews: Subviews) -> Metrics {
        let n = subviews.count
        guard n > 0 else { return Metrics(cols: 1, rows: 0, cell: .zero, width: 0) }
        var width = proposal.width ?? .infinity
        if !width.isFinite || width <= 0 { width = CGFloat(n) * minWidth + CGFloat(n - 1) * spacing }
        let fit = Swift.max(1, Int((width + spacing) / (minWidth + spacing)))
        let half = (n + 1) / 2
        let cols = fit >= n ? n : (fit >= half ? half : fit)
        let rows = Int((Double(n) / Double(cols)).rounded(.up))
        let cellW = Swift.max(0, (width - CGFloat(cols - 1) * spacing) / CGFloat(cols))
        let cellH = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellW, height: nil)).height }.max() ?? 0
        return Metrics(cols: cols, rows: rows, cell: CGSize(width: cellW, height: cellH), width: width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = metrics(proposal, subviews)
        guard m.rows > 0 else { return .zero }
        return CGSize(width: m.width, height: CGFloat(m.rows) * m.cell.height + CGFloat(m.rows - 1) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = metrics(ProposedViewSize(width: bounds.width, height: nil), subviews)
        for (i, v) in subviews.enumerated() {
            let c = i % m.cols, r = i / m.cols
            v.place(at: CGPoint(x: bounds.minX + CGFloat(c) * (m.cell.width + spacing),
                                y: bounds.minY + CGFloat(r) * (m.cell.height + spacing)),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: m.cell.width, height: m.cell.height))
        }
    }
}

/// Titre de carte.
struct CardTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .center) {
            Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                .lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            trailing().layoutPriority(1)
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

/// Barre de progression fine.
struct ThinBar: View {
    var value: Double
    var color: Color = Theme.green
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.07))
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
                    Muted(rangeLabel(days)).lineLimit(1).fixedSize()
                    navButton("chevron.left") { withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { weekOffset -= 1 } }
                    if weekOffset != 0 {
                        Button("Aujourd'hui") { weekOffset = 0 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.blue)
                            .lineLimit(1).fixedSize()
                    }
                    navButton("chevron.right") { withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { weekOffset += 1 } }
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
                Text(dayLabel(d)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(today ? Theme.blue : Theme.text).lineLimit(1)
                if today { Circle().fill(Theme.blue).frame(width: 5, height: 5) }
            }
            if list.isEmpty {
                Muted("Rien de prévu", size: 12).lineLimit(1).padding(.vertical, 8)
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
                Text(m.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if showPeople, !people.isEmpty { MemberStack(profiles: people, size: 18) }
                    Text(chipFoot(m)).font(.system(size: 11.5)).foregroundStyle(m.isLate ? Theme.red : Theme.muted).lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(color.opacity(0.16), lineWidth: 0.5))
            .contentShape(Rectangle())
            .hoverRow(radius: 11)
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
                .frame(width: 26, height: 26).background(Theme.ink.opacity(0.07), in: Circle())
                .contentShape(Circle())
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
                let color = now ? Color(hex: MissionStatus.color(mission.status)) : (done ? Theme.green : Theme.ink.opacity(0.08))
                VStack(alignment: .leading, spacing: 8) {
                    Capsule().fill(color).frame(height: 4)
                    Text(now ? MissionStatus.label(mission.status) : MissionStatus.label(s))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(now ? color.mix(white: 0.35) : (done ? Theme.text : Theme.muted))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
