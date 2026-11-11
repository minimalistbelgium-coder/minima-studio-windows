import Foundation
import SwiftUI
import AppKit
import Supabase

/// Données partagées de l'app : clients, séries, missions, équipe.
@MainActor
final class DataStore: ObservableObject {
    @Published var clients: [Client] = []
    @Published var series: [Series] = []
    @Published var missions: [Mission] = []
    @Published var members: [MissionMember] = []
    @Published var profiles: [Profile] = []
    @Published var finances: [String: MissionFinance] = [:]
    @Published var loaded = false
    @Published var lastError: String?
    /// Sessions en cours (admin) pour voir qui travaille.
    @Published var liveSessions: [WorkSession] = []
    /// Gains et temps du monteur connecté, par mission.
    @Published var mySplit: [String: MySplitRow] = [:]
    /// Notifications reçues (statuts, messages au client).
    @Published var notifications: [AppNotification] = []
    /// Lien de dépôt des montages (WeTransfer), réglé par l'admin.
    @Published var deliveryLink: String?
    /// Historique des versions livrées, toutes missions confondues.
    @Published var versions: [MissionVersion] = []
    /// Montages faits par Claude.
    @Published var aiWork: [AIWork] = []

    /// Sessions de travail visibles (toutes pour l'admin, celles de ses missions pour un monteur).
    @Published var sessions: [WorkSession] = []

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    private var isAdmin = false
    private var refreshTimer: Timer?

    /// Rafraîchit missions et sessions en direct toutes les 30 s.
    func startAutoRefresh() {
        guard refreshTimer == nil else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reload() }
        }
    }

    func load(admin: Bool) async {
        isAdmin = admin
        do {
            async let c: [Client] = supa.from("clients").select().order("name").execute().value
            async let s: [Series] = supa.from("series").select().order("name").execute().value
            async let m: [Mission] = supa.from("missions").select().order("deadline", ascending: true).execute().value
            async let mm: [MissionMember] = supa.from("mission_members").select().execute().value
            async let p: [Profile] = supa.from("profiles").select().order("created_at").execute().value
            clients = try await c
            series = try await s
            missions = try await m
            members = try await mm
            profiles = try await p
            if !admin && missions.isEmpty {
                // Comptes client : leurs projets passent par client_projects() (budgets masqués)
                missions = (try? await supa.rpc("client_projects").execute().value) ?? []
            }
            if admin {
                let f: [MissionFinance] = try await supa.from("mission_finance").select().execute().value
                finances = Dictionary(uniqueKeysWithValues: f.map { ($0.mission_id, $0) })
                await loadLive()
            } else {
                let rows: [MySplitRow] = (try? await supa.rpc("my_split").execute().value) ?? []
                mySplit = Dictionary(rows.map { ($0.mission_id, $0) }, uniquingKeysWith: { a, _ in a })
            }
            sessions = (try? await supa.from("sessions").select()
                .order("started_at", ascending: false).limit(4000).execute().value) ?? []
            await loadNotifications()
            let st: [AppSetting] = (try? await supa.from("app_settings").select().execute().value) ?? []
            deliveryLink = st.first { $0.key == "delivery_link" }?.value
            versions = (try? await supa.from("mission_versions").select()
                .order("created_at", ascending: true).execute().value) ?? []
            aiWork = (try? await supa.from("ai_work").select()
                .order("ended_at", ascending: false).execute().value) ?? []
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        loaded = true
    }

    func reload() async { await load(admin: isAdmin) }

    // MARK: lookups

    var team: [Profile] { profiles.filter { $0.active && $0.role != "none" } }
    func client(_ id: String?) -> Client? { clients.first { $0.id == id } }
    func profile(_ id: String?) -> Profile? { profiles.first { $0.id == id } }
    func seriesItem(_ id: String?) -> Series? { series.first { $0.id == id } }
    func memberIds(of missionId: String) -> [String] { members.filter { $0.mission_id == missionId }.map(\.user_id) }
    func memberProfiles(of missionId: String) -> [Profile] { memberIds(of: missionId).compactMap { profile($0) } }
    func mission(_ id: String) -> Mission? { missions.first { $0.id == id } }

    // MARK: clients

    @discardableResult
    func createClient(name: String) async throws -> Client {
        let color = Theme.palette[clients.count % Theme.palette.count]
        let c: Client = try await supa.from("clients")
            .insert(ClientInsert(name: name.trimmingCharacters(in: .whitespaces), color: "#" + color))
            .select().single().execute().value
        clients.append(c)
        clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return c
    }

    func deleteClient(_ c: Client) async throws {
        try await supa.from("clients").delete().eq("id", value: c.id).execute()
        clients.removeAll { $0.id == c.id }
    }

    // MARK: missions

    @discardableResult
    func createMission(_ insert: MissionInsert, memberIds: [String], clientPrice: Double?) async throws -> String {
        let m: Mission = try await supa.from("missions").insert(insert).select().single().execute().value
        if !memberIds.isEmpty {
            try await supa.from("mission_members")
                .insert(memberIds.map { MissionMember(mission_id: m.id, user_id: $0) })
                .execute()
        }
        if clientPrice != nil {
            try await supa.from("mission_finance")
                .upsert(MissionFinanceUpsert(mission_id: m.id, client_price: clientPrice, invoiced: false))
                .execute()
        }
        await reload()
        return m.id
    }

    func updateMission(_ id: String, _ update: MissionUpdate, memberIds: [String], clientPrice: Double?) async throws {
        try await supa.from("missions").update(update).eq("id", value: id).execute()
        let current = Set(self.memberIds(of: id))
        let wanted = Set(memberIds)
        for uid in current.subtracting(wanted) {
            try await supa.from("mission_members").delete().eq("mission_id", value: id).eq("user_id", value: uid).execute()
        }
        let toAdd = wanted.subtracting(current)
        if !toAdd.isEmpty {
            try await supa.from("mission_members").insert(toAdd.map { MissionMember(mission_id: id, user_id: $0) }).execute()
        }
        try await supa.from("mission_finance")
            .upsert(MissionFinanceUpsert(mission_id: id, client_price: clientPrice, invoiced: finances[id]?.invoiced ?? false))
            .execute()
        await reload()
    }

    func setStatus(_ m: Mission, _ status: String) async throws {
        if status == "v1_delivered" && ["assigned", "editing"].contains(m.status) {
            try await supa.rpc("mark_v1_delivered", params: ["m": m.id]).execute()
        } else {
            let validated = (status == "validated" || status == "paid") ? (m.validated_at ?? DateFmt.iso(Date())) : nil
            try await supa.from("missions").update(MissionStatusUpdate(status: status, validated_at: validated)).eq("id", value: m.id).execute()
        }
        await reload()
    }

    func setRushes(_ m: Mission, url: String) async throws {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        try await supa.from("missions")
            .update(RushesUpdate(rushes_url: clean.isEmpty ? nil : clean, rushes_added_at: clean.isEmpty ? nil : DateFmt.iso(Date())))
            .eq("id", value: m.id).execute()
        await reload()
    }

    func deleteMission(_ m: Mission) async throws {
        try await supa.from("missions").delete().eq("id", value: m.id).execute()
        await reload()
    }

    func split(for missionId: String) async -> [SplitRow] {
        do {
            let rows: [SplitRow] = try await supa.rpc("compute_split", params: ["m": missionId]).execute().value
            return rows
        } catch {
            return []
        }
    }

    // MARK: séries

    func createSeries(_ insert: SeriesInsert) async throws {
        try await supa.from("series").insert(insert).execute()
        await reload()
    }

    func setSeriesActive(_ s: Series, _ active: Bool) async throws {
        try await supa.from("series").update(SeriesActiveUpdate(active: active)).eq("id", value: s.id).execute()
        await reload()
    }

    func deleteSeries(_ s: Series) async throws {
        try await supa.from("series").delete().eq("id", value: s.id).execute()
        await reload()
    }

    /// Crée les missions des séries actives pour les prochains jours. Renvoie le nombre créé.
    func generateSeries(days: Int = 14) async throws -> Int {
        let n: Int = try await supa.rpc("generate_series_missions", params: ["days_ahead": days]).execute().value
        await reload()
        return n
    }

    // MARK: suivi en direct

    func loadLive() async {
        let since = DateFmt.iso(Date().addingTimeInterval(-120))
        let rows: [WorkSession] = (try? await supa.from("sessions").select()
            .eq("live", value: true).gte("ended_at", value: since).execute().value) ?? []
        liveSessions = rows.filter(\.isLiveNow)
    }

    func liveSession(for missionId: String) -> [WorkSession] {
        liveSessions.filter { $0.mission_id == missionId }
    }

    /// Part estimée du monteur connecté sur une mission (avant tout temps enregistré : budget partagé à parts égales).
    func myShare(of m: Mission) -> (amount: Double, estimated: Bool) {
        if let r = mySplit[m.id], let a = r.amount { return (a, false) }
        let n = max(1, memberIds(of: m.id).count)
        return ((m.editor_budget ?? 0) / Double(n), true)
    }

    // MARK: temps et répartition (calculés à partir des sessions)

    func sessions(for missionId: String) -> [WorkSession] { sessions.filter { $0.mission_id == missionId } }

    func aiWork(for missionId: String) -> [AIWork] { aiWork.filter { $0.mission_id == missionId } }

    /// Temps humain de référence : moyenne des 5 dernières missions livrées du même client, montées sans Claude.
    func humanReference(_ m: Mission) -> (seconds: Double, count: Int)? {
        let done: Set<String> = ["v1_delivered", "revisions", "fix_delivered", "validated", "paid"]
        let refs = missions
            .filter { $0.id != m.id && $0.client_id == m.client_id && done.contains($0.status) && aiWork(for: $0.id).isEmpty }
            .map { x in (x, seconds(mission: x.id)) }
            .filter { $0.1 >= 600 }
            .sorted { (DateFmt.parse($0.0.v1_delivered_at ?? $0.0.created_at) ?? .distantPast) > (DateFmt.parse($1.0.v1_delivered_at ?? $1.0.created_at) ?? .distantPast) }
            .prefix(5)
        guard !refs.isEmpty else { return nil }
        return (refs.map(\.1).reduce(0, +) / Double(refs.count), refs.count)
    }

    /// Temps que Claude a fait gagner sur une mission (nil si pas de référence).
    func claudeSaved(_ m: Mission) -> (saved: Double, reference: Double, count: Int)? {
        let ai = aiWork(for: m.id).map { Double($0.duration_sec ?? 0) }.reduce(0, +)
        guard ai > 0, let ref = humanReference(m) else { return nil }
        return (max(0, ref.seconds - ai), ref.seconds, ref.count)
    }

    func seconds(mission: String, user: String? = nil) -> Double {
        sessions.filter { $0.mission_id == mission && (user == nil || $0.user_id == user) }
            .map { Double($0.duration_sec ?? 0) }.reduce(0, +)
    }

    /// Même règle que la base : l'admin compte ×1,5 seulement s'il partage la mission avec quelqu'un.
    func localSplit(_ m: Mission) -> [SplitRow] {
        var byUser: [String: Double] = [:]
        for s in sessions(for: m.id) { byUser[s.user_id, default: 0] += Double(s.duration_sec ?? 0) }
        let shared = byUser.count > 1
        let weighted = byUser.map { uid, secs -> (String, Double, Double) in
            let w = (shared && profile(uid)?.role == "admin") ? (m.admin_weight ?? 1.5) : 1
            return (uid, secs, secs * w)
        }
        let total = weighted.map { $0.2 }.reduce(0, +)
        guard total > 0 else { return [] }
        let budget = m.editor_budget ?? 0
        return weighted.map { uid, secs, w in
            SplitRow(user_id: uid, seconds: secs, weighted: w, percent: (100 * w / total * 10).rounded() / 10,
                     amount: (budget * w / total * 100).rounded() / 100)
        }.sorted { ($0.amount ?? 0) > ($1.amount ?? 0) }
    }

    /// Ce que l'admin reverse aux monteurs sur une mission (sa propre part exclue).
    func editorPayout(_ m: Mission) -> Double {
        let split = localSplit(m)
        if !split.isEmpty {
            return split.filter { profile($0.user_id)?.role != "admin" }.compactMap(\.amount).reduce(0, +)
        }
        let hasEditor = memberProfiles(of: m.id).contains { $0.role != "admin" }
        return hasEditor ? (m.editor_budget ?? 0) : 0
    }

    /// Missions dont la deadline (ou la création) tombe dans le mois donné.
    func missions(inMonthOf month: Date) -> [Mission] {
        missions.filter { m in
            guard let d = m.deadlineDate ?? DateFmt.parse(m.created_at) else { return false }
            return Calendar.current.isDate(d, equalTo: month, toGranularity: .month)
        }
    }

    // MARK: équipe

    func setRole(_ p: Profile, role: String, clientId: String?) async throws {
        try await supa.from("profiles")
            .update(ProfileRoleUpdate(role: role, active: role != "none", client_id: role == "client" ? clientId : nil))
            .eq("id", value: p.id).execute()
        try await supa.from("team_invites")
            .upsert(InviteInsert(email: p.email.lowercased(), role: role == "none" ? "editor" : role, client_id: role == "client" ? clientId : nil))
            .execute()
        await reload()
    }

    // MARK: PDF du brief

    func uploadBriefFiles(missionId: String, urls: [URL], keep: [BriefFile]) async throws -> [BriefFile] {
        var files = keep
        let bucket = supa.storage.from("briefs")
        for url in urls {
            let safe = url.deletingPathExtension().lastPathComponent
                .folding(options: .diacriticInsensitive, locale: nil)
                .replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
            let path = "\(missionId)/\(Int(Date().timeIntervalSince1970))-\(safe).pdf"
            let data = try Data(contentsOf: url)
            try await bucket.upload(path, data: data, options: FileOptions(contentType: "application/pdf", upsert: true))
            files.append(BriefFile(path: path, name: url.lastPathComponent))
        }
        try await supa.from("missions").update(BriefFilesUpdate(brief_files: files)).eq("id", value: missionId).execute()
        return files
    }

    func removeBriefFiles(_ files: [BriefFile]) async {
        guard !files.isEmpty else { return }
        _ = try? await supa.storage.from("briefs").remove(paths: files.map(\.path))
    }

    /// Télécharge le PDF et l'ouvre dans Aperçu.
    func openBriefFile(_ f: BriefFile) async throws {
        let url = try await supa.storage.from("briefs").createSignedURL(path: f.path, expiresIn: 600)
        let (tmp, _) = try await URLSession.shared.download(from: url)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MinimaBriefs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(f.name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        NSWorkspace.shared.open(dest)
    }

    // MARK: statut monteur et notifications

    /// Le monteur (ou l'admin) indique où il en est. Les admins reçoivent une notification.
    func editorSetStatus(_ m: Mission, _ status: String) async throws {
        try await supa.rpc("editor_set_status", params: ["m": m.id, "s": status]).execute()
        await reload()
    }

    /// Prévient les comptes client liés au client de la mission. Renvoie le nombre de personnes prévenues.
    @discardableResult
    func notifyClient(_ missionId: String, message: String) async throws -> Int {
        let n: Int = try await supa.rpc("notify_client", params: ["m": missionId, "msg": message]).execute().value
        await loadNotifications()
        return n
    }

    func hasClientAccount(_ m: Mission) -> Bool {
        guard let c = m.client_id else { return false }
        return profiles.contains { $0.role == "client" && $0.active && $0.client_id == c }
    }

    func dismissNotification(_ n: AppNotification) async {
        _ = try? await supa.from("notifications").update(NotificationHandled(handled: true)).eq("id", value: n.id).execute()
        await loadNotifications()
    }

    /// Marque une notification comme lue dès qu'on clique dessus.
    func markRead(_ n: AppNotification) async {
        guard !n.isRead else { return }
        _ = try? await supa.from("notifications").update(NotificationRead(read_at: DateFmt.iso(Date()))).eq("id", value: n.id).execute()
        await loadNotifications()
    }

    func markAllRead() async {
        guard unreadCount > 0 else { return }
        let now = DateFmt.iso(Date())
        for n in notifications where !n.isRead {
            _ = try? await supa.from("notifications").update(NotificationRead(read_at: now)).eq("id", value: n.id).execute()
        }
        await loadNotifications()
    }

    func loadNotifications() async {
        let list: [AppNotification] = (try? await supa.from("notifications").select()
            .order("created_at", ascending: false).limit(50).execute().value) ?? []
        notifications = list
        SystemNotifier.post(list.filter { !$0.isRead })
    }

    func comments(for missionId: String) async -> [MissionComment] {
        (try? await supa.from("mission_comments").select().eq("mission_id", value: missionId)
            .order("created_at", ascending: true).execute().value) ?? []
    }

    func addComment(_ missionId: String, body: String) async throws {
        try await supa.rpc("add_comment", params: ["m": missionId, "body": body]).execute()
    }

    func setVersionLink(_ m: Mission, url: String) async throws {
        try await supa.rpc("set_delivery_url", params: ["m": m.id, "url": url]).execute()
        await reload()
    }

    func versions(of missionId: String) -> [MissionVersion] { versions.filter { $0.mission_id == missionId } }

    /// Livraison en une étape : enregistre le lien de la version et passe le statut à « livrée ».
    func deliver(_ m: Mission, url: String) async throws {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        try await supa.rpc("set_delivery_url", params: ["m": m.id, "url": clean]).execute()
        let next = m.status == "revisions" ? "fix_delivered" : "v1_delivered"
        try await supa.rpc("editor_set_status", params: ["m": m.id, "s": next]).execute()
        await reload()
    }

    /// Refuse une demande client : elle est supprimée et le client est prévenu.
    func refuseRequest(_ m: Mission, reason: String) async throws {
        try await supa.rpc("refuse_request", params: ["m": m.id, "reason": reason]).execute()
        await reload()
    }

    /// Copie une mission une semaine plus tard (« épisode 50 » devient « épisode 51 »).
    @discardableResult
    func duplicateMission(_ m: Mission) async throws -> String {
        var deadline: String?
        if let d = m.deadlineDate, let next = Calendar.current.date(byAdding: .day, value: 7, to: d) { deadline = DateFmt.iso(next) }
        let insert = MissionInsert(client_id: m.client_id, title: DataStore.nextTitle(m.title), brief: m.brief,
                                   editor_budget: m.editor_budget ?? 0, deadline: deadline, rushes_url: nil, rushes_added_at: nil)
        return try await createMission(insert, memberIds: memberIds(of: m.id), clientPrice: finances[m.id]?.client_price)
    }

    static func nextTitle(_ title: String) -> String {
        let chars = Array(title)
        guard let end = chars.lastIndex(where: { $0.isASCII && $0.isNumber }) else { return title + " (copie)" }
        var start = end
        while start > 0 && chars[start - 1].isASCII && chars[start - 1].isNumber { start -= 1 }
        guard let n = Int(String(chars[start...end])) else { return title + " (copie)" }
        return String(chars[..<start]) + String(n + 1) + String(chars[(end + 1)...])
    }

    func setDeliveryLink(_ url: String) async throws {
        let clean = url.trimmingCharacters(in: .whitespacesAndNewlines)
        try await supa.from("app_settings").upsert(AppSetting(key: "delivery_link", value: clean.isEmpty ? nil : clean)).execute()
        deliveryLink = clean.isEmpty ? nil : clean
    }

    // MARK: client

    func clientSetRushes(_ m: Mission, url: String) async throws {
        try await supa.rpc("client_set_rushes", params: ["m": m.id, "url": url]).execute()
        await reload()
    }
}
