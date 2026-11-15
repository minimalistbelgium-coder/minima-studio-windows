import SwiftUI
import AppKit
import Supabase

/// « Apps et site » : statistiques de FastSign, MinimaClap, Agora, de l'App Store et du site.
/// Les chiffres viennent de la fonction serveur apps-stats (admin uniquement, gardés 1 h en cache).
struct AppsStatsView: View {
    @State private var stats: [String: Any]? = nil
    @State private var loading = false
    @State private var error: String? = nil

    private var base: [String: Any]? { ok(stats?["base"]) }
    private var store: [String: Any]? { ok(stats?["store"]) }
    private var site: [String: Any]? { ok(stats?["site"]) }

    var body: some View {
        Page {
            PageHeader(kicker: updatedLabel, title: "Apps et site") {
                Button { Task { await load(refresh: true) } } label: { Label(loading ? "Chargement…" : "Actualiser", systemImage: "arrow.clockwise") }
                    .buttonStyle(SecondaryButton()).disabled(loading)
            }
            if stats == nil {
                VStack(spacing: 10) {
                    if let error { Muted(error) } else { ProgressView().controlSize(.small); Muted("Chargement des statistiques…") }
                }
                .frame(maxWidth: .infinity).padding(30).glassCard()
            } else {
                tiles
                appCards
                if let b = base, let weekly = b["users"].dict?["weekly"] as? [[String: Any]], !weekly.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Muted("Nouveaux comptes par semaine", size: 12.5)
                        MiniBars(values: weekly.map { num($0["n"]) }, labels: weekly.map { "Semaine du \($0["w"] as? String ?? "") : \(Int(num($0["n"])))" })
                    }
                    .padding(18).glassCard()
                }
                if let sub = ok(stats?["subs"]) { subsCard(sub) }
                if let st = store { storeCard(st) }
                instagramSection
                if let s = site { siteCard(s) }
                connections
            }
        }
        .task { await load(refresh: false) }
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
                appCard("Topclap", "F5A524", storeKey: "clap",
                        users: c["devices"] == nil ? nil : AppUsers(total: num(c["devices"]), new30: num(c["devices_new30"]), active7: num(c["devices_active7"]), active30: num(c["devices_active30"]),
                                                               note: "Topclap n'a pas de compte : un utilisateur = un iPhone."),
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
        let tiles: [(String, String?, String?)] = [
            ("Téléchargements 30 j", hasStore ? fmt(dl) : nil, hasStore ? "\(fmt(dl7)) sur 7 j" : nil),
            ("Utilisateurs", users.map { fmt($0.total) }, users.map { "+ \(fmt($0.new30)) sur 30 j" }),
            ("Actifs 7 j", users.map { fmt($0.active7) }, users.map { "\(fmt($0.active30)) sur 30 j" }),
            ("Abonnés payants", paid.map(fmt), trial.map { "\(fmt($0)) en essai" }),
            ("Revenus 30 j", hasStore ? proceeds(apps.compactMap { $0["proceeds"] as? [String: Any] }) : nil, hasStore ? "App Store, net" : nil),
            ("Activité 30 j", activity.0, activity.1),
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
                    Text("\(p["app"] as? String ?? "") · \(p["plan"] as? String ?? "")").font(.system(size: 13)).lineLimit(1)
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

    private func storeCard(_ st: [String: Any]) -> some View {
        let apps = ((st["apps"] as? [[String: Any]]) ?? []).sorted { num($0["downloads"]) > num($1["downloads"]) }
        let daily = (st["daily"] as? [[String: Any]]) ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("App Store · 30 derniers jours").font(.system(size: 15, weight: .semibold))
                Spacer()
                Muted("Revenus nets " + proceeds(apps.compactMap { $0["proceeds"] as? [String: Any] }), size: 12.5)
            }
            MiniBars(values: daily.map { num($0["n"]) }, labels: daily.map { "\($0["d"] as? String ?? "") : \(Int(num($0["n"]))) téléchargements" })
            if apps.isEmpty { Muted("Aucune vente sur la période.") }
            ForEach(Array(apps.enumerated()), id: \.offset) { _, a in
                HStack {
                    Text(a["name"] as? String ?? "?").font(.system(size: 13))
                    Spacer()
                    Text("\(fmt(num(a["downloads"]))) tél. · \(proceeds([a["proceeds"] as? [String: Any] ?? [:]]))")
                        .font(.system(size: 13)).monospacedDigit()
                }
            }
        }
        .padding(18).glassCard()
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
