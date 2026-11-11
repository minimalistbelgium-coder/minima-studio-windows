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
    /// Page ouverte au lancement (sinon celle du rôle). Sert aux captures de mise en page.
    var initialRoute: Route? = nil

    init(initialRoute: Route? = nil) { self.initialRoute = initialRoute }

    /// Sous cette largeur de fenêtre, la barre latérale se replie en icônes.
    static let sidebarBreak: CGFloat = 1120

    var body: some View {
        GeometryReader { g in
            // Tout découle de la largeur de la fenêtre : barre latérale, marges et dispositions des pages.
            let compact = g.size.width < Self.sidebarBreak
            let side: CGFloat = compact ? 76 : 248
            let area = Swift.max(0, g.size.width - side)
            HStack(spacing: 0) {
                Sidebar(route: $route, compact: compact)
                    .frame(width: side)
                VStack(spacing: 0) {
                    UpdateBanner()
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(route)
                        .transition(.opacity)
                }
                .frame(width: area)
            }
            .environment(\.compactLayout, area < 860)
            .environment(\.layoutWidth, area)
        }
        .overlay { PanelHost() }
        .onAppear { route = initialRoute ?? defaultRoute }
        .onChange(of: app.profile?.role) { _ in route = defaultRoute }
    }

    private var defaultRoute: Route {
        if app.isAdmin { return .today }
        if app.isClient { return .clientProjects }
        return .myDashboard
    }

    @ViewBuilder private var content: some View {
        if !data.loaded {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Muted("Chargement de tes données…")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

// MARK: - Fiche par-dessus la page (fermeture au clic à côté ou Échap)

/// Fond assombri et flouté sur toute la fenêtre, fiche centrée en verre aux coins arrondis.
/// L'ordre compte : on fixe la taille, on arrondit le contenu, on pose le verre derrière,
/// et seulement ensuite on ajoute la marge. (Avant, la marge était ajoutée avant l'arrondi :
/// le cadre et l'ombre dépassaient de 24 points de chaque côté de la fiche.)
struct PanelHost: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        GeometryReader { g in
            host(size: g.size)
        }
    }

    private func host(size: CGSize) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // Largeur réelle de la fiche : celle de la fenêtre moins les marges, plafonnée.
        let sheetWidth = Swift.min(1040, Swift.max(0, size.width - 56))
        return ZStack {
            if let t = presenter.mission {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Theme.scrim)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { presenter.close() }
                    .transition(.opacity)
                    .zIndex(0)

                MissionSheet(target: t, presetDeadline: presenter.presetDeadline, onClose: { presenter.close() })
                    .frame(maxWidth: 1040, maxHeight: 820)
                    .layoutWidth(sheetWidth)
                    .foregroundStyle(Theme.text)
                    .clipShape(shape)
                    .glassSurface(shape, tint: Theme.bg.opacity(0.55), fill: Theme.bg.opacity(0.82))
                    .shadow(color: .black.opacity(0.28), radius: 40, y: 16)
                    .padding(.horizontal, 28).padding(.vertical, 32)
                    .onExitCommand { presenter.close() }
                    .transition(.scale(scale: 0.96).combined(with: .opacity).combined(with: .offset(y: 14)))
                    .zIndex(1)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: presenter.mission)
    }
}

// MARK: - Bandeau de mise à jour

struct UpdateBanner: View {
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        if let r = updater.updateAvailable {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 16)).foregroundStyle(Theme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nouvelle version \(r.version) disponible").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if let n = r.notes, !n.isEmpty {
                        Text(n).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    if let e = updater.error {
                        Text(e).font(.system(size: 12)).foregroundStyle(Theme.red).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                if updater.installing {
                    ProgressView().controlSize(.small)
                    Text(updater.progressText ?? "").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).fixedSize()
                } else {
                    Button("Mettre à jour") { Task { @MainActor in await updater.install(r, tracker: tracker) } }
                        .buttonStyle(PrimaryButton())
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: Theme.blue.opacity(0.12))
            .padding(.horizontal, 20).padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Barre latérale (panneau flottant en verre)

private struct Sidebar: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @Binding var route: Route
    var compact = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @Namespace private var nav

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
                        Text("Minima Studio").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        Text(app.profile?.roleLabel ?? "").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 4)
                    NotificationBell()
                }
                .padding(.horizontal, 10).padding(.top, 38).padding(.bottom, 22)
            }

            // La liste défile si la fenêtre est trop basse : le pied (chrono, thème, compte) reste visible.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) { items }
            }
            .frame(maxHeight: .infinity)
            .padding(.bottom, 8)

            if app.isTeam && !compact {
                TrackerCard()
                    .padding(.bottom, 10)
            }

            ThemeToggle(compact: compact)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 10)

            if let p = app.profile, compact {
                accountMenu { AvatarView(profile: p, size: 32) }
                    .frame(maxWidth: .infinity).padding(.bottom, 14)
            } else if let p = app.profile {
                HStack(spacing: 10) {
                    AvatarView(profile: p, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                        Text("\(p.roleLabel) · v\(AppVersion.current)").font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    accountMenu { Image(systemName: "ellipsis").foregroundStyle(Theme.muted).frame(width: 24, height: 24).contentShape(Rectangle()) }
                        .frame(width: 24)
                }
                .padding(10)
                .glassCard(radius: 14)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, compact ? 6 : 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), fill: Theme.card.opacity(0.5))
        .padding(.leading, 8).padding(.vertical, 8)
    }

    @ViewBuilder private var items: some View {
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

    }

    /// Bouton du compte : un vrai bouton SwiftUI qui ouvre un popover.
    /// (Un Menu macOS convertit son étiquette en image et perd le découpage rond de l'avatar :
    /// la photo s'affichait en grand rectangle dans la barre réduite.)
    private func accountMenu<L: View>(@ViewBuilder label: () -> L) -> some View {
        AccountButton(launchAtLogin: $launchAtLogin, label: label())
    }

    @ViewBuilder
    private func section(_ t: String) -> some View {
        if compact {
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 12).padding(.horizontal, 8)
        } else {
            Text(t.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8)
                .foregroundStyle(Theme.muted.opacity(0.85))
                .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 6)
        }
    }

    private func item(_ title: String, _ icon: String, _ r: Route, badge: Int = 0, live: Int = 0) -> some View {
        SidebarItem(title: title, icon: icon, active: route == r, compact: compact, badge: badge, live: live, nav: nav) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { route = r }
        }
    }
}

/// Compte : popover avec les réglages et la déconnexion.
private struct AccountButton<L: View>: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @Binding var launchAtLogin: Bool
    let label: L
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: { label.contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help("Mon compte")
            .accessibilityLabel("Mon compte")
            .popover(isPresented: $open, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 4) {
                    if let p = app.profile {
                        HStack(spacing: 10) {
                            AvatarView(profile: p, size: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.displayName).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                                Text("\(p.roleLabel) · v\(AppVersion.current)").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    row("Actualiser", "arrow.clockwise") { Task { @MainActor in await data.reload() } }
                    Toggle(isOn: Binding(
                        get: { launchAtLogin },
                        set: { v in
                            do { try LaunchAtLogin.set(v); launchAtLogin = LaunchAtLogin.isEnabled }
                            catch { app.showToast("Impossible : \(error.localizedDescription)") }
                        })) {
                        Text("Ouvrir au démarrage du Mac").font(.system(size: 13))
                    }
                    .toggleStyle(.switch).controlSize(.small).padding(.vertical, 6).padding(.horizontal, 8)
                    if app.isTeam {
                        row("Mode mini (⇧⌘M)", "rectangle.inset.bottomright.filled") { MiniWindow.shared.show(app: app, data: data, tracker: tracker) }
                        row("Diagnostic du chrono", "stethoscope") { DiagnosticWindow.show(tracker: tracker) }
                    }
                    Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 4)
                    row("Se déconnecter", "rectangle.portrait.and.arrow.right", danger: true) { Task { @MainActor in await app.signOut() } }
                }
                .padding(14)
                .frame(width: 260)
            }
    }

    private func row(_ title: String, _ icon: String, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { open = false; action() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18).foregroundStyle(danger ? Theme.red : Theme.muted)
                Text(title).font(.system(size: 13)).foregroundStyle(danger ? Theme.red : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverRow(radius: 8)
    }
}

/// Une entrée de la barre latérale : pastille active qui glisse, survol doux.
private struct SidebarItem: View {
    let title: String
    let icon: String
    let active: Bool
    let compact: Bool
    var badge = 0
    var live = 0
    let nav: Namespace.ID
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Group {
                if compact { compactLabel } else { wideLabel }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(compact ? title : "")
        .accessibilityLabel(title)
    }

    @ViewBuilder private func plate(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if active {
            shape.fill(Theme.ink.opacity(0.09))
                .overlay(shape.strokeBorder(Theme.rim.opacity(0.35), lineWidth: 0.5))
                .matchedGeometryEffect(id: "active", in: nav)
        } else if hover {
            shape.fill(Theme.ink.opacity(0.045))
        }
    }

    private var compactLabel: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: icon).font(.system(size: 15))
                .symbolVariant(active ? .fill : .none)
                .foregroundStyle(active ? Theme.blue : Theme.muted)
                .frame(width: 44, height: 40)
                .background { plate(11) }
            if live > 0 { Circle().fill(Theme.green).frame(width: 7, height: 7).offset(x: -6, y: 6) }
        }
        .frame(maxWidth: .infinity)
    }

    private var wideLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18)
                .symbolVariant(active ? .fill : .none)
                .foregroundStyle(active ? Theme.blue : Theme.muted)
            Text(title).font(.system(size: 13.5, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Theme.text : Theme.text2)
                .lineLimit(1)
            Spacer(minLength: 4)
            if live > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Theme.green).frame(width: 6, height: 6)
                    Text("\(live)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.green)
                }
                .help("\(live) personne(s) en train de monter")
            }
            if badge > 0 {
                Text("\(badge)").font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(active ? Theme.text2 : Theme.muted)
                    .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 18)
                    .background(Theme.ink.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background { plate(10) }
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
                Text(tracker.mission?.title ?? "Chrono").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 4)
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
        .glassCard(radius: 14)
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
