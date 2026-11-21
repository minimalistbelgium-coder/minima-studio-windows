import SwiftUI
import AppKit

/// Finances › Analyse : rentabilité détaillée sur le mois, le trimestre, l'année ou 12 mois.
/// Tout est calculé à partir des données déjà chargées (prix, budgets, heures du chrono).
struct FinanceAnalysis: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter
    let month: Date
    @State private var span = "m"

    private let cal = Calendar.current
    private func add(_ d: Date, _ n: Int) -> Date { cal.date(byAdding: .month, value: n, to: d) ?? d }

    /// Mois couverts par la période choisie.
    private var months: [Date] {
        let c = cal.dateComponents([.year, .month], from: month)
        let y = c.year ?? 2026, m = c.month ?? 1
        let first = { (yy: Int, mm: Int) in self.cal.date(from: DateComponents(year: yy, month: mm, day: 1)) ?? self.month }
        switch span {
        case "q": let q = ((m - 1) / 3) * 3 + 1; return (0..<3).map { first(y, q + $0) }
        case "y": return (1...12).map { first(y, $0) }
        case "12": return (0..<12).map { add(month, $0 - 11) }
        default: return [first(y, m)]
        }
    }

    private struct Totals { var billed = 0.0, cost = 0.0, n = 0; var margin: Double { billed - cost } }
    private func totals(endingAt end: Date, count: Int) -> Totals {
        var t = Totals()
        for p in data.monthlyFinance(endingAt: end, count: count) { t.billed += p.billed; t.cost += p.cost; t.n += p.missions }
        return t
    }

    private struct Rated: Identifiable { let m: Mission; let secs: Double; let margin: Double; var rate: Double { margin / (secs / 3600) }; var id: String { m.id } }
    private struct ClientLine: Identifiable { let id: String; let name: String; let hex: String; var billed = 0.0, cost = 0.0, n = 0 }

    private func pct(_ a: Double, _ b: Double) -> Int { b == 0 ? 0 : Int((a / b * 100).rounded()) }
    private var periodLabel: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_BE")
        switch span {
        case "q": f.dateFormat = "LLLL"; let a = f.string(from: months[0]); f.dateFormat = "LLLL yyyy"; return "\(a.capitalized) à \(f.string(from: months[2]))"
        case "y": f.dateFormat = "yyyy"; return "Année \(f.string(from: month))"
        case "12": f.dateFormat = "LLLL yyyy"; return "12 mois jusqu'à \(f.string(from: month))"
        default: f.dateFormat = "LLLL yyyy"; return f.string(from: month).capitalized
        }
    }

    var body: some View {
        let ms = months
        let last = ms[ms.count - 1]
        let list = data.missions(inMonths: ms).filter { $0.status != "requested" }
        let cur = totals(endingAt: last, count: ms.count)
        let prev = totals(endingAt: add(ms[0], -1), count: ms.count)
        let yoy = totals(endingAt: add(last, -12), count: ms.count)
        let secsBy = Dictionary(uniqueKeysWithValues: list.map { ($0.id, data.seconds(mission: $0.id)) })
        let hours = secsBy.values.reduce(0, +)
        let open = list.filter(\.isOpen)
        let openSum = open.compactMap { data.finances[$0.id]?.client_price }.reduce(0, +)
        let year = totals(endingAt: cal.date(from: DateComponents(year: cal.component(.year, from: month), month: 12, day: 1)) ?? month, count: 12)
        let leads: [Double] = list.compactMap { m in
            guard let v = m.v1_delivered_at.flatMap(DateFmt.parse), let c = DateFmt.parse(m.created_at) else { return nil }
            let d = v.timeIntervalSince(c) / 86400
            return d >= 0 ? d : nil
        }
        let trend = data.monthlyFinance(endingAt: month, count: 12)

        VStack(alignment: .leading, spacing: 22) {
            WidthReader { w in
                let layout = w < 640 ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ChipPicker(selection: $span, options: [
                        .init(value: "m", label: "Mois"), .init(value: "q", label: "Trimestre"),
                        .init(value: "y", label: "Année"), .init(value: "12", label: "12 mois"),
                    ])
                    Text(periodLabel).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    Spacer(minLength: 8)
                    Button { exportCSV(list, secsBy) } label: { Label("Exporter en CSV", systemImage: "square.and.arrow.up") }
                        .buttonStyle(SecondaryButton())
                }
            }

            StatGrid {
                StatCard(label: "Chiffre d'affaires", value: Money.eur(cur.billed.rounded()), foot: delta(cur.billed, prev.billed),
                         footColor: prev.billed > 0 ? (cur.billed >= prev.billed ? Theme.green : Theme.red) : Theme.muted)
                StatCard(label: "Marge nette", value: Money.eur(cur.margin.rounded()), foot: cur.billed > 0 ? "\(pct(cur.margin, cur.billed)) % du facturé" : nil,
                         footColor: cur.margin >= 0 ? Theme.green : Theme.red)
                StatCard(label: "Prix moyen par mission", value: cur.n > 0 ? Money.eur((cur.billed / Double(cur.n)).rounded()) : "–", foot: "\(cur.n) mission\(cur.n > 1 ? "s" : "")")
                StatCard(label: "Coût monteur moyen", value: cur.n > 0 ? Money.eur((cur.cost / Double(cur.n)).rounded()) : "–", foot: cur.billed > 0 ? "\(pct(cur.cost, cur.billed)) % du facturé" : nil)
                StatCard(label: "Marge par heure montée", value: hours >= 1800 ? "\(Int((cur.margin / (hours / 3600)).rounded())) €/h" : "–",
                         foot: hours >= 1800 ? "\(TimeFmt.hm(hours)) suivies par le chrono" : "pas assez d'heures suivies")
                StatCard(label: "Cumul \(String(cal.component(.year, from: month)))", value: Money.eur(year.billed.rounded()), foot: "marge \(Money.eur(year.margin.rounded()))")
                StatCard(label: "Encore en cours", value: Money.eur(openSum.rounded()),
                         foot: open.isEmpty ? "tout est livré" : "\(open.count) mission\(open.count > 1 ? "s" : "") pas encore livrée\(open.count > 1 ? "s" : "")",
                         footColor: open.isEmpty ? Theme.green : Theme.amber)
                StatCard(label: "Délai moyen jusqu'à la V1", value: leads.isEmpty ? "–" : String(format: "%.1f j", leads.reduce(0, +) / Double(leads.count)).replacingOccurrences(of: ".", with: ","),
                         foot: leads.isEmpty ? "aucune livraison sur la période" : "sur \(leads.count) mission\(leads.count > 1 ? "s" : "")")
            }

            EqualGrid(minWidth: 360, spacing: 16) {
                barsCard("Chiffre d'affaires · 12 mois", "moyenne \(Money.eur((trend.map(\.billed).reduce(0, +) / 12).rounded()))", trend, Theme.blue, { $0.billed }, { Money.eur($0.rounded()) })
                barsCard("Taux de marge · 12 mois", "en % du facturé", trend, Theme.green, { $0.billed > 0 ? $0.margin / $0.billed * 100 : 0 }, { "\(Int($0.rounded())) %" })
                barsCard("Missions par mois", "volume de production", trend, Theme.violet, { Double($0.missions) }, { "\(Int($0)) mission\(Int($0) > 1 ? "s" : "")" })
                barsCard("Payé aux monteurs · 12 mois", "ce que tu leur verses", trend, Theme.amber, { $0.cost }, { Money.eur($0.rounded()) })
            }

            clientsCard(list)
            editorsCard(list)
            ratedCards(list, secsBy)

            if yoy.billed > 0 {
                SectionTitle(text: "Comparaison avec l'an dernier", trailing: "même période, un an plus tôt")
                VStack(spacing: 0) {
                    compareRow("Chiffre d'affaires", cur.billed, yoy.billed, money: true)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    compareRow("Marge", cur.margin, yoy.margin, money: true)
                    Rectangle().fill(Theme.line).frame(height: 1)
                    compareRow("Missions", Double(cur.n), Double(yoy.n), money: false)
                }
                .card(padding: 0)
            }
        }
    }

    private func delta(_ a: Double, _ b: Double) -> String {
        guard b > 0 else { return "pas de période précédente" }
        return "\(a >= b ? "+" : "−") \(abs(pct(a - b, b))) % vs période précédente"
    }

    // MARK: graphiques

    private func barsCard(_ title: String, _ sub: String, _ pts: [MonthFinance], _ color: Color, _ val: @escaping (MonthFinance) -> Double, _ fmt: @escaping (Double) -> String) -> some View {
        let mx = Swift.max(1, pts.map(val).max() ?? 1)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.85)
                Text(sub).font(.system(size: 12.5)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(pts) { p in
                    let v = Swift.max(0, val(p))
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.opacity(0.9))
                            .frame(height: Swift.max(2, 120 * v / mx))
                        Text(String(p.label.prefix(1)).uppercased()).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .help("\(p.label) : \(fmt(val(p)))")
                }
            }
            .frame(height: 144)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: rentabilité

    private func line(_ color: Color, _ name: String, _ sub: String, _ value: String, _ small: String, _ share: Double) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(color).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(sub).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value).font(.system(size: 13.5, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1)
                    if !small.isEmpty { Text(small).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1) }
                }
                .layoutPriority(1)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color).frame(width: Swift.max(4, g.size.width * Swift.min(1, Swift.max(0, share))))
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    @ViewBuilder private func clientsCard(_ list: [Mission]) -> some View {
        let lines: [ClientLine] = {
            var d: [String: ClientLine] = [:]
            for m in list {
                let id = m.client_id ?? ""
                var l = d[id] ?? ClientLine(id: id.isEmpty ? "none" : id, name: data.client(id)?.name ?? "Sans client", hex: data.client(id)?.color ?? "8B8D94")
                l.billed += data.finances[m.id]?.client_price ?? 0; l.cost += data.editorPayout(m); l.n += 1
                d[id] = l
            }
            return d.values.filter { $0.billed > 0 || $0.cost > 0 }.sorted { $0.billed > $1.billed }
        }()
        let total = lines.map(\.billed).reduce(0, +)
        let dep = lines.count > 1 && total > 0 && (lines.first?.billed ?? 0) / total >= 0.4
        SectionTitle(text: "Rentabilité par client",
                     trailing: dep ? "\(lines[0].name) pèse \(pct(lines[0].billed, total)) % du chiffre : dépendance élevée" : "facturé, coût monteurs, marge et part du chiffre")
        VStack(spacing: 0) {
            if lines.isEmpty { EmptyHint(text: "Aucune mission suivie dans l'app sur cette période.") }
            ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                line(Color(hex: l.hex), l.name,
                     "\(l.n) mission\(l.n > 1 ? "s" : "") · coût \(Money.eur(l.cost.rounded())) · marge \(Money.eur((l.billed - l.cost).rounded())) (\(pct(l.billed - l.cost, l.billed)) %)",
                     Money.eur(l.billed.rounded()), total > 0 ? "\(pct(l.billed, total)) % du CA" : "", total > 0 ? l.billed / total : 0)
            }
        }
        .card(padding: 0)
    }

    @ViewBuilder private func editorsCard(_ list: [Mission]) -> some View {
        let eds = data.editorSlices(list)
        let mx = Swift.max(1, eds.map(\.value).max() ?? 1)
        SectionTitle(text: "Coût par monteur", trailing: "montant, heures suivies et coût horaire")
        VStack(spacing: 0) {
            if eds.isEmpty { EmptyHint(text: "Aucun monteur payé sur cette période.") }
            ForEach(Array(eds.enumerated()), id: \.element.id) { i, e in
                if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                line(Color(hex: e.colorHex), e.name, e.seconds > 0 ? "\(TimeFmt.hm(e.seconds)) de montage" : "pas de chrono",
                     Money.eur(e.value.rounded()), e.seconds >= 1800 ? "\(Int((e.value / (e.seconds / 3600)).rounded())) €/h" : "", e.value / mx)
            }
        }
        .card(padding: 0)
    }

    @ViewBuilder private func ratedCards(_ list: [Mission], _ secsBy: [String: Double]) -> some View {
        let rated: [Rated] = list.compactMap { m in
            guard let p = data.finances[m.id]?.client_price, p > 0, let s = secsBy[m.id], s >= 1800 else { return nil }
            return Rated(m: m, secs: s, margin: p - data.editorPayout(m))
        }.sorted { $0.rate > $1.rate }
        let best = Array(rated.prefix(3))
        let worst = rated.count > 3 ? Array(rated.suffix(Swift.min(3, rated.count - 3)).reversed()) : []
        SectionTitle(text: "Missions les plus rentables", trailing: "marge par heure de montage")
        ratedList(best, empty: "Il faut au moins 30 min de chrono sur une mission facturée.")
        if !worst.isEmpty {
            SectionTitle(text: "Missions les moins rentables", trailing: "à surveiller")
            ratedList(worst, empty: "")
        }
    }

    private func ratedList(_ rows: [Rated], empty: String) -> some View {
        VStack(spacing: 0) {
            if rows.isEmpty { EmptyHint(text: empty) }
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                Button { presenter.open(.existing(r.m.id)) } label: {
                    HStack(spacing: 12) {
                        Circle().fill(Color(hex: data.client(r.m.client_id ?? "")?.color ?? "8B8D94")).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.m.title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                            Text("\(data.client(r.m.client_id ?? "")?.name ?? "Sans client") · \(TimeFmt.hm(r.secs)) de montage · marge \(Money.eur(r.margin.rounded()))")
                                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(Int(r.rate.rounded())) €/h").font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(r.rate >= 0 ? Theme.green : Theme.red).layoutPriority(1)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card(padding: 0)
    }

    private func compareRow(_ title: String, _ a: Double, _ b: Double, money: Bool) -> some View {
        let f: (Double) -> String = { money ? Money.eur($0.rounded()) : String(Int($0)) }
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                Text("\(f(b)) l'an dernier").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(f(a))\(b > 0 ? " · \(a >= b ? "+" : "−") \(abs(pct(a - b, b))) %" : "")").font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
                .foregroundStyle(a >= b ? Theme.green : Theme.red)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    // MARK: export

    private func exportCSV(_ list: [Mission], _ secsBy: [String: Double]) {
        let q: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        var rows = [["Mois", "Client", "Mission", "Statut", "Prix client HTVA", "Monteurs", "Marge", "Heures de montage"].map(q).joined(separator: ";")]
        for m in list.sorted(by: { ($0.workMonth ?? .distantPast) < ($1.workMonth ?? .distantPast) }) {
            let p = data.finances[m.id]?.client_price ?? 0, pay = data.editorPayout(m)
            let num: (Double) -> String = { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") }
            rows.append([m.workMonth.map(f.string(from:)) ?? "", data.client(m.client_id ?? "")?.name ?? "", m.title, m.status, num(p), num(pay), num(p - pay), num((secsBy[m.id] ?? 0) / 3600)].map(q).joined(separator: ";"))
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "minima-studio-analyse-\(f.string(from: month)).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try ("\u{FEFF}" + rows.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8); app.showToast("Fichier CSV enregistré") }
        catch { app.showToast("Impossible d'enregistrer le fichier") }
    }
}
