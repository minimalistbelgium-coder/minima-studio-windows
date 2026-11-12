import SwiftUI

// MARK: - Prochaine étape (livraison en un geste)

struct NextStepCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    let mission: Mission

    @State private var link = ""
    @State private var showField = false
    @State private var busy = false
    @State private var askClient: String?
    /// Largeur utile de la fiche.
    @Environment(\.layoutWidth) private var width

    private var canAct: Bool {
        app.isAdmin || data.memberIds(of: mission.id).contains(app.profile?.id ?? "")
    }

    private var text: String? {
        switch mission.status {
        case "assigned":
            if !canAct { return nil }
            return mission.rushes_url == nil ? "Les rushes ne sont pas encore arrivés." : "Les rushes sont là : le montage peut commencer."
        case "editing":
            return canAct ? "Quand la V1 est prête, colle son lien. Le statut passe tout seul à « V1 livrée »." : nil
        case "revisions":
            return canAct ? "Le client a envoyé ses retours (voir Échanges)." : nil
        case "v1_delivered", "fix_delivered":
            return app.isAdmin ? "Vérifie la version, puis préviens le client pour qu'il la valide." : "Livré. En attente de la validation du client."
        case "validated":
            return app.isAdmin ? "Validée par le client. Passe-la en « Client payé » quand son paiement arrive." : "Validée par le client. Bravo !"
        default:
            return nil
        }
    }

    private var tint: Color { Color(hex: MissionStatus.color(mission.status)) }

    var body: some View {
        if let text {
            VStack(alignment: .leading, spacing: 12) {
                // Texte et boutons côte à côte, ou les boutons sous le texte quand la fiche est étroite.
                let layout = width >= 620
                    ? AnyLayout(HStackLayout(alignment: .center, spacing: 14))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        Muted("Prochaine étape", size: 11.5)
                        Text(text).font(.system(size: 13.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small) }
                        actions
                    }
                }
                if showField { deliverField }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.4)))
            .confirmationDialog("Prévenir le client ?", isPresented: askBinding) {
                Button("Envoyer : \(ClientMessage.text(askClient ?? ""))") { notify(askClient ?? "") }
                Button("Ne pas prévenir", role: .cancel) {}
            } message: {
                Text("Le client reçoit une notification et un e-mail.")
            }
        }
    }

    private var askBinding: Binding<Bool> {
        Binding(get: { askClient != nil }, set: { if !$0 { askClient = nil } })
    }

    @ViewBuilder private var actions: some View {
        switch mission.status {
        case "assigned":
            if canAct {
                Button("Commencer le montage") { run { try await data.editorSetStatus(mission, "editing") } }
                    .buttonStyle(PrimaryButton())
            }
        case "editing", "revisions":
            if canAct && !showField {
                Button(mission.status == "revisions" ? "Livrer les corrections" : "Livrer la V1") { showField = true }
                    .buttonStyle(PrimaryButton())
            }
        case "v1_delivered", "fix_delivered":
            if app.isAdmin {
                Button("Prévenir le client") { askToNotify(mission.status) }.buttonStyle(PrimaryButton())
                Button("Marquer validée") { run { try await data.setStatus(mission, "validated") } }.buttonStyle(SecondaryButton())
            }
        case "validated":
            if app.isAdmin {
                Button("Le client a payé") { run { try await data.setStatus(mission, "paid") } }.buttonStyle(SecondaryButton())
            }
        default:
            EmptyView()
        }
    }

    private var deliverField: some View {
        HStack(spacing: 8) {
            TextField("Lien de la version (Frame.io, Drive, WeTransfer…)", text: $link).input().onSubmit(deliver)
            Button("Livrer", action: deliver).buttonStyle(PrimaryButton())
                .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Annuler") { showField = false }.buttonStyle(SecondaryButton())
        }
    }

    private func deliver() {
        let url = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        let next = mission.status == "revisions" ? "fix_delivered" : "v1_delivered"
        run {
            try await data.deliver(mission, url: url)
            showField = false
            link = ""
            app.showToast(app.isAdmin ? "Version livrée" : "Livré, l'admin est prévenu")
            if app.isAdmin && data.hasClientAccount(mission) { askClient = next }
        }
    }

    private func askToNotify(_ status: String) {
        if !data.hasClientAccount(mission) {
            app.showToast("Ce client n'a pas encore d'accès. Ajoute-le dans Équipe.")
        } else if mission.delivery_url == nil {
            app.showToast("Ajoute d'abord le lien de la version.")
        } else {
            askClient = status
        }
    }

    private func notify(_ status: String) {
        run {
            let n = try await data.notifyClient(mission.id, message: ClientMessage.text(status))
            app.showToast(n > 0 ? "Client prévenu" : "Aucun compte client")
        }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        Task { @MainActor in
            do { try await op() } catch { app.showToast("Erreur : \(error.localizedDescription)") }
            busy = false
        }
    }
}

// MARK: - Historique des versions

struct VersionsHistory: View {
    @EnvironmentObject var data: DataStore
    let mission: Mission

    var body: some View {
        let list = Array(data.versions(of: mission.id).reversed())
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardTitle(text: "Historique des versions") { Muted("\(list.count)") }.padding(.bottom, 8)
                ForEach(Array(list.enumerated()), id: \.element.id) { i, v in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    row(v, latest: i == 0)
                }
            }
            .card(padding: 16)
        }
    }

    private func row(_ v: MissionVersion, latest: Bool) -> some View {
        HStack(spacing: 10) {
            Tag(text: v.label, color: latest ? Theme.green : Theme.muted)
            Muted(detail(v), size: 12).lineLimit(1)
            Spacer(minLength: 8)
            Button("Ouvrir") { Links.open(v.url) }
                .buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.blue).lineLimit(1).fixedSize()
        }
        .padding(.vertical, 8)
    }

    private func detail(_ v: MissionVersion) -> String {
        var parts: [String] = []
        if let d = DateFmt.parse(v.created_at) { parts.append(DateFmt.deadline(d)) }
        if let p = data.profile(v.created_by) { parts.append(p.firstName) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Demande d'un client à valider

struct RequestBanner: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    let mission: Mission
    var onEdit: () -> Void
    var onClose: () -> Void

    @State private var confirmRefuse = false
    @State private var busy = false

    private let pink = Theme.pink

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Demande du client").font(.system(size: 13.5, weight: .semibold))
            Text("Fixe le budget, le prix et le monteur avec « Modifier », puis lance le projet. Le client est prévenu automatiquement.")
                .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Modifier", action: onEdit).buttonStyle(SecondaryButton())
                Button("Lancer le projet", action: launch).buttonStyle(PrimaryButton())
                Button("Refuser") { confirmRefuse = true }.buttonStyle(SecondaryButton(danger: true))
                if busy { ProgressView().controlSize(.small) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pink.opacity(0.4)))
        .confirmationDialog("Refuser cette demande ?", isPresented: $confirmRefuse) {
            Button("Refuser et prévenir le client", role: .destructive, action: refuse)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La demande est supprimée et le client reçoit une notification.")
        }
    }

    private func launch() {
        busy = true
        Task { @MainActor in
            do {
                try await data.setStatus(mission, "assigned")
                app.showToast("Projet lancé, le client est prévenu")
            } catch { app.showToast("Erreur : \(error.localizedDescription)") }
            busy = false
        }
    }

    private func refuse() {
        busy = true
        Task { @MainActor in
            do {
                try await data.refuseRequest(mission, reason: "")
                app.showToast("Demande refusée, client prévenu")
                busy = false
                onClose()
            } catch {
                busy = false
                app.showToast("Erreur : \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Qui a monté cette mission, et combien de temps

/// Bandeau en haut de la fiche : temps passé par chaque personne, d'un coup d'œil.
struct MissionTimeStrip: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    let mission: Mission

    private static let colors = ["A78BFA", "4C8DFF", "34D399", "F5A524", "F472B6", "2DD4BF"]
    /// Identifiant fictif de Claude dans la liste des personnes.
    static let claude = "__claude"
    static let claudeColor = Color(hex: "D97757")

    private struct Row: Identifiable {
        let id: String
        let seconds: Double
        let last: Date?
        let live: Bool
    }

    private var rows: [Row] {
        var secs: [String: Double] = [:]
        var last: [String: Date] = [:]
        var live: Set<String> = []
        for s in data.sessions(for: mission.id) {
            secs[s.user_id, default: 0] += Double(s.duration_sec ?? 0)
            if let d = DateFmt.parse(s.ended_at ?? s.started_at), d > (last[s.user_id] ?? .distantPast) { last[s.user_id] = d }
            if s.isLiveNow { live.insert(s.user_id) }
        }
        if mission.hasClaude {
            secs[Self.claude, default: 0] += 0
            for w in data.aiWork(for: mission.id) {
                secs[Self.claude, default: 0] += Double(w.duration_sec ?? 0)
                if let d = DateFmt.parse(w.ended_at), d > (last[Self.claude] ?? .distantPast) { last[Self.claude] = d }
            }
        }
        return secs.map { Row(id: $0.key, seconds: $0.value, last: last[$0.key], live: live.contains($0.key)) }
            .sorted { $0.seconds > $1.seconds }
    }

    private func color(_ uid: String, _ all: [Row]) -> Color {
        if uid == Self.claude { return Self.claudeColor }
        if data.profile(uid)?.role == "admin" { return Theme.blue }
        let others = all.map(\.id).filter { $0 != Self.claude && data.profile($0)?.role != "admin" }
        return Color(hex: Self.colors[(others.firstIndex(of: uid) ?? 0) % Self.colors.count])
    }

    private func name(_ uid: String) -> String {
        uid == Self.claude ? "Claude" : uid == app.profile?.id ? "Toi" : (data.profile(uid)?.firstName ?? "Ancien membre")
    }

    private func lastLabel(_ r: Row) -> String {
        if r.live { return "en train de monter" }
        guard let d = r.last else { return r.id == Self.claude ? "monteur IA · pas encore de temps" : "" }
        let day = DateFmt.relative(d).lowercased()
        let prefix = r.id == Self.claude ? "montage IA " : "dernière session "
        return prefix + (day == "aujourd'hui" ? "aujourd'hui à \(AgendaCal.time(d))" : day)
    }

    var body: some View {
        let list = rows
        let total = list.map(\.seconds).reduce(0, +)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Temps passé").font(.system(size: 13.5, weight: .semibold))
                Spacer(minLength: 8)
                Text(total > 0 ? "\(TimeFmt.hm(total)) au total" : list.isEmpty ? "Personne n'a encore travaillé dessus" : "Pas encore de temps")
                    .font(.system(size: 12.5)).monospacedDigit().foregroundStyle(Theme.muted).lineLimit(1)
            }
            if total > 0 {
                GeometryReader { g in
                    let bars = list.filter { $0.seconds > 0 }
                    HStack(spacing: 2) {
                        ForEach(bars) { r in
                            Rectangle().fill(color(r.id, list))
                                .frame(width: max(3, (g.size.width - CGFloat(bars.count - 1) * 2) * CGFloat(r.seconds / total)))
                        }
                    }
                }
                .frame(height: 8).clipShape(Capsule())
            }
            if !list.isEmpty {
                FlowRows(spacing: 10) {
                    ForEach(list) { r in
                        HStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                if r.id == Self.claude { ClaudeBadge(size: 26) }
                                else if let p = data.profile(r.id) { AvatarView(profile: p, size: 26).clipShape(Circle()) }
                                else { Circle().fill(Theme.card2).frame(width: 26, height: 26) }
                                if r.live { Circle().fill(Theme.green).frame(width: 8, height: 8).overlay(Circle().stroke(Theme.bg, lineWidth: 1.5)) }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Circle().fill(color(r.id, list)).frame(width: 7, height: 7)
                                    Text(name(r.id)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text(TimeFmt.hm(r.seconds)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                    if total > 0 { Text("\(Int((100 * r.seconds / total).rounded())) %").font(.system(size: 11.5)).foregroundStyle(Theme.muted) }
                                }
                                Text(lastLabel(r)).font(.system(size: 11.5))
                                    .foregroundStyle(r.live ? Theme.green : Theme.muted).lineLimit(1)
                            }
                        }
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(r.id == Self.claude ? Self.claudeColor.opacity(0.12) : Theme.ink.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(r.id == Self.claude ? Self.claudeColor.opacity(0.35) : .clear))
                    }
                }
                if list.contains(where: { $0.id == Self.claude && $0.seconds > 0 }) { savedLine }
            }
            if app.isAdmin && mission.hasClaude { ClaudeTimeEditor(mission: mission) }
        }
        .card(padding: 16)
    }
}

/// Admin : ajouter ou retirer à la main du temps de Claude sur une mission.
struct ClaudeTimeEditor: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    let mission: Mission
    @State private var adding = false
    @State private var text = ""
    @State private var busy = false
    @State private var toDelete: AIWork?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 1)
            FlowRows(spacing: 8) {
                HStack(spacing: 6) {
                    ClaudeBadge(size: 18)
                    Muted("Temps de Claude", size: 12)
                }
                .frame(height: 28)
                ForEach(data.aiWork(for: mission.id)) { w in
                    HStack(spacing: 4) {
                        Text(TimeFmt.hm(Double(w.duration_sec ?? 0)) + ((w.notes ?? "").isEmpty ? "" : " · \(w.notes!)"))
                            .font(.system(size: 12)).lineLimit(1)
                        Button { toDelete = w } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted)
                                .frame(width: 18, height: 18).contentShape(Circle())
                        }
                        .buttonStyle(.plain).help("Supprimer ce temps")
                    }
                    .padding(.leading, 10).padding(.trailing, 4).frame(height: 28)
                    .background(MissionTimeStrip.claudeColor.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(MissionTimeStrip.claudeColor.opacity(0.3)))
                }
                if adding {
                    HStack(spacing: 6) {
                        TextField("1h30", text: $text)
                            .textFieldStyle(.plain).font(.system(size: 12.5)).frame(width: 70)
                            .padding(.horizontal, 8).frame(height: 28)
                            .background(Theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.ink.opacity(0.12)))
                            .onSubmit(save)
                        Button("Ajouter", action: save).buttonStyle(.borderedProminent).controlSize(.small).disabled(busy)
                        Button("Annuler") { adding = false; text = "" }.buttonStyle(.bordered).controlSize(.small)
                    }
                } else {
                    Button { adding = true } label: { Label("Ajouter du temps", systemImage: "plus") }
                        .buttonStyle(.bordered).controlSize(.small).frame(height: 28)
                }
            }
            if adding { Muted("Exemples : 45, 1h30, 2h.", size: 11) }
        }
        .confirmationDialog("Supprimer ce temps ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Supprimer", role: .destructive) {
                guard let w = toDelete else { return }
                Task {
                    do { try await data.deleteAIWork(w.id); app.showToast("Temps supprimé") }
                    catch { app.showToast("Impossible de supprimer : \(error.localizedDescription)") }
                }
            }
        } message: {
            Text("\(TimeFmt.hm(Double(toDelete?.duration_sec ?? 0))) de Claude seront retirées de cette mission.")
        }
    }

    private func save() {
        guard let secs = DataStore.parseDuration(text), secs > 0, secs <= 24 * 3600 else {
            app.showToast("Durée non reconnue. Écris par exemple 45 ou 1h30."); return
        }
        busy = true
        Task {
            do { try await data.addClaudeTime(missionId: mission.id, seconds: secs); app.showToast("\(TimeFmt.hm(secs)) ajoutées à Claude"); text = ""; adding = false }
            catch { app.showToast("Impossible d'ajouter : \(error.localizedDescription)") }
            busy = false
        }
    }
}

extension MissionTimeStrip {
    @ViewBuilder fileprivate var savedLine: some View {
        if let s = data.claudeSaved(mission) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    ClaudeBadge(size: 18)
                    Text("Claude t'a fait gagner environ ").font(.system(size: 13))
                        + Text(TimeFmt.hm(s.saved)).font(.system(size: 13, weight: .semibold))
                        + Text(" sur ce montage").font(.system(size: 13))
                }
                Text("Par rapport à la moyenne des \(s.count) dernier\(s.count > 1 ? "s" : "") épisode\(s.count > 1 ? "s" : "") monté\(s.count > 1 ? "s" : "") à la main (\(TimeFmt.hm(s.reference))).")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            Muted("Pas encore assez d'épisodes montés à la main pour estimer le temps gagné.", size: 11.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Pastille de Claude (monteur IA).
struct ClaudeBadge: View {
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: "E8916F"), Color(hex: "C76546")], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("✳").font(.system(size: size * 0.55, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Claude")
    }
}

/// Résumé du mois pour l'admin : montages faits par Claude et temps gagné.
struct ClaudeMonthCard: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var presenter: Presenter

    var body: some View {
        let cal = Calendar.current
        let month = data.aiWork.filter { data.mission($0.mission_id)?.hasClaude == true }.filter { DateFmt.parse($0.ended_at).map { cal.isDate($0, equalTo: Date(), toGranularity: .month) } ?? false }
        let ids = Array(Set(month.map(\.mission_id))).filter { data.mission($0) != nil }
        let time = month.map { Double($0.duration_sec ?? 0) }.reduce(0, +)
        let saved = ids.compactMap { data.mission($0) }.compactMap { data.claudeSaved($0)?.saved }.reduce(0, +)
        if data.missions.contains(where: \.hasClaude) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ClaudeBadge(size: 22)
                    Text("Claude").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Muted("ce mois", size: 12)
                }
                HStack(spacing: 8) {
                    figure("\(ids.count)", ids.count > 1 ? "montages" : "montage")
                    figure(TimeFmt.hm(time), "de travail")
                    figure(saved > 0 ? TimeFmt.hm(saved) : "–", "gagnées", color: Theme.green)
                }
                if let last = data.aiWork.first(where: { data.mission($0.mission_id)?.hasClaude == true }), let m = data.mission(last.mission_id) {
                    Button { presenter.open(.existing(m.id)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Muted("Dernier montage · \(DateFmt.relative(DateFmt.parse(last.ended_at)).lowercased())", size: 11.5)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).hoverRow(radius: 8)
                }
            }
            .card()
        }
    }

    private func figure(_ v: String, _ l: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 18, weight: .semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            Muted(l, size: 11.5).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Dispose les éléments en lignes qui passent à la ligne quand la place manque.
struct FlowRows: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width.isFinite ? width : maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(s.width, bounds.width), height: s.height))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}


/// Chrono dans la fiche mission : le temps qui tourne, et le bouton pour démarrer ou arrêter.
struct MissionChronoCard: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    let mission: Mission

    private var here: Bool { tracker.mission?.id == mission.id }

    var body: some View {
        let me = app.profile?.id ?? ""
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if here { StatusDot(status: tracker.status) } else { Circle().fill(Theme.muted.opacity(0.5)).frame(width: 8, height: 8) }
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if here {
                    LiveClock(tracker: tracker, size: 26)
                } else {
                    Text(LiveClock.format(data.seconds(mission: mission.id, user: me)))
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            if here, let mx = tracker.maxAmount {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Money.eur(mx)).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.green)
                    TimelineView(.periodic(from: .now, by: 5)) { ctx in
                        if let r = tracker.hourlyRate(at: ctx.date) {
                            Text("\(Money.eur(r.rounded())) / h").font(.system(size: 11)).monospacedDigit().foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            if here && tracker.manual {
                Button { Task { @MainActor in await tracker.stopManual() } } label: { Label("Arrêter", systemImage: "stop.fill") }
                    .buttonStyle(SecondaryButton(danger: true))
            } else if !here || !(tracker.status == .running) {
                Button { Task { @MainActor in await tracker.startManual(mission) } } label: { Label("Démarrer", systemImage: "play.fill") }
                    .buttonStyle(PrimaryButton())
                    .help(tracker.mission != nil && !here ? "Le chrono tourne sur « \(tracker.mission!.title) » : il passera sur cette mission" : "Compte le temps sur cette mission même hors de Premiere")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(here && tracker.status == .running ? Theme.green.opacity(0.4) : .clear))
    }

    private var title: String {
        guard here else {
            if let other = tracker.mission { return "Chrono sur « \(other.title) » · ton temps ici" }
            return "Chrono · ton temps sur cette mission"
        }
        switch tracker.status {
        case .running: return tracker.manual ? "Chrono en cours" : "Chrono en cours · suivi Premiere"
        case .paused(let why): return "En pause · \(why)"
        case .askAway: return "Tu as quitté Premiere"
        default: return "Chrono"
        }
    }
}
