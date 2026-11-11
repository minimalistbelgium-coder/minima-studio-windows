import SwiftUI

// MARK: - Aujourd'hui (tableau de bord admin)

struct TodayView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        let open = data.missions.filter(\.isOpen)
        let month = data.missions(inMonthOf: Date())
        let prevMonth = data.missions(inMonthOf: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date())
        let billed = month.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let billedPrev = prevMonth.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let payout = month.map { data.editorPayout($0) }.reduce(0, +)
        let margin = billed - payout
        let revisions = open.filter { $0.status == "revisions" }.count
        let late = open.filter(\.isLate).count
        let monthName = Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "fr_BE")))

        Page {
            PageHeader(kicker: DateFmt.todayLabel(), title: "Bonjour \(app.profile?.firstName ?? "")") {
                Button { presenter.open(.new) } label: { Label("Nouvelle mission", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }

            StatGrid {
                StatCard(label: "Facturé aux clients · \(monthName)", value: Money.eur(billed),
                         foot: trend(billed, billedPrev), footColor: billed >= billedPrev ? Theme.green : Theme.amber)
                StatCard(label: "À payer aux monteurs", value: Money.eur(payout.rounded()),
                         foot: "\(month.count) mission\(month.count > 1 ? "s" : "") ce mois")
                StatCard(label: "Ta marge", value: Money.eur(margin.rounded()),
                         foot: billed > 0 ? "\(Int((margin / billed * 100).rounded())) % du facturé" : "Renseigne les prix clients",
                         footColor: margin >= 0 ? Theme.muted : Theme.red)
                StatCard(label: "Missions en cours", value: "\(open.count)",
                         foot: late > 0 ? "\(late) en retard" : (revisions > 0 ? "\(revisions) en retouches" : "Tout est à l'heure"),
                         footColor: late > 0 ? Theme.red : (revisions > 0 ? Theme.amber : Theme.green))
            }

            Columns(minLeft: 460, rightWidth: 320) {
                WeekAgenda(missions: data.missions)
            } right: {
                LiveNowCard()
                ClaudeMonthCard()
                ToDoCard()
            }

            DailyHoursCard(people: data.profiles.filter { $0.active && ($0.role == "editor" || $0.role == "admin") },
                           title: "Heures par jour")

            ActiveMissionsTable(missions: open)
        }
    }

    private func trend(_ a: Double, _ b: Double) -> String? {
        guard b > 0 else { return nil }
        let p = Int(((a - b) / b * 100).rounded())
        return "\(p >= 0 ? "+" : "")\(p) % vs le mois dernier"
    }
}

/// L'équipe en direct : qui monte, depuis quand.
struct LiveNowCard: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        let team = data.team.filter { $0.role == "editor" || $0.role == "admin" }
        let live = data.liveSessions
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(text: "En direct") {
                Tag(text: live.isEmpty ? "Personne" : "\(live.count) actif\(live.count > 1 ? "s" : "")",
                    color: live.isEmpty ? Theme.muted : Theme.green, dot: true)
            }
            if team.isEmpty { Muted("Ajoute ton équipe dans l'onglet Équipe.") }
            ForEach(team) { p in
                let s = live.first { $0.user_id == p.id }
                let today = todaySeconds(p.id)
                Button {
                    if let s { presenter.open(.existing(s.mission_id)) }
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(profile: p, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.firstName).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            Muted(subtitle(p, live: s), size: 12).lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(s != nil ? TimeFmt.hm(Double(s?.duration_sec ?? 0)) : TimeFmt.hm(today))
                            .font(.system(size: 13, weight: s != nil ? .semibold : .regular, design: .monospaced))
                            .lineLimit(1).fixedSize()
                            .foregroundStyle(s != nil ? Theme.green : Theme.muted)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .hoverRow(radius: 10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, -8).padding(.vertical, -5)
            }
        }
        .card()
    }

    private func subtitle(_ p: Profile, live s: WorkSession?) -> String {
        if let s, let m = data.mission(s.mission_id) {
            return "\(m.title) · \(s.source == "manual" ? "chrono manuel" : "dans Premiere")"
        }
        if let last = data.sessions.first(where: { $0.user_id == p.id }), let e = last.ended_at.flatMap(DateFmt.parse) {
            if Calendar.current.isDateInToday(e) {
                return "Dernière session à " + e.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_BE")))
            }
            return "Dernière session " + DateFmt.relative(e).lowercased()
        }
        return "Pas encore actif"
    }

    private func todaySeconds(_ uid: String) -> Double {
        data.sessions.filter { s in
            s.user_id == uid && (DateFmt.parse(s.started_at).map { Calendar.current.isDateInToday($0) } ?? false)
        }.map { Double($0.duration_sec ?? 0) }.reduce(0, +)
    }
}

/// Ce qui demande une action de l'admin.
struct ToDoCard: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter

    private struct Item: Identifiable { let id: String; let color: Color; let text: String; let mission: String }

    var body: some View {
        let items = todo()
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("À traiter")
            if items.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    Muted("Rien d'urgent pour l'instant.")
                }
            }
            ForEach(items.prefix(6)) { it in
                Button { presenter.open(.existing(it.mission)) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(it.color).frame(width: 8, height: 8).padding(.top, 5)
                        Text(it.text).font(.system(size: 13)).foregroundStyle(Theme.text2)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    private func todo() -> [Item] {
        var out: [Item] = []
        let open = data.missions.filter(\.isOpen)
        for m in open where m.status == "requested" {
            out.append(Item(id: "req\(m.id)", color: Theme.pink, text: "Demande client : \(m.title). Fixe le budget puis passe-la en Assignée.", mission: m.id))
        }
        for m in open where m.isLate {
            out.append(Item(id: "late\(m.id)", color: Theme.red, text: "\(m.title) est en retard", mission: m.id))
        }
        for m in open where !m.isLate {
            if let d = m.deadlineDate, Calendar.current.isDateInToday(d), ["assigned", "editing", "revisions"].contains(m.status) {
                out.append(Item(id: "today\(m.id)", color: Theme.red, text: "\(m.title) à livrer aujourd'hui \(d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_BE"))))", mission: m.id))
            }
        }
        for m in open where m.status == "v1_delivered" || m.status == "fix_delivered" {
            out.append(Item(id: "rev\(m.id)", color: Theme.blue, text: "\(m.title) : \(MissionStatus.label(m.status).lowercased()), à regarder", mission: m.id))
        }
        for m in open where m.rushes_url == nil && ["assigned", "editing"].contains(m.status) {
            out.append(Item(id: "rush\(m.id)", color: Theme.amber, text: "Rushes de \(m.title) pas encore partagés", mission: m.id))
        }
        for m in open where data.memberIds(of: m.id).isEmpty && m.status != "requested" {
            out.append(Item(id: "nobody\(m.id)", color: Theme.amber, text: "Personne n'est assigné à \(m.title)", mission: m.id))
        }
        return out
    }
}

/// Tableau des missions actives (comme dans la maquette).
struct ActiveMissionsTable: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let missions: [Mission]
    var title = "Missions actives"
    var emptyText = "Aucune mission en cours."

    @Environment(\.layoutWidth) private var width

    /// Tableau complet à partir de cette largeur, lignes compactes en dessous.
    /// Une seule décision pour l'en-tête et toutes les lignes (elles restent alignées).
    private var wide: Bool { width >= 800 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: title) { Muted("\(missions.count)") }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            header
            if missions.isEmpty { EmptyHint(text: emptyText, icon: "film.stack") }
            ForEach(missions) { m in
                Rectangle().fill(Theme.line).frame(height: 1)
                row(m)
            }
        }
        .padding(.bottom, 6)
        .glassCard()
    }

    private var header: some View {
        Group {
            if wide {
                HStack(spacing: 12) {
                    Muted("Mission", size: 12).frame(maxWidth: .infinity, alignment: .leading)
                    Muted("Monteur", size: 12).frame(width: 130, alignment: .leading)
                    Muted("Étape", size: 12).frame(width: 132, alignment: .leading)
                    Muted("Deadline", size: 12).frame(width: 110, alignment: .leading)
                    Muted("Temps", size: 12).frame(width: 70, alignment: .trailing)
                    Muted("Budget", size: 12).frame(width: 80, alignment: .trailing)
                }
            } else {
                HStack {
                    Muted("Mission", size: 12)
                    Spacer()
                    Muted("Étape · Budget", size: 12)
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    private func row(_ m: Mission) -> some View {
        let c = data.client(m.client_id)
        let people = data.memberProfiles(of: m.id)
        let names = people.map(\.firstName).joined(separator: " + ")
        return Button { presenter.open(.existing(m.id)) } label: {
            Group {
                if wide {
                    HStack(spacing: 12) {
                        titleCell(m, c).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 6) {
                            MemberStack(profiles: people, size: 20)
                            Text(names.isEmpty ? "–" : names).font(.system(size: 13)).foregroundStyle(Theme.text2).lineLimit(1)
                        }
                        .frame(width: 130, alignment: .leading)
                        StatusPill(status: m.status, flexible: true).frame(width: 132, alignment: .leading)
                        Text(deadline(m)).font(.system(size: 13)).foregroundStyle(m.isLate ? Theme.red : Theme.text2)
                            .lineLimit(1).minimumScaleFactor(0.85)
                            .frame(width: 110, alignment: .leading)
                        Text(TimeFmt.hm(data.seconds(mission: m.id))).font(.system(size: 13, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 70, alignment: .trailing)
                        Text(m.editor_budget.map(Money.eur) ?? "–").font(.system(size: 13, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 80, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            titleCell(m, c)
                            Text("\(names.isEmpty ? "Personne" : names) · \(deadline(m))").font(.system(size: 12))
                                .foregroundStyle(m.isLate ? Theme.red : Theme.muted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 3) {
                            StatusPill(status: m.status)
                            Text(m.editor_budget.map(Money.eur) ?? "–").font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .contentShape(Rectangle())
            .hoverRow()
        }
        .buttonStyle(.plain)
    }

    private func titleCell(_ m: Mission, _ c: Client?) -> some View {
        HStack(spacing: 10) {
            ClientDot(color: c?.color)
            Text(c.map { "\($0.name) · \(m.title)" } ?? m.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
            if !data.liveSession(for: m.id).isEmpty {
                Circle().fill(Theme.green).frame(width: 6, height: 6).help("Quelqu'un monte en ce moment")
            }
        }
    }

    private func deadline(_ m: Mission) -> String {
        guard let d = m.deadlineDate else { return "Sans deadline" }
        let cal = Calendar.current
        let h = d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_BE")))
        if cal.isDateInToday(d) { return "Auj. \(h)" }
        if cal.isDateInTomorrow(d) { return "Demain \(h)" }
        let s = d.formatted(.dateTime.weekday(.abbreviated).day().locale(Locale(identifier: "fr_BE")))
        return (s.prefix(1).uppercased() + s.dropFirst()) + " " + h
    }
}

// MARK: - Missions

struct MissionsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    @State private var filter = 0
    @State private var clientFilter = ""
    @State private var search = ""

    var body: some View {
        let byStatus = statusFiltered
        let list = clientAndSearch(byStatus)
        Page {
            PageHeader(kicker: "\(data.missions.filter(\.isOpen).count) en cours", title: "Missions") {
                Button { presenter.open(.new) } label: { Label("Nouvelle mission", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }

            WidthReader { w in
                // Filtres et recherche côte à côte, ou l'un sous l'autre quand la page est étroite.
                let stacked = w < 640
                let layout = stacked
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    statusPicker.frame(maxWidth: .infinity, alignment: .leading)
                    searchField.frame(maxWidth: stacked ? .infinity : 240)
                }
            }
            ClientFilterBar(selection: $clientFilter, missions: byStatus)

            ActiveMissionsTable(missions: list, title: filter == 0 ? "En cours" : (filter == 1 ? "Terminées" : "Toutes les missions"),
                                emptyText: (search.isEmpty && clientFilter.isEmpty) ? "Aucune mission ici pour le moment." : "Aucune mission ne correspond à ta recherche.")
        }
    }

    private var statusPicker: some View {
        ChipPicker(selection: $filter, options: [
            .init(value: 0, label: "En cours", count: data.missions.filter(\.isOpen).count),
            .init(value: 1, label: "Terminées", count: data.missions.filter { !$0.isOpen }.count),
            .init(value: 2, label: "Toutes", count: data.missions.count),
        ])
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Theme.muted)
            TextField("Rechercher une mission", text: $search).textFieldStyle(.plain).font(.system(size: 13.5))
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background { GlassBackground(shape: Capsule(), fill: Theme.card.opacity(0.6), shadow: false) }
    }

    private var statusFiltered: [Mission] {
        var l = data.missions
        switch filter {
        case 0: l = l.filter(\.isOpen)
        case 1: l = l.filter { !$0.isOpen }.reversed()
        default: break
        }
        return l
    }

    private func clientAndSearch(_ base: [Mission]) -> [Mission] {
        var l = base
        if !clientFilter.isEmpty { l = l.filter { $0.client_id == clientFilter } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            l = l.filter { m in
                m.title.lowercased().contains(q) || (data.client(m.client_id)?.name.lowercased().contains(q) ?? false)
            }
        }
        return l
    }
}

// MARK: - Clients

struct ClientsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @State private var name = ""
    @State private var toDelete: Client?

    var body: some View {
        Page {
            PageHeader(kicker: "\(data.clients.count) client\(data.clients.count > 1 ? "s" : "")", title: "Clients")

            HStack(spacing: 10) {
                TextField("Nom du client", text: $name).input().onSubmit(add)
                Button("Ajouter", action: add).buttonStyle(PrimaryButton())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .card(padding: 14)

            VStack(spacing: 0) {
                if data.clients.isEmpty { EmptyHint(text: "Aucun client. Tu peux aussi en créer un directement depuis une mission.", icon: "person.2") }
                ForEach(Array(data.clients.enumerated()), id: \.element.id) { i, c in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    let missions = data.missions.filter { $0.client_id == c.id }
                    let price = missions.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
                    HStack(spacing: 12) {
                        ClientDot(color: c.color, size: 10)
                        Text(c.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(missions.count) mission\(missions.count > 1 ? "s" : "")").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            .lineLimit(1).fixedSize()
                        Text(Money.eur(price)).font(.system(size: 13)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 90, alignment: .trailing)
                        Button { toDelete = c } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(Theme.muted)
                            .help(missions.isEmpty ? "Supprimer" : "Impossible : ce client a des missions")
                            .disabled(!missions.isEmpty)
                            .opacity(missions.isEmpty ? 1 : 0.3)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .hoverRow()
                }
            }
            .card(padding: 0)
        }
        .confirmationDialog("Supprimer ce client ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Supprimer", role: .destructive) {
                if let c = toDelete {
                    Task { @MainActor in
                        do { try await data.deleteClient(c) } catch { app.showToast("Erreur : \(error.localizedDescription)") }
                    }
                }
            }
        } message: {
            Text("Cette action est définitive.")
        }
    }

    private func add() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        Task { @MainActor in
            do { try await data.createClient(name: n); name = ""; app.showToast("Client ajouté") }
            catch { app.showToast("Erreur : \(error.localizedDescription)") }
        }
    }
}

