import Foundation
import AppKit
import ApplicationServices
import UserNotifications
import Supabase

/// Suivi automatique du temps passé dans Premiere Pro.
///
/// Règles :
/// - Le chrono tourne quand Premiere est au premier plan avec un projet lié à une mission.
/// - Inactivité : sans clavier ni souris pendant 3 min, le chrono s'arrête et ces 3 min sont retirées.
/// - Premiere quitté pour une autre app : pause immédiate, rien n'est compté tant que Premiere n'est pas revenu
///   au premier plan. Sans retour après 15 min, la session est close.
/// - Le projet est reconnu par son nom de fichier, où qu'il soit enregistré (Mac ou disque externe).
/// - Chrono manuel possible sur n'importe quelle mission (bouton Démarrer).
@MainActor
final class Tracker: ObservableObject {
    static let idleLimit: Double = 180
    static let focusGrace: Double = 120
    static let awayTimeout: Double = 900
    static let tickInterval: Double = 5
    static let heartbeatInterval: Double = 30

    enum Status: Equatable {
        case disabled          // pas connecté ou client
        case noPermission      // accès Accessibilité manquant
        case waiting           // Premiere fermé ou projet non lié
        case running
        case paused(String)
        case askAway           // a quitté Premiere depuis plus de 2 min
    }

    @Published private(set) var status: Status = .disabled
    @Published private(set) var premiereOpen = false
    @Published private(set) var premiereFront = false
    @Published private(set) var projectName: String?
    @Published private(set) var projectPath: String?
    @Published private(set) var mission: Mission?
    @Published private(set) var sessionSeconds: Double = 0
    @Published private(set) var baseSeconds: Double = 0
    @Published private(set) var manual = false
    @Published var unlinkedProject: String?
    @Published private(set) var axTrusted = AXIsProcessTrusted()
    /// Pour l'écran Diagnostic : ce que l'app lit dans les fenêtres de Premiere.
    @Published private(set) var seenTitles: [String] = []
    @Published private(set) var premiereBundle: String?

    private weak var data: DataStore?
    private var userId: String?
    private var isAdminUser = false
    private var timer: Timer?
    private var lastTick = Date()
    private var lastBeat = Date.distantPast

    private var sessionId: String?
    private var sessionStart: Date?
    private var countedIdle: Double = 0
    private var countedAway: Double = 0
    private var awayStart: Date?
    private var manualMission: Mission?
    private var dismissedProjects: Set<String> = []

    // Pour l'estimation du montant en direct
    private var budget: Double = 0
    private var othersWeighted: Double = 0
    private var myWeight: Double = 1

    var totalSeconds: Double { baseSeconds + sessionSeconds }

    /// Moment du dernier ajout de temps, pour faire avancer l'affichage à la seconde.
    @Published private(set) var lastCountAt: Date?

    func displaySeconds(at date: Date) -> Double {
        guard status == .running, let last = lastCountAt else { return totalSeconds }
        return totalSeconds + min(Self.tickInterval, max(0, date.timeIntervalSince(last)))
    }

    /// Budget montage de la mission en cours : ce qu'il est possible de gagner au maximum.
    var maxAmount: Double? {
        guard mission != nil, budget > 0 else { return nil }
        return budget
    }

    /// Rapport entre ce que la mission rapporte et le temps passé (à partir de 5 min de travail).
    func hourlyRate(at date: Date = Date()) -> Double? {
        let secs = displaySeconds(at: date)
        guard secs >= 300, let a = estimatedAmount ?? maxAmount else { return nil }
        return a / (secs / 3600)
    }

    var estimatedAmount: Double? {
        guard mission != nil, budget > 0 else { return nil }
        let mine = totalSeconds * myWeight
        if mine + othersWeighted <= 0 { return nil }
        return budget * mine / (mine + othersWeighted)
    }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.endSession(deduct: 0, reason: "Mac en veille") }
        }
        center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.endSession(deduct: 0, reason: "Session macOS verrouillée") }
        }
    }

    // MARK: Configuration

    func configure(data: DataStore, userId: String?, isAdmin: Bool, enabled: Bool) {
        self.data = data
        self.userId = userId
        self.isAdminUser = isAdmin
        if enabled && userId != nil {
            if timer == nil {
                lastTick = Date()
                timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
                    Task { @MainActor in await self?.tick() }
                }
            }
            Task { await tick() }
        } else {
            timer?.invalidate()
            timer = nil
            Task { await endSession(deduct: 0, reason: nil) }
            status = .disabled
        }
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        axTrusted = AXIsProcessTrustedWithOptions(opts)
        if !axTrusted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Actions utilisateur

    /// Démarre un chrono manuel sur une mission (même sans Premiere).
    func startManual(_ m: Mission) async {
        if sessionId != nil { await endSession(deduct: 0, reason: nil) }
        manual = true
        manualMission = m
        awayStart = nil
        await tick()
    }

    func stopManual() async {
        manual = false
        manualMission = nil
        await endSession(deduct: 0, reason: "Chrono arrêté")
    }

    /// Réponse à « Tu travailles toujours dessus ? »
    func answerAway(stillWorking: Bool) async {
        guard let left = awayStart else { return }
        if stillWorking, let m = mission {
            // On compte tout le temps passé hors de Premiere, puis on continue en manuel.
            let away = Date().timeIntervalSince(left)
            sessionSeconds += max(0, away - countedAway)
            countedAway = 0
            awayStart = nil
            manual = true
            manualMission = m
            status = .running
            await heartbeat(live: true)
        } else {
            awayStart = nil
            await endSession(deduct: countedAway, reason: "Hors de Premiere")
        }
    }

    /// Associe le projet Premiere ouvert à une mission.
    func link(projectKey: String, to m: Mission) async {
        var map = UserDefaults.standard.dictionary(forKey: "premiereLinks") as? [String: String] ?? [:]
        map[projectKey] = m.id
        UserDefaults.standard.set(map, forKey: "premiereLinks")
        unlinkedProject = nil
        _ = try? await supa.rpc("link_premiere", params: ["m": m.id, "key": projectKey]).execute()
        await data?.reload()
        await tick()
    }

    func ignoreCurrentProject() {
        if let k = unlinkedProject { dismissedProjects.insert(k) }
        unlinkedProject = nil
    }

    // MARK: Boucle principale

    private func tick() async {
        let now = Date()
        var dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard let data, let userId else { return }

        // Un trou de plus d'une minute (veille, app gelée) ne compte jamais.
        if dt > 60 {
            if sessionId != nil { await endSession(deduct: 0, reason: "Interruption") }
            dt = 0
        }
        dt = min(dt, 15)

        axTrusted = AXIsProcessTrusted()
        let ws = NSWorkspace.shared
        let prem = ws.runningApplications.first { ($0.bundleIdentifier ?? "").hasPrefix("com.adobe.PremierePro") }
        premiereOpen = prem != nil
        premiereBundle = prem?.bundleIdentifier
        premiereFront = (ws.frontmostApplication?.bundleIdentifier ?? "").hasPrefix("com.adobe.PremierePro")

        if let prem, axTrusted {
            seenTitles = Self.windowTexts(pid: prem.processIdentifier)
            if let found = Self.premiereProject(pid: prem.processIdentifier) {
                projectPath = found.path
                projectName = found.name
            }
        } else if prem == nil {
            projectPath = nil
            projectName = nil
        }

        // Mission visée
        var target: Mission?
        if manual, let m = manualMission {
            target = data.mission(m.id) ?? m
        } else if let name = projectName {
            let key = Self.key(for: name)
            target = matchMission(key: key, data: data, userId: userId)
            if target == nil {
                if !dismissedProjects.contains(key) && unlinkedProject != key { unlinkedProject = key }
            } else if unlinkedProject == key {
                unlinkedProject = nil
            }
        }

        if !axTrusted && !manual {
            if sessionId != nil { await endSession(deduct: 0, reason: nil) }
            status = .noPermission
            return
        }

        // Changement de mission : on clôt la session précédente.
        if let current = mission, sessionId != nil, current.id != target?.id {
            await endSession(deduct: 0, reason: nil)
        }

        guard let target else {
            if sessionId != nil { await endSession(deduct: 0, reason: nil) }
            if case .paused = status {} else { status = .waiting }
            if !premiereOpen && !manual { mission = nil }
            return
        }

        let idle = Self.idleSeconds()

        // Inactivité
        if idle >= Self.idleLimit {
            if sessionId != nil {
                await endSession(deduct: max(countedIdle, countedAway), reason: "Inactif depuis 3 min")
                if manual { manual = false; manualMission = nil }
            }
            if case .paused = status {} else { status = .paused("Inactif") }
            mission = target
            return
        }

        // Hors de Premiere (mode auto uniquement) : pause immédiate, rien n'est compté.
        // La session reste ouverte 15 min pour reprendre sans couture, puis elle est close.
        if !manual && !premiereFront {
            if awayStart == nil { awayStart = now }
            let away = now.timeIntervalSince(awayStart ?? now)
            if sessionId != nil {
                if away > Self.awayTimeout {
                    awayStart = nil
                    await endSession(deduct: 0, reason: "Hors de Premiere")
                    return
                }
                status = .paused("Hors de Premiere")
                if now.timeIntervalSince(lastBeat) >= Self.heartbeatInterval { await heartbeat(live: true) }
            } else if case .paused = status {} else { status = .waiting }
            mission = target
            return
        } else if awayStart != nil {
            awayStart = nil
            countedAway = 0
            if manual && manualMission?.id == target.id { manual = false; manualMission = nil }
        }

        // On compte. Une nouvelle session ne démarre que dans Premiere (ou en manuel).
        if sessionId == nil {
            guard manual || premiereFront else {
                mission = target
                if case .paused = status {} else { status = .waiting }
                return
            }
            await startSession(target)
        }
        sessionSeconds += dt
        lastCountAt = now
        countedIdle = idle > dt + 1 ? countedIdle + dt : 0
        countedAway = (!manual && !premiereFront) ? countedAway + dt : 0
        status = .running

        if now.timeIntervalSince(lastBeat) >= Self.heartbeatInterval {
            await heartbeat(live: true)
        }
    }

    private func matchMission(key: String, data: DataStore, userId: String) -> Mission? {
        let map = UserDefaults.standard.dictionary(forKey: "premiereLinks") as? [String: String] ?? [:]
        if let id = map[key], let m = data.mission(id) { return m }
        let mine = data.missions.filter { isAdminUser || data.memberIds(of: $0.id).contains(userId) }
        return mine.first { ($0.premiere_key ?? "").lowercased() == key }
    }

    // MARK: Sessions en base

    private func startSession(_ m: Mission) async {
        guard let userId else { return }
        mission = m
        sessionSeconds = 0
        countedIdle = 0
        countedAway = 0
        let id = UUID().uuidString.lowercased()
        let start = Date()
        sessionId = id
        sessionStart = start
        lastBeat = start
        await loadBaseline(for: m)
        do {
            try await supa.from("sessions").insert(SessionInsert(
                id: id, mission_id: m.id, user_id: userId,
                started_at: DateFmt.iso(start), ended_at: DateFmt.iso(start),
                duration_sec: 0, source: manual ? "manual" : "auto", live: true,
                project_path: manual ? nil : projectPath
            )).execute()
        } catch {
            // On garde le chrono local, le prochain battement réessaiera via une nouvelle session.
            sessionId = nil
        }
    }

    private func heartbeat(live: Bool) async {
        guard let id = sessionId else { return }
        lastBeat = Date()
        let end = (sessionStart ?? Date()).addingTimeInterval(sessionSeconds)
        _ = try? await supa.from("sessions")
            .update(SessionHeartbeat(ended_at: DateFmt.iso(live ? Date() : end), duration_sec: Int(sessionSeconds), live: live))
            .eq("id", value: id).execute()
    }

    /// Clôt la session en cours en retirant `deduct` secondes (temps inactif ou hors Premiere).
    func endSession(deduct: Double, reason: String?) async {
        guard let id = sessionId else {
            if let reason { status = .paused(reason) }
            return
        }
        sessionSeconds = max(0, sessionSeconds - deduct)
        let final = Int(sessionSeconds)
        let end = (sessionStart ?? Date()).addingTimeInterval(sessionSeconds)
        sessionId = nil
        _ = try? await supa.from("sessions")
            .update(SessionHeartbeat(ended_at: DateFmt.iso(end), duration_sec: final, live: false))
            .eq("id", value: id).execute()
        baseSeconds += sessionSeconds
        sessionSeconds = 0
        lastCountAt = nil
        countedIdle = 0
        countedAway = 0
        awayStart = nil
        if let reason { status = .paused(reason) } else { status = .waiting }
    }

    private func loadBaseline(for m: Mission) async {
        guard let data, let userId else { return }
        budget = m.editor_budget ?? 0
        myWeight = isAdminUser ? (m.admin_weight ?? 1.2) : 1
        let rows = await data.split(for: m.id)
        baseSeconds = rows.first { $0.user_id == userId }?.seconds ?? 0
        othersWeighted = rows.filter { $0.user_id != userId }.compactMap(\.weighted).reduce(0, +)
    }

    private func notifyAway(_ m: Mission) {
        let content = UNMutableNotificationContent()
        content.title = "Tu travailles toujours sur \(m.title) ?"
        content.body = "Premiere n'est plus au premier plan. Le chrono est en pause, réponds dans Minima Studio."
        let req = UNNotificationRequest(identifier: "away", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    // MARK: Détection système

    /// Secondes depuis la dernière action clavier ou souris (aucune autorisation requise).
    static func idleSeconds() -> Double {
        let types: [CGEventType] = [.mouseMoved, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .flagsChanged, .leftMouseDragged]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    static func key(for name: String) -> String {
        var n = name
        if n.lowercased().hasSuffix(".prproj") { n = String(n.dropLast(7)) }
        return n.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Lit le titre des fenêtres de Premiere pour trouver le projet ouvert (n'importe quel disque).
    static func premiereProject(pid: pid_t) -> (path: String?, name: String)? {
        let titles = windowTexts(pid: pid)
        for t in titles {
            if let r = parse(title: t) { return r }
        }
        // Certaines versions de Premiere n'affichent pas « .prproj » : on se rabat sur le titre de la fenêtre.
        for t in titles {
            if let r = parseLoose(title: t) { return r }
        }
        return nil
    }

    /// Titres et documents de toutes les fenêtres de Premiere.
    static func windowTexts(pid: pid_t) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        var titles: [String] = []

        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(app, attr as CFString, &value) == .success, let value {
                let win = value as! AXUIElement
                if let d = document(of: win) { titles.append(d) }
                if let t = title(of: win) { titles.append(t) }
            }
        }
        var list: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &list) == .success,
           let windows = list as? [AXUIElement] {
            for w in windows {
                if let d = document(of: w) { titles.append(d) }
                if let t = title(of: w) { titles.append(t) }
            }
        }

        var seen = Set<String>()
        return titles.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// « Adobe Premiere Pro 2025 - Mon projet * » ou « Mon projet - Adobe Premiere Pro » → nom du projet.
    static func parseLoose(title: String) -> (path: String?, name: String)? {
        var parts = title.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }
        parts.removeAll { $0.isEmpty || $0.lowercased().hasPrefix("adobe premiere") || $0.lowercased().hasPrefix("premiere pro") }
        guard var name = parts.first else { return nil }
        if name.hasSuffix("*") { name = String(name.dropLast()).trimmingCharacters(in: .whitespaces) }
        if name.hasPrefix("/") { return (name, (name as NSString).lastPathComponent) }
        // Écarte les panneaux et fenêtres secondaires
        let ignored = ["accueil", "home", "projet", "project", "effets", "effects", "source", "programme", "program", "timeline"]
        guard name.count > 1, !ignored.contains(name.lowercased()) else { return nil }
        return (nil, name + ".prproj")
    }

    /// Réinitialise l'autorisation Accessibilité de l'app puis la redemande (utile après une réinstallation).
    func resetAccessibility() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", "Accessibility", Bundle.main.bundleIdentifier ?? "be.minimalist.minimastudio"]
        try? p.run()
        p.waitUntilExit()
        requestAccessibility()
    }

    /// Relance l'app (macOS ne prend parfois l'autorisation en compte qu'au redémarrage).
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? task.run()
        AppDelegate.forceQuit = true
        NSApp.terminate(nil)
    }

    /// Chemin du document de la fenêtre (attribut AXDocument), si Premiere le fournit.
    private static func document(of el: AXUIElement) -> String? {
        var d: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXDocumentAttribute as CFString, &d) == .success,
              let s = d as? String else { return nil }
        if let u = URL(string: s), u.isFileURL { return u.path }
        return s.removingPercentEncoding ?? s
    }

    private static func title(of el: AXUIElement) -> String? {
        var t: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &t) == .success else { return nil }
        return t as? String
    }

    /// « Adobe Premiere Pro 2025 - /Volumes/T7/Projet.prproj * » → chemin + nom
    static func parse(title: String) -> (path: String?, name: String)? {
        guard let ext = title.range(of: ".prproj", options: [.caseInsensitive, .backwards]) else { return nil }
        let head = title[..<ext.upperBound]
        if let slash = head.firstIndex(of: "/") {
            let path = String(head[slash...])
            let name = (path as NSString).lastPathComponent
            return (path, name)
        }
        var name = String(head)
        if let dash = name.range(of: " - ", options: .backwards) { name = String(name[dash.upperBound...]) }
        return (nil, name.trimmingCharacters(in: .whitespaces))
    }
}
