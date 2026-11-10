import SwiftUI

/// Heures effectives par jour (temps actif mesuré dans Premiere), semaine par semaine.
/// Une seule personne : barres par jour. Plusieurs : tableau personne × jour.
struct DailyHoursCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    let people: [Profile]
    let title: String
    @State private var weekOffset = 0
    /// Largeur du conteneur de la carte (la carte retire ensuite ses marges).
    @Environment(\.layoutWidth) private var width

    /// Largeur minimale du tableau personne × jour. En dessous, il défile horizontalement.
    private static let minGrid: CGFloat = 520

    private var days: [Date] {
        let start = AgendaCal.cal.date(byAdding: .day, value: 7 * weekOffset, to: AgendaCal.weekStart(Date())) ?? Date()
        return AgendaCal.week(start)
    }

    /// Secondes par « utilisateur|jour ».
    private var table: [String: Double] {
        let ids = Set(people.map(\.id))
        var out: [String: Double] = [:]
        for s in data.sessions where ids.contains(s.user_id) {
            guard let d = DateFmt.parse(s.started_at) else { continue }
            out["\(s.user_id)|\(AgendaCal.day(d).timeIntervalSince1970)", default: 0] += Double(s.duration_sec ?? 0)
        }
        return out
    }

    var body: some View {
        let t = table
        let ds = days
        let cell: (String, Date) -> Double = { u, d in t["\(u)|\(d.timeIntervalSince1970)"] ?? 0 }
        let dayTotal: (Date) -> Double = { d in people.reduce(0) { $0 + cell($1.id, d) } }
        let week = ds.reduce(0) { $0 + dayTotal($1) }

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Muted("Temps actif dans Premiere · \(TimeFmt.hm(week)) sur la semaine", size: 12)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    AgendaNavButton(icon: "chevron.left") { weekOffset -= 1 }
                    Text(weekOffset == 0 ? "Cette semaine" : AgendaCal.weekLabel(ds[0]))
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.8).frame(width: 116)
                    AgendaNavButton(icon: "chevron.right") { if weekOffset < 0 { weekOffset += 1 } }
                        .opacity(weekOffset < 0 ? 1 : 0.35)
                }
            }
            if people.count == 1 {
                bars(ds, dayTotal)
            } else if width - 40 >= Self.minGrid {
                grid(ds, cell, dayTotal, week)
            } else {
                // Carte trop étroite pour 7 colonnes lisibles : le tableau garde sa largeur et défile.
                ScrollView(.horizontal, showsIndicators: true) {
                    grid(ds, cell, dayTotal, week)
                        .frame(width: Self.minGrid)
                        .padding(.bottom, 12)
                }
            }
        }
        .card()
    }

    private func dayLabel(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).locale(AgendaCal.fr)).replacingOccurrences(of: ".", with: "")
    }

    private func bars(_ ds: [Date], _ total: @escaping (Date) -> Double) -> some View {
        let maxV = max(3600, ds.map(total).max() ?? 0)
        return HStack(alignment: .bottom, spacing: 10) {
            ForEach(ds, id: \.self) { d in
                let v = total(d)
                let today = AgendaCal.cal.isDateInToday(d)
                VStack(spacing: 6) {
                    Text(v > 0 ? TimeFmt.hm(v) : " ").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.text2)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [Theme.blue, Theme.blue.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                                .frame(height: g.size.height * v / maxV)
                        }
                    }
                    .frame(maxWidth: 44).frame(height: 110)
                    .background(Theme.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    Text("\(dayLabel(d)) \(AgendaCal.cal.component(.day, from: d))")
                        .font(.system(size: 11.5, weight: today ? .semibold : .regular))
                        .foregroundStyle(today ? Theme.blue : Theme.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(_ ds: [Date], _ cell: @escaping (String, Date) -> Double, _ total: @escaping (Date) -> Double, _ week: Double) -> some View {
        let active = people.filter { p in ds.contains { cell(p.id, $0) > 0 } }
        // Carte étroite : colonnes du nom et du total resserrées pour garder 7 jours lisibles.
        let tight = width - 40 < 620
        let nameW: CGFloat = tight ? 92 : 110
        let weekW: CGFloat = tight ? 62 : 76
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Color.clear.frame(width: nameW, height: 1)
                ForEach(ds, id: \.self) { d in
                    let today = AgendaCal.cal.isDateInToday(d)
                    VStack(spacing: 2) {
                        Text(dayLabel(d).capitalized).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(today ? Theme.blue : Theme.muted).lineLimit(1)
                        Text("\(AgendaCal.cal.component(.day, from: d))").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(today ? Theme.blue : Theme.text2).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                Muted("Semaine", size: 11).lineLimit(1).frame(width: weekW)
            }
            if active.isEmpty { Muted("Aucun temps enregistré cette semaine.").padding(.vertical, 10) }
            ForEach(active) { p in
                HStack(spacing: 4) {
                    HStack(spacing: 8) {
                        AvatarView(profile: p, size: 22)
                        Text(p.id == app.profile?.id ? "Moi" : p.firstName).font(.system(size: 13)).lineLimit(1)
                    }
                    .frame(width: nameW, alignment: .leading)
                    ForEach(ds, id: \.self) { d in
                        let v = cell(p.id, d)
                        let today = AgendaCal.cal.isDateInToday(d)
                        Text(v > 0 ? TimeFmt.hm(v) : "·").font(.system(size: 12.5)).monospacedDigit()
                            .foregroundStyle(v > 0 ? Theme.text : Theme.muted)
                            .lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background(v > 0 ? Theme.blue.opacity(0.08 + 0.4 * min(1, v / 28800)) : Theme.ink.opacity(0.025),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(today ? Theme.blue.opacity(0.45) : .clear))
                    }
                    Text(TimeFmt.hm(ds.reduce(0) { $0 + cell(p.id, $1) })).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75)
                        .frame(width: weekW, height: 34)
                        .background(Theme.ink.opacity(0.025), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if active.count > 1 {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 2)
                HStack(spacing: 4) {
                    Text("Total").font(.system(size: 13, weight: .semibold)).frame(width: nameW, alignment: .leading)
                    ForEach(ds, id: \.self) { d in
                        Text(total(d) > 0 ? TimeFmt.hm(total(d)) : "").font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.text2).lineLimit(1).minimumScaleFactor(0.75).frame(maxWidth: .infinity)
                    }
                    Text(TimeFmt.hm(week)).font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.75).frame(width: weekW)
                }
            }
        }
    }
}
