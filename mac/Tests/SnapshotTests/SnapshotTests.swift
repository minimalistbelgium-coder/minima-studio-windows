import XCTest
import SwiftUI
import AppKit
@testable import MinimaStudio

// Captures de mise en page : rend les pages de l'app avec des données fictives,
// à plusieurs largeurs de fenêtre et dans les deux thèmes, sans aucun appel réseau.
// Les PNG sont écrits dans le dossier SNAPSHOT_DIR (ou ./shots).

@MainActor
final class SnapshotTests: XCTestCase {
    private var outDir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? "shots")
    private var report: [String] = []

    private let app = AppState(observeAuth: false)
    private let data = DataStore()
    private let tracker = Tracker()
    private let updater = Updater()
    private let presenter = Presenter()

    private let cal = Calendar.current

    // MARK: - Données fictives

    private func at(_ dayOffset: Int, _ hour: Int = 18, _ minute: Int = 0) -> Date {
        let d = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: d) ?? d
    }

    private func profile(_ id: String, _ name: String, _ role: String, _ color: String, client: String? = nil, active: Bool = true) -> Profile {
        Profile(id: id, email: name.lowercased().replacingOccurrences(of: " ", with: ".") + "@exemple.be", full_name: name,
                avatar_url: nil, role: role, color: color, active: active, created_at: DateFmt.iso(at(-200)), client_id: client)
    }

    private func mission(_ id: String, _ client: String?, _ title: String, _ status: String, _ deadline: Date?, budget: Double?,
                         rushes: Bool = true, brief: String? = nil) -> Mission {
        Mission(id: id, client_id: client, series_id: nil, title: title, brief: brief, editor_budget: budget,
                deadline: deadline.map(DateFmt.iso), rushes_url: rushes ? "https://exemple.be/rushes/\(id)" : nil,
                rushes_added_at: rushes ? DateFmt.iso(at(-3)) : nil, status: status, admin_weight: 1.5, split_comment: nil,
                v1_delivered_at: ["v1_delivered", "revisions", "fix_delivered", "validated", "paid"].contains(status) ? DateFmt.iso(min(deadline ?? at(-2), at(-2))) : nil,
                validated_at: ["validated", "paid"].contains(status) ? DateFmt.iso(at(-1)) : nil,
                created_at: DateFmt.iso((deadline ?? Date()).addingTimeInterval(-6 * 86_400)), premiere_key: status == "editing" ? "EP48_montage_v3" : nil,
                brief_files: id == "m1" ? [BriefFile(path: "m1/brief.pdf", name: "Brief épisode 48 et charte graphique.pdf")] : nil,
                delivery_url: ["v1_delivered", "fix_delivered"].contains(status) ? "https://exemple.be/v/\(id)" : nil)
    }

    private func populate() {
        let admin = profile("u-admin", "Camille Dubois", "admin", "4C8DFF")
        let leo = profile("u-leo", "Léo Martin", "editor", "3DD68C")
        let max = profile("u-max", "Maximilien de Saint-Amand", "editor", "F5A524")
        let ines = profile("u-ines", "Inès Lambert", "editor", "F472B6")
        let client = profile("u-client", "Jeanne Peeters", "client", "A78BFA", client: "c2")
        let out = profile("u-out", "Compte Inconnu", "none", "8B8D94", active: false)
        data.profiles = [admin, leo, max, ines, client, out]

        data.clients = [
            Client(id: "c1", name: "Studio Horizon", color: "#4C8DFF"),
            Client(id: "c2", name: "Brasserie du Canal", color: "#F5A524"),
            Client(id: "c3", name: "Podcast Les Grandes Ondes", color: "#A78BFA"),
            Client(id: "c4", name: "Atelier Nova", color: "#2DD4BF"),
        ]

        var ms: [Mission] = [
            mission("m1", "c3", "Épisode 48 : interview longue durée avec la fondatrice", "editing", at(0, 18), budget: 350,
                    brief: "Format 16:9, durée cible 42 minutes. Générique habituel, habillage de la saison 3. Couper les hésitations, garder les rires. Références : épisodes 44 et 45."),
            mission("m2", "c1", "Reel pub rentrée", "assigned", at(-1, 12), budget: 120),
            mission("m3", "c2", "Teaser festival d'été", "v1_delivered", at(1, 10), budget: 280),
            mission("m4", "c2", "Aftermovie soirée de lancement", "revisions", at(2, 18), budget: 600),
            mission("m5", "c4", "Capsule produit 3", "fix_delivered", at(3, 16), budget: 1250.5),
            mission("m6", "c1", "Vidéo témoignage client", "requested", at(6, 18), budget: nil, rushes: false),
            mission("m7", "c3", "Épisode 49", "assigned", at(7, 18), budget: 350, rushes: false),
            mission("m8", "c4", "Vlog coulisses de l'atelier", "editing", at(0, 12), budget: 220),
            mission("m9", "c1", "Motion logo", "assigned", at(2, 9), budget: 90),
            mission("m10", "c3", "Épisode 47", "validated", at(-5, 18), budget: 350),
            mission("m11", "c1", "Reel recrutement", "paid", at(-9, 18), budget: 150),
            mission("m12", "c2", "Sans date précise", "assigned", nil, budget: 80),
        ]
        // Historique : deux à trois missions payées par mois sur un an.
        var prices: [String: Double] = ["m1": 900, "m2": 400, "m3": 750, "m4": 1600, "m5": 2890, "m7": 900, "m8": 520,
                                        "m9": 300, "m10": 900, "m11": 450, "m12": 200]
        for k in 1...11 {
            guard let base = cal.date(byAdding: .month, value: -k, to: Date()) else { continue }
            for j in 0..<(2 + k % 2) {
                let id = "h\(k)-\(j)"
                var comps = cal.dateComponents([.year, .month], from: base)
                comps.day = 5 + j * 8
                comps.hour = 18
                let day = cal.date(from: comps) ?? base
                let c = ["c1", "c2", "c3", "c4"][(k + j) % 4]
                ms.append(mission(id, c, "Projet \(k)-\(j)", "paid", day, budget: Double(180 + 40 * ((k * 3 + j) % 7))))
                prices[id] = Double(500 + 130 * ((k * 5 + j * 2) % 9))
            }
        }
        // Claude monteur : m7 avec du temps, m9 choisi mais sans temps encore.
        ms = ms.map { m in var m = m; if m.id == "m7" || m.id == "m9" { m.claude_editor = true }; return m }
        data.aiWork = [
            AIWork(id: "ai1", mission_id: "m7", agent: "Claude", started_at: DateFmt.iso(at(0, 9)), ended_at: DateFmt.iso(at(0, 9, 22)),
                   duration_sec: 1320, notes: "Montage auto"),
            AIWork(id: "ai2", mission_id: "m7", agent: "Claude", started_at: DateFmt.iso(at(0, 10)), ended_at: DateFmt.iso(at(0, 10, 45)),
                   duration_sec: 2700, notes: "saisi à la main"),
        ]
        data.missions = ms.sorted { ($0.deadlineDate ?? .distantFuture) < ($1.deadlineDate ?? .distantFuture) }
        data.finances = Dictionary(uniqueKeysWithValues: prices.map { id, p in
            (id, MissionFinance(mission_id: id, client_price: p, invoiced: id.hasPrefix("h") || id == "m11", notes: nil))
        })

        let pairs: [(String, String)] = [("m1", "u-leo"), ("m2", "u-max"), ("m3", "u-ines"), ("m4", "u-leo"), ("m4", "u-admin"),
                                         ("m5", "u-leo"), ("m5", "u-max"), ("m7", "u-ines"), ("m8", "u-ines"), ("m8", "u-max"),
                                         ("m10", "u-leo"), ("m11", "u-max"), ("m12", "u-leo")]
        var members = pairs.map { MissionMember(mission_id: $0.0, user_id: $0.1) }
        for m in ms where m.id.hasPrefix("h") { members.append(MissionMember(mission_id: m.id, user_id: "u-leo")) }
        data.members = members

        // Sessions : 30 derniers jours, durées déterministes.
        var sessions: [WorkSession] = []
        var n = 0
        for back in 0..<30 {
            for (mid, uid) in pairs where mid != "m12" {
                n += 1
                let seed = (n * 7919 + back * 104_729) % 100
                guard seed < 34 else { continue }
                let start = at(-back, 9 + seed % 5)
                let secs = 1800 + (seed * 541) % 30_000
                sessions.append(WorkSession(id: "s\(n)", mission_id: mid, user_id: uid, started_at: DateFmt.iso(start),
                                            ended_at: DateFmt.iso(start.addingTimeInterval(Double(secs))), duration_sec: secs,
                                            source: seed % 4 == 0 ? "manual" : "premiere", live: false, project_path: nil))
            }
        }
        // Une grosse journée cette semaine pour vérifier la largeur des cases (« 12 h 30 »).
        sessions.append(WorkSession(id: "big", mission_id: "m1", user_id: "u-leo", started_at: DateFmt.iso(at(0, 6)),
                                    ended_at: DateFmt.iso(at(0, 18, 30)), duration_sec: 45_000, source: "premiere", live: false, project_path: nil))
        let live = WorkSession(id: "live", mission_id: "m1", user_id: "u-leo", started_at: DateFmt.iso(Date().addingTimeInterval(-4200)),
                               ended_at: DateFmt.iso(Date().addingTimeInterval(600)), duration_sec: 4200, source: "premiere", live: true, project_path: nil)
        data.sessions = sessions.sorted { $0.started_at > $1.started_at }
        data.liveSessions = [live]
        // Paiements des monteurs : tout est payé sauf le mois dernier.
        data.payments = (2...11).flatMap { k -> [EditorPayment] in
            let mo = cal.date(byAdding: .month, value: -k, to: Date()) ?? Date()
            return ["u-leo", "u-max", "u-ines"].map { u in
                EditorPayment(id: "p\(k)\(u)", user_id: u, month: BillMonth.key(mo), amount: 500, paid_at: DateFmt.iso(cal.date(byAdding: .month, value: -k + 1, to: Date()) ?? Date()), note: nil)
            }
        }

        data.notifications = [
            AppNotification(id: "n1", user_id: "u-admin", mission_id: "m3", from_user: "u-ines", kind: "status",
                            title: "Inès a livré la V1 de Teaser festival d'été", body: "Lien de la version ajouté. À regarder avant d'envoyer au client.",
                            status: "v1_delivered", handled: false, created_at: DateFmt.iso(Date().addingTimeInterval(-1800)), read_at: nil),
            AppNotification(id: "n2", user_id: "u-admin", mission_id: "m4", from_user: "u-client", kind: "comment",
                            title: "Nouveau message du client", body: "Peut-on raccourcir l'intro et changer la musique de fin ?",
                            status: nil, handled: false, created_at: DateFmt.iso(Date().addingTimeInterval(-7200)), read_at: nil),
            AppNotification(id: "n3", user_id: "u-admin", mission_id: "m10", from_user: nil, kind: "status", title: "Épisode 47 validé",
                            body: nil, status: "validated", handled: true, created_at: DateFmt.iso(at(-2)), read_at: DateFmt.iso(at(-2))),
        ]
        data.versions = [
            MissionVersion(id: "v1", mission_id: "m3", url: "https://exemple.be/v/m3-1", label: "V1", created_by: "u-ines", created_at: DateFmt.iso(at(-2))),
            MissionVersion(id: "v2", mission_id: "m3", url: "https://exemple.be/v/m3-2", label: "V2", created_by: "u-ines", created_at: DateFmt.iso(at(-1))),
        ]
        data.deliveryLink = "https://exemple.be/depot"
        data.mySplit = [
            "m1": MySplitRow(mission_id: "m1", seconds: 52_000, percent: 100, amount: 350),
            "m4": MySplitRow(mission_id: "m4", seconds: 9_000, percent: 62, amount: 372),
            "m5": MySplitRow(mission_id: "m5", seconds: 14_400, percent: 55, amount: 687.78),
            "m10": MySplitRow(mission_id: "m10", seconds: 21_600, percent: 100, amount: 350),
        ]
        data.loaded = true
    }

    private func signIn(_ id: String) { app.profile = data.profiles.first { $0.id == id } }

    // MARK: - Rendu

    /// Les pages entières sont écrites en JPEG (dégradés lourds en PNG), les graphiques en PNG.
    private func write(_ rep: NSBitmapImageRep, _ name: String, jpeg: Bool = false) {
        let data = jpeg
            ? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
            : rep.representation(using: .png, properties: [:])
        guard let data else { report.append("\(name): image impossible"); return }
        do { try data.write(to: outDir.appendingPathComponent(name + (jpeg ? ".jpg" : ".png"))) } catch { report.append("\(name): \(error)") }
    }

    private func appearance(_ dark: Bool) -> NSAppearance? { NSAppearance(named: dark ? .darkAqua : .aqua) }

    /// Rendu dans une vraie fenêtre (hors écran) : ScrollView, champs et menus sont dessinés.
    @discardableResult
    private func window<V: View>(_ name: String, width: CGFloat, height: CGFloat, dark: Bool = true, wait: TimeInterval = 0.35,
                                 @ViewBuilder _ view: () -> V) -> NSBitmapImageRep? {
        NSApplication.shared.appearance = appearance(dark)
        let root = view()
            .environmentObject(app).environmentObject(data).environmentObject(tracker)
            .environmentObject(updater).environmentObject(presenter)
            .frame(width: width, height: height)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: NSRect(x: 40, y: 40, width: width, height: height),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = appearance(dark)
        win.isReleasedWhenClosed = false
        win.contentView = host
        win.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(wait))
        host.layoutSubtreeIfNeeded()
        win.displayIfNeeded()
        defer { win.orderOut(nil); win.contentView = nil }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        host.cacheDisplay(in: host.bounds, to: rep)
        write(rep, name, jpeg: true)
        return rep
    }

    /// Rendu direct par SwiftUI (ImageRenderer) : fiable pour les graphiques, sans fenêtre.
    @discardableResult
    private func image<V: View>(_ name: String, width: CGFloat, dark: Bool = true, @ViewBuilder _ view: () -> V) -> NSBitmapImageRep? {
        NSApplication.shared.appearance = appearance(dark)
        let content = view()
            .environmentObject(app).environmentObject(data).environmentObject(tracker)
            .environmentObject(updater).environmentObject(presenter)
            .layoutWidth(width)
            .frame(width: width)
            .padding(16)
            .background(Theme.bg)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        var out: NSBitmapImageRep?
        appearance(dark)?.performAsCurrentDrawingAppearance {
            if let cg = renderer.cgImage { out = NSBitmapImageRep(cgImage: cg) }
        }
        guard let rep = out else { report.append("\(name): rendu impossible"); return nil }
        write(rep, name)
        return rep
    }

    /// Compare deux rendus : mêmes dimensions ? Où sont les pixels différents ?
    private func compare(_ label: String, _ a: NSBitmapImageRep?, _ b: NSBitmapImageRep?) {
        guard let a, let b else { report.append("\(label): rendu manquant"); return }
        let sameSize = a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh
        var line = "\(label): sans survol \(a.pixelsWide)x\(a.pixelsHigh), avec survol \(b.pixelsWide)x\(b.pixelsHigh), tailles \(sameSize ? "identiques" : "DIFFERENTES")"
        if sameSize, let pa = a.bitmapData, let pb = b.bitmapData, a.bytesPerRow == b.bytesPerRow {
            let bpp = a.bitsPerPixel / 8
            var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
            for y in 0..<a.pixelsHigh {
                let row = y * a.bytesPerRow
                for x in 0..<a.pixelsWide {
                    let o = row + x * bpp
                    var diff = false
                    for k in 0..<bpp where abs(Int(pa[o + k]) - Int(pb[o + k])) > 6 { diff = true }
                    if diff { minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y) }
                }
            }
            line += maxX < 0 ? ", aucun pixel different" : ", pixels differents dans x \(minX)...\(maxX), y \(minY)...\(maxY)"
        }
        report.append(line)
    }

    private func shell(_ route: Route?) -> some View {
        ShellView(initialRoute: route)
            .foregroundStyle(Theme.text)
            .background { AmbientBackground() }
            .overlay(alignment: .bottom) { ToastView() }
            .tint(Theme.blue)
    }

    private func tag(_ w: CGFloat, _ dark: Bool) -> String { String(format: "w%04d-%@", Int(w), dark ? "sombre" : "clair") }

    // MARK: - Test

    func testSnapshots() throws {
        _ = NSApplication.shared
        SnapshotMode.on = true
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        app.loading = false
        populate()

        let widths: [CGFloat] = [700, 760, 900, 1100, 1200, 1440]
        let tall: CGFloat = 1500

        // --- Admin
        signIn("u-admin")
        let adminRoutes: [(String, Route, String?)] = [
            ("aujourdhui", .today, nil), ("missions", .missions, nil),
            ("agenda-mois", .agenda, "month"), ("agenda-semaine", .agenda, "week"), ("agenda-liste", .agenda, "list"),
            ("clients", .clients, nil), ("equipe", .team, nil), ("finances", .finances, nil),
            ("temps", .time, nil), ("mises-a-jour", .updates, nil),
        ]
        for (name, route, mode) in adminRoutes {
            if let mode { UserDefaults.standard.set(mode, forKey: "agendaMode") }
            for w in widths {
                window("admin-\(name)-\(tag(w, true))", width: w, height: tall) { shell(route) }
            }
            for w in [700, 1200] as [CGFloat] where ["aujourdhui", "finances", "agenda-mois", "agenda-semaine"].contains(name) {
                window("admin-\(name)-\(tag(w, false))", width: w, height: tall, dark: false) { shell(route) }
            }
        }
        UserDefaults.standard.set("month", forKey: "agendaMode")

        // Taille minimale de la fenêtre et fenêtres basses (barre latérale).
        window("admin-aujourdhui-min-700x540", width: 700, height: 540) { shell(.today) }
        window("admin-aujourdhui-1120x540", width: 1120, height: 540) { shell(.today) }
        window("admin-finances-760x560", width: 760, height: 560) { shell(.finances) }
        let prevMonth = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        for w in [760, 1200] as [CGFloat] {
            window("admin-paiements-mois-dernier-\(tag(w, true))", width: w, height: 2600) { FinancesView(month: prevMonth).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(Theme.bg) }
        }

        // Bandeau de mise à jour.
        updater.setPreviewRelease(AppRelease(id: "r1", version: "99.0.0", zip_path: "x.zip", dmg_path: "x.dmg",
                                             notes: "Nouveau calendrier, graphiques des finances et correctifs de mise en page pour les petites fenêtres",
                                             created_at: DateFmt.iso(Date())))
        for w in [700, 1200] as [CGFloat] {
            window("admin-bandeau-\(tag(w, true))", width: w, height: 700) { shell(.today) }
        }
        updater.setPreviewRelease(nil)

        // Fiche mission (admin) et création.
        for id in ["m5", "m3", "m6", "m7", "m9"] {
            presenter.mission = .existing(id)
            for w in [700, 900, 1440] as [CGFloat] {
                window("fiche-\(id)-admin-\(tag(w, true))", width: w, height: w < 800 ? 900 : 1000) { shell(.missions) }
            }
        }
        presenter.mission = .existing("m5")
        window("fiche-m5-admin-min-700x540", width: 700, height: 540) { shell(.missions) }
        window("fiche-m5-admin-\(tag(700, false))", width: 700, height: 900, dark: false) { shell(.missions) }
        presenter.mission = .new
        for w in [700, 900, 1440] as [CGFloat] {
            window("fiche-nouvelle-\(tag(w, true))", width: w, height: 1000) { shell(.missions) }
        }
        presenter.mission = nil

        // Notifications et connexion.
        window("notifications-sombre", width: 360, height: 420) {
            NotificationsPanel(onClose: {}).background(Theme.bg)
        }
        window("connexion-700x540-sombre", width: 700, height: 540) {
            LoginView().foregroundStyle(Theme.text).background { AmbientBackground() }
        }

        // --- Monteur
        signIn("u-leo")
        let editorRoutes: [(String, Route)] = [("tableau-de-bord", .myDashboard), ("mes-missions", .myMissions), ("finances", .myFinances)]
        for (name, route) in editorRoutes {
            for w in widths {
                window("monteur-\(name)-\(tag(w, true))", width: w, height: name == "tableau-de-bord" ? 2300 : tall) { shell(route) }
            }
            window("monteur-\(name)-\(tag(700, false))", width: 700, height: name == "tableau-de-bord" ? 2300 : tall, dark: false) { shell(route) }
        }
        let prevMonthE = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        for w in [700, 1200] as [CGFloat] {
            window("monteur-facture-mois-dernier-\(tag(w, true))", width: w, height: 1800) { MyFinancesView(month: prevMonthE).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).background(Theme.bg) }
        }
        presenter.mission = .existing("m5")
        for w in [700, 1440] as [CGFloat] {
            window("fiche-m5-monteur-\(tag(w, true))", width: w, height: 1000) { shell(.myMissions) }
        }
        presenter.mission = nil

        // --- Client
        signIn("u-client")
        for w in [700, 1200] as [CGFloat] {
            window("client-projets-\(tag(w, true))", width: w, height: 900) { shell(.clientProjects) }
        }

        // --- Graphiques : sans survol puis survol simulé, géométrie comparée.
        signIn("u-admin")
        let trend = data.monthlyFinance(endingAt: Date())
        let month = trend.last?.month ?? Date()
        let hovered = trend.count > 4 ? trend[trend.count - 4].label : nil
        for w in [544, 760, 1100] as [CGFloat] {
            for mode in [0, 1] {
                let kind = mode == 0 ? "barres" : "courbes"
                for dark in [true, false] where dark || w == 760 {
                    let a = image("graph-evolution-\(kind)-\(tag(w, dark))-repos", width: w, dark: dark) {
                        FinanceTrendCard(points: trend, month: .constant(month), previewMode: mode)
                    }
                    let b = image("graph-evolution-\(kind)-\(tag(w, dark))-survol", width: w, dark: dark) {
                        FinanceTrendCard(points: trend, month: .constant(month), previewMode: mode, previewHover: hovered)
                    }
                    compare("evolution \(kind) largeur \(Int(w)) \(dark ? "sombre" : "clair")", a, b)
                }
            }
        }
        let inMonth = data.missions(inMonths: [month])
        let slices = data.editorSlices(data.missions(inMonths: trend.map(\.month)))
        for w in [260, 366, 760] as [CGFloat] {
            let a = image("graph-repartition-\(tag(w, true))-repos", width: w) {
                SliceBarsCard(title: "Par monteur", subtitle: "Budget montage réparti selon le temps passé", slices: slices, showTime: true)
            }
            let b = image("graph-repartition-\(tag(w, true))-survol", width: w) {
                SliceBarsCard(title: "Par monteur", subtitle: "Budget montage réparti selon le temps passé", slices: slices,
                              showTime: true, previewHover: slices.first?.name)
            }
            compare("repartition largeur \(Int(w))", a, b)
        }
        _ = inMonth

        signIn("u-leo")
        let days = data.dailyEarnings(user: "u-leo", from: at(-29, 0), to: Date())
        let hoverDay = days.last(where: { $0.amount > 0 })?.day
        for w in [420, 544, 1100] as [CGFloat] {
            for cumulative in [false, true] {
                let kind = cumulative ? "cumul" : "jour"
                let a = image("graph-gains-\(kind)-\(tag(w, true))-repos", width: w) {
                    DailyEarningsCard(title: "Mes gains par jour · 30 derniers jours", days: days, previewCumulative: cumulative)
                }
                let b = image("graph-gains-\(kind)-\(tag(w, true))-survol", width: w) {
                    DailyEarningsCard(title: "Mes gains par jour · 30 derniers jours", days: days, previewCumulative: cumulative, previewHover: hoverDay)
                }
                compare("gains \(kind) largeur \(Int(w))", a, b)
            }
        }
        // Même carte dans une vraie fenêtre (contrôle du rendu des graphiques par cacheDisplay).
        window("graph-gains-fenetre-sombre", width: 640, height: 420) {
            DailyEarningsCard(title: "Mes gains par jour · 30 derniers jours", days: days, previewHover: hoverDay)
                .layoutWidth(600).padding(20).background(Theme.bg)
        }

        report.append("captures: \((try? FileManager.default.contentsOfDirectory(atPath: outDir.path).count) ?? 0) fichiers")
        try report.joined(separator: "\n").write(to: outDir.appendingPathComponent("geometrie.txt"), atomically: true, encoding: .utf8)
        print(report.joined(separator: "\n"))
    }
}
