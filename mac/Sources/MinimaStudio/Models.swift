import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: String
    let email: String
    let full_name: String?
    let avatar_url: String?
    let role: String
    let color: String
    let active: Bool
    let created_at: String
    let client_id: String?

    var isAdmin: Bool { role == "admin" }
    var roleLabel: String { Roles.label(role) }

    var displayName: String { (full_name?.isEmpty == false ? full_name! : email) }
    var firstName: String { displayName.split(whereSeparator: { $0 == " " || $0 == "@" }).first.map(String.init) ?? displayName }
    var initials: String {
        let parts = displayName.split(whereSeparator: { " @._-".contains($0) }).prefix(2)
        return parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }
}

struct TeamInvite: Codable, Identifiable, Hashable {
    let email: String
    let invited_at: String
    let accepted_at: String?
    let role: String?
    let client_id: String?
    var id: String { email }
}

struct InviteInsert: Encodable { let email: String; let role: String; let client_id: String? }

enum Roles {
    static let assignable = ["editor", "admin", "client"]
    static func label(_ r: String) -> String {
        switch r {
        case "admin": return "Admin"
        case "editor": return "Monteur"
        case "client": return "Client"
        default: return "Sans accès"
        }
    }
    static func color(_ r: String) -> String {
        switch r {
        case "admin": return "4C8DFF"
        case "editor": return "3DD68C"
        case "client": return "F472B6"
        default: return "8B8D94"
        }
    }
}

struct ProfileRoleUpdate: Encodable { let role: String; let active: Bool; let client_id: String? }

enum DateFmt {
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoNoFrac = ISO8601DateFormatter()

    static func parse(_ s: String) -> Date? { iso.date(from: s) ?? isoNoFrac.date(from: s) }

    static func short(_ s: String) -> String {
        guard let d = parse(s) else { return "" }
        return d.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "fr_BE")))
    }

    static func todayLabel() -> String {
        let s = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

// MARK: - Clients, séries, missions

struct Client: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let color: String
}

struct ClientInsert: Encodable { let name: String; let color: String }

struct Series: Codable, Identifiable, Hashable {
    let id: String
    let client_id: String
    let name: String
    let editor_budget: Double?
    let default_editor: String?
    let weekdays: [Int]?
    let deadline_time: String?
    let brief: String?
    let active: Bool

    var daysLabel: String {
        let names = ["", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
        return (weekdays ?? []).sorted().compactMap { (1...7).contains($0) ? names[$0] : nil }.joined(separator: " · ")
    }
    var timeLabel: String { String((deadline_time ?? "18:00").prefix(5)) }
}

struct SeriesInsert: Encodable {
    let client_id: String
    let name: String
    let editor_budget: Double
    let default_editor: String?
    let weekdays: [Int]
    let deadline_time: String
    let brief: String?
}

struct SeriesActiveUpdate: Encodable { let active: Bool }

struct Mission: Codable, Identifiable, Hashable {
    let id: String
    let client_id: String?
    let series_id: String?
    let title: String
    let brief: String?
    let editor_budget: Double?
    let deadline: String?
    let rushes_url: String?
    let rushes_added_at: String?
    let status: String
    let admin_weight: Double?
    let split_comment: String?
    let v1_delivered_at: String?
    let validated_at: String?
    let created_at: String
    let premiere_key: String?
    let brief_files: [BriefFile]?
    var delivery_url: String? = nil
    /// Claude est choisi comme monteur de cette mission (défini par l'admin).
    var claude_editor: Bool? = nil
    /// Mois où le monteur facture la mission (« 2026-10-01 »), choisi par l'admin. Vide : mois de la première livraison.
    var bill_month: String? = nil

    var hasClaude: Bool { claude_editor ?? false }
    var isDelivered: Bool { ["v1_delivered", "revisions", "fix_delivered", "validated", "paid"].contains(status) }
    var clientPaid: Bool { status == "paid" }
    /// Mois de facturation du monteur (nil : pas encore livrée).
    var billMonth: Date? {
        let cal = Calendar.current
        func month(_ d: Date?) -> Date? { d.flatMap { cal.dateInterval(of: .month, for: $0)?.start } }
        if let b = bill_month, let d = BillMonth.parse(b) { return d }
        if let v = v1_delivered_at, let d = DateFmt.parse(v) { return month(d) }
        if isDelivered { return month(validated_at.flatMap(DateFmt.parse) ?? deadlineDate ?? DateFmt.parse(created_at)) }
        return nil
    }
    /// Mois de rattachement pour les finances : facturation, sinon deadline.
    var workMonth: Date? {
        billMonth ?? Calendar.current.dateInterval(of: .month, for: deadlineDate ?? DateFmt.parse(created_at) ?? Date())?.start
    }
    var missionDay: Date? { v1_delivered_at.flatMap(DateFmt.parse) ?? deadlineDate ?? DateFmt.parse(created_at) }
    var files: [BriefFile] { brief_files ?? [] }
    var deadlineDate: Date? { deadline.flatMap(DateFmt.parse) }
    var isOpen: Bool { !["validated", "paid"].contains(status) }
    var isLate: Bool {
        guard let d = deadlineDate else { return false }
        return d < Date() && ["assigned", "editing"].contains(status)
    }
}

struct MissionInsert: Encodable {
    let client_id: String?
    let title: String
    let brief: String?
    let editor_budget: Double
    let deadline: String?
    let rushes_url: String?
    let rushes_added_at: String?
    var claude_editor: Bool = false
}

struct BriefFile: Codable, Hashable, Identifiable {
    let path: String
    let name: String
    var id: String { path }
}

struct BriefFilesUpdate: Encodable { let brief_files: [BriefFile] }

struct MissionUpdate: Encodable {
    let client_id: String?
    let title: String
    let brief: String?
    let editor_budget: Double
    let deadline: String?
    let rushes_url: String?
    var claude_editor: Bool = false
}

struct MissionStatusUpdate: Encodable {
    let status: String
    let validated_at: String?
}

struct RushesUpdate: Encodable { let rushes_url: String?; let rushes_added_at: String? }

struct MissionFinance: Codable, Hashable {
    let mission_id: String
    let client_price: Double?
    let invoiced: Bool?
    let notes: String?
}

struct MissionFinanceUpsert: Encodable {
    let mission_id: String
    let client_price: Double?
    let invoiced: Bool
}

struct MissionMember: Codable, Hashable {
    let mission_id: String
    let user_id: String
}

struct SplitRow: Codable, Hashable, Identifiable {
    let user_id: String
    let seconds: Double?
    let weighted: Double?
    let percent: Double?
    let amount: Double?
    var id: String { user_id }
}

enum MissionStatus {
    static let all = ["requested", "assigned", "editing", "v1_delivered", "revisions", "fix_delivered", "validated", "paid"]
    /// Statuts que le monteur peut choisir lui-même.
    static let editorChoices = ["editing", "v1_delivered", "fix_delivered"]
    static func label(_ s: String) -> String {
        switch s {
        case "requested": return "Demande"
        case "assigned": return "Assignée"
        case "editing": return "En montage"
        case "v1_delivered": return "V1 livrée"
        case "revisions": return "Retours"
        case "fix_delivered": return "Corrections livrées"
        case "validated": return "Validée"
        case "paid": return "Client payé"
        default: return s
        }
    }
    static func color(_ s: String) -> String {
        switch s {
        case "requested": return "F472B6"
        case "assigned": return "8B8D94"
        case "editing": return "4C8DFF"
        case "v1_delivered": return "A78BFA"
        case "revisions": return "F5A524"
        case "fix_delivered": return "C084FC"
        case "validated": return "3DD68C"
        case "paid": return "2DD4BF"
        default: return "8B8D94"
        }
    }
}

extension DateFmt {
    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }
    static func deadline(_ d: Date?) -> String {
        guard let d else { return "Sans deadline" }
        let s = d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    static func relative(_ d: Date?) -> String {
        guard let d else { return "" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Aujourd'hui" }
        if cal.isDateInTomorrow(d) { return "Demain" }
        if cal.isDateInYesterday(d) { return "Hier" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        return days > 0 ? "Dans \(days) j" : "Il y a \(-days) j"
    }
}

enum TimeFmt {
    static func hm(_ seconds: Double?) -> String {
        let s = Int(seconds ?? 0)
        let h = s / 3600, m = (s % 3600) / 60
        return h > 0 ? "\(h) h \(String(format: "%02d", m))" : "\(m) min"
    }
}


// MARK: - Sessions de travail

/// Un montage fait par Claude (enregistré par l'automatisation des podcasts).
struct AIWork: Codable, Identifiable, Hashable {
    let id: String
    let mission_id: String
    let agent: String?
    let started_at: String
    let ended_at: String
    let duration_sec: Int?
    let notes: String?
}

/// Paiement mensuel d'un monteur par l'admin (différent du paiement par le client).
struct EditorPayment: Codable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let month: String
    let amount: Double
    let paid_at: String
    let note: String?
}

struct EditorPaymentUpsert: Encodable {
    let user_id: String
    let month: String
    let amount: Double
    let paid_at: String
}

/// Met à jour bill_month en écrivant null explicitement quand on revient au mode automatique.
struct BillMonthUpdate: Encodable {
    let bill_month: String?
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let b = bill_month { try c.encode(b, forKey: .bill_month) } else { try c.encodeNil(forKey: .bill_month) }
    }
    enum CodingKeys: String, CodingKey { case bill_month }
}

enum BillMonth {
    private static let f: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    static func parse(_ s: String) -> Date? { f.date(from: String(s.prefix(10))) }
    static func key(_ d: Date) -> String { f.string(from: Calendar.current.dateInterval(of: .month, for: d)?.start ?? d) }
    static func label(_ d: Date) -> String {
        let s = d.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}

struct AIWorkInsert: Encodable {
    let mission_id: String
    let started_at: String
    let ended_at: String
    let notes: String?
}

struct WorkSession: Codable, Identifiable, Hashable {
    let id: String
    let mission_id: String
    let user_id: String
    let started_at: String
    let ended_at: String?
    let duration_sec: Int?
    let source: String?
    let live: Bool?
    let project_path: String?

    var isLiveNow: Bool {
        guard live == true, let e = ended_at.flatMap(DateFmt.parse) else { return false }
        return Date().timeIntervalSince(e) < 120
    }
}

struct SessionInsert: Encodable {
    let id: String
    let mission_id: String
    let user_id: String
    let started_at: String
    let ended_at: String
    let duration_sec: Int
    let source: String
    let live: Bool
    let project_path: String?
}

struct SessionHeartbeat: Encodable {
    let ended_at: String
    let duration_sec: Int
    let live: Bool
}

struct MySplitRow: Codable, Hashable {
    let mission_id: String
    let seconds: Double?
    let percent: Double?
    let amount: Double?
}

struct MonthTime: Codable, Hashable {
    let month: String
    let seconds: Double?
}

// MARK: - Versions de l'app

struct AppRelease: Codable, Identifiable, Hashable {
    let id: String
    let version: String
    let zip_path: String
    let dmg_path: String?
    let notes: String?
    let created_at: String
}

struct AppReleaseInsert: Encodable {
    let version: String
    let zip_path: String
    let dmg_path: String?
    let notes: String?
}

enum AppVersion {
    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0" }
    /// true si a > b (comparaison 1.2.10 > 1.2.9)
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}


// MARK: - Notifications

struct AppNotification: Codable, Identifiable, Hashable {
    let id: String
    let user_id: String
    let mission_id: String?
    let from_user: String?
    let kind: String
    let title: String
    let body: String?
    let status: String?
    let handled: Bool
    let created_at: String
    let read_at: String?

    var isRead: Bool { read_at != nil }
}

struct NotificationRead: Encodable { let read_at: String }
struct NotificationHandled: Encodable { let handled: Bool }

struct MissionComment: Codable, Identifiable, Hashable {
    let id: String
    let mission_id: String
    let author: String?
    let body: String
    let kind: String
    let created_at: String
}

struct AppSetting: Codable, Hashable { let key: String; let value: String? }

/// Une version livrée (V1, V2…) : chaque nouveau lien est gardé dans l'historique.
struct MissionVersion: Codable, Identifiable, Hashable {
    let id: String
    let mission_id: String
    let url: String
    let label: String
    let created_by: String?
    let created_at: String
}
