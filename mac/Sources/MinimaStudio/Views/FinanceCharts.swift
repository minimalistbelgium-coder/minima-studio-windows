import SwiftUI
import Charts

// MARK: - Petits éléments communs aux graphiques

private struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }
}

/// Valeur mise en avant au-dessus d'un graphique (elle suit le survol).
private struct Readout: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted).lineLimit(1)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(minWidth: 84, alignment: .leading)
    }
}

private struct SeriesPoint: Identifiable {
    let label: String
    let series: String
    let value: Double
    var id: String { label + series }
}

// MARK: - Admin : évolution sur 12 mois

/// Facturé, budget équipe et marge sur 12 mois. Survol : valeurs du mois. Clic : sélectionne le mois.
struct FinanceTrendCard: View {
    let points: [MonthFinance]
    @Binding var month: Date
    @State private var mode = 0
    @State private var hover: String?

    private var flat: [SeriesPoint] {
        points.flatMap { p in
            [SeriesPoint(label: p.label, series: ChartSeries.billed, value: p.billed),
             SeriesPoint(label: p.label, series: ChartSeries.cost, value: p.cost),
             SeriesPoint(label: p.label, series: ChartSeries.margin, value: p.margin)]
        }
    }

    private var selected: MonthFinance? { points.first { $0.month == month } }
    private var focus: MonthFinance? { points.first { $0.label == hover } ?? selected }
    private var hasData: Bool { points.contains { $0.billed != 0 || $0.cost != 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(text: "Évolution sur 12 mois") {
                ChipPicker(selection: $mode, options: [
                    .init(value: 0, label: "Barres"),
                    .init(value: 1, label: "Courbes"),
                ])
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 22) { readouts; Spacer(minLength: 8); legend }
                VStack(alignment: .leading, spacing: 10) { HStack(spacing: 22) { readouts }; legend }
            }
            if hasData {
                chart.frame(height: 240)
                Muted("Survole un mois pour voir ses chiffres, clique pour l'ouvrir en détail plus bas.", size: 11.5)
            } else {
                EmptyHint(text: "Pas encore de chiffres sur ces 12 mois. Renseigne les prix clients dans les missions.", icon: "chart.bar.xaxis")
                    .frame(height: 200)
            }
        }
        .card()
    }

    @ViewBuilder private var readouts: some View {
        let f = focus
        Readout(label: f.map { Self.title($0.month) } ?? "Mois", value: "\(f?.missions ?? 0) mission\((f?.missions ?? 0) > 1 ? "s" : "")")
        Readout(label: ChartSeries.billed, value: Money.eur((f?.billed ?? 0).rounded()), color: Theme.blue)
        Readout(label: ChartSeries.cost, value: Money.eur((f?.cost ?? 0).rounded()), color: Theme.amber)
        Readout(label: ChartSeries.margin, value: Money.eur((f?.margin ?? 0).rounded()),
                color: (f?.margin ?? 0) >= 0 ? Theme.green : Theme.red)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            LegendDot(color: Theme.blue, text: ChartSeries.billed)
            LegendDot(color: Theme.amber, text: ChartSeries.cost)
            LegendDot(color: Theme.green, text: ChartSeries.margin)
        }
    }

    private var chart: some View {
        Chart {
            if let f = focus {
                RuleMark(x: .value("Mois", f.label))
                    .foregroundStyle(Theme.ink.opacity(0.07))
                    .lineStyle(StrokeStyle(lineWidth: 34, lineCap: .round))
            }
            if mode == 0 { bars } else { lines }
        }
        .chartForegroundStyleScale([ChartSeries.billed: Theme.blue, ChartSeries.cost: Theme.amber, ChartSeries.margin: Theme.green])
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(Money.short(d)).font(.system(size: 10.5)).foregroundStyle(Theme.muted) }
                }
            }
        }
        .chartXAxis {
            AxisMarks { v in
                AxisValueLabel {
                    if let s = v.as(String.self) {
                        Text(s).font(.system(size: 11, weight: s == selected?.label ? .semibold : .regular))
                            .foregroundStyle(s == selected?.label ? Theme.blue : Theme.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let x = p.x - geo[proxy.plotAreaFrame].origin.x
                            let v: String? = proxy.value(atX: x)
                            if v != hover { hover = v }
                        case .ended:
                            hover = nil
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { g in
                        let x = g.location.x - geo[proxy.plotAreaFrame].origin.x
                        let v: String? = proxy.value(atX: x)
                        if let p = points.first(where: { $0.label == v }) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { month = p.month }
                        }
                    })
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
    }

    @ChartContentBuilder private var bars: some ChartContent {
        ForEach(flat) { p in
            BarMark(x: .value("Mois", p.label), y: .value("Montant", p.value))
                .foregroundStyle(by: .value("Série", p.series))
                .position(by: .value("Série", p.series))
                .cornerRadius(3)
        }
    }

    @ChartContentBuilder private var lines: some ChartContent {
        ForEach(points) { p in
            AreaMark(x: .value("Mois", p.label), y: .value("Montant", p.billed))
                .foregroundStyle(LinearGradient(colors: [Theme.blue.opacity(0.22), Theme.blue.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
        }
        ForEach(flat) { p in
            LineMark(x: .value("Mois", p.label), y: .value("Montant", p.value))
                .foregroundStyle(by: .value("Série", p.series))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            PointMark(x: .value("Mois", p.label), y: .value("Montant", p.value))
                .foregroundStyle(by: .value("Série", p.series))
                .symbolSize(p.label == focus?.label ? 70 : 22)
        }
    }

    static func title(_ d: Date) -> String {
        let s = d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

// MARK: - Répartition en barres horizontales (par client, par monteur, par projet)

struct SliceBarsCard: View {
    let title: String
    var subtitle: String? = nil
    let slices: [ShareSlice]
    var empty = "Rien à afficher sur cette période."
    /// Affiche le temps passé et le taux horaire dans le détail survolé.
    var showTime = false
    @State private var hover: String?

    private var total: Double { slices.map(\.value).reduce(0, +) }
    private var top: Double { slices.map(\.value).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardTitle(text: title) { Muted(Money.eur(total.rounded()), size: 12.5) }
            if let line = detail { Muted(line, size: 12).lineLimit(1) }
            if slices.isEmpty {
                EmptyHint(text: empty, icon: "chart.bar.doc.horizontal")
            } else {
                chart.frame(height: CGFloat(slices.count) * 34 + 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private var detail: String? {
        guard let s = slices.first(where: { $0.name == hover }) else { return subtitle }
        var parts = [s.name, Money.eur(s.value)]
        if total > 0 { parts.append("\(Int((s.value / total * 100).rounded())) % du total") }
        if showTime, s.seconds >= 60 {
            parts.append(TimeFmt.hm(s.seconds))
            if s.seconds >= 300 { parts.append("\(Money.eur((s.value / (s.seconds / 3600)).rounded())) / h") }
        }
        if s.estimated { parts.append("estimation") }
        return parts.joined(separator: " · ")
    }

    private var chart: some View {
        Chart(slices) { s in
            BarMark(x: .value("Montant", s.value), y: .value("Nom", s.name), height: .fixed(16))
                .foregroundStyle(Color(hex: s.colorHex))
                .cornerRadius(5)
                .opacity(hover == nil || hover == s.name ? 1 : 0.4)
                .annotation(position: .trailing, alignment: .leading, spacing: 8) {
                    Text(Money.eur(s.value.rounded())).font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.text2)
                }
        }
        .chartXScale(domain: 0...Swift.max(1, top * 1.28))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading) { v in
                AxisValueLabel {
                    if let s = v.as(String.self) {
                        Text(s).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(1)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let y = p.y - geo[proxy.plotAreaFrame].origin.y
                            let v: String? = proxy.value(atY: y)
                            if v != hover { hover = v }
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Monteur : gains par jour

/// Courbe des gains par jour (ou cumulés). Survol : détail du jour.
struct DailyEarningsCard: View {
    let title: String
    let days: [DayEarning]
    var empty = "Pas encore de temps enregistré sur cette période. Tes gains apparaissent ici dès que tu montes."
    @State private var cumulative = false
    @State private var hover: Date?

    private static let fr = Locale(identifier: "fr_BE")
    private var total: Double { days.map(\.amount).reduce(0, +) }
    private var seconds: Double { days.map(\.seconds).reduce(0, +) }
    private var focus: DayEarning? { hover.flatMap { h in days.first { $0.day == h } } }
    private func value(_ d: DayEarning) -> Double { cumulative ? d.cumulative : d.amount }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(text: title) {
                ChipPicker(selection: $cumulative, options: [
                    .init(value: false, label: "Par jour"),
                    .init(value: true, label: "Cumulé"),
                ])
            }
            HStack(alignment: .bottom, spacing: 22) {
                if let f = focus {
                    Readout(label: Self.dayLabel(f.day), value: Money.eur(value(f)), color: Theme.green)
                    Readout(label: "Temps ce jour", value: TimeFmt.hm(f.seconds))
                } else {
                    Readout(label: "Total sur la période", value: Money.eur(total.rounded()), color: Theme.green)
                    Readout(label: "Temps", value: TimeFmt.hm(seconds))
                    Readout(label: "Meilleur jour", value: Money.eur((days.map(\.amount).max() ?? 0).rounded()))
                }
                Spacer(minLength: 0)
            }
            if total > 0 {
                chart.frame(height: 200)
                Muted("Le montant de chaque mission est réparti sur tes jours de travail, selon le temps passé chaque jour.", size: 11.5)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                EmptyHint(text: empty, icon: "chart.xyaxis.line").frame(height: 160)
            }
        }
        .card()
    }

    private var chart: some View {
        Chart {
            ForEach(days) { d in
                AreaMark(x: .value("Jour", d.day, unit: .day), y: .value("Gains", value(d)))
                    .foregroundStyle(LinearGradient(colors: [Theme.green.opacity(0.30), Theme.green.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Jour", d.day, unit: .day), y: .value("Gains", value(d)))
                    .foregroundStyle(Theme.green)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            if let f = focus {
                RuleMark(x: .value("Jour", f.day, unit: .day))
                    .foregroundStyle(Theme.ink.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Jour", f.day, unit: .day), y: .value("Gains", value(f)))
                    .foregroundStyle(Theme.green)
                    .symbolSize(80)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { v in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let d = v.as(Double.self) { Text(Money.short(d)).font(.system(size: 10.5)).foregroundStyle(Theme.muted) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 16 ? 5 : 2)) { v in
                AxisValueLabel {
                    if let d = v.as(Date.self) {
                        Text(d.formatted(.dateTime.day().month(.abbreviated).locale(Self.fr)))
                            .font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let x = p.x - geo[proxy.plotAreaFrame].origin.x
                            let v: Date? = proxy.value(atX: x)
                            let day = v.map { Calendar.current.startOfDay(for: $0) }
                            if day != hover { hover = day }
                        case .ended:
                            hover = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: cumulative)
    }

    private static func dayLabel(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
    }
}
