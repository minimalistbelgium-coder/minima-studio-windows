import SwiftUI
import Supabase


private struct InvoicedUpdate: Encodable { let mission_id: String; let client_price: Double?; let invoiced: Bool }

private func monthKey(_ d: Date?) -> String {
    guard let d else { return "Sans date" }
    let s = d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
    return s.prefix(1).uppercased() + s.dropFirst()
}

private func monthStart(_ d: Date?) -> Date {
    guard let d else { return .distantPast }
    return Calendar.current.dateInterval(of: .month, for: d)?.start ?? d
}

// MARK: - Finances (admin)

struct FinancesView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @State private var month: Date
    @State private var wideScope = false
    @EnvironmentObject var presenter: Presenter

    init(month: Date? = nil) { _month = State(initialValue: monthStart(month ?? Date())) }

    /// Dernier mois affiché dans le graphique : le mois courant, ou le mois choisi s'il sort des 12 derniers mois.
    private var chartEnd: Date {
        let now = monthStart(Date())
        let oldest = Calendar.current.date(byAdding: .month, value: -11, to: now) ?? now
        return (month > now || month < oldest) ? month : now
    }

    var body: some View {
        let inMonth = data.missions(inMonthOf: month).filter { $0.status != "requested" }
        let revenue = inMonth.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let cost = inMonth.compactMap(\.editor_budget).reduce(0, +)
        let margin = revenue - cost
        let toInvoice = inMonth.filter { $0.status == "validated" || $0.status == "paid" }.filter { data.finances[$0.id]?.invoiced != true }
        let trend = data.monthlyFinance(endingAt: chartEnd)
        let scoped = wideScope ? data.missions(inMonths: trend.map(\.month)) : inMonth

        Page {
            PageHeader(kicker: "Visible uniquement par toi", title: "Finances") {
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SecondaryButton()).help("Mois précédent")
                    Text(monthKey(month)).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85).frame(width: 140)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SecondaryButton()).help("Mois suivant")
                }
            }

            StatGrid {
                StatCard(label: "Facturé aux clients", value: Money.eur(revenue), foot: "\(inMonth.count) mission\(inMonth.count > 1 ? "s" : "") ce mois")
                StatCard(label: "Pour les monteurs", value: Money.eur(cost), foot: revenue > 0 ? "\(Int((cost / revenue * 100).rounded())) % du CA" : "Budgets montage")
                StatCard(label: "Marge", value: Money.eur(margin),
                         foot: revenue > 0 ? "\(Int((margin / revenue * 100).rounded())) % du CA" : "Renseigne les prix clients",
                         footColor: margin >= 0 ? Theme.green : Theme.red)
                StatCard(label: "À facturer", value: "\(toInvoice.count)", foot: "Missions validées non facturées")
            }

            EditorPayoutsSection(month: month)

            FinanceTrendCard(points: trend, month: $month)

            HStack(spacing: 12) {
                Text("Répartition").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 8)
                ChipPicker(selection: $wideScope, options: [
                    .init(value: false, label: monthKey(month)),
                    .init(value: true, label: "12 mois"),
                ])
            }
            EqualGrid(minWidth: 360, spacing: 16) {
                SliceBarsCard(title: "Par client", subtitle: "Facturé aux clients", slices: data.clientSlices(scoped),
                              empty: "Aucun prix client renseigné sur cette période.")
                SliceBarsCard(title: "Par monteur", subtitle: "Budget montage réparti selon le temps passé",
                              slices: data.editorSlices(scoped), empty: "Aucun budget montage sur cette période.", showTime: true)
            }

            SectionTitle(text: "Détail par client · \(monthKey(month))", trailing: "Facturé · Équipe · Marge")
            VStack(spacing: 0) {
                let byClient = Dictionary(grouping: inMonth) { $0.client_id ?? "" }
                let keys = byClient.keys.sorted { (data.client($0)?.name ?? "") < (data.client($1)?.name ?? "") }
                if keys.isEmpty { EmptyHint(text: "Aucune mission ce mois-ci.") }
                ForEach(Array(keys.enumerated()), id: \.element) { i, k in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    let ms = byClient[k] ?? []
                    let r = ms.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
                    let c = ms.compactMap(\.editor_budget).reduce(0, +)
                    HStack(spacing: 12) {
                        ClientDot(color: data.client(k)?.color, size: 9)
                        Text(data.client(k)?.name ?? "Sans client").font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                        Text("\(ms.count)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                        Spacer(minLength: 8)
                        moneyCol(r)
                        moneyCol(c)
                        moneyCol(r - c, color: r - c >= 0 ? Theme.green : Theme.red, bold: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
            }
            .card(padding: 0)

            SectionTitle(text: "Missions du mois", trailing: "Prix client · Équipe · Marge · Facture envoyée ?")
            WidthReader { w in
                // Colonnes alignées quand la page est large, deux lignes par mission quand elle est étroite.
                let wide = w >= 780
                VStack(spacing: 0) {
                    if inMonth.isEmpty { EmptyHint(text: "Aucune mission ce mois-ci.") }
                    ForEach(Array(inMonth.enumerated()), id: \.element.id) { i, m in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        missionRow(m, wide: wide)
                    }
                }
                .card(padding: 0)
            }
        }
    }

    @ViewBuilder
    private func missionRow(_ m: Mission, wide: Bool) -> some View {
        let f = data.finances[m.id]
        let p = f?.client_price
        let b = m.editor_budget ?? 0
        let invoiced = f?.invoiced ?? false
        if wide {
            HStack(spacing: 12) {
                Button { presenter.open(.existing(m.id)) } label: {
                    HStack(spacing: 10) {
                        ClientDot(color: data.client(m.client_id)?.color)
                        Text(m.title).font(.system(size: 13.5)).lineLimit(1)
                        StatusPill(status: m.status)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(p.map(Money.eur) ?? "–").font(.system(size: 13)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8).frame(width: 90, alignment: .trailing)
                moneyCol(b)
                if let p { moneyCol(p - b, color: p - b >= 0 ? Theme.green : Theme.red, bold: true) }
                else { Text("–").frame(width: 90, alignment: .trailing).foregroundStyle(Theme.muted) }
                InvoicedButton(on: invoiced) { setInvoiced(m, p, !invoiced) }
                    .frame(width: 104, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .hoverRow()
        } else {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    Button { presenter.open(.existing(m.id)) } label: {
                        HStack(spacing: 10) {
                            ClientDot(color: data.client(m.client_id)?.color)
                            Text(m.title).font(.system(size: 13.5)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    InvoicedButton(on: invoiced) { setInvoiced(m, p, !invoiced) }
                }
                HStack(spacing: 10) {
                    StatusPill(status: m.status)
                    Spacer(minLength: 4)
                    Text("\(p.map(Money.eur) ?? "–") · \(Money.eur(b))").font(.system(size: 12.5)).monospacedDigit()
                        .foregroundStyle(Theme.text2).lineLimit(1).minimumScaleFactor(0.8)
                    if let p {
                        Text(Money.eur(p - b)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(p - b >= 0 ? Theme.green : Theme.red).lineLimit(1).fixedSize()
                    }
                }
                .padding(.leading, 18)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .hoverRow()
        }
    }

    private func moneyCol(_ v: Double, color: Color = Theme.text2, bold: Bool = false) -> some View {
        Text(Money.eur(v)).font(.system(size: 13, weight: bold ? .semibold : .regular)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(color).frame(width: 90, alignment: .trailing)
    }

    private func shift(_ n: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
        }
    }

    private func setInvoiced(_ m: Mission, _ price: Double?, _ v: Bool) {
        Task { @MainActor in
            do {
                try await supa.from("mission_finance").upsert(InvoicedUpdate(mission_id: m.id, client_price: price, invoiced: v)).execute()
                await data.reload()
            } catch { app.showToast("Erreur : \(error.localizedDescription)") }
        }
    }
}

// MARK: - Analyse du temps (admin)

struct TimeView: View {
    @EnvironmentObject var data: DataStore
    @State private var sessions: [WorkSession] = []
    @State private var loaded = false

    var body: some View {
        let total = Double(sessions.compactMap(\.duration_sec).reduce(0, +))
        let byUser = Dictionary(grouping: sessions, by: \.user_id)
        let byMission = Dictionary(grouping: sessions, by: \.mission_id)

        Page {
            PageHeader(kicker: "Temps mesuré dans Premiere Pro", title: "Analyse du temps")

            if loaded && sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pas encore de temps enregistré").font(.system(size: 15, weight: .semibold))
                    Text("Le suivi automatique dans Premiere Pro arrive à la prochaine étape. Dès qu'il est installé, chaque minute passée sur un projet lié à une mission apparaîtra ici, et la répartition des budgets se calculera toute seule.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                .card()
            } else if !loaded {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Muted("Chargement du temps enregistré…") }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                DailyHoursCard(people: data.profiles.filter { $0.active && ($0.role == "editor" || $0.role == "admin") },
                               title: "Heures par jour")
                StatGrid {
                    StatCard(label: "Temps total", value: TimeFmt.hm(total))
                    StatCard(label: "Sessions", value: "\(sessions.count)")
                    StatCard(label: "Missions suivies", value: "\(byMission.count)")
                }

                SectionTitle(text: "Par personne")
                VStack(spacing: 0) {
                    let users = byUser.keys.sorted()
                    ForEach(Array(users.enumerated()), id: \.element) { i, uid in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        let secs = Double((byUser[uid] ?? []).compactMap(\.duration_sec).reduce(0, +))
                        HStack(spacing: 12) {
                            if let p = data.profile(uid) { AvatarView(profile: p, size: 26) }
                            Text(data.profile(uid)?.displayName ?? "Inconnu").font(.system(size: 13.5)).lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ThinBar(value: total > 0 ? secs / total : 0, color: Theme.blue)
                                .frame(minWidth: 60, maxWidth: 220)
                            Text(TimeFmt.hm(secs)).font(.system(size: 13)).monospacedDigit().lineLimit(1).frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                }
                .card(padding: 0)

                SectionTitle(text: "Par mission", trailing: "Budget montage à l'heure")
                VStack(spacing: 0) {
                    let ids = byMission.keys.sorted { a, b in
                        (byMission[a] ?? []).compactMap(\.duration_sec).reduce(0, +) > (byMission[b] ?? []).compactMap(\.duration_sec).reduce(0, +)
                    }
                    ForEach(Array(ids.enumerated()), id: \.element) { i, mid in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        let secs = Double((byMission[mid] ?? []).compactMap(\.duration_sec).reduce(0, +))
                        let m = data.mission(mid)
                        HStack(spacing: 12) {
                            ClientDot(color: data.client(m?.client_id)?.color)
                            Text(m?.title ?? "Mission supprimée").font(.system(size: 13.5)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(TimeFmt.hm(secs)).font(.system(size: 13)).monospacedDigit().lineLimit(1).frame(width: 80, alignment: .trailing)
                            Text(hourly(m?.editor_budget, secs)).font(.system(size: 13)).monospacedDigit()
                                .foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8).frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                }
                .card(padding: 0)
            }
        }
        .task {
            if SnapshotMode.on { sessions = data.sessions; loaded = true; return }
            do {
                let list: [WorkSession] = try await supa.from("sessions").select().order("started_at", ascending: false).limit(5000).execute().value
                sessions = list
            } catch {
                sessions = []
            }
            loaded = true
        }
    }

    private func hourly(_ budget: Double?, _ secs: Double) -> String {
        guard let b = budget, secs >= 60 else { return "–" }
        return Money.eur((b / (secs / 3600) * 100).rounded() / 100) + "/h"
    }
}



/// Indique si la facture client est envoyée. Un clic bascule l'état.
private struct InvoicedButton: View {
    let on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: on ? "checkmark.circle.fill" : "doc.text")
                    .font(.system(size: 11, weight: .semibold))
                Text(on ? "Client facturé" : "Facturer le client").font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
            }
            .fixedSize()
            .foregroundStyle(on ? Theme.green : Theme.amber)
            .padding(.horizontal, 9).frame(height: 24)
            .background((on ? Theme.green : Theme.amber).opacity(0.13), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(on ? "Facture envoyée au client. Clique pour annuler." : "Clique quand tu as envoyé la facture au client.")
    }
}
