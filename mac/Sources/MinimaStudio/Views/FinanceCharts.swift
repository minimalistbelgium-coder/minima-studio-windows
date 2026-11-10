import SwiftUI
import Charts

// Règle pour tous les graphiques de ce fichier : le survol ne change jamais la géométrie.
//   - les lectures au-dessus du graphique ont une largeur et une hauteur fixes ;
//   - le contenu du Chart (marques, axes, domaines) ne dépend pas du survol ;
//   - le repère de survol est dessiné dans un calque posé par-dessus (chartOverlay) ;
//   - aucune animation n'est déclenchée par le survol.
// Sinon la carte change de taille sous la souris, ce qui relance le survol : le graphique tremble.

// MARK: - Petits éléments communs aux graphiques

/// Valeur mise en avant au-dessus d'un graphique (elle suit le survol).
/// Sa taille ne dépend pas du texte affiché : il se réduit ou se tronque dans sa case.
private struct Readout: View {
    let label: String
    let value: String
    var color: Color = Theme.text
    var dot: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.6)
                    .foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 13)
            Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 38)
    }
}

/// Rangée de lectures de même largeur, quelle que soit la valeur affichée.
private struct ReadoutRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 14) { content() }
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38)
    }
}

private struct SeriesPoint: Identifiable {
    let label: String
    let series: String
    let value: Double
    var id: String { label + series }
}

/// Change l'état de survol sans animation.
private func setHover<T: Equatable>(_ binding: Binding<T?>, _ value: T?) {
    guard binding.wrappedValue != value else { return }
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t) { binding.wrappedValue = value }
}

// MARK: - Admin : évolution sur 12 mois

/// Facturé, budget équipe et marge sur 12 mois. Survol : valeurs du mois. Clic : sélectionne le mois.
struct FinanceTrendCard: View {
    let points: [MonthFinance]
    @Binding var month: Date
    @State private var mode: Int
    @State private var hover: String?

    /// `previewMode` et `previewHover` servent aux captures de mise en page (survol simulé).
    init(points: [MonthFinance], month: Binding<Date>, previewMode: Int = 0, previewHover: String? = nil) {
        self.points = points
        _month = month
        _mode = State(initialValue: previewMode)
        _hover = State(initialValue: previewHover)
    }

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

    /// Échelle verticale fixe, calculée sur les 12 mois (elle ne bouge pas au survol).
    private var yDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.billed, $0.cost, $0.margin] }
        let hi = Swift.max(values.max() ?? 0, 1)
        let lo = Swift.min(values.min() ?? 0, 0)
        return (lo * 1.12)...(hi * 1.12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(text: "Évolution sur 12 mois") {
                ChipPicker(selection: $mode, options: [
                    .init(value: 0, label: "Barres"),
                    .init(value: 1, label: "Courbes"),
                ])
            }
            readouts
            if hasData {
                chart.frame(height: 240)
                Muted("Survole un mois pour voir ses chiffres, clique pour l'ouvrir en détail plus bas.", size: 11.5)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            } else {
                EmptyHint(text: "Pas encore de chiffres sur ces 12 mois. Renseigne les prix clients dans les missions.", icon: "chart.bar.xaxis")
                    .frame(height: 200)
            }
        }
        .card()
    }

    /// Quatre cases fixes : le mois, puis une case par série (la pastille sert de légende).
    private var readouts: some View {
        let f = focus
        let n = f?.missions ?? 0
        let margin = f?.margin ?? 0
        return ReadoutRow {
            Readout(label: f.map { Self.title($0.month) } ?? "Mois", value: "\(n) mission\(n > 1 ? "s" : "")")
            Readout(label: ChartSeries.billed, value: Money.eur((f?.billed ?? 0).rounded()), color: Theme.blue, dot: Theme.blue)
            Readout(label: ChartSeries.cost, value: Money.eur((f?.cost ?? 0).rounded()), color: Theme.amber, dot: Theme.amber)
            Readout(label: ChartSeries.margin, value: Money.eur(margin.rounded()),
                    color: margin >= 0 ? Theme.green : Theme.red, dot: Theme.green)
        }
    }

    private var chart: some View {
        Chart {
            if mode == 0 { bars } else { lines }
        }
        .chartForegroundStyleScale([ChartSeries.billed: Theme.blue, ChartSeries.cost: Theme.amber, ChartSeries.margin: Theme.green])
        .chartLegend(.hidden)
        .chartXScale(domain: points.map(\.label))
        .chartYScale(domain: yDomain)
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
                        // Même graisse pour tous les mois : seule la couleur signale le mois choisi.
                        Text(s).font(.system(size: 11, weight: .medium))
                            .foregroundStyle(s == selected?.label ? Theme.blue : Theme.muted)
                    }
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                // Mois sélectionné (clic) : bande teintée derrière les marques.
                band(selected?.label, proxy: proxy, plot: geo[proxy.plotAreaFrame], color: Theme.blue.opacity(0.09))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = geo[proxy.plotAreaFrame]
                // Mois survolé : calque séparé, le Chart lui-même ne change pas.
                band(hover, proxy: proxy, plot: plot, color: Theme.ink.opacity(0.07))
                if mode == 1 { hoverDots(proxy: proxy, plot: plot) }
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            let v: String? = plot.contains(p) ? proxy.value(atX: p.x - plot.minX, as: String.self) : nil
                            setHover($hover, v)
                        case .ended:
                            setHover($hover, nil)
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { g in
                        let v: String? = proxy.value(atX: g.location.x - plot.minX, as: String.self)
                        if let p = points.first(where: { $0.label == v }) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { month = p.month }
                        }
                    })
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
    }

    /// Bande verticale sur la colonne d'un mois.
    @ViewBuilder
    private func band(_ label: String?, proxy: ChartProxy, plot: CGRect, color: Color) -> some View {
        if let label, let x = proxy.position(forX: label), plot.width > 0 {
            let step = plot.width / CGFloat(Swift.max(points.count, 1))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)
                .frame(width: Swift.max(6, step - 6), height: plot.height)
                .position(x: plot.minX + x, y: plot.midY)
                .allowsHitTesting(false)
        }
    }

    /// Points du mois survolé sur les courbes.
    @ViewBuilder
    private func hoverDots(proxy: ChartProxy, plot: CGRect) -> some View {
        if let h = hover, let p = points.first(where: { $0.label == h }), let x = proxy.position(forX: h) {
            dot(p.billed, Theme.blue, x: x, proxy: proxy, plot: plot)
            dot(p.cost, Theme.amber, x: x, proxy: proxy, plot: plot)
            dot(p.margin, Theme.green, x: x, proxy: proxy, plot: plot)
        }
    }

    @ViewBuilder
    private func dot(_ value: Double, _ color: Color, x: CGFloat, proxy: ChartProxy, plot: CGRect) -> some View {
        if let y = proxy.position(forY: value) {
            Circle().fill(color)
                .frame(width: 9, height: 9)
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 1.5))
                .position(x: plot.minX + x, y: plot.minY + y)
                .allowsHitTesting(false)
        }
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
                .symbolSize(22)
        }
    }

    static func title(_ d: Date) -> String {
        let s = d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

// MARK: - Répartition en barres horizontales (par client, par monteur, par projet)

/// Barres dessinées à la main (pas de Chart) : chaque ligne a une hauteur fixe, le nom se tronque
/// proprement quand la carte est étroite, et le survol ne déplace rien.
struct SliceBarsCard: View {
    let title: String
    var subtitle: String?
    let slices: [ShareSlice]
    var empty: String
    /// Affiche le temps passé et le taux horaire dans le détail survolé.
    var showTime: Bool
    @State private var hover: String?

    private static let rowHeight: CGFloat = 38

    /// `previewHover` sert aux captures de mise en page (survol simulé).
    init(title: String, subtitle: String? = nil, slices: [ShareSlice],
         empty: String = "Rien à afficher sur cette période.", showTime: Bool = false, previewHover: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.slices = slices
        self.empty = empty
        self.showTime = showTime
        _hover = State(initialValue: previewHover)
    }

    private var total: Double { slices.map(\.value).reduce(0, +) }
    private var top: Double { slices.map(\.value).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle(text: title) { Muted(Money.eur(total.rounded()), size: 12.5).lineLimit(1).fixedSize() }
            // Ligne de détail toujours présente, sur une seule ligne : sa hauteur ne change pas au survol.
            Text(detail ?? " ").font(.system(size: 12)).foregroundStyle(Theme.muted)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 16)
            if slices.isEmpty {
                EmptyHint(text: empty, icon: "chart.bar.doc.horizontal")
            } else {
                rows
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

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(slices) { s in row(s) }
        }
        .padding(.horizontal, -8)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                // Hauteur de ligne fixe : la ligne survolée se déduit de la position, sans mesure.
                let i = Int((p.y / Self.rowHeight).rounded(.down))
                setHover($hover, slices.indices.contains(i) ? slices[i].name : nil)
            case .ended:
                setHover($hover, nil)
            }
        }
    }

    private func row(_ s: ShareSlice) -> some View {
        let on = hover == s.name
        let share = top > 0 ? CGFloat(s.value / top) : 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(s.name).font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(Money.eur(s.value.rounded())).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .foregroundStyle(Theme.text2).lineLimit(1).fixedSize()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.ink.opacity(0.06))
                    Capsule().fill(Color(hex: s.colorHex)).frame(width: Swift.max(5, g.size.width * share))
                }
            }
            .frame(height: 7)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(Theme.ink.opacity(on ? 0.05 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(hover == nil || on ? 1 : 0.45)
    }
}

// MARK: - Monteur : gains par jour

/// Courbe des gains par jour (ou cumulés). Survol : détail du jour.
struct DailyEarningsCard: View {
    let title: String
    let days: [DayEarning]
    var empty: String
    @State private var cumulative: Bool
    @State private var hover: Date?

    /// `previewHover` sert aux captures de mise en page (survol simulé).
    init(title: String, days: [DayEarning],
         empty: String = "Pas encore de temps enregistré sur cette période. Tes gains apparaissent ici dès que tu montes.",
         previewCumulative: Bool = false, previewHover: Date? = nil) {
        self.title = title
        self.days = days
        self.empty = empty
        _cumulative = State(initialValue: previewCumulative)
        _hover = State(initialValue: previewHover)
    }

    private static let fr = Locale(identifier: "fr_BE")
    private var total: Double { days.map(\.amount).reduce(0, +) }
    private var seconds: Double { days.map(\.seconds).reduce(0, +) }
    private var focus: DayEarning? { hover.flatMap { h in days.first { $0.day == h } } }
    private func value(_ d: DayEarning) -> Double { cumulative ? d.cumulative : d.amount }

    /// Échelles fixes (elles ne dépendent que des données et du mode, jamais du survol).
    private var yDomain: ClosedRange<Double> {
        let hi = days.map { value($0) }.max() ?? 0
        return 0...(Swift.max(hi, 1) * 1.15)
    }

    private var xDomain: ClosedRange<Date> {
        let first = days.first?.day ?? Date()
        let last = days.last?.day ?? first
        return first...(last > first ? last : first.addingTimeInterval(86_400))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardTitle(text: title) {
                ChipPicker(selection: $cumulative, options: [
                    .init(value: false, label: "Par jour"),
                    .init(value: true, label: "Cumulé"),
                ])
            }
            readouts
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

    /// Toujours trois cases : seul leur contenu change au survol.
    private var readouts: some View {
        let best = days.map(\.amount).max() ?? 0
        return ReadoutRow {
            if let f = focus {
                Readout(label: Self.dayLabel(f.day), value: Money.eur(f.amount), color: Theme.green)
                Readout(label: "Temps ce jour", value: TimeFmt.hm(f.seconds))
                Readout(label: "Cumul à ce jour", value: Money.eur(f.cumulative.rounded()))
            } else {
                Readout(label: "Total période", value: Money.eur(total.rounded()), color: Theme.green)
                Readout(label: "Temps", value: TimeFmt.hm(seconds))
                Readout(label: "Meilleur jour", value: Money.eur(best.rounded()))
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(days) { d in
                AreaMark(x: .value("Jour", d.day), y: .value("Gains", value(d)))
                    .foregroundStyle(LinearGradient(colors: [Theme.green.opacity(0.30), Theme.green.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Jour", d.day), y: .value("Gains", value(d)))
                    .foregroundStyle(Theme.green)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
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
                let plot = geo[proxy.plotAreaFrame]
                // Repère du jour survolé : calque séparé, le Chart lui-même ne change pas.
                marker(proxy: proxy, plot: plot)
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            setHover($hover, plot.contains(p) ? day(at: p.x - plot.minX, proxy: proxy) : nil)
                        case .ended:
                            setHover($hover, nil)
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: cumulative)
    }

    /// Jour le plus proche de la position survolée (parmi les jours affichés).
    private func day(at x: CGFloat, proxy: ChartProxy) -> Date? {
        guard let v = proxy.value(atX: x, as: Date.self) else { return nil }
        let d = Calendar.current.startOfDay(for: v.addingTimeInterval(43_200))
        return days.contains { $0.day == d } ? d : nil
    }

    @ViewBuilder
    private func marker(proxy: ChartProxy, plot: CGRect) -> some View {
        if let f = focus, let x = proxy.position(forX: f.day), let y = proxy.position(forY: value(f)) {
            Rectangle().fill(Theme.ink.opacity(0.22))
                .frame(width: 1, height: plot.height)
                .position(x: plot.minX + x, y: plot.midY)
                .allowsHitTesting(false)
            Circle().fill(Theme.green)
                .frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                .position(x: plot.minX + x, y: plot.minY + y)
                .allowsHitTesting(false)
        }
    }

    private static func dayLabel(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(fr))
    }
}
