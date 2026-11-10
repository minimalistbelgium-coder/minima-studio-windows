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
    @State private var month: Date = monthStart(Date())
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        let inMonth = data.missions.filter { monthStart($0.deadlineDate ?? DateFmt.parse($0.created_at)) == month }
        let revenue = inMonth.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let cost = inMonth.compactMap(\.editor_budget).reduce(0, +)
        let margin = revenue - cost
        let toInvoice = inMonth.filter { $0.status == "validated" || $0.status == "paid" }.filter { data.finances[$0.id]?.invoiced != true }

        Page {
            PageHeader(kicker: "Visible uniquement par toi", title: "Finances") {
                HStack(spacing: 8) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(SecondaryButton())
                    Text(monthKey(month)).font(.system(size: 14, weight: .medium)).frame(minWidth: 140)
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(SecondaryButton())
                }
            }

            HStack(spacing: 14) {
                StatCard(label: "Facturé aux clients", value: Money.eur(revenue))
                StatCard(label: "Payé à l'équipe", value: Money.eur(cost))
                StatCard(label: "Marge", value: Money.eur(margin),
                         foot: revenue > 0 ? "\(Int((margin / revenue * 100).rounded())) % du CA" : nil,
                         footColor: margin >= 0 ? Theme.green : Theme.red)
                StatCard(label: "À facturer", value: "\(toInvoice.count)", foot: "Missions validées non facturées")
            }

            SectionTitle(text: "Par client")
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
                        Text(data.client(k)?.name ?? "Sans client").font(.system(size: 13.5, weight: .medium))
                        Text("\(ms.count)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Spacer()
                        moneyCol(r)
                        moneyCol(c)
                        moneyCol(r - c, color: r - c >= 0 ? Theme.green : Theme.red, bold: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
            }
            .card(padding: 0)

            SectionTitle(text: "Missions du mois", trailing: "Prix client · Équipe · Marge · Facture envoyée ?")
            VStack(spacing: 0) {
                if inMonth.isEmpty { EmptyHint(text: "Aucune mission ce mois-ci.") }
                ForEach(Array(inMonth.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    let f = data.finances[m.id]
                    let p = f?.client_price
                    let b = m.editor_budget ?? 0
                    HStack(spacing: 12) {
                        Button { presenter.open(.existing(m.id)) } label: {
                            HStack(spacing: 10) {
                                ClientDot(color: data.client(m.client_id)?.color)
                                Text(m.title).font(.system(size: 13.5)).lineLimit(1)
                                StatusPill(status: m.status)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text(p.map(Money.eur) ?? "–").font(.system(size: 13)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        moneyCol(b)
                        if let p { moneyCol(p - b, color: p - b >= 0 ? Theme.green : Theme.red, bold: true) }
                        else { Text("–").frame(width: 90, alignment: .trailing).foregroundStyle(Theme.muted) }
                        InvoicedButton(on: f?.invoiced ?? false) { setInvoiced(m, p, !(f?.invoiced ?? false)) }
                            .frame(width: 104, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .card(padding: 0)
        }
    }

    private func moneyCol(_ v: Double, color: Color = Theme.text2, bold: Bool = false) -> some View {
        Text(Money.eur(v)).font(.system(size: 13, weight: bold ? .semibold : .regular)).monospacedDigit()
            .foregroundStyle(color).frame(width: 90, alignment: .trailing)
    }

    private func shift(_ n: Int) {
        month = Calendar.current.date(byAdding: .month, value: n, to: month) ?? month
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
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                .card()
            } else {
                HStack(spacing: 14) {
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
                            Text(data.profile(uid)?.displayName ?? "Inconnu").font(.system(size: 13.5))
                            Spacer()
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 3).fill(Theme.blue.opacity(0.7))
                                    .frame(width: total > 0 ? g.size.width * secs / total : 0)
                            }
                            .frame(width: 220, height: 6)
                            Text(TimeFmt.hm(secs)).font(.system(size: 13)).monospacedDigit().frame(width: 80, alignment: .trailing)
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
                            Spacer()
                            Text(TimeFmt.hm(secs)).font(.system(size: 13)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Text(hourly(m?.editor_budget, secs)).font(.system(size: 13)).monospacedDigit()
                                .foregroundStyle(Theme.muted).frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                }
                .card(padding: 0)
            }
        }
        .task {
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
                Text(on ? "Facturée" : "À facturer").font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(on ? Theme.green : Theme.amber)
            .padding(.horizontal, 9).frame(height: 24)
            .background((on ? Theme.green : Theme.amber).opacity(0.13), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(on ? "Facture envoyée au client. Clique pour annuler." : "Clique quand tu as envoyé la facture au client.")
    }
}
