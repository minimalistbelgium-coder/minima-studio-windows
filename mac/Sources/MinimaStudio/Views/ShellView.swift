import SwiftUI

enum Route: Hashable {
    // admin
    case today, missions, agenda, clients, team, finances, time, updates
    // monteur
    case myDashboard, myMissions, myFinances
    // client
    case clientProjects
}

struct ShellView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var presenter: Presenter
    @State private var route: Route = .today

    var body: some View {
        GeometryReader { g in
            let compact = g.size.width < 1060
            HStack(spacing: 0) {
                Sidebar(route: $route, compact: compact)
                    .frame(width: compact ? 68 : 236)
                Rectangle().fill(Theme.line).frame(width: 1)
                VStack(spacing: 0) {
                    UpdateBanner()
                    content.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environment(\.compactLayout, g.size.width < 980)
        }
        .background(Theme.bg)
        .overlay { PanelHost() }
        .onAppear { route = defaultRoute }
        .onChange(of: app.profile?.role) { _ in route = defaultRoute }
    }

    private var defaultRoute: Route {
        if app.isAdmin { return .today }
        if app.isClient { return .clientProjects }
        return .myDashboard
    }

    @ViewBuilder private var content: some View {
        if !data.loaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if app.isAdmin {
            switch route {
            case .missions: MissionsView()
            case .agenda: AgendaView()
            case .clients: ClientsView()
            case .team: TeamView()
            case .finances: FinancesView()
            case .time: TimeView()
            case .updates: UpdatesView()
            default: TodayView()
            }
        } else if app.isClient {
            switch route {
            case .agenda: AgendaView()
            default: ClientProjectsView()
            }
        } else {
            switch route {
            case .myMissions: MyMissionsView()
            case .agenda: AgendaView()
            case .myFinances: MyFinancesView()
            default: MyDashboardView()
            }
        }
    }
}

// MARK: - Panneau par-dessus la page (fermeture au clic à côté ou Échap)

struct PanelHost: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        ZStack {
            if presenter.isOpen {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { presenter.close() }
                    .transition(.opacity)

                Group {
                    if let t = presenter.mission {
                        MissionSheet(target: t, presetDeadline: presenter.presetDeadline, onClose: { presenter.close() })
                    }
                }
                .frame(maxHeight: 820)
                .padding(.horizontal, 24)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
                .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
                .padding(.vertical, 30)
                .onExitCommand { presenter.close() }
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.16), value: presenter.isOpen)
    }
}

// MARK: - Bandeau de mise à jour

struct UpdateBanner: View {
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        if let r = updater.updateAvailable {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouvelle version \(r.version) disponible").font(.system(size: 13, weight: .semibold))
                    if let n = r.notes, !n.isEmpty {
                        Text(n).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    if let e = updater.error {
                        Text(e).font(.system(size: 12)).foregroundStyle(Theme.red)
                    }
                }
                Spacer()
                if updater.installing {
                    ProgressView().controlSize(.small)
                    Text(updater.progressText ?? "").font(.system(size: 12)).foregroundStyle(Theme.muted)
                } else {
                    Button("Mettre à jour") { Task { @MainActor in await updater.install(r, tracker: tracker) } }
                        .buttonStyle(PrimaryButton())
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Theme.blue.opacity(0.1))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        }
    }
}

// MARK: - Barre latérale

private struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @Binding var route: Route
    var compact = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if compact {
                VStack(spacing: 14) {
                    AppLogo(size: 30)
                    NotificationBell()
                }
                .frame(maxWidth: .infinity).padding(.top, 38).padding(.bottom, 18)
            } else {
                HStack(spacing: 10) {
                    AppLogo(size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Minima Studio").font(.system(size: 14.5, weight: .semibold))
                        Text(app.profile?.roleLabel ?? "").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    NotificationBell()
                }
                .padding(.horizontal, 10).padding(.top, 38).padding(.bottom, 22)
            }

            if app.isAdmin {
                item("Aujourd'hui", "sun.max", .today, live: data.liveSessions.count)
                item("Missions", "film.stack", .missions, badge: data.missions.filter(\.isOpen).count)
                item("Agenda", "calendar", .agenda)
                item("Clients", "person.2", .clients)
                item("Équipe", "person.3", .team)
                section("Admin")
                item("Finances", "eurosign.circle", .finances)
                item("Analyse du temps", "clock", .time)
                item("Mises à jour", "arrow.down.circle", .updates)
            } else if app.isClient {
                item("Mes projets", "film.stack", .clientProjects)
                item("Calendrier", "calendar", .agenda)
            } else {
                item("Tableau de bord", "chart.bar", .myDashboard)
                item("Mes missions", "film.stack", .myMissions, badge: data.missions.filter(\.isOpen).count)
                item("Agenda", "calendar", .agenda)
                item("Finances", "eurosign.circle", .myFinances)
            }

            Spacer()

            if app.isTeam && !compact {
                TrackerCard()
                    .padding(.bottom, 10)
            }

            if let p = app.profile, compact {
                accountMenu { AvatarView(profile: p, size: 32) }
                    .frame(maxWidth: .infinity).padding(.bottom, 16)
            } else if let p = app.profile {
                HStack(spacing: 10) {
                    AvatarView(profile: p, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.displayName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text("\(p.roleLabel) · v\(AppVersion.current)").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    accountMenu { Image(systemName: "ellipsis").foregroundStyle(Theme.muted) }
                        .frame(width: 24)
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 14)
            }
        }
        .padding(.horizontal, compact ? 6 : 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "0F1013"))
    }

    private func accountMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        Menu {
            Button("Actualiser") { Task { @MainActor in await data.reload() } }
            Toggle("Ouvrir au démarrage du Mac", isOn: Binding(
                get: { launchAtLogin },
                set: { v in
                    do { try LaunchAtLogin.set(v); launchAtLogin = LaunchAtLogin.isEnabled }
                    catch { app.showToast("Impossible : \(error.localizedDescription)") }
                }))
            if app.isTeam {
                Button("Mode mini (⇧⌘M)") { MiniWindow.shared.show(app: app, data: data, tracker: tracker) }
                Button("Diagnostic du chrono") { DiagnosticWindow.show(tracker: tracker) }
            }
            Divider()
            Button("Se déconnecter") { Task { @MainActor in await app.signOut() } }
        } label: { label() }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    @ViewBuilder
    private func section(_ t: String) -> some View {
        if compact {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 12).padding(.horizontal, 8)
        } else {
        Text(t.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8)
            .foregroundStyle(Theme.muted.opacity(0.8))
            .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 6)
        }
    }

    private func item(_ title: String, _ icon: String, _ r: Route, badge: Int = 0, live: Int = 0) -> some View {
        let active = route == r
        if compact {
            return AnyView(Button { route = r } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon).font(.system(size: 15))
                        .foregroundStyle(active ? Theme.blue : Theme.muted)
                        .frame(width: 44, height: 40)
                        .background(active ? Theme.card2 : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    if live > 0 { Circle().fill(Theme.green).frame(width: 7, height: 7).offset(x: -6, y: 6) }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(title))
        }
        return AnyView(Button { route = r } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                    .foregroundStyle(active ? Theme.blue : Theme.muted)
                Text(title).font(.system(size: 13.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Theme.text : Theme.text2)
                Spacer()
                if live > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.green).frame(width: 6, height: 6)
                        Text("\(live)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green)
                    }
                    .help("\(live) personne(s) en train de monter")
                }
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(active ? Theme.card2 : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain))
    }
}

/// Chrono dans la barre latérale.
struct TrackerCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                StatusDot(status: tracker.status)
                Text(tracker.mission?.title ?? "Chrono").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Button {
                    MiniWindow.shared.show(app: app, data: data, tracker: tracker)
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                .help("Mode mini (⇧⌘M)")
            }
            HStack(alignment: .firstTextBaseline) {
                LiveClock(tracker: tracker, size: 20)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    if let mx = tracker.maxAmount {
                        Text(Money.eur(mx)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Theme.green).help("À la clé sur cette mission")
                    }
                    TimelineView(.periodic(from: .now, by: 5)) { ctx in
                        if let r = tracker.hourlyRate(at: ctx.date) {
                            Text("\(Money.eur(r.rounded())) / h").font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            TrackerHint()
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
    }
}


// MARK: - Mise en page compacte (fenêtre étroite)

private struct CompactLayoutKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}
