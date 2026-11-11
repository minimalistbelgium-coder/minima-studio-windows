import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers
import Supabase

// MARK: - Monteur : tableau de bord

struct MyDashboardView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        let open = data.missions.filter(\.isOpen)
        let month = data.missions(inMonthOf: Date())
        let earned = month.map { data.myShare(of: $0).amount }.reduce(0, +)
        let validated = month.filter { ["validated", "paid"].contains($0.status) }.map { data.myShare(of: $0).amount }.reduce(0, +)
        let secs = monthSeconds()
        let toCome = open.map { data.myShare(of: $0).amount }.reduce(0, +)

        Page {
            PageHeader(kicker: DateFmt.todayLabel(), title: "Salut \(app.profile?.firstName ?? "")") {
                if let n = data.notifications.first(where: { !$0.isRead }) {
                    Button {
                        Task { @MainActor in await data.markRead(n) }
                        if let id = n.mission_id { presenter.open(.existing(id)) }
                    } label: {
                        Tag(text: n.title, color: Theme.blue, dot: true)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 260, alignment: .trailing)
                }
            }

            InvoiceNudge()

            SessionHero()

            StatGrid {
                StatCard(label: "Ce mois-ci", value: Money.eur(earned.rounded()), foot: "Chiffre d'affaires", footColor: Theme.green)
                StatCard(label: "Temps ce mois-ci", value: TimeFmt.hm(secs))
                StatCard(label: "Taux horaire", value: secs >= 600 ? "\(Money.eur((earned / (secs / 3600)).rounded())) / h" : "–",
                         foot: "Ce que tu gagnes par heure de montage")
                StatCard(label: "À venir", value: Money.eur(toCome.rounded()), foot: "\(open.count) mission\(open.count > 1 ? "s" : "") en cours")
            }

            Columns(minLeft: 460, rightWidth: 300) {
                WeekAgenda(missions: data.missions, showPeople: false)
                if let me = app.profile {
                    DailyEarningsCard(title: "Mes gains par jour · 30 derniers jours",
                                      days: data.dailyEarnings(user: me.id,
                                                               from: Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date(),
                                                               to: Date()))
                }
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "Mes missions", trailing: "Ta part · budget max")
                    EarningsList(missions: open)
                }
                if let me = app.profile { DailyHoursCard(people: [me], title: "Mes heures par jour") }
            } right: {
                VStack(alignment: .leading, spacing: 0) {
                    Muted("Mes gains · \(Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "fr_BE"))))")
                    Text(Money.eur(validated.rounded())).font(.system(size: 30, weight: .semibold)).tracking(-0.5).padding(.top, 10)
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    Muted("validés, plus \(Money.eur((earned - validated).rounded())) en attente").padding(.top, 6)
                        .fixedSize(horizontal: false, vertical: true)
                    GeometryReader { g in
                        HStack(spacing: 0) {
                            Rectangle().fill(Theme.green).frame(width: earned > 0 ? g.size.width * validated / earned : 0)
                            Rectangle().fill(earned > 0 ? Theme.amber : Theme.ink.opacity(0.07))
                        }
                    }
                    .frame(height: 8).clipShape(Capsule()).padding(.top, 16)
                    HStack(spacing: 14) {
                        legend(Theme.green, "Validé")
                        legend(Theme.amber, "En attente")
                    }
                    .padding(.top, 10)
                }
                .card()
                if let me = app.profile {
                    SliceBarsCard(title: "Gains par projet", subtitle: "Ce mois-ci, ta part par mission",
                                  slices: data.projectEarnings(user: me.id, missions: month.filter { m in
                                      data.memberIds(of: m.id).contains(me.id) || data.mySplit[m.id] != nil
                                  }, limit: 6),
                                  empty: "Aucune mission ce mois-ci.", showTime: true)
                }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.shield").foregroundStyle(Theme.muted)
                    Muted("Seul ton temps actif dans Premiere Pro est mesuré. Rien d'autre sur ton Mac n'est enregistré.", size: 12)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { Circle().fill(c).frame(width: 7, height: 7); Muted(t, size: 12) }
    }

    private func monthSeconds() -> Double {
        let me = app.profile?.id
        return data.sessions.filter { s in
            s.user_id == me && (DateFmt.parse(s.started_at).map { Calendar.current.isDate($0, equalTo: Date(), toGranularity: .month) } ?? false)
        }.map { Double($0.duration_sec ?? 0) }.reduce(0, +)
    }
}

/// Grande carte « session en cours » du tableau de bord monteur.
struct SessionHero: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var presenter: Presenter
    @Environment(\.layoutWidth) private var width

    var body: some View {
        let next = data.missions.filter(\.isOpen).sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }.first
        if let m = tracker.mission {
            let running = tracker.status == .running
            VStack(alignment: .leading, spacing: 0) {
                // Largeur de la carte moins ses marges : texte et actions côte à côte, ou empilés.
                let side = width - 52 >= 640
                let layout = side
                    ? AnyLayout(HStackLayout(alignment: .center, spacing: 24))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                layout {
                    heroText(m, running: running).frame(maxWidth: .infinity, alignment: .leading)
                    heroActions(m)
                }
                if let b = m.editor_budget, b > 0 {
                    let share = tracker.estimatedAmount ?? b
                    ThinBar(value: share / b, color: Theme.green).padding(.top, 22)
                    HStack {
                        Muted("Ta part actuelle : \(Money.eur(share.rounded())) sur \(Money.eur(b))").lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        TimelineView(.periodic(from: .now, by: 5)) { ctx in
                            Muted(tracker.hourlyRate(at: ctx.date).map { "\(Money.eur($0.rounded())) / h" } ?? "Taux horaire après 5 min")
                                .lineLimit(1).fixedSize()
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 20, tint: (running ? Theme.green : Theme.amber).opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder((running ? Theme.green : Theme.amber).opacity(0.32)))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: running)
        } else {
            HStack(spacing: 16) {
                Image(systemName: "film").font(.system(size: 20)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aucune session en cours").font(.system(size: 15, weight: .semibold))
                    Muted(next.map { "Prochaine deadline : \($0.title), \(DateFmt.deadline($0.deadlineDate).lowercased())" }
                          ?? "Ouvre ton projet dans Premiere : le chrono démarre tout seul.")
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let n = next { Button("Ouvrir la mission") { presenter.open(.existing(n.id)) }.buttonStyle(SecondaryButton()) }
            }
            .card()
        }
    }

    private func heroText(_ m: Mission, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Tag(text: running ? (tracker.manual ? "Chrono manuel en cours" : "Session en cours · détectée dans Premiere Pro") : "En pause",
                color: running ? Theme.green : Theme.amber, dot: true)
            Text([data.client(m.client_id)?.name, m.title].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 20, weight: .semibold)).padding(.top, 14)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(LiveClock.format(tracker.displaySeconds(at: ctx.date)))
                    .font(.system(size: 54, weight: .medium, design: .monospaced)).tracking(-1.5)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(running ? Theme.green : Theme.muted)
            }
            .padding(.top, 4)
            Muted("Livraison \(DateFmt.deadline(m.deadlineDate).lowercased())").padding(.top, 8)
        }
    }

    private func heroActions(_ m: Mission) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if m.isOpen && app.isEditor {
                EditorStatusMenu(current: m.status) { s in
                    Task { @MainActor in
                        do { try await data.editorSetStatus(m, s); app.showToast("Statut envoyé à l'admin") }
                        catch { app.showToast("Erreur : \(error.localizedDescription)") }
                    }
                }
            }
            Button("Ouvrir la mission") { presenter.open(.existing(m.id)) }.buttonStyle(SecondaryButton())
            Button("Mode mini") { MiniWindow.shared.show(app: app, data: data, tracker: tracker) }.buttonStyle(SecondaryButton())
        }
        .fixedSize()
    }
}

// MARK: - Monteur : finances

struct MyFinancesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    @State private var month: Date

    init(month: Date? = nil) { _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: month ?? Date())?.start ?? Date()) }

    private struct Row: Identifiable {
        let mission: Mission
        let amount: Double
        let estimated: Bool
        let seconds: Double
        var id: String { mission.id }
        var rate: Double? { seconds >= 300 ? amount / (seconds / 3600) : nil }
    }

    var body: some View {
        let rows = rowsFor(month)
        let total = rows.map(\.amount).reduce(0, +)
        let validated = rows.filter { ["validated", "paid"].contains($0.mission.status) }.map(\.amount).reduce(0, +)
        let secs = rows.map(\.seconds).reduce(0, +)
        let avg = secs >= 600 ? total / (secs / 3600) : nil
        let label = monthLabel(month)

        Page {
            PageHeader(kicker: "Ce que tu factures chaque mois", title: "Finances") {
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SecondaryButton())
                    Text(label).font(.system(size: 14, weight: .medium)).lineLimit(1).frame(width: 136)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SecondaryButton())
                }
            }

            if let me = app.profile?.id { EditorStatementCard(user: me, month: month, showRows: false) }

            StatGrid {
                StatCard(label: "À facturer à Minimalist", value: Money.eur((total * 100).rounded() / 100),
                         foot: "\(Money.eur(validated.rounded())) déjà validés", footColor: Theme.green)
                StatCard(label: "Missions", value: "\(rows.count)")
                StatCard(label: "Heures travaillées", value: TimeFmt.hm(secs))
                StatCard(label: "Rentabilité moyenne", value: avg.map { "\(Money.eur($0.rounded())) / h" } ?? "–",
                         foot: "Montant facturé ÷ heures travaillées")
            }

            DailyEarningsCard(title: "Gains par jour · \(label)", days: data.dailyEarnings(user: app.profile?.id ?? "", from: month, to: monthEnd))
            SliceBarsCard(title: "Gains par projet", subtitle: "Ta part sur chaque mission du mois",
                          slices: data.projectEarnings(user: app.profile?.id ?? "", missions: rows.map(\.mission)),
                          empty: "Aucune mission sur ce mois.", showTime: true)

            WidthReader { w in
                // Une seule décision pour l'en-tête et les lignes : tableau complet ou lignes compactes.
                let wide = w >= 720
                VStack(alignment: .leading, spacing: 0) {
                    CardTitle(text: "Détail des missions · \(label)") {
                        Button { copyRecap(rows, total: total, label: label) } label: {
                            Label("Copier le récap", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(SecondaryButton())
                        .disabled(rows.isEmpty)
                    }
                    .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
                    Group {
                        if wide {
                            HStack(spacing: 12) {
                                Muted("Mission", size: 12).frame(maxWidth: .infinity, alignment: .leading)
                                Muted("Statut", size: 12).frame(width: 132, alignment: .leading)
                                Muted("Temps", size: 12).frame(width: 70, alignment: .trailing)
                                Muted("Montant", size: 12).frame(width: 90, alignment: .trailing)
                                Muted("Rentabilité", size: 12).frame(width: 100, alignment: .trailing)
                            }
                        } else {
                            HStack { Muted("Mission", size: 12); Spacer(); Muted("Montant", size: 12) }
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 20).padding(.bottom, 10)
                    if rows.isEmpty { EmptyHint(text: "Aucune mission sur ce mois.", icon: "tray") }
                    ForEach(rows) { r in
                        Rectangle().fill(Theme.line).frame(height: 1)
                        row(r, avg: avg, wide: wide)
                    }
                    Rectangle().fill(Theme.line).frame(height: 1)
                    HStack {
                        Text("Total à facturer").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        Text(Money.eur((total * 100).rounded() / 100)).font(.system(size: 16, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.green).lineLimit(1).fixedSize()
                    }
                    .padding(.horizontal, 20).padding(.vertical, 14)
                }
                .glassCard()
            }

            Muted("Une mission compte dans la facture du mois où tu la livres. Les montants « estimés » peuvent encore bouger tant que le mois n'est pas fini. « Copier le récap » colle le détail dans ta facture.", size: 12)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ r: Row, avg: Double?, wide: Bool) -> some View {
        let c = data.client(r.mission.client_id)
        let rateColor: Color = {
            guard let x = r.rate, let a = avg, a > 0 else { return Theme.text2 }
            return x >= a ? Theme.green : (x >= a * 0.7 ? Theme.amber : Theme.red)
        }()
        let amount = Money.eur((r.amount * 100).rounded() / 100)
        let rate = r.rate.map { "\(Money.eur($0.rounded())) / h" } ?? "–"
        return Button { presenter.open(.existing(r.mission.id)) } label: {
            Group {
                if wide {
                    HStack(spacing: 12) {
                        HStack(spacing: 10) {
                            ClientDot(color: c?.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.mission.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                                Muted(c?.name ?? "Sans client", size: 12).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        StatusPill(status: r.mission.status, flexible: true).frame(width: 132, alignment: .leading)
                        Text(TimeFmt.hm(r.seconds)).font(.system(size: 13, design: .monospaced))
                            .lineLimit(1).minimumScaleFactor(0.8).frame(width: 70, alignment: .trailing)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(amount).font(.system(size: 13.5, weight: .semibold, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8)
                            if r.estimated { Muted("estimation", size: 10.5).lineLimit(1) }
                        }
                        .frame(width: 90, alignment: .trailing)
                        Text(rate).font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(rateColor).lineLimit(1).minimumScaleFactor(0.8).frame(width: 100, alignment: .trailing)
                    }
                } else {
                    HStack(spacing: 10) {
                        ClientDot(color: c?.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.mission.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            Muted("\(TimeFmt.hm(r.seconds)) · \(rate)\(r.estimated ? " · estimation" : "")", size: 12).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(amount).font(.system(size: 13.5, weight: .semibold, design: .monospaced)).lineLimit(1).fixedSize()
                            StatusPill(status: r.mission.status)
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 11)
            .contentShape(Rectangle())
            .hoverRow()
        }
        .buttonStyle(.plain)
    }

    private func rowsFor(_ m: Date) -> [Row] {
        let me = app.profile?.id ?? ""
        // Missions de la facture du mois : celles livrées ce mois-là (ou rangées à la main par l'admin).
        return data.statement(user: me, month: m).rows.map { r in
            let secs = data.mySplit[r.mission.id]?.seconds ?? data.seconds(mission: r.mission.id, user: me)
            return Row(mission: r.mission, amount: r.amount, estimated: r.estimated || !["validated", "paid"].contains(r.mission.status), seconds: secs)
        }
    }

    private func copyRecap(_ rows: [Row], total: Double, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(data.statementText(user: app.profile?.id ?? "", month: month), forType: .string)
        app.showToast("Détail copié : colle-le dans ta facture")
    }

    private func shift(_ n: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
        }
    }

    /// Dernier jour affiché : la fin du mois, ou aujourd'hui pour le mois en cours.
    private var monthEnd: Date {
        let cal = Calendar.current
        let next = cal.date(byAdding: .month, value: 1, to: month) ?? month
        let last = cal.date(byAdding: .day, value: -1, to: next) ?? month
        return cal.isDate(Date(), equalTo: month, toGranularity: .month) ? Date() : last
    }

    private func monthLabel(_ d: Date) -> String {
        let s = d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

/// Liste de missions avec la part du monteur connecté.
struct EarningsList: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    @Environment(\.layoutWidth) private var width
    let missions: [Mission]

    var body: some View {
        // Colonnes complètes quand la liste est large, deux lignes par mission sinon.
        let wide = width >= 620
        VStack(spacing: 0) {
            if missions.isEmpty { EmptyHint(text: "Aucune mission pour le moment.", icon: "film.stack") }
            ForEach(Array(missions.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                let share = data.myShare(of: m)
                let live = !data.liveSession(for: m.id).isEmpty
                Button { presenter.open(.existing(m.id)) } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(hex: data.client(m.client_id)?.color ?? "8B8D94")).frame(width: 3, height: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(m.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                                if live && !wide { Circle().fill(Theme.green).frame(width: 6, height: 6).help("En cours") }
                            }
                            Text("\(data.client(m.client_id)?.name ?? "Sans client") · \(DateFmt.deadline(m.deadlineDate))")
                                .font(.system(size: 12)).foregroundStyle(m.isLate ? Theme.red : Theme.muted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if wide {
                            if live { Pill(text: "En cours", color: Theme.green) }
                            Text(TimeFmt.hm(data.mySplit[m.id]?.seconds)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Theme.muted)
                                .lineLimit(1).frame(width: 70, alignment: .trailing)
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.eur((share.amount * 100).rounded() / 100)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.green).lineLimit(1).minimumScaleFactor(0.8)
                            if let b = m.editor_budget, b > 0 {
                                Text("max \(Money.eur(b))").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Theme.muted)
                                    .lineLimit(1).minimumScaleFactor(0.8)
                            } else if share.estimated {
                                Text("estimation").font(.system(size: 10.5)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                        }
                        .frame(width: 90, alignment: .trailing)
                        StatusPill(status: m.status, flexible: true).frame(width: wide ? 132 : 104, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
                    .hoverRow()
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 0)
    }
}

// MARK: - Monteur : mes missions

struct MyMissionsView: View {
    @EnvironmentObject var data: DataStore
    @State private var showDone = false

    var body: some View {
        let open = data.missions.filter(\.isOpen)
        let done = Array(data.missions.filter { !$0.isOpen }.reversed())
        Page {
            PageHeader(kicker: "\(open.count) en cours", title: "Mes missions") {
                ChipPicker(selection: $showDone, options: [
                    .init(value: false, label: "En cours", count: open.count),
                    .init(value: true, label: "Terminées", count: done.count),
                ])
            }
            Text("Le chrono démarre tout seul quand tu travailles dans Premiere sur le projet lié à la mission. Pas besoin d'y penser.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            EarningsList(missions: showDone ? done : open)
        }
    }
}

// MARK: - Client

struct ClientProjectsView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @State private var editing: String?
    @State private var link = ""

    var body: some View {
        let client = data.client(app.profile?.client_id)
        let list = data.missions.sorted { ($0.deadlineDate ?? .distantFuture) > ($1.deadlineDate ?? .distantFuture) }
        Page {
            PageHeader(kicker: client?.name ?? "Client", title: "Mes projets")
            VStack(spacing: 0) {
                if list.isEmpty { EmptyHint(text: "Aucun projet pour le moment. Tes montages apparaîtront ici dès leur création.", icon: "film.stack") }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.title).font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(DateFmt.deadline(m.deadlineDate)).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if m.rushes_url == nil {
                                Button("Déposer mes rushes") { editing = m.id; link = "" }.buttonStyle(SecondaryButton())
                            } else {
                                Label("Rushes reçus", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.green)
                                    .lineLimit(1).fixedSize()
                            }
                            StatusPill(status: m.status)
                        }
                        if editing == m.id {
                            HStack(spacing: 8) {
                                TextField("Colle ton lien WeTransfer ou Drive", text: $link).input()
                                Button("Envoyer") {
                                    Task { @MainActor in
                                        do { try await data.clientSetRushes(m, url: link); editing = nil; app.showToast("Lien envoyé, merci !") }
                                        catch { app.showToast("Erreur : \(error.localizedDescription)") }
                                    }
                                }
                                .buttonStyle(PrimaryButton()).disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                                Button("Annuler") { editing = nil }.buttonStyle(SecondaryButton())
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .card(padding: 0)
        }
    }
}

// MARK: - Admin : mises à jour

struct UpdatesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var updater: Updater
    @State private var zipURL: URL?
    @State private var version = ""
    @State private var notes = ""
    @State private var publishing = false
    @State private var cleaning = false

    var body: some View {
        Page {
            PageHeader(kicker: "Version installée : \(AppVersion.current)", title: "Mises à jour")

            VStack(alignment: .leading, spacing: 10) {
                Text("Comment ça marche").font(.system(size: 15, weight: .semibold))
                Text("1. Sur ton Mac, dans le Terminal : ./release.sh 0.4.0 (avec le nouveau numéro, toujours plus grand que le précédent). Le script compile, signe, et crée le .zip et le .dmg dans le dossier build.\n2. Ici, choisis le .zip créé, écris ce qui change, puis Publier.\n3. Chez tes monteurs, un bandeau « Nouvelle version disponible » apparaît : un clic et l'app se met à jour.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            .card()

            VStack(alignment: .leading, spacing: 16) {
                Text("Publier une version").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 10) {
                    Button(zipURL == nil ? "Choisir le .zip…" : "Changer") { choose() }.buttonStyle(SecondaryButton())
                    Text(zipURL?.lastPathComponent ?? "Aucun fichier").font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle)
                    if let z = zipURL, FileManager.default.fileExists(atPath: z.deletingPathExtension().appendingPathExtension("dmg").path) {
                        Pill(text: "+ installeur .dmg", color: Theme.green)
                    }
                }
                FormField(label: "Numéro de version") {
                    TextField("0.4.0", text: $version).input().frame(width: 160)
                }
                FormField(label: "Ce qui change (affiché aux monteurs)") {
                    TextField("Ex. Nouveau calendrier, PDF dans le brief", text: $notes).input()
                }
                HStack {
                    Button(publishing ? "Envoi…" : "Publier") { publish() }
                        .buttonStyle(PrimaryButton())
                        .disabled(zipURL == nil || version.isEmpty || publishing)
                    if let t = updater.progressText, publishing {
                        ProgressView().controlSize(.small)
                        Text(t).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Text("Installer l'app chez un nouveau monteur").font(.system(size: 15, weight: .semibold))
                if let l = updater.latest {
                    Text("Dernière version publiée : \(l.version)").font(.system(size: 13)).foregroundStyle(Theme.text2)
                }
                if updater.latest?.dmg_path != nil, let url = Updater.latestDmgURL {
                    Text("Envoie-lui ce lien, il télécharge toujours la dernière version :").font(.system(size: 13)).foregroundStyle(Theme.muted)
                    HStack(spacing: 8) {
                        Text(url.absoluteString).font(.system(size: 12.5, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10).frame(height: 32)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Button("Copier") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            app.showToast("Lien copié")
                        }
                        .buttonStyle(SecondaryButton())
                    }
                } else {
                    Text("Publie une première version avec son .dmg pour obtenir un lien de téléchargement.").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
            }
            .card()

            VStack(alignment: .leading, spacing: 10) {
                Text("Anciennes versions").font(.system(size: 15, weight: .semibold))
                Text("Les anciennes versions sont supprimées automatiquement à chaque publication. Tu peux aussi faire le ménage maintenant : seule la dernière version publiée est gardée.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button(cleaning ? "Nettoyage…" : "Supprimer les anciennes versions") {
                    guard let keep = updater.latest?.version else { return }
                    cleaning = true
                    Task { @MainActor in
                        do {
                            let n = try await updater.cleanup(keep: keep)
                            app.showToast("\(n) ancien\(n > 1 ? "s" : "") fichier\(n > 1 ? "s" : "") supprimé\(n > 1 ? "s" : "")")
                        } catch { app.showToast("Erreur : \(error.localizedDescription)") }
                        cleaning = false
                    }
                }
                .buttonStyle(SecondaryButton(danger: true))
                .disabled(cleaning || updater.latest == nil)
            }
            .card()
        }
        .task { if !SnapshotMode.on { await updater.check() } }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let u = panel.url {
            zipURL = u
            if let r = u.lastPathComponent.range(of: #"\d+\.\d+\.\d+"#, options: .regularExpression) {
                version = String(u.lastPathComponent[r])
            }
        }
    }

    private func publish() {
        guard let z = zipURL else { return }
        publishing = true
        Task { @MainActor in
            do {
                try await updater.publish(zipURL: z, version: version.trimmingCharacters(in: .whitespaces), notes: notes)
                app.showToast("Version \(version) publiée")
                zipURL = nil
                notes = ""
            } catch {
                app.showToast("Erreur : \(error.localizedDescription)")
            }
            publishing = false
        }
    }
}
