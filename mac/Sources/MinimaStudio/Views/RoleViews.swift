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
                }
            }

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
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(text: "Mes missions", trailing: "Ta part · budget max")
                    EarningsList(missions: open)
                }
                if let me = app.profile { DailyHoursCard(people: [me], title: "Mes heures par jour") }
            } right: {
                VStack(alignment: .leading, spacing: 0) {
                    Muted("Mes gains · \(Date().formatted(.dateTime.month(.wide).locale(Locale(identifier: "fr_BE"))))")
                    Text(Money.eur(validated.rounded())).font(.system(size: 30, weight: .semibold)).tracking(-0.5).padding(.top, 10)
                    Muted("validés, plus \(Money.eur((earned - validated).rounded())) en attente").padding(.top, 6)
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

    var body: some View {
        let next = data.missions.filter(\.isOpen).sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }.first
        if let m = tracker.mission {
            let running = tracker.status == .running
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 24) { heroText(m, running: running); Spacer(minLength: 0); heroActions(m) }
                    VStack(alignment: .leading, spacing: 18) { heroText(m, running: running); heroActions(m) }
                }
                if let b = m.editor_budget, b > 0 {
                    let share = tracker.estimatedAmount ?? b
                    ThinBar(value: share / b, color: Theme.green).padding(.top, 22)
                    HStack {
                        Muted("Ta part actuelle : \(Money.eur(share.rounded())) sur \(Money.eur(b))")
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 5)) { ctx in
                            Muted(tracker.hourlyRate(at: ctx.date).map { "\(Money.eur($0.rounded())) / h" } ?? "Taux horaire après 5 min")
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke((running ? Theme.green : Theme.amber).opacity(0.3)))
        } else {
            HStack(spacing: 16) {
                Image(systemName: "film").font(.system(size: 20)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aucune session en cours").font(.system(size: 15, weight: .semibold))
                    Muted(next.map { "Prochaine deadline : \($0.title), \(DateFmt.deadline($0.deadlineDate).lowercased())" }
                          ?? "Ouvre ton projet dans Premiere : le chrono démarre tout seul.")
                }
                Spacer(minLength: 8)
                if let n = next { Button("Ouvrir la mission") { presenter.open(.existing(n.id)) }.buttonStyle(SecondaryButton()) }
            }
            .card()
        }
    }

    private func heroText(_ m: Mission, running: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Tag(text: running ? (tracker.manual ? "Chrono manuel en cours" : "Session en cours · détectée dans Premiere Pro") : "En pause",
                color: running ? Theme.green : Theme.amber, dot: true)
            Text("\(data.client(m.client_id)?.name ?? "") · \(m.title)").font(.system(size: 20, weight: .semibold)).padding(.top, 14)
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(LiveClock.format(tracker.displaySeconds(at: ctx.date)))
                    .font(.system(size: 54, weight: .medium, design: .monospaced)).tracking(-1.5)
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
        .frame(minWidth: 220, alignment: .leading)
    }
}

// MARK: - Monteur : finances

struct MyFinancesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

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
            PageHeader(kicker: "Ton récapitulatif", title: "Finances") {
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SecondaryButton())
                    Text(label).font(.system(size: 14, weight: .medium)).frame(minWidth: 130)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SecondaryButton())
                }
            }

            StatGrid {
                StatCard(label: "À facturer à Gaston", value: Money.eur((total * 100).rounded() / 100),
                         foot: "\(Money.eur(validated.rounded())) déjà validés", footColor: Theme.green)
                StatCard(label: "Missions", value: "\(rows.count)")
                StatCard(label: "Heures travaillées", value: TimeFmt.hm(secs))
                StatCard(label: "Rentabilité moyenne", value: avg.map { "\(Money.eur($0.rounded())) / h" } ?? "–",
                         foot: "Montant facturé ÷ heures travaillées")
            }

            VStack(alignment: .leading, spacing: 0) {
                CardTitle(text: "Détail des missions · \(label)") {
                    Button { copyRecap(rows, total: total, label: label) } label: {
                        Label("Copier le récap", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(SecondaryButton())
                    .disabled(rows.isEmpty)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Muted("Mission", size: 12).frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                        Muted("Statut", size: 12).frame(width: 120, alignment: .leading)
                        Muted("Temps", size: 12).frame(width: 70, alignment: .trailing)
                        Muted("Montant", size: 12).frame(width: 90, alignment: .trailing)
                        Muted("Rentabilité", size: 12).frame(width: 100, alignment: .trailing)
                    }
                    HStack { Muted("Mission", size: 12); Spacer(); Muted("Montant", size: 12) }
                }
                .padding(.horizontal, 20).padding(.bottom, 10)
                if rows.isEmpty { EmptyHint(text: "Aucune mission sur ce mois.") }
                ForEach(rows) { r in
                    Rectangle().fill(Theme.line).frame(height: 1)
                    row(r, avg: avg)
                }
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack {
                    Text("Total à facturer").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(Money.eur((total * 100).rounded() / 100)).font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.green)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))

            Muted("Les montants « estimés » peuvent encore bouger : ils sont définitifs quand Gaston valide la mission. Tu peux coller le récap dans ta facture.", size: 12)
        }
    }

    private func row(_ r: Row, avg: Double?) -> some View {
        let c = data.client(r.mission.client_id)
        let rateColor: Color = {
            guard let x = r.rate, let a = avg, a > 0 else { return Theme.text2 }
            return x >= a ? Theme.green : (x >= a * 0.7 ? Theme.amber : Theme.red)
        }()
        return Button { presenter.open(.existing(r.mission.id)) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    HStack(spacing: 10) {
                        ClientDot(color: c?.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.mission.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            Muted(c?.name ?? "Sans client", size: 12)
                        }
                    }
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                    StatusPill(status: r.mission.status).frame(width: 120, alignment: .leading)
                    Text(TimeFmt.hm(r.seconds)).font(.system(size: 13, design: .monospaced)).frame(width: 70, alignment: .trailing)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Money.eur((r.amount * 100).rounded() / 100)).font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                        if r.estimated { Muted("estimation", size: 10.5) }
                    }
                    .frame(width: 90, alignment: .trailing)
                    Text(r.rate.map { "\(Money.eur($0.rounded())) / h" } ?? "–").font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(rateColor).frame(width: 100, alignment: .trailing)
                }
                HStack(spacing: 10) {
                    ClientDot(color: c?.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.mission.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                        Muted("\(TimeFmt.hm(r.seconds)) · \(r.rate.map { "\(Money.eur($0.rounded())) / h" } ?? "–")", size: 12)
                    }
                    Spacer()
                    Text(Money.eur((r.amount * 100).rounded() / 100)).font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowsFor(_ m: Date) -> [Row] {
        let me = app.profile?.id ?? ""
        return data.missions(inMonthOf: m)
            .filter { data.memberIds(of: $0.id).contains(me) || data.mySplit[$0.id] != nil }
            .sorted { ($0.deadlineDate ?? .distantPast) < ($1.deadlineDate ?? .distantPast) }
            .map { mission in
                let share = data.myShare(of: mission)
                let secs = data.mySplit[mission.id]?.seconds ?? data.seconds(mission: mission.id, user: me)
                return Row(mission: mission, amount: share.amount, estimated: share.estimated || !["validated", "paid"].contains(mission.status), seconds: secs)
            }
    }

    private func copyRecap(_ rows: [Row], total: Double, label: String) {
        var lines = ["Récapitulatif \(label) · \(app.profile?.displayName ?? "")", ""]
        for r in rows {
            let c = data.client(r.mission.client_id)?.name ?? "Sans client"
            lines.append("\(c) · \(r.mission.title) : \(Money.eur((r.amount * 100).rounded() / 100)) (\(TimeFmt.hm(r.seconds)))")
        }
        lines.append("")
        lines.append("Total HTVA : \(Money.eur((total * 100).rounded() / 100))")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        app.showToast("Récapitulatif copié")
    }

    private func shift(_ n: Int) { month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month }

    private func monthLabel(_ d: Date) -> String {
        let s = d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

/// Liste de missions avec la part du monteur connecté.
struct EarningsList: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let missions: [Mission]

    var body: some View {
        VStack(spacing: 0) {
            if missions.isEmpty { EmptyHint(text: "Aucune mission pour le moment.") }
            ForEach(Array(missions.enumerated()), id: \.element.id) { i, m in
                if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                let share = data.myShare(of: m)
                Button { presenter.open(.existing(m.id)) } label: {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(hex: data.client(m.client_id)?.color ?? "8B8D94")).frame(width: 3, height: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.title).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                            Text("\(data.client(m.client_id)?.name ?? "Sans client") · \(DateFmt.deadline(m.deadlineDate))")
                                .font(.system(size: 12)).foregroundStyle(m.isLate ? Theme.red : Theme.muted)
                        }
                        Spacer()
                        if !data.liveSession(for: m.id).isEmpty { Pill(text: "En cours", color: Theme.green) }
                        Text(TimeFmt.hm(data.mySplit[m.id]?.seconds)).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Theme.muted)
                            .frame(width: 70, alignment: .trailing)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Money.eur((share.amount * 100).rounded() / 100)).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Theme.green)
                            if let b = m.editor_budget, b > 0 {
                                Text("max \(Money.eur(b))").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(Theme.muted)
                            } else if share.estimated {
                                Text("estimation").font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(width: 90, alignment: .trailing)
                        StatusPill(status: m.status).frame(width: 96, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                    .contentShape(Rectangle())
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
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
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
                if list.isEmpty { EmptyHint(text: "Aucun projet pour le moment.") }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.title).font(.system(size: 14, weight: .medium))
                                Text(DateFmt.deadline(m.deadlineDate)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            if m.rushes_url == nil {
                                Button("Déposer mes rushes") { editing = m.id; link = "" }.buttonStyle(SecondaryButton())
                            } else {
                                Label("Rushes reçus", systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Theme.green)
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
                    Text(zipURL?.lastPathComponent ?? "Aucun fichier").font(.system(size: 13)).foregroundStyle(Theme.muted)
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
                        Text(t).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
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
        .task { await updater.check() }
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
