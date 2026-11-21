import SwiftUI
import AppKit
import Supabase

/// « Apps et site » : statistiques de FastSign, MinimaClap, Agora, de l'App Store et du site.
/// Les chiffres viennent de la fonction serveur apps-stats (admin uniquement, gardés 1 h en cache).
struct AppsStatsView: View {
    @State private var stats: [String: Any]? = nil
    @State private var loading = false
    @State private var error: String? = nil
    @State private var schedDays = 7
    @State private var editing: PostDraft? = nil
    @State private var tab = "summary"
    /// Dans Réglages : seulement le bloc des connexions.
    var connectionsOnly = false

    private var base: [String: Any]? { ok(stats?["base"]) }
    private var store: [String: Any]? { ok(stats?["store"]) }
    private var site: [String: Any]? { ok(stats?["site"]) }

    var body: some View {
        Page {
            PageHeader(kicker: connectionsOnly ? "Tes clés sont enregistrées côté serveur" : updatedLabel, title: connectionsOnly ? "Connexions" : "Marques") {
                Button { Task { await load(refresh: true) } } label: { Label(loading ? "Chargement…" : "Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(SecondaryButton()).disabled(loading)
            }
            if stats == nil {
                VStack(spacing: 10) {
                    if let error { Muted(error) } else { ProgressView().controlSize(.small); Muted("Chargement des statistiques…") }
                }
                .frame(maxWidth: .infinity).padding(30).glassCard()
            } else {
                if connectionsOnly {
                    connections
                } else {
                    ChipPicker(selection: $tab, options: [
                        .init(value: "summary", label: "Résumé"),
                        .init(value: "apps", label: "Apps"),
                        .init(value: "pubs", label: "Publications"),
                        .init(value: "site", label: "Site"),
                    ])
                    switch tab {
                    case "apps":
                        appCards
                        if let sub = ok(stats?["subs"]) { subsCard(sub) }
                        if let st = store { storeCard(st) }
                    case "pubs":
                        ScheduledPostsCard()
                        scheduleSection
                        instagramSection
                    case "site":
                        if let s = site { siteCard(s) } else { EmptyHint(text: "Le site n'est pas encore connecté. Ouvre Réglages, puis Connexions.") }
                    default:
                        tiles
                        if let st = store { storeCard(st) }
                    }
                }
            }
        }
        .task { await load(refresh: false) }
        .sheet(item: $editing) { d in
            PostEditor(draft: d, media: igMedia(for: d.url), handles: igHandles) { Task { await load(refresh: false) } }
        }
    }

    // MARK: blocs

    private var tiles: some View {
        let users = base?["users"].dict
        let dl = (store?["apps"] as? [[String: Any]])?.map { num($0["downloads"]) }.reduce(0, +)
        let week = site?["week"].dict
        return StatGrid {
            StatCard(label: "Comptes FastSign", value: users.map { fmt(num($0["total"])) } ?? "–",
                     foot: users.map { "+ \(Int(num($0["new7"]))) cette semaine" } ?? "indisponible",
                     footColor: num(users?["new7"]) > 0 ? Theme.green : Theme.muted)
            StatCard(label: "Actifs sur 7 jours", value: users.map { fmt(num($0["active7"])) } ?? "–",
                     foot: users.map { "\(Int(num($0["active30"]))) sur 30 jours" })
            StatCard(label: "Téléchargements 30 j", value: dl.map(fmt) ?? "–",
                     foot: dl == nil ? "App Store à connecter" : "toutes apps · App Store", footColor: dl == nil ? Theme.amber : Theme.muted)
            StatCard(label: "Visites du site 7 j", value: week.map { fmt(num($0["visits"])) } ?? "–",
                     foot: week.map { "\(fmt(num($0["views"]))) pages vues" } ?? "Cloudflare à connecter", footColor: week == nil ? Theme.amber : Theme.muted)
            StatCard(label: "Abonnés Instagram", value: igTotal.map(fmt) ?? "–", foot: igTotal == nil ? "indisponible" : "tous tes comptes")
            StatCard(label: "Abonnements actifs", value: subsPaid.map(fmt) ?? "–",
                     foot: subsPaid == nil ? "App Store à connecter" : "App Store", footColor: subsPaid == nil ? Theme.amber : Theme.muted)
        }
    }

    /// Utilisateurs d'une app (nil = non mesuré).
    private struct AppUsers { let total, new30, active7, active30: Double; var note: String? = nil }

    @ViewBuilder private var appCards: some View {
        if let b = base {
            let u = b["users"].dict ?? [:], f = b["fastsign"].dict ?? [:], c = b["minimaclap"].dict ?? [:], a = b["agora"].dict ?? [:]
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14, alignment: .top)], spacing: 14) {
                appCard("FastSign", "4C8DFF", storeKey: "fastsign",
                        users: AppUsers(total: num(u["total"]), new30: num(u["new30"]), active7: num(u["active7"]), active30: num(u["active30"])),
                        activity: (fmt(num(f["signatures30"])), "signature(s) · \(fmt(num(f["projects30"]))) projet(s)"))
                appCard("MinimaClap", "F5A524", storeKey: "clap",
                        users: c["devices"] == nil ? nil : AppUsers(total: num(c["devices"]), new30: num(c["devices_new30"]), active7: num(c["devices_active7"]), active30: num(c["devices_active30"]),
                                                               note: "MinimaClap n'a pas de compte : un utilisateur = un iPhone."),
                        activity: (fmt(num(c["projects30"] ?? c["projects"])), "projet(s) · \(fmt(num(c["joins30"]))) connexion(s) QR"))
                appCard("Agora", "C084FC", storeKey: "agora", users: nil,
                        activity: (fmt(num(a["posts30"] ?? a["posts"])), "publications suivies · \(fmt(num(a["translations"]))) traductions"))
            }
        } else {
            Muted((stats?["base"].dict?["error"] as? String) ?? "Statistiques des apps indisponibles.")
                .frame(maxWidth: .infinity).padding(24).glassCard()
        }
    }

    private func appCard(_ name: String, _ hex: String, storeKey: String, users: AppUsers?, activity: (String, String)) -> some View {
        let apps = ((store?["apps"] as? [[String: Any]]) ?? []).filter { (($0["name"] as? String) ?? "").lowercased().contains(storeKey) }
        let dl = apps.map { num($0["downloads"]) }.reduce(0, +), dl7 = apps.map { num($0["downloads7"]) }.reduce(0, +)
        let subs = ok(stats?["subs"]).map { s in ((s["plans"] as? [[String: Any]]) ?? []).filter { (($0["app"] as? String) ?? "").lowercased().contains(storeKey) } }
        let paid = subs?.map { num($0["paid"]) }.reduce(0, +), trial = subs?.map { num($0["trial"]) }.reduce(0, +)
        let color = Color(hex: hex)
        let hasStore = store != nil
        let mainApp = apps.first { !(($0["appleId"] as? String) ?? "").isEmpty }
        let tiles: [(String, String?, String?)] = [
            ("Téléchargements 30 j", hasStore ? fmt(dl) : nil, hasStore ? "\(fmt(dl7)) sur 7 j" : nil),
            ("Utilisateurs", users.map { fmt($0.total) }, users.map { "+ \(fmt($0.new30)) sur 30 j" }),
            ("Actifs 7 j", users.map { fmt($0.active7) }, users.map { "\(fmt($0.active30)) sur 30 j" }),
            ("Abonnés payants", paid.map(fmt), trial.map { "\(fmt($0)) en essai" }),
            ("Revenus 30 j", hasStore ? proceeds(apps.compactMap { $0["proceeds"] as? [String: Any] }) : nil, hasStore ? "App Store, net" : nil),
            ("Activité 30 j", activity.0, activity.1),
            ("Note App Store", mainApp.map { a in num(a["ratings"]) > 0 ? "★ " + String(format: "%.1f", num(a["rating"])).replacingOccurrences(of: ".", with: ",") : "–" },
             mainApp.map { a in num(a["ratings"]) > 0 ? "\(fmt(num(a["ratings"]))) avis" : "pas encore de note" }),
            ("Retéléch. et MAJ 30 j", hasStore ? fmt(apps.map { num($0["redownloads"]) }.reduce(0, +)) : nil,
             hasStore ? "retéléch. · \(fmt(apps.map { num($0["updates"]) }.reduce(0, +))) mises à jour" : nil),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(name).font(.system(size: 15, weight: .semibold))
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, t in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.0).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        Text(t.1 ?? "–").font(.system(size: 20, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text(t.2 ?? "non mesuré").font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(2)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                    .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            if let n = users?.note { Muted(n, size: 12) }
            if users == nil { Muted("Utilisateurs non mesurés : l'app ne remonte pas encore cette info.", size: 12) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
        .overlay(alignment: .top) { RoundedRectangle(cornerRadius: 1).fill(color).frame(height: 2).padding(.horizontal, 16) }
    }

    private func subsCard(_ sub: [String: Any]) -> some View {
        let plans = ((sub["plans"] as? [[String: Any]]) ?? []).sorted { num($0["paid"]) > num($1["paid"]) }
        let paid = plans.map { num($0["paid"]) }.reduce(0, +), trial = plans.map { num($0["trial"]) }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Abonnements actifs").font(.system(size: 15, weight: .semibold))
                Spacer()
                Muted((sub["day"] as? String).map { "rapport Apple du \($0)" } ?? "aucun rapport encore", size: 12.5)
            }
            HStack(spacing: 28) {
                VStack(alignment: .leading) { Text(fmt(paid)).font(.system(size: 24, weight: .bold)); Muted("payants", size: 12) }
                VStack(alignment: .leading) { Text(fmt(trial)).font(.system(size: 24, weight: .bold)); Muted("en essai gratuit", size: 12) }
            }
            ForEach(Array(plans.enumerated()), id: \.offset) { _, p in
                HStack {
                    Text("\(Self.appName(p["app"] as? String ?? "")) · \(Self.appName(p["plan"] as? String ?? ""))").font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(fmt(num(p["paid"])) + (num(p["trial"]) > 0 ? " + \(fmt(num(p["trial"]))) essai" : "")).font(.system(size: 13)).monospacedDigit()
                }
            }
        }
        .padding(18).glassCard()
    }

    // MARK: Instagram

    @ViewBuilder private var instagramSection: some View {
        let ig = stats?["ig"] as? [String: Any]
        let accounts = (ig?["accounts"] as? [[String: Any]]) ?? []
        if !accounts.isEmpty || ig?["error"] != nil {
            HStack {
                Text("Instagram").font(.system(size: 17, weight: .semibold))
                Spacer()
                Muted("\(fmt(accounts.filter { ($0["ok"] as? Bool) == true }.map { num($0["followers"]) }.reduce(0, +))) abonnés au total", size: 12.5)
            }
            .padding(.top, 8)
            if let e = ig?["error"] as? String { Muted(e).padding(14).glassCard() }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14, alignment: .top)], spacing: 14) {
                ForEach(Array(accounts.enumerated()), id: \.offset) { _, a in igCard(a) }
            }
            Muted("Ajouter ou retirer un compte suivi : version web, page Apps et site.", size: 12)
        }
    }

    private func igCard(_ a: [String: Any]) -> some View {
        let handle = a["handle"] as? String ?? ""
        let media = (a["media"] as? [[String: Any]]) ?? []
        let liked = media.filter { $0["likes"] is NSNumber }
        let avgLikes = liked.isEmpty ? nil : liked.map { num($0["likes"]) }.reduce(0, +) / Double(liked.count)
        let avgCom = liked.isEmpty ? nil : liked.map { num($0["comments"]) }.reduce(0, +) / Double(liked.count)
        let followers = num(a["followers"])
        let rate = (avgLikes != nil && followers > 0) ? ((avgLikes! + (avgCom ?? 0)) / followers * 100) : nil
        let d7 = a["d7"] as? NSNumber
        return VStack(alignment: .leading, spacing: 12) {
            if (a["ok"] as? Bool) != true {
                Text("@\(handle)").font(.system(size: 14, weight: .semibold))
                Text(a["error"] as? String ?? "Compte introuvable").font(.system(size: 12.5)).foregroundStyle(Theme.red)
            } else {
                HStack(spacing: 12) {
                    AsyncImage(url: URL(string: a["avatar"] as? String ?? "")) { img in img.resizable().scaledToFill() } placeholder: { Theme.card2 }
                        .frame(width: 44, height: 44).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a["label"] as? String ?? handle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Link("@\(handle)", destination: URL(string: "https://instagram.com/\(handle)")!).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(fmt(followers)).font(.system(size: 20, weight: .bold)).monospacedDigit()
                        Text(d7.map { $0.intValue == 0 ? "±0 sur 7 j" : ($0.intValue > 0 ? "+ \($0.intValue) sur 7 j" : "− \(-$0.intValue) sur 7 j") } ?? "abonnés")
                            .font(.system(size: 11.5)).foregroundStyle((d7?.intValue ?? 0) > 0 ? Theme.green : ((d7?.intValue ?? 0) < 0 ? Theme.red : Theme.muted))
                    }
                }
                HStack(spacing: 8) {
                    kpi("Posts", fmt(num(a["posts"])))
                    kpi("J'aime moy.", avgLikes.map(fmt) ?? "–")
                    kpi("Comment.", avgCom.map(fmt) ?? "–")
                    kpi("Engagement", rate.map { String(format: "%.1f %%", $0).replacingOccurrences(of: ".", with: ",") } ?? "–")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Array(media.enumerated()), id: \.offset) { _, m in
                        Link(destination: URL(string: m["url"] as? String ?? "https://instagram.com")!) {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    AsyncImage(url: URL(string: m["img"] as? String ?? "")) { img in img.resizable().scaledToFill() } placeholder: { Theme.card2 }
                                }
                                .overlay(alignment: .bottomLeading) {
                                    Text("♥ \(fmt(num(m["likes"]))) · \(fmt(num(m["comments"])))")
                                        .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.white)
                                        .padding(.horizontal, 6).padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .help(m["caption"] as? String ?? "")
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .glassCard()
    }

    private func kpi(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sur l'App Store, MinimaClap s'appelle encore Topclap (et son abonnement MinimaTime).
    static func appName(_ n: String) -> String {
        n.replacingOccurrences(of: "Topclap", with: "MinimaClap", options: .caseInsensitive).replacingOccurrences(of: "MinimaTime", with: "MinimaClap", options: .caseInsensitive)
    }

    private static let countries: [String: String] = ["BE": "Belgique", "FR": "France", "NL": "Pays-Bas", "LU": "Luxembourg", "DE": "Allemagne", "CH": "Suisse", "CA": "Canada",
        "US": "États-Unis", "GB": "Royaume-Uni", "ES": "Espagne", "IT": "Italie", "MA": "Maroc", "CD": "RD Congo", "SN": "Sénégal", "CI": "Côte d'Ivoire", "DZ": "Algérie", "TN": "Tunisie"]

    private func storeCard(_ st: [String: Any]) -> some View {
        let apps = ((st["apps"] as? [[String: Any]]) ?? []).filter { !(($0["appleId"] as? String) ?? "").isEmpty }.sorted { num($0["downloads"]) > num($1["downloads"]) }
        let all = (st["apps"] as? [[String: Any]]) ?? []
        let daily = (st["daily"] as? [[String: Any]]) ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App Store · 30 derniers jours").font(.system(size: 15, weight: .semibold))
                Spacer()
                Muted("Revenus nets " + proceeds(all.compactMap { $0["proceeds"] as? [String: Any] }), size: 12.5)
            }
            MiniBars(values: daily.map { num($0["n"]) }, labels: daily.map { "\($0["d"] as? String ?? "") : \(Int(num($0["n"]))) téléchargements" })
            if apps.isEmpty { Muted("Aucune vente sur la période.") }
            ForEach(Array(apps.enumerated()), id: \.offset) { _, a in storeApp(a) }
        }
        .padding(18).glassCard()
    }

    private func storeApp(_ a: [String: Any]) -> some View {
        let name = Self.appName(a["name"] as? String ?? "?")
        let color = Color(hex: name.range(of: "agora", options: .caseInsensitive) != nil ? "C084FC" : (name.range(of: "clap", options: .caseInsensitive) != nil || name.range(of: "minimatime", options: .caseInsensitive) != nil) ? "F5A524" : "4C8DFF")
        let daily = (a["daily"] as? [[String: Any]]) ?? []
        let top: (Any?) -> [[String: Any]] = { raw in
            ((raw as? [String: Any]) ?? [:]).map { ["k": $0.key, "n": $0.value] }.sorted { num($0["n"]) > num($1["n"]) }.prefix(4).map { $0 }
        }
        var info: [String] = []
        if let v = a["version"] as? String { info.append("Version \(v)") }
        if let r = a["released"] as? String, let d = DateFmt.parse(r) { info.append(d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE")))) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let ic = a["icon"] as? String, let u = URL(string: ic) {
                    AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Theme.card2 }
                        .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 6) {
                        Muted(info.joined(separator: " · "), size: 12)
                        if let s = a["url"] as? String, let u = URL(string: s) { Link("App Store", destination: u).font(.system(size: 12)) }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(fmt(num(a["downloads"]))).font(.system(size: 18, weight: .bold)).monospacedDigit()
                    Muted("téléch. 30 j", size: 11.5)
                }
            }
            MiniBars(values: daily.map { num($0["n"]) }, labels: daily.map { "\($0["d"] as? String ?? "") : \(Int(num($0["n"])))" })
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 20, alignment: .top)], spacing: 10) {
                topList("Pays", top(a["countries"])) { Self.countries[$0] ?? $0 }
                topList("Appareils", top(a["devices"])) { $0 }
                topList("En plus", [["k": "Retéléchargements", "n": num(a["redownloads"])], ["k": "Mises à jour", "n": num(a["updates"])], ["k": "Achats et abonnements", "n": num(a["iapUnits"])]]) { $0 }
            }
        }
        .padding(14)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Programme de publication

    private static let igBrand: [String: (String, String)] = ["fastsign.app": ("FastSign", "4C8DFF"), "agora.app.be": ("Agora", "C084FC"), "agenceimage.be": ("L'Agence Image", "F472B6"), "minimalist.belgium": ("Minimalist", "8B8D94")]
    private static let schedNext: [String: String] = ["Prêt": "Programmé", "Programmé": "Publié", "Publié": "Prêt", "À créer": "Prêt"]
    private static func schedColor(_ s: String) -> Color { s == "Prêt" ? Theme.green : s == "Programmé" ? Color(hex: "4C8DFF") : s == "À créer" ? Theme.amber : Theme.muted }

    private struct SchedRow: Identifiable { let id: Int; let handle: String; let at: Date; let format: String; let title: String; let status: String; let url: String? }

    private var schedRows: [SchedRow] {
        ((ok(stats?["sched"])?["rows"] as? [[String: Any]]) ?? []).compactMap { r in
            guard let at = (r["at"] as? String).flatMap(DateFmt.parse) else { return nil }
            return SchedRow(id: Int(num(r["id"])), handle: r["handle"] as? String ?? "", at: at, format: r["format"] as? String ?? "", title: r["title"] as? String ?? "", status: r["status"] as? String ?? "Prêt", url: r["post_url"] as? String)
        }
    }

    @ViewBuilder private var scheduleSection: some View {
        if let sc = ok(stats?["sched"]) {
            let rows = schedRows
            let cal = Calendar(identifier: .iso8601)
            let now = Date()
            let startToday = cal.startOfDay(for: now)
            let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)!
            let posts = rows.filter { $0.format != "Story" }
            let curWeek = posts.filter { thisWeek.contains($0.at) }
            let useNext = !curWeek.contains { $0.at >= now }
            let nextWeek = DateInterval(start: thisWeek.end, duration: thisWeek.duration)
            let week = useNext ? posts.filter { nextWeek.contains($0.at) } : curWeek
            let wLbl = useNext && !week.isEmpty ? "la semaine prochaine" : "cette semaine"
            let brands = ["fastsign.app", "agora.app.be", "agenceimage.be", "minimalist.belgium"].filter { h in rows.contains { $0.handle == h } }
            let late = posts.filter { $0.status != "Publié" && $0.at < startToday }
            let limit = cal.date(byAdding: .day, value: schedDays, to: now)!
            let up = rows.filter { $0.at >= startToday && $0.at <= limit }
            let days = Dictionary(grouping: up) { cal.startOfDay(for: $0.at) }.sorted { $0.key < $1.key }
            let todo = (sc["todo"] as? [[String: Any]]) ?? []
            Text("Publications").font(.system(size: 17, weight: .semibold)).padding(.top, 8)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Programme de publication").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if let u = (sc["until"] as? String).flatMap(DateFmt.parse) { Muted("planifié jusqu'au " + u.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE"))), size: 12.5) }
                }
                if !brands.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                        ForEach(brands, id: \.self) { h in
                            let l = week.filter { $0.handle == h }
                            let brand = Self.igBrand[h] ?? (h, "8B8D94")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(brand.0).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                                Text("\(l.filter { $0.status == "Publié" }.count)/\(l.count)").font(.system(size: 20, weight: .bold)).monospacedDigit()
                                Text("posts publiés \(wLbl)").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: brand.1).opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                if !late.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(late.count) post\(late.count > 1 ? "s" : "") pas encore vu\(late.count > 1 ? "s" : "") en ligne").font(.system(size: 13, weight: .semibold)).padding(.bottom, 4)
                        ForEach(late) { schedLine($0) }
                    }
                    .padding(12)
                    .background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if days.isEmpty { Muted("Rien de prévu sur cette période.") }
                ForEach(days, id: \.key) { entry in
                    Text(cal.isDateInToday(entry.key) ? "AUJOURD'HUI" : entry.key.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE"))).uppercased())
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.muted).padding(.top, 6)
                    ForEach(entry.value.sorted { $0.at < $1.at }) { schedLine($0) }
                }
                HStack(spacing: 10) {
                    Button { editing = PostDraft() } label: { Label("Ajouter une publication", systemImage: "plus") }.buttonStyle(PrimaryButton())
                    Button(schedDays == 7 ? "Voir 4 semaines" : "Voir 7 jours") { schedDays = schedDays == 7 ? 28 : 7 }.buttonStyle(SecondaryButton())
                    if let first = todo.first, let at = (first["at"] as? String).flatMap(DateFmt.parse) {
                        Text("\(todo.count) contenu\(todo.count > 1 ? "s" : "") encore à créer, le premier pour le \(at.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE"))))")
                            .font(.system(size: 12.5)).foregroundStyle(Theme.amber)
                    }
                }
                Muted("Les carrousels et reels publiés sont cochés tout seuls quand ils apparaissent sur Instagram. Les stories et les reels d'essai, tu les coches en cliquant sur leur statut. Clique sur une publication pour l'afficher et la modifier.", size: 12)
            }
            .padding(18).glassCard()
        }
    }

    private func schedLine(_ r: SchedRow) -> some View {
        let brand = Self.igBrand[r.handle] ?? (r.handle, "8B8D94")
        let bn = brand.0, bc = brand.1
        let col = Self.schedColor(r.status)
        return HStack(spacing: 8) {
            Text(r.at.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_BE")))).font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Theme.muted).frame(width: 44, alignment: .leading)
            Circle().fill(Color(hex: bc)).frame(width: 7, height: 7)
            Text(bn).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize()
            Text(r.format).font(.system(size: 11)).padding(.horizontal, 7).padding(.vertical, 2).background(Theme.card2, in: Capsule()).fixedSize()
            Text(r.title).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 6)
            Button { Task { await setSchedStatus(r) } } label: {
                Text(r.status).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(col)
                    .padding(.horizontal, 9).padding(.vertical, 3).background(col.opacity(0.15), in: Capsule())
            }
            .buttonStyle(.plain).help("Changer le statut")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { open(r) }
        .help("Afficher et modifier")
    }

    private func open(_ r: SchedRow) {
        let raw = ((ok(stats?["sched"])?["rows"] as? [[String: Any]]) ?? []).first { Int(num($0["id"])) == r.id }
        editing = PostDraft(rowId: r.id, handle: r.handle, format: r.format, title: r.title, status: r.status,
                            ref: raw?["ref"] as? String ?? "", url: r.url ?? "", at: r.at)
    }

    private var igHandles: [String] {
        let acc = ((stats?["ig"] as? [String: Any])?["accounts"] as? [[String: Any]] ?? []).compactMap { $0["handle"] as? String }
        var out = ["fastsign.app", "agora.app.be", "agenceimage.be", "minimalist.belgium"]
        for h in acc where !out.contains(h) { out.append(h) }
        return out
    }

    private func igMedia(for url: String) -> [String: Any]? {
        guard !url.isEmpty else { return nil }
        for a in ((stats?["ig"] as? [String: Any])?["accounts"] as? [[String: Any]] ?? []) {
            for m in (a["media"] as? [[String: Any]] ?? []) where (m["url"] as? String) == url { return m }
        }
        return nil
    }

    private func setSchedStatus(_ r: SchedRow) async {
        let next = Self.schedNext[r.status] ?? "Prêt"
        if var sc = stats?["sched"] as? [String: Any], var rows = sc["rows"] as? [[String: Any]], let i = rows.firstIndex(where: { Int(num($0["id"])) == r.id }) {
            rows[i]["status"] = next; sc["rows"] = rows; stats?["sched"] = sc
        }
        do {
            try await supa.from("ig_schedule").update(["status": next, "updated_at": ISO8601DateFormatter().string(from: Date())]).eq("id", value: r.id).execute()
        } catch {
            self.error = "Statut non enregistré : \(error.localizedDescription)"
        }
    }

    private func siteCard(_ s: [String: Any]) -> some View {
        let days = (s["days"] as? [[String: Any]]) ?? []
        let visits = days.map { num($0["visits"]) }.reduce(0, +), views = days.map { num($0["views"]) }.reduce(0, +)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("minimalistbelgium.com · 30 jours").font(.system(size: 15, weight: .semibold))
                Spacer()
                Muted("\(fmt(visits)) visites · \(fmt(views)) pages vues", size: 12.5)
            }
            MiniBars(values: days.map { num($0["visits"]) }, labels: days.map { "\($0["d"] as? String ?? "") : \(Int(num($0["visits"]))) visites" })
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 20, alignment: .top)], spacing: 10) {
                topList("Pages les plus vues", s["pages"]) { $0 == "/" ? "Accueil" : $0 }
                topList("Pays", s["countries"]) { $0 }
                topList("Provenance", s["refs"]) { $0 }
            }
        }
        .padding(18).glassCard()
    }

    private func topList(_ title: String, _ raw: Any?, _ label: @escaping (String) -> String) -> some View {
        let list = (raw as? [[String: Any]]) ?? []
        return VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.5).foregroundStyle(Theme.muted)
            if list.isEmpty { Muted("Pas encore de données.", size: 12.5) }
            ForEach(Array(list.enumerated()), id: \.offset) { _, x in
                HStack {
                    Text(label(x["k"] as? String ?? "?")).font(.system(size: 13)).lineLimit(1)
                    Spacer()
                    Text(fmt(num(x["n"]))).font(.system(size: 13)).monospacedDigit()
                }
            }
        }
    }

    @ViewBuilder private var connections: some View {
        let ascMissing = (stats?["store"].dict?["missing"] as? Bool) == true
        let cfMissing = (stats?["site"].dict?["missing"] as? Bool) == true
        let errs = [stats?["store"].dict?["error"] as? String, stats?["site"].dict?["error"] as? String].compactMap { $0 }
        if ascMissing || cfMissing || !errs.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "link").foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ascMissing || cfMissing ? "Connexions à faire" : "Une connexion ne répond pas").font(.system(size: 14, weight: .semibold))
                    Muted([ascMissing ? "App Store Connect (téléchargements et revenus)" : nil, cfMissing ? "Cloudflare (visites du site)" : nil].compactMap { $0 }.joined(separator: " · ")
                          + (errs.isEmpty ? "" : (ascMissing || cfMissing ? " · " : "") + errs.joined(separator: " · ")), size: 12.5)
                    Muted("Les clés se collent dans la version web, page Apps et site, en bas.", size: 12.5)
                }
                Spacer()
                Button("Ouvrir la version web") { NSWorkspace.shared.open(URL(string: "https://studio.minimalistbelgium.com/")!) }
                    .buttonStyle(SecondaryButton())
            }
            .padding(16).glassCard()
        }
    }

    // MARK: données

    private var igTotal: Double? {
        guard let acc = (stats?["ig"] as? [String: Any])?["accounts"] as? [[String: Any]], !acc.isEmpty else { return nil }
        return acc.filter { ($0["ok"] as? Bool) == true }.map { num($0["followers"]) }.reduce(0, +)
    }
    private var subsPaid: Double? {
        guard let s = ok(stats?["subs"]) else { return nil }
        return ((s["plans"] as? [[String: Any]]) ?? []).map { num($0["paid"]) }.reduce(0, +)
    }

    private var updatedLabel: String {
        guard let s = (stats?["cached"] as? String) ?? (stats?["at"] as? String), let d = DateFmt.parse(s) else { return "Statistiques de tes apps et de ton site" }
        return "Statistiques · mises à jour à " + d.formatted(.dateTime.hour().minute().locale(Locale(identifier: "fr_BE")))
    }

    private func load(refresh: Bool) async {
        loading = true
        defer { loading = false }
        do {
            let token = try await supa.auth.session.accessToken
            var req = URLRequest(url: Config.supabaseURL.appendingPathComponent("functions/v1/apps-stats").appending(queryItems: refresh ? [URLQueryItem(name: "refresh", value: "1")] : []))
            req.httpMethod = "POST"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(Config.supabaseKey, forHTTPHeaderField: "apikey")
            let (data, _) = try await URLSession.shared.data(for: req)
            stats = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            error = nil
        } catch {
            self.error = "Impossible de charger les statistiques : \(error.localizedDescription)"
        }
    }

    private func ok(_ x: Any?) -> [String: Any]? {
        guard let d = x as? [String: Any], (d["ok"] as? Bool) == true else { return nil }
        return d
    }
    private func num(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? Double(x as? String ?? "") ?? 0 }
    private func fmt(_ n: Double) -> String { Int(n.rounded()).formatted(.number.locale(Locale(identifier: "fr_BE"))) }
    private func proceeds(_ list: [[String: Any]]) -> String {
        var sum: [String: Double] = [:]
        for p in list { for (c, v) in p { sum[c, default: 0] += num(v) } }
        if sum.isEmpty { return "0 €" }
        return sum.sorted { $0.key < $1.key }.map { $0.key == "EUR" ? Money.eur($0.value.rounded()) : "\(fmt($0.value)) \($0.key)" }.joined(separator: " + ")
    }
}

private extension Optional where Wrapped == Any {
    var dict: [String: Any]? { self as? [String: Any] }
}

/// Petites barres (30 jours, semaines…) avec le détail au survol.
struct MiniBars: View {
    let values: [Double]
    let labels: [String]

    var body: some View {
        let mx = max(1, values.max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.blue, Theme.blue.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, 70 * v / mx))
                    .help(i < labels.count ? labels[i] : "")
            }
        }
        .frame(height: 70, alignment: .bottom)
    }
}
