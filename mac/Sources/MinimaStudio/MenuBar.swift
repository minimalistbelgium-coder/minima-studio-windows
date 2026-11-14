import SwiftUI
import AppKit

/// Chrono dans la barre des menus, à côté de l'heure.
/// Il tourne : « ⏱ 1:23 », en pause : « ⏸ 1:23 », sinon juste l'icône.
struct MenuBarLabel: View {
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        switch tracker.status {
        case .running:
            Text("\(Image(systemName: "timer")) \(MenuBarLabel.hm(tracker.totalSeconds))")
        case .paused, .askAway:
            if tracker.mission != nil {
                Text("\(Image(systemName: "pause.circle")) \(MenuBarLabel.hm(tracker.totalSeconds))")
            } else {
                Image(systemName: "timer")
            }
        default:
            Image(systemName: "timer")
        }
    }

    /// 1:23 (heures:minutes), assez court pour la barre des menus.
    static func hm(_ s: Double) -> String {
        let t = Int(max(0, s))
        return String(format: "%d:%02d", t / 3600, (t % 3600) / 60)
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var presenter: Presenter

    private var statusText: String {
        switch tracker.status {
        case .running: return tracker.manual ? "Chrono manuel en cours" : "Chrono en cours"
        case .paused(let why): return "En pause · \(why)"
        case .askAway: return "En pause · hors de Premiere"
        case .waiting: return tracker.premiereOpen ? "En attente d'un projet lié" : "Premiere fermé"
        case .noPermission: return "Autorisation Accessibilité manquante"
        case .disabled: return "Chrono désactivé"
        }
    }

    /// Prochaine livraison à venir (les miennes, ou toutes pour l'admin).
    private var nextDelivery: Mission? {
        let me = app.profile?.id
        return data.missions
            .filter { m in
                m.isOpen && m.status != "requested" && (m.deadlineDate ?? .distantPast) > Date()
                    && (app.isAdmin || (me.map { data.memberIds(of: m.id).contains($0) } ?? false))
            }
            .min { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
    }

    private func whenLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter(); f.locale = Locale(identifier: "fr_BE"); f.dateFormat = "HH:mm"
        if cal.isDateInToday(d) { return "aujourd'hui \(f.string(from: d))" }
        if cal.isDateInTomorrow(d) { return "demain \(f.string(from: d))" }
        f.dateFormat = "EEE d MMM HH:mm"
        return f.string(from: d)
    }

    @ViewBuilder private var nextDeliveryItem: some View {
        if let n = nextDelivery, let d = n.deadlineDate {
            Button("Prochaine livraison : \(n.title), \(whenLabel(d))") {
                if MiniWindow.shared.isVisible { MiniWindow.shared.hide(app: app) }
                app.showMainWindow()
                presenter.open(.existing(n.id))
            }
            Divider()
        }
    }

    var body: some View {
        if let m = tracker.mission {
            Text(m.title)
            Text("\(statusText) · \(LiveClock.format(tracker.totalSeconds)) sur la mission")
            if let r = tracker.hourlyRate() {
                Text("\(Money.eur(r.rounded())) / h · part estimée \(Money.eur((tracker.estimatedAmount ?? 0).rounded()))")
            }
            Divider()
            Button("Ouvrir la mission") {
                if MiniWindow.shared.isVisible { MiniWindow.shared.hide(app: app) }
                app.showMainWindow()
                presenter.open(.existing(m.id))
            }
        } else {
            Text(statusText)
            Divider()
        }
        nextDeliveryItem
        Button("Ouvrir Minima Studio") {
            if MiniWindow.shared.isVisible { MiniWindow.shared.hide(app: app) }
            app.showMainWindow()
        }
        Button("Mode mini") { MiniWindow.shared.show(app: app, data: data, tracker: tracker) }
        if tracker.manual {
            Button("Arrêter le chrono manuel") { Task { await tracker.stopManual() } }
        }
        Divider()
        Button("Quitter Minima Studio") { NSApp.terminate(nil) }
    }
}
