import Foundation

// Calculs pour les graphiques, à partir des données déjà chargées par DataStore
// (missions, finances, sessions, mySplit, profiles). Aucun appel réseau ici.

/// Chiffres d'un mois (admin).
struct MonthFinance: Identifiable, Hashable {
    let month: Date
    /// Étiquette courte et unique sur 12 mois (« nov »).
    let label: String
    let billed: Double
    let cost: Double
    let missions: Int
    var margin: Double { billed - cost }
    var id: Date { month }
}

/// Une part d'une répartition (par client, par monteur, par projet).
struct ShareSlice: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String
    let value: Double
    var seconds: Double = 0
    var estimated = false
}

/// Gains d'un jour (monteur).
struct DayEarning: Identifiable, Hashable {
    let day: Date
    let amount: Double
    let seconds: Double
    let cumulative: Double
    var id: Date { day }
}

enum ChartSeries {
    static let billed = "Facturé"
    static let cost = "Équipe"
    static let margin = "Marge"
}

extension DataStore {
    /// Mois de rattachement d'une mission : mois de facturation du monteur, sinon sa deadline.
    func financeMonth(of m: Mission) -> Date? {
        m.workMonth
    }

    /// Facturé, budget équipe et marge sur les `count` mois qui finissent à `end` (inclus).
    func monthlyFinance(endingAt end: Date, count: Int = 12) -> [MonthFinance] {
        let cal = Calendar.current
        let last = cal.dateInterval(of: .month, for: end)?.start ?? end
        var billed: [Date: Double] = [:], cost: [Date: Double] = [:], n: [Date: Int] = [:]
        for m in missions {
            guard let k = financeMonth(of: m) else { continue }
            billed[k, default: 0] += finances[m.id]?.client_price ?? 0
            cost[k, default: 0] += m.editor_budget ?? 0
            n[k, default: 0] += 1
        }
        let fr = Locale(identifier: "fr_BE")
        return (0..<count).reversed().compactMap { back in
            guard let d = cal.date(byAdding: .month, value: -back, to: last) else { return nil }
            let label = d.formatted(.dateTime.month(.abbreviated).locale(fr)).replacingOccurrences(of: ".", with: "")
            return MonthFinance(month: d, label: label, billed: billed[d] ?? 0, cost: cost[d] ?? 0, missions: n[d] ?? 0)
        }
    }

    /// Missions rattachées à l'un des mois donnés.
    func missions(inMonths months: [Date]) -> [Mission] {
        let set = Set(months)
        return missions.filter { m in financeMonth(of: m).map(set.contains) ?? false }
    }

    /// Facturé par client, du plus gros au plus petit.
    func clientSlices(_ list: [Mission]) -> [ShareSlice] {
        var sums: [String: Double] = [:]
        for m in list { sums[m.client_id ?? "", default: 0] += finances[m.id]?.client_price ?? 0 }
        let out = sums.filter { $0.value > 0 }.map { id, v in
            ShareSlice(id: id.isEmpty ? "none" : id, name: client(id)?.name ?? "Sans client",
                       colorHex: client(id)?.color ?? "8B8D94", value: v)
        }
        return Self.uniqueNames(out.sorted { $0.value > $1.value })
    }

    /// Budget montage réparti par personne. Même règle que la base : au prorata du temps,
    /// l'admin compte plus s'il partage la mission. Sans temps enregistré : parts égales entre les assignés.
    func editorSlices(_ list: [Mission]) -> [ShareSlice] {
        let byMission = Dictionary(grouping: sessions, by: \.mission_id)
        let roles = Dictionary(profiles.map { ($0.id, $0.role) }, uniquingKeysWith: { a, _ in a })
        let membersByMission = Dictionary(grouping: members, by: \.mission_id)
        var sums: [String: Double] = [:], secs: [String: Double] = [:]
        for m in list {
            let budget = m.editor_budget ?? 0
            // Répartition de la base (règle de la marge depuis novembre 2026) quand elle existe.
            if let srv = serverSplits[m.id], !srv.isEmpty {
                for r in srv { sums[r.user_id, default: 0] += r.amount ?? 0; secs[r.user_id, default: 0] += r.seconds ?? 0 }
                continue
            }
            var time: [String: Double] = [:]
            for s in byMission[m.id] ?? [] { time[s.user_id, default: 0] += Double(s.duration_sec ?? 0) }
            time = DataStore.dropTiny(time)
            for (u, t) in time { secs[u, default: 0] += t }
            let shared = time.count > 1
            var weighted: [String: Double] = [:]
            for (u, t) in time { weighted[u] = t * ((shared && roles[u] == "admin") ? (m.admin_weight ?? 1.2) : 1) }
            let total = weighted.values.reduce(0, +)
            if total > 0 {
                for (u, w) in weighted { sums[u, default: 0] += budget * w / total }
            } else {
                let ids = (membersByMission[m.id] ?? []).map(\.user_id)
                if ids.isEmpty { sums["", default: 0] += budget }
                else { for u in ids { sums[u, default: 0] += budget / Double(ids.count) } }
            }
        }
        let out = sums.filter { $0.value > 0 }.map { id, v -> ShareSlice in
            let p = profile(id)
            return ShareSlice(id: id.isEmpty ? "none" : id, name: p?.firstName ?? (id.isEmpty ? "Non assigné" : "Inconnu"),
                              colorHex: p?.color ?? "8B8D94", value: (v * 100).rounded() / 100, seconds: secs[id] ?? 0)
        }
        return Self.uniqueNames(out.sorted { $0.value > $1.value })
    }

    /// Missions sur lesquelles une personne a une part (assignée, ou une ligne dans mySplit).
    func earningMissions(user: String) -> [Mission] {
        let mine = Set(members.filter { $0.user_id == user }.map(\.mission_id))
        return missions.filter { mine.contains($0.id) || mySplit[$0.id] != nil }
    }

    /// Gains par jour : le montant de chaque mission est réparti sur ses jours de session,
    /// au prorata du temps passé ce jour-là. Un point par jour entre `from` et `to` (inclus).
    func dailyEarnings(user: String, from: Date, to: Date) -> [DayEarning] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from), end = cal.startOfDay(for: to)
        guard start <= end else { return [] }
        var perMission: [String: [Date: Double]] = [:]
        for s in sessions where s.user_id == user {
            guard let d = DateFmt.parse(s.started_at) else { continue }
            perMission[s.mission_id, default: [:]][cal.startOfDay(for: d), default: 0] += Double(s.duration_sec ?? 0)
        }
        var money: [Date: Double] = [:], time: [Date: Double] = [:]
        for (mid, days) in perMission {
            let total = days.values.reduce(0, +)
            let amount = mission(mid).map { myShare(of: $0).amount } ?? 0
            for (day, secs) in days {
                time[day, default: 0] += secs
                if total > 0 { money[day, default: 0] += amount * secs / total }
            }
        }
        var out: [DayEarning] = []
        var running = 0.0
        var d = start
        while d <= end {
            let a = money[d] ?? 0
            running += a
            out.append(DayEarning(day: d, amount: (a * 100).rounded() / 100, seconds: time[d] ?? 0,
                                  cumulative: (running * 100).rounded() / 100))
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    /// Gains par projet pour une personne, du plus gros au plus petit.
    func projectEarnings(user: String, missions list: [Mission], limit: Int = 8) -> [ShareSlice] {
        let out = list.map { m -> ShareSlice in
            let share = myShare(of: m)
            let secs = mySplit[m.id]?.seconds ?? seconds(mission: m.id, user: user)
            return ShareSlice(id: m.id, name: m.title, colorHex: client(m.client_id)?.color ?? "8B8D94",
                              value: (share.amount * 100).rounded() / 100, seconds: secs,
                              estimated: share.estimated || !["validated", "paid"].contains(m.status))
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }
        return Self.uniqueNames(Array(out.prefix(limit)))
    }

    /// Les graphiques utilisent le nom comme catégorie : on le raccourcit et on évite les doublons.
    static func uniqueNames(_ list: [ShareSlice]) -> [ShareSlice] {
        var seen: [String: Int] = [:]
        return list.map { s in
            var name = s.name.count > 28 ? String(s.name.prefix(27)) + "…" : s.name
            let k = (seen[name] ?? 0) + 1
            seen[name] = k
            if k > 1 { name += " (\(k))" }
            return ShareSlice(id: s.id, name: name, colorHex: s.colorHex, value: s.value, seconds: s.seconds, estimated: s.estimated)
        }
    }
}
