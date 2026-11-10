import SwiftUI

// MARK: - Outils de calendrier (semaine du lundi au dimanche)

enum AgendaCal {
    static let fr = Locale(identifier: "fr_BE")
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "fr_BE")
        return c
    }()
    static let weekdays = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

    static func day(_ d: Date) -> Date { cal.startOfDay(for: d) }

    static func weekStart(_ d: Date) -> Date {
        let start = day(d)
        let lead = (cal.component(.weekday, from: start) + 5) % 7
        return cal.date(byAdding: .day, value: -lead, to: start) ?? start
    }

    static func week(_ d: Date) -> [Date] {
        let start = weekStart(d)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    static func monthStart(_ d: Date) -> Date { cal.dateInterval(of: .month, for: d)?.start ?? day(d) }

    /// Toutes les cases du mois, complétées pour former des semaines entières.
    static func monthGrid(_ d: Date) -> [Date] {
        let first = monthStart(d)
        let lead = (cal.component(.weekday, from: first) + 5) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let weeks = (lead + count + 6) / 7
        let start = cal.date(byAdding: .day, value: -lead, to: first) ?? first
        return (0..<(weeks * 7)).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    static func time(_ d: Date?) -> String {
        guard let d else { return "–" }
        return String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
    }

    static func capital(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    static func long(_ d: Date) -> String {
        capital(d.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(fr)))
    }

    static func short(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
    }

    static func relative(_ d: Date) -> String {
        if cal.isDateInToday(d) { return "Aujourd'hui" }
        if cal.isDateInTomorrow(d) { return "Demain" }
        return long(d)
    }

    static func monthLabel(_ d: Date) -> String {
        capital(d.formatted(.dateTime.month(.wide).year().locale(fr)))
    }

    static func weekLabel(_ d: Date) -> String {
        let days = week(d)
        guard let a = days.first, let b = days.last else { return "" }
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(fr)
        return "\(a.formatted(f)) au \(b.formatted(f))"
    }

    /// Couleur du client, ou rouge si la mission est en retard.
    static func color(_ m: Mission, _ c: Client?) -> Color {
        m.isLate ? Theme.red : Color(hex: c?.color ?? "8B8D94")
    }
}

// MARK: - Page Agenda

struct AgendaView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    @AppStorage("agendaMode") private var mode = "month"
    @State private var anchor = Date()
    @State private var selected = AgendaCal.day(Date())
    @State private var editorFilter = ""
    @State private var clientFilter = ""

    private var filtered: [Mission] {
        data.missions.filter { m in
            if !clientFilter.isEmpty && m.client_id != clientFilter { return false }
            if !editorFilter.isEmpty && !data.memberIds(of: m.id).contains(editorFilter) { return false }
            return true
        }
    }

    private var byDay: [Date: [Mission]] {
        var out: [Date: [Mission]] = [:]
        for m in filtered {
            if let d = m.deadlineDate { out[AgendaCal.day(d), default: []].append(m) }
        }
        for key in Array(out.keys) {
            out[key] = (out[key] ?? []).sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
        }
        return out
    }

    private var rangeStart: Date { mode == "week" ? AgendaCal.weekStart(anchor) : AgendaCal.monthStart(anchor) }
    private var rangeEnd: Date {
        let c = AgendaCal.cal
        if mode == "week" { return c.date(byAdding: .day, value: 7, to: rangeStart) ?? rangeStart }
        return c.date(byAdding: .month, value: 1, to: rangeStart) ?? rangeStart
    }

    private var inRange: [Mission] {
        let a = rangeStart
        let b = rangeEnd
        return filtered.filter { m in
            guard let d = m.deadlineDate else { return false }
            return d >= a && d < b
        }
    }

    private var kicker: String {
        if mode == "list" {
            let n = filtered.filter { $0.deadlineDate != nil && $0.isOpen }.count
            return "\(n) deadline\(n > 1 ? "s" : "") à venir"
        }
        let list = inRange
        let late = list.filter(\.isLate).count
        var s = "\(list.count) deadline\(list.count > 1 ? "s" : "")"
        if late > 0 { s += " · \(late) en retard" }
        return s
    }

    private var editors: [Profile] { data.profiles.filter { $0.active && ($0.role == "editor" || $0.role == "admin") } }
    private var clientsShown: [Client] { data.clients.filter { c in data.missions.contains { $0.client_id == c.id } } }
    private var showEditors: Bool { app.isAdmin && editors.count > 1 }
    private var showClients: Bool { !app.isClient && clientsShown.count > 1 }

    var body: some View {
        let map = byDay
        Page {
            PageHeader(kicker: kicker, title: app.isClient ? "Calendrier" : "Agenda") {
                ChipPicker(selection: $mode, options: [
                    ChipPicker<String>.Option(value: "month", label: "Mois"),
                    ChipPicker<String>.Option(value: "week", label: "Semaine"),
                    ChipPicker<String>.Option(value: "list", label: "Liste")
                ])
            }
            if mode != "list" { navBar }
            if showEditors || showClients { filterBar }
            if mode == "week" {
                AgendaWeek(days: AgendaCal.week(anchor), map: map)
            } else if mode == "list" {
                AgendaList(missions: filtered)
            } else {
                monthBlock(map)
            }
            legend
        }
    }

    // MARK: navigation

    private var navBar: some View {
        HStack(spacing: 8) {
            AgendaNavButton(icon: "chevron.left") { shift(-1) }
            Text(mode == "week" ? AgendaCal.weekLabel(anchor) : AgendaCal.monthLabel(anchor))
                .font(.system(size: 17, weight: .semibold))
                .frame(minWidth: 170)
            AgendaNavButton(icon: "chevron.right") { shift(1) }
            Spacer()
            Button("Aujourd'hui") {
                anchor = Date()
                selected = AgendaCal.day(Date())
            }
            .buttonStyle(SecondaryButton())
        }
    }

    private func shift(_ n: Int) {
        let c = AgendaCal.cal
        if mode == "week" {
            anchor = c.date(byAdding: .day, value: 7 * n, to: anchor) ?? anchor
        } else {
            let next = c.date(byAdding: .month, value: n, to: AgendaCal.monthStart(anchor)) ?? anchor
            anchor = next
            selected = c.isDate(next, equalTo: Date(), toGranularity: .month) ? AgendaCal.day(Date()) : AgendaCal.monthStart(next)
        }
    }

    // MARK: filtres

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if showEditors {
                    AgendaFilterChip(label: "Toute l'équipe", on: editorFilter.isEmpty) { editorFilter = "" }
                    ForEach(editors) { p in
                        AgendaFilterChip(label: p.firstName, on: editorFilter == p.id, profile: p, count: load(p.id)) { editorFilter = p.id }
                    }
                }
                if showEditors && showClients {
                    Rectangle().fill(Theme.line).frame(width: 1, height: 20).padding(.horizontal, 4)
                }
                if showClients {
                    AgendaFilterChip(label: "Tous les clients", on: clientFilter.isEmpty) { clientFilter = "" }
                    ForEach(clientsShown) { c in
                        AgendaFilterChip(label: c.name, on: clientFilter == c.id, dot: Color(hex: c.color)) { clientFilter = c.id }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Nombre de missions à livrer par ce monteur sur la période affichée.
    private func load(_ uid: String) -> Int {
        if mode == "list" { return 0 }
        return inRange.filter { $0.isOpen && $0.status != "requested" && data.memberIds(of: $0.id).contains(uid) }.count
    }

    // MARK: vue mois

    private func monthBlock(_ map: [Date: [Mission]]) -> some View {
        let days = AgendaCal.monthGrid(anchor)
        let month = AgendaCal.cal.component(.month, from: AgendaCal.monthStart(anchor))
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: 7)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(AgendaCal.weekdays, id: \.self) { w in
                        Text(w.uppercased())
                            .font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                    }
                }
                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(days, id: \.self) { d in
                        AgendaDayCell(day: d,
                                      inMonth: AgendaCal.cal.component(.month, from: d) == month,
                                      missions: map[d] ?? [],
                                      selected: d == selected) { selected = d }
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))

            dayPanel(map[selected] ?? [])
        }
    }

    private func dayPanel(_ list: [Mission]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitle(text: AgendaCal.relative(selected)) {
                if app.isAdmin {
                    Button { presenter.openNew(on: selected) } label: { Label("Mission ce jour", systemImage: "plus") }
                        .buttonStyle(SecondaryButton())
                } else {
                    Muted("\(list.count) mission\(list.count > 1 ? "s" : "")")
                }
            }
            if list.isEmpty { Muted("Rien de prévu ce jour-là.").padding(.vertical, 6) }
            ForEach(list) { m in AgendaRow(mission: m) }
        }
        .card()
    }

    // MARK: légende

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(Theme.red, "En retard")
            legendItem(Theme.muted.opacity(0.5), "Terminée (estompée)")
            Muted("La couleur est celle du client.", size: 12)
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 8)
            Muted(text, size: 12)
        }
    }
}

// MARK: - Petits éléments de l'agenda

struct AgendaNavButton: View {
    let icon: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.text2)
                .frame(width: 32, height: 32)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AgendaFilterChip: View {
    let label: String
    let on: Bool
    var profile: Profile? = nil
    var dot: Color? = nil
    var count: Int = 0
    var action: () -> Void

    private var tint: Color { dot ?? Theme.blue }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let profile { AvatarView(profile: profile, size: 18) }
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label).font(.system(size: 12.5, weight: on ? .semibold : .medium)).lineLimit(1)
                if count > 0 {
                    Text("\(count)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 6).frame(height: 17)
                        .background(Color.white.opacity(0.1), in: Capsule())
                }
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

/// Barre de couleur à gauche d'une mission.
struct AgendaBar: View {
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3).padding(.vertical, 4).padding(.leading, 3)
    }
}

/// Une case de jour dans la vue mois.
struct AgendaDayCell: View {
    let day: Date
    let inMonth: Bool
    let missions: [Mission]
    let selected: Bool
    var onSelect: () -> Void

    var body: some View {
        let today = AgendaCal.cal.isDateInToday(day)
        let extra = missions.count - 3
        VStack(alignment: .leading, spacing: 4) {
            Text("\(AgendaCal.cal.component(.day, from: day))")
                .font(.system(size: 12.5, weight: today ? .bold : .medium)).monospacedDigit()
                .foregroundStyle(today ? Color(hex: "06101F") : Theme.text2)
                .frame(width: 24, height: 24)
                .background(today ? Theme.blue : Color.clear, in: Circle())
            ForEach(Array(missions.prefix(3))) { m in AgendaChip(mission: m) }
            if extra > 0 { Muted("+ \(extra) autre\(extra > 1 ? "s" : "")", size: 11).padding(.leading, 4) }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .opacity(inMonth ? 1 : 0.4)
        .background(selected ? Theme.blue.opacity(0.08) : Color.clear)
        .overlay(Rectangle().stroke(selected ? Theme.blue.opacity(0.55) : Theme.line, lineWidth: selected ? 1.5 : 0.5))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

/// Mission compacte dans une case du mois.
struct AgendaChip: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let mission: Mission

    var body: some View {
        let color = AgendaCal.color(mission, data.client(mission.client_id))
        let done = !mission.isOpen
        let request = mission.status == "requested"
        Button { presenter.open(.existing(mission.id)) } label: {
            HStack(spacing: 5) {
                Text(AgendaCal.time(mission.deadlineDate)).font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(Theme.text2.opacity(0.8))
                Text((done ? "✓ " : "") + mission.title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 9).padding(.trailing, 5).frame(height: 21)
            .background(color.opacity(request ? 0.05 : 0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(color.opacity(request ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .overlay(alignment: .leading) { AgendaBar(color: color) }
            .opacity(done ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mission.title)
    }
}

/// Ligne de mission (jour sélectionné et vue liste).
struct AgendaRow: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let mission: Mission
    var showDate = false

    var body: some View {
        let client = data.client(mission.client_id)
        let color = AgendaCal.color(mission, client)
        Button { presenter.open(.existing(mission.id)) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AgendaCal.time(mission.deadlineDate)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.text2)
                    if showDate, let d = mission.deadlineDate {
                        Text(AgendaCal.short(d)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                .frame(width: showDate ? 92 : 44, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mission.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                    Text(subtitle(client)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                if !app.isClient { MemberStack(profiles: data.memberProfiles(of: mission.id), size: 20) }
                StatusPill(status: mission.status)
            }
            .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 10)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(alignment: .leading) { AgendaBar(color: color) }
            .opacity(mission.isOpen ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func subtitle(_ client: Client?) -> String {
        var parts: [String] = []
        if let name = client?.name { parts.append(name) }
        let people = data.memberProfiles(of: mission.id).map(\.firstName)
        if !app.isClient && !people.isEmpty { parts.append(people.joined(separator: " + ")) }
        if mission.isLate { parts.append("En retard") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Vue semaine

struct AgendaWeek: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var presenter: Presenter
    let days: [Date]
    let map: [Date: [Mission]]

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(days, id: \.self) { d in column(d) }
        }
    }

    private func column(_ d: Date) -> some View {
        let list = map[d] ?? []
        let today = AgendaCal.cal.isDateInToday(d)
        let weekday = d.formatted(.dateTime.weekday(.abbreviated).locale(AgendaCal.fr)).uppercased()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(weekday).font(.system(size: 10.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
                Text("\(AgendaCal.cal.component(.day, from: d))").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(today ? Theme.blue : Theme.text)
                Spacer(minLength: 0)
                if app.isAdmin {
                    Button { presenter.openNew(on: d) } label: {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                            .frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Nouvelle mission ce jour")
                }
            }
            Rectangle().fill(Theme.line).frame(height: 1)
            if list.isEmpty {
                Text("Libre").font(.system(size: 12)).foregroundStyle(Theme.muted.opacity(0.5)).padding(.vertical, 4)
            }
            ForEach(list) { m in AgendaWeekCard(mission: m) }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(today ? Theme.blue.opacity(0.5) : Theme.line))
    }
}

struct AgendaWeekCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let mission: Mission

    var body: some View {
        let client = data.client(mission.client_id)
        let color = AgendaCal.color(mission, client)
        Button { presenter.open(.existing(mission.id)) } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text((client?.name ?? "Sans client").uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(0.3)
                    .foregroundStyle(color.mix(white: 0.4)).lineLimit(1)
                Text(mission.title).font(.system(size: 12.5, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(AgendaCal.time(mission.deadlineDate)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                    Spacer(minLength: 0)
                    if !app.isClient { MemberStack(profiles: data.memberProfiles(of: mission.id), size: 18) }
                }
                StatusPill(status: mission.status)
            }
            .padding(.leading, 11).padding(.trailing, 8).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) { AgendaBar(color: color) }
            .opacity(mission.isOpen ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vue liste

struct AgendaList: View {
    let missions: [Mission]

    private struct Bucket: Identifiable {
        let id: String
        let late: Bool
        let dates: Bool
        let items: [Mission]
    }

    private var buckets: [Bucket] {
        let cal = AgendaCal.cal
        let today = AgendaCal.day(Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let after = cal.date(byAdding: .day, value: 2, to: today) ?? today
        let weekEnd = cal.date(byAdding: .day, value: 7, to: AgendaCal.weekStart(today)) ?? today
        let nextWeekEnd = cal.date(byAdding: .day, value: 7, to: weekEnd) ?? weekEnd
        let dated = missions.filter { $0.deadlineDate != nil }
            .sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
        let overdue = dated.filter(\.isLate)
        let rest = dated.filter { m in !m.isLate && (m.deadlineDate ?? .distantPast) >= today }

        func between(_ a: Date, _ b: Date) -> [Mission] {
            rest.filter { m in
                guard let d = m.deadlineDate else { return false }
                return d >= a && d < b
            }
        }

        var out: [Bucket] = []
        func add(_ title: String, _ items: [Mission], late: Bool = false, dates: Bool = true) {
            if !items.isEmpty { out.append(Bucket(id: title, late: late, dates: dates, items: items)) }
        }
        let laterStart = max(after, nextWeekEnd)
        add("En retard", overdue, late: true)
        add("Aujourd'hui", between(today, tomorrow), dates: false)
        add("Demain", between(tomorrow, after), dates: false)
        add("Cette semaine", between(after, weekEnd))
        add("Semaine prochaine", between(max(after, weekEnd), nextWeekEnd))
        add("Plus tard", rest.filter { ($0.deadlineDate ?? .distantPast) >= laterStart })
        add("Sans deadline", missions.filter { $0.deadlineDate == nil && $0.isOpen }, dates: false)
        return out
    }

    var body: some View {
        let list = buckets
        VStack(alignment: .leading, spacing: 12) {
            if list.isEmpty { EmptyHint(text: "Aucune deadline à venir.").card() }
            ForEach(list) { b in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(b.id).font(.system(size: 15, weight: .semibold)).foregroundStyle(b.late ? Theme.red : Theme.text)
                        Spacer()
                        Muted("\(b.items.count)")
                    }
                    ForEach(b.items) { m in AgendaRow(mission: m, showDate: b.dates) }
                }
                .card()
            }
        }
    }
}
