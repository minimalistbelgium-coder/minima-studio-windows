import SwiftUI
import AppKit

/// Ce qui est affiché par-dessus la page (fiche mission, nouvelle série).
@MainActor
final class Presenter: ObservableObject {
    @Published var mission: MissionTarget?

    /// Date proposée pour une nouvelle mission créée depuis l'agenda.
    var presetDeadline: Date?

    var isOpen: Bool { mission != nil }
    func open(_ t: MissionTarget) { presetDeadline = nil; mission = t }
    func openNew(on day: Date) {
        presetDeadline = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: day) ?? day
        mission = .new
    }
    func close() { mission = nil }

    // MARK: navigation demandée par une tuile ou une ligne cliquable
    /// Profils des monteurs en popup (index du monteur affiché), nil = fermé.
    @Published var editorsIndex: Int?
    /// Incrémenté à chaque demande de navigation : ShellView change de page, la page lit les réglages en attente.
    @Published var navTick = 0
    var navRoute: Route?
    var navFinanceTab: FinanceTab?
    var navMonth: Date?
    var navAnchor: String?
    /// Onglet à ouvrir dans la prochaine fiche mission (« messages » depuis une notification).
    var missionTab: String?

    func go(_ route: Route, financeTab: FinanceTab? = nil, month: Date? = nil, anchor: String? = nil) {
        mission = nil; editorsIndex = nil
        navRoute = route; navFinanceTab = financeTab; navMonth = month; navAnchor = anchor
        navTick += 1
    }
}

/// Onglets de la page Finances (admin).
enum FinanceTab: String, Hashable { case overview, missions, payouts, charts }

/// Récupère la NSWindow qui contient une vue SwiftUI.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { onWindow(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onWindow(w) } }
    }
}

/// Vue hôte qui laisse déplacer la fenêtre en glissant n'importe où.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

// MARK: - Fenêtre mini (chrono + montant, toujours au premier plan)

@MainActor
final class MiniWindow {
    static let shared = MiniWindow()
    private var panel: NSPanel?
    private(set) var isVisible = false

    func show(app: AppState, data: DataStore, tracker: Tracker) {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 128),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true
            [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
                p.standardWindowButton($0)?.isHidden = true
            }
            let root = MiniView()
                .environmentObject(app)
                .environmentObject(data)
                .environmentObject(tracker)
            let host = DraggableHostingView(rootView: root)
            p.contentView = host
            p.setContentSize(host.fittingSize)
            // Position mémorisée : la fenêtre reste là où on l'a déplacée.
            if !p.setFrameUsingName("MinimaMiniChrono"), let screen = NSScreen.main {
                let f = screen.visibleFrame
                p.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.maxY - p.frame.height - 20))
            }
            p.setFrameAutosaveName("MinimaMiniChrono")
            panel = p
        }
        panel?.orderFrontRegardless()
        isVisible = true
        app.mainWindow?.orderOut(nil)
    }

    /// Ajuste la hauteur de la mini-fenêtre à son contenu (questions du chrono), le coin haut gauche ne bouge pas.
    func fit(_ size: CGSize) {
        DispatchQueue.main.async { [weak self] in
            guard let p = self?.panel, size.height > 40, size.width > 40 else { return }
            var f = p.frame
            guard abs(f.height - size.height) > 0.5 || abs(f.width - size.width) > 0.5 else { return }
            f.origin.y += f.height - size.height
            f.size = size
            p.setFrame(f, display: true, animate: p.isVisible)
        }
    }

    func hide(app: AppState) {
        panel?.orderOut(nil)
        isVisible = false
        app.showMainWindow()
    }
}

struct MiniView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(status: tracker.status)
                Text(tracker.mission?.title ?? "Aucune mission").font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Spacer()
                Button { MiniWindow.shared.hide(app: app) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Agrandir")
            }

            LiveClock(tracker: tracker, size: 32)

            HStack(spacing: 8) {
                miniStat("À la clé", tracker.maxAmount.map(Money.eur) ?? "–", color: Theme.green)
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    miniStat("Ratio", tracker.hourlyRate(at: ctx.date).map { "\(Money.eur($0.rounded())) / h" } ?? "–", color: Theme.text)
                }
            }

            TrackerHint(compact: true)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
        .frame(width: 320, alignment: .leading)
        .foregroundStyle(Theme.text)
        .environment(\.glassDepth, 1)
        .background(WindowDragArea())
        .background { MiniGlass(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
        .background(GeometryReader { g in
            Color.clear
                .onAppear { MiniWindow.shared.fit(g.size) }
                .onChange(of: g.size) { MiniWindow.shared.fit($0) }
        })
    }
}

extension MiniView {
    func miniStat(_ label: String, _ value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Chrono qui avance à la seconde entre deux mesures du tracker.
struct LiveClock: View {
    @ObservedObject var tracker: Tracker
    var size: CGFloat = 30

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format(tracker.displaySeconds(at: ctx.date)))
                .font(.system(size: size, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(tracker.status == .running ? Theme.text : Theme.muted)
        }
    }

    static func format(_ s: Double) -> String {
        let t = Int(s)
        return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }
}

struct StatusDot: View {
    let status: Tracker.Status
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .shadow(color: color.opacity(status == .running ? 0.8 : 0), radius: 4)
    }
    private var color: Color {
        switch status {
        case .running: return Theme.green
        case .askAway, .paused: return Theme.amber
        case .noPermission: return Theme.red
        default: return Theme.muted
        }
    }
}

/// Ligne d'état + questions du tracker (projet à lier, « tu travailles toujours ? »).
struct TrackerHint: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch tracker.status {
            case .askAway:
                Text("Tu travailles toujours dessus ?").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.amber)
                HStack(spacing: 6) {
                    Button("Oui, compter ce temps") { Task { @MainActor in await tracker.answerAway(stillWorking: true) } }
                        .buttonStyle(MiniButton(primary: true))
                    Button("Non") { Task { @MainActor in await tracker.answerAway(stillWorking: false) } }
                        .buttonStyle(MiniButton())
                }
            case .noPermission:
                Text("Autorise Minima Studio dans Accessibilité pour détecter Premiere.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button("Autoriser") { tracker.requestAccessibility() }.buttonStyle(MiniButton(primary: true))
                    Button("Diagnostic") { DiagnosticWindow.show(tracker: tracker) }.buttonStyle(MiniButton())
                }
            default:
                if let key = tracker.unlinkedProject {
                    Text("Projet « \(key) » non lié").font(.system(size: 11.5)).foregroundStyle(Theme.amber).lineLimit(1)
                    LinkProjectMenu(projectKey: key)
                } else {
                    Text(line).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(compact ? 1 : 2)
                    if !compact, case .waiting = tracker.status, tracker.premiereOpen {
                        Button("Diagnostic") { DiagnosticWindow.show(tracker: tracker) }.buttonStyle(MiniButton())
                    }
                }
                if tracker.manual {
                    Button("Arrêter le chrono") { Task { @MainActor in await tracker.stopManual() } }.buttonStyle(MiniButton())
                }
            }
        }
    }

    private var line: String {
        switch tracker.status {
        case .running:
            if tracker.manual { return "Chrono manuel" }
            return "Premiere · \(tracker.projectName ?? "")"
        case .paused(let why): return "En pause · \(why)"
        case .waiting:
            if !tracker.premiereOpen { return "Ouvre un projet dans Premiere Pro" }
            if tracker.projectName == nil { return "Aucun projet détecté dans Premiere" }
            return "En attente de Premiere au premier plan"
        case .disabled: return "Suivi désactivé"
        default: return ""
        }
    }
}

/// Menu pour associer le projet Premiere ouvert à une mission.
struct LinkProjectMenu: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    let projectKey: String

    var body: some View {
        HStack(spacing: 6) {
            Menu("Associer à une mission") {
                ForEach(candidates) { m in
                    Button("\(data.client(m.client_id)?.name ?? "Sans client") · \(m.title)") {
                        Task { @MainActor in await tracker.link(projectKey: projectKey, to: m) }
                    }
                }
                if candidates.isEmpty { Text("Aucune mission en cours") }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10).frame(height: 26)
            .background(Theme.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Button("Ignorer") { tracker.ignoreCurrentProject() }.buttonStyle(MiniButton())
        }
    }

    private var candidates: [Mission] {
        let me = app.profile?.id ?? ""
        return data.missions.filter { $0.isOpen && (app.isAdmin || data.memberIds(of: $0.id).contains(me)) }
    }
}

struct MiniButton: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(primary ? Theme.onAccent : Theme.text)
            .lineLimit(1)
            .padding(.horizontal, 10).frame(height: 26)
            .glassButton(tint: primary ? Theme.blue : nil, radius: 8, prominent: primary)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
