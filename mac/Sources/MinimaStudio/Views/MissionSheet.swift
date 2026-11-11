import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Fiche mission : création, consultation et modification.
struct MissionSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore

    let target: MissionTarget
    var presetDeadline: Date? = nil
    var onClose: () -> Void
    @State private var editing = false

    var body: some View {
        Group {
            switch target {
            case .new:
                MissionEditor(mission: nil, onDone: onClose, onCancel: onClose, presetDeadline: presetDeadline)
            case .existing(let id):
                if let m = data.mission(id) {
                    if editing && app.isAdmin {
                        MissionEditor(mission: m, onDone: { editing = false }, onCancel: { editing = false }, onDeleted: onClose)
                    } else {
                        MissionDetail(mission: m, onEdit: { editing = true }, onClose: onClose)
                    }
                } else {
                    VStack(spacing: 14) {
                        EmptyHint(text: "Cette mission n'existe plus.")
                        Button("Fermer", action: onClose).buttonStyle(SecondaryButton())
                    }.padding(30)
                }
            }
        }
        .frame(minWidth: 520, idealWidth: 1000, maxWidth: 1040)
        .frame(minHeight: 420)
    }
}

// MARK: - Détail

private struct MissionDetail: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var presenter: Presenter
    let mission: Mission
    var onEdit: () -> Void
    var onClose: () -> Void

    @State private var rushes = ""
    @State private var editingRushes = false
    @State private var split: [SplitRow] = []
    @State private var busy = false
    @State private var editingDelivery = false
    @State private var delivery = ""
    @State private var askClient: String?
    @State private var editingVersion = false
    @State private var version = ""
    @State private var comments: [MissionComment] = []
    @State private var newComment = ""
    /// Largeur de la fiche (transmise par PanelHost).
    @Environment(\.layoutWidth) private var sheetWidth

    private static let personColors = ["A78BFA", "4C8DFF", "34D399", "F5A524", "F472B6", "2DD4BF"]

    var body: some View {
        let client = data.client(mission.client_id)
        let me = app.profile?.id ?? ""
        let live = data.liveSession(for: mission.id)
        let rows = split.isEmpty ? data.localSplit(mission) : split
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(client)

                    if !live.isEmpty {
                        HStack(spacing: 8) {
                            Circle().fill(Theme.green).frame(width: 8, height: 8)
                            Text(live.map { $0.user_id == me ? "Tu travailles" : "\(data.profile($0.user_id)?.firstName ?? "Quelqu'un") travaille" }
                                .joined(separator: ", ") + " dessus en ce moment")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.green)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    if app.isAdmin && mission.status == "requested" {
                        RequestBanner(mission: mission, onEdit: onEdit, onClose: onClose)
                    } else if app.isTeam {
                        NextStepCard(mission: mission)
                    }

                    if app.isTeam && mission.status != "requested" { MissionTimeStrip(mission: mission) }

                    StepProgress(mission: mission, notes: stepNotes(rows)).card()

                    Columns(minLeft: 380, rightWidth: 300) {
                        WidthReader { w in
                            // Rushes et dépôt côte à côte, ou l'un sous l'autre si la colonne est étroite.
                            let layout = w >= 520
                                ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
                                : AnyLayout(VStackLayout(spacing: 12))
                            layout { rushesCard; deliveryCard }
                        }
                        if app.isTeam { versionCard }
                        if app.isTeam { VersionsHistory(mission: mission) }
                        briefCard
                        if mission.client_id != nil { commentsCard }
                        sessionsCard
                        if app.isTeam { premiereLine }
                    } right: {
                        if app.isAdmin {
                            timeCard(rows)
                            splitCard(rows)
                        } else {
                            myShareCard(rows, me: me)
                            teamCard(me: me)
                        }
                    }
                }
                .layoutWidth(sheetWidth - 52)
                .padding(26)
            }

            // Barre d'actions
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 10) {
                if app.isAdmin {
                    Menu {
                        ForEach(MissionStatus.all, id: \.self) { s in
                            Button(MissionStatus.label(s)) {
                                run {
                                    try await data.setStatus(mission, s)
                                    if ["v1_delivered", "fix_delivered", "validated"].contains(s) && data.hasClientAccount(mission) { askClient = s }
                                }
                            }
                        }
                    } label: { Text("Statut : \(MissionStatus.label(mission.status))") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else if app.isEditor && mission.isOpen {
                    EditorStatusMenu(current: mission.status) { s in
                        run { try await data.editorSetStatus(mission, s); app.showToast("Statut envoyé à l'admin") }
                    }
                }
                if app.isTeam && (app.isAdmin || data.memberIds(of: mission.id).contains(me)) {
                    if tracker.manual && tracker.mission?.id == mission.id {
                        Button("Arrêter le chrono") { Task { @MainActor in await tracker.stopManual() } }
                            .buttonStyle(SecondaryButton(danger: true))
                    } else {
                        Button("Démarrer le chrono") { Task { @MainActor in await tracker.startManual(mission) } }
                            .buttonStyle(SecondaryButton())
                            .help("Compte le temps sur cette mission même hors de Premiere")
                    }
                }
                if busy { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                Button("Fermer", action: onClose).buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .task(id: mission.id) {
            guard !SnapshotMode.on else { return }
            split = await data.split(for: mission.id)
            comments = await data.comments(for: mission.id)
        }
        .confirmationDialog("Prévenir le client ?", isPresented: Binding(get: { askClient != nil }, set: { if !$0 { askClient = nil } })) {
            Button("Envoyer : \(ClientMessage.text(askClient ?? ""))") {
                let s = askClient ?? ""
                run {
                    let n = try await data.notifyClient(mission.id, message: ClientMessage.text(s))
                    app.showToast(n > 0 ? "Client prévenu" : "Aucun compte client")
                }
            }
            Button("Ne pas prévenir", role: .cancel) {}
        } message: {
            Text("Le client reçoit une notification dans son app Minima Studio.")
        }
    }

    // MARK: blocs

    /// Les boutons restent sur la première ligne, le titre a toute la largeur en dessous :
    /// rien ne se chevauche, même quand la fiche est étroite.
    private func header(_ client: Client?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Muted("Missions / \(client?.name ?? "Sans client")").lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if app.isAdmin && mission.status != "requested" {
                    Button("Dupliquer", action: duplicate).buttonStyle(SecondaryButton())
                        .help("Crée la même mission une semaine plus tard")
                }
                if app.isAdmin { Button("Modifier", action: onEdit).buttonStyle(SecondaryButton()) }
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30).background(Theme.card2, in: Circle())
                }
                .buttonStyle(.plain).help("Fermer (Échap)")
            }
            Text(mission.title).font(.system(size: 24, weight: .semibold)).tracking(-0.3)
                .lineLimit(3).multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 8, lineSpacing: 6) {
                if let c = client { Tag(text: c.name, color: Color(hex: c.color)) }
                StatusPill(status: mission.status)
                Muted(DateFmt.deadline(mission.deadlineDate), size: 12.5)
                    .foregroundStyle(mission.isLate ? Theme.red : Theme.muted)
                    .lineLimit(1).padding(.vertical, 3)
            }
        }
    }

    private func duplicate() {
        run {
            let id = try await data.duplicateMission(mission)
            app.showToast("Mission dupliquée : vérifie le titre et la date")
            presenter.open(.existing(id))
        }
    }

    private var rushesCard: some View {
        linkCard(
            title: "Rushes", icon: "tray.and.arrow.down.fill", color: Theme.blue,
            url: mission.rushes_url,
            empty: "Pas encore de lien.",
            action: "Télécharger les rushes",
            editing: $editingRushes, text: $rushes,
            canEdit: app.isAdmin,
            save: { url in try await data.setRushes(mission, url: url) },
            footnote: mission.rushes_added_at.flatMap(DateFmt.parse).map { "Ajoutés " + DateFmt.relative($0).lowercased() }
        )
    }

    @ViewBuilder private var deliveryCard: some View {
        if app.isTeam {
            linkCard(
                title: "Dépôt du montage", icon: "tray.and.arrow.up.fill", color: Theme.green,
                url: data.deliveryLink,
                empty: "Aucun lien de dépôt réglé.",
                action: "Déposer mon montage",
                editing: $editingDelivery, text: $delivery,
                canEdit: app.isAdmin,
                save: { url in try await data.setDeliveryLink(url) },
                footnote: app.isAdmin ? "Lien commun à toutes les missions." : "Dépose ton fichier puis indique où tu en es."
            )
        }
    }

    private var versionCard: some View {
        linkCard(
            title: "Version à montrer au client", icon: "play.rectangle.fill", color: Theme.green,
            url: mission.delivery_url,
            empty: "Colle ici le lien de la V1 (Frame.io, Drive, WeTransfer…). Le client pourra la regarder et la valider sur son espace web.",
            action: "Ouvrir la version",
            editing: $editingVersion, text: $version,
            canEdit: true,
            save: { url in try await data.setVersionLink(mission, url: url) }
        )
    }

    private var commentsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: "Échanges avec le client") { Muted("\(comments.count)") }.padding(.bottom, 8)
            if comments.isEmpty { Muted("Aucun message pour l'instant.").padding(.vertical, 6) }
            ForEach(comments) { c in
                Rectangle().fill(Theme.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(c.author == app.profile?.id ? "Toi" : (data.profile(c.author)?.firstName ?? "Client"))
                            .font(.system(size: 13, weight: .semibold))
                        if c.kind == "approve" { Tag(text: "Validé", color: Theme.green) }
                        if c.kind == "changes" { Tag(text: "Retours", color: Theme.amber) }
                        Muted(DateFmt.parse(c.created_at).map { DateFmt.relative($0) } ?? "", size: 11.5)
                    }
                    Text(c.body).font(.system(size: 13.5)).foregroundStyle(Theme.text2).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 9)
            }
            HStack(spacing: 8) {
                TextField("Écrire au client…", text: $newComment).input().onSubmit(sendComment)
                Button("Envoyer", action: sendComment).buttonStyle(SecondaryButton())
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
        .card()
    }

    private func sendComment() {
        let body = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        run {
            try await data.addComment(mission.id, body: body)
            newComment = ""
            comments = await data.comments(for: mission.id)
        }
    }

    @ViewBuilder private var briefCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Brief")
            if let b = mission.brief, !b.isEmpty {
                Text(b).font(.system(size: 13.5)).foregroundStyle(Theme.text2).lineSpacing(3).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else if mission.files.isEmpty {
                Muted("Pas de brief écrit pour cette mission.")
            }
            ForEach(mission.files) { f in
                Button { run { try await data.openBriefFile(f) } } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.richtext").foregroundStyle(Theme.red)
                        Text(f.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        Text("Ouvrir").font(.system(size: 12)).foregroundStyle(Theme.blue)
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }

    @ViewBuilder private var sessionsCard: some View {
        let list = data.sessions(for: mission.id).filter { app.isAdmin || $0.user_id == app.profile?.id }
        VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: app.isAdmin ? "Sessions" : "Mes sessions") {
                Muted(TimeFmt.hm(list.map { Double($0.duration_sec ?? 0) }.reduce(0, +)))
            }
            .padding(.bottom, 8)
            if list.isEmpty { Muted("Aucune session pour l'instant.").padding(.vertical, 8) }
            ForEach(list.prefix(10)) { s in
                Rectangle().fill(Theme.line).frame(height: 1)
                HStack(spacing: 10) {
                    if let p = data.profile(s.user_id) { AvatarView(profile: p, size: 22) }
                    Text(s.user_id == app.profile?.id ? "Toi" : (data.profile(s.user_id)?.firstName ?? "?"))
                        .font(.system(size: 13.5)).lineLimit(1)
                    if s.source == "manual" { Muted("chrono manuel", size: 11.5).lineLimit(1) }
                    if s.isLiveNow { Tag(text: "En cours", color: Theme.green, dot: true) }
                    Spacer(minLength: 8)
                    Muted(sessionRange(s), size: 12).lineLimit(1).minimumScaleFactor(0.85)
                    Text(TimeFmt.hm(Double(s.duration_sec ?? 0))).font(.system(size: 13, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.vertical, 9)
            }
        }
        .card()
    }

    private var premiereLine: some View {
        HStack(spacing: 10) {
            Image(systemName: "film").foregroundStyle(Theme.muted)
            if let k = mission.premiere_key {
                Text("Projet Premiere lié : \(k).prproj").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                    .lineLimit(2).truncationMode(.middle)
            } else {
                Muted("Aucun projet Premiere lié. Ouvre ton projet dans Premiere, l'app te proposera de l'associer.")
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func color(for uid: String, in rows: [SplitRow]) -> Color {
        if data.profile(uid)?.role == "admin" { return Theme.blue }
        let editors = rows.map(\.user_id).filter { data.profile($0)?.role != "admin" }
        let i = editors.firstIndex(of: uid) ?? 0
        return Color(hex: Self.personColors[i % Self.personColors.count])
    }

    private func name(_ uid: String) -> String {
        uid == app.profile?.id ? "Toi" : (data.profile(uid)?.firstName ?? "?")
    }

    private func timeCard(_ rows: [SplitRow]) -> some View {
        let maxS = rows.compactMap(\.seconds).max() ?? 0
        let shared = rows.count > 1
        return VStack(alignment: .leading, spacing: 14) {
            CardTitle("Temps par personne")
            if rows.isEmpty { Muted("Pas encore de temps enregistré.") }
            ForEach(rows) { r in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(name(r.user_id)).font(.system(size: 13.5)).lineLimit(1)
                        if shared && data.profile(r.user_id)?.role == "admin" { Muted("(× \(weightLabel))", size: 12).lineLimit(1).fixedSize() }
                        Spacer(minLength: 8)
                        Text(TimeFmt.hm(r.seconds)).font(.system(size: 13, design: .monospaced)).lineLimit(1).fixedSize()
                    }
                    ThinBar(value: maxS > 0 ? (r.seconds ?? 0) / maxS : 0, color: color(for: r.user_id, in: rows), height: 8)
                }
            }
        }
        .card()
    }

    private var weightLabel: String {
        let w = mission.admin_weight ?? 1.5
        return w.rounded() == w ? "\(Int(w))" : String(format: "%.1f", w).replacingOccurrences(of: ".", with: ",")
    }

    private func splitCard(_ rows: [SplitRow]) -> some View {
        let budget = mission.editor_budget ?? 0
        let price = data.finances[mission.id]?.client_price
        return VStack(alignment: .leading, spacing: 0) {
            CardTitle(text: "Répartition") { Tag(text: "Calcul auto", color: Theme.blue) }
                .padding(.bottom, 14)
            Muted("Budget de la mission")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Money.eur(budget)).font(.system(size: 30, weight: .semibold)).tracking(-0.5)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Muted("HTVA", size: 13).lineLimit(1).fixedSize()
            }
            .padding(.top, 6).padding(.bottom, 14)
            if !rows.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(rows) { r in
                            Rectangle().fill(color(for: r.user_id, in: rows))
                                .frame(width: g.size.width * CGFloat((r.percent ?? 0) / 100))
                        }
                    }
                }
                .frame(height: 10).clipShape(Capsule()).padding(.bottom, 10)
            }
            ForEach(rows) { r in
                kv(dot: color(for: r.user_id, in: rows), "\(name(r.user_id)) · \(Int((r.percent ?? 0).rounded())) %",
                   Money.eur(r.amount ?? 0), bold: true)
            }
            if rows.isEmpty {
                Muted("La répartition se calcule dès que quelqu'un a travaillé dessus.").padding(.vertical, 6)
            } else {
                Muted(formula(rows), size: 12).padding(.top, 10).fixedSize(horizontal: false, vertical: true)
            }
            if let p = price {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 12)
                kv(dot: nil, "Prix client", Money.eur(p))
                kv(dot: nil, "Ta marge", Money.eur(p - data.editorPayout(mission)), bold: true,
                   color: p - data.editorPayout(mission) >= 0 ? Theme.green : Theme.red)
            }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.blue.opacity(0.35)))
    }

    private func formula(_ rows: [SplitRow]) -> String {
        if rows.count == 1 { return "Une seule personne a travaillé dessus : elle touche tout le budget, sans pondération." }
        let parts = rows.map { r -> String in
            let h = TimeFmt.hm(r.seconds)
            return data.profile(r.user_id)?.role == "admin" ? "\(h) × \(weightLabel)" : h
        }
        return "Répartition au temps : " + parts.joined(separator: " + ") + ". Ton temps de retouche compte × \(weightLabel)."
    }

    private func myShareCard(_ rows: [SplitRow], me: String) -> some View {
        let share = data.myShare(of: mission)
        let secs = data.mySplit[mission.id]?.seconds ?? data.seconds(mission: mission.id, user: me)
        let rate = secs >= 300 ? share.amount / (secs / 3600) : nil
        return VStack(alignment: .leading, spacing: 0) {
            Muted("Budget de la mission")
            Text(mission.editor_budget.map(Money.eur) ?? "–").font(.system(size: 30, weight: .semibold)).tracking(-0.5)
                .lineLimit(1).minimumScaleFactor(0.6)
                .padding(.top, 6).padding(.bottom, 14)
            kv(dot: Theme.green, share.estimated ? "Ta part (estimation)" : "Ta part", Money.eur((share.amount * 100).rounded() / 100),
               bold: true, color: Theme.green)
            kv(dot: nil, "Ton temps", TimeFmt.hm(secs))
            kv(dot: nil, "Ton taux horaire", rate.map { "\(Money.eur($0.rounded())) / h" } ?? "–")
            Muted("Si tu montes seul, tu touches tout le budget. Si Gaston fait des retouches, son temps compte × \(weightLabel).", size: 12)
                .padding(.top, 10).fixedSize(horizontal: false, vertical: true)
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.green.opacity(0.3)))
    }

    private func teamCard(me: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Équipe")
            let people = data.memberProfiles(of: mission.id)
            if people.isEmpty { Muted("Personne n'est assigné.") }
            ForEach(people) { p in
                HStack(spacing: 10) {
                    AvatarView(profile: p, size: 26)
                    Text(p.id == me ? "\(p.firstName) (toi)" : p.firstName).font(.system(size: 13.5)).lineLimit(1)
                    Spacer(minLength: 8)
                    Muted(p.roleLabel, size: 12).lineLimit(1).fixedSize()
                }
            }
        }
        .card()
    }

    private func kv(dot: Color?, _ label: String, _ value: String, bold: Bool = false, color: Color = Theme.text) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 8) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                Text(label).font(.system(size: 13.5)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Text(value).font(.system(size: 13.5, weight: bold ? .semibold : .regular, design: .monospaced)).foregroundStyle(color)
                    .lineLimit(1).fixedSize()
            }
            .padding(.vertical, 10)
        }
    }

    private func stepNotes(_ rows: [SplitRow]) -> [String: String] {
        var n: [String: String] = [:]
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE"))
        if let d = DateFmt.parse(mission.created_at) { n["assigned"] = d.formatted(f) }
        let editors = rows.filter { data.profile($0.user_id)?.role != "admin" }
        if let e = editors.first { n["editing"] = "\(name(e.user_id)) · \(TimeFmt.hm(e.seconds))" }
        if let d = mission.v1_delivered_at.flatMap(DateFmt.parse) {
            n["v1_delivered"] = d.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(Locale(identifier: "fr_BE")))
        }
        if let a = rows.first(where: { data.profile($0.user_id)?.role == "admin" }) { n["revisions"] = "Toi · \(TimeFmt.hm(a.seconds))" }
        if let d = mission.validated_at.flatMap(DateFmt.parse) { n["validated"] = d.formatted(f) }
        return n
    }

    private func sessionRange(_ s: WorkSession) -> String {
        guard let a = DateFmt.parse(s.started_at) else { return "" }
        let day = a.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_BE")))
        let h = Date.FormatStyle.dateTime.hour().minute().locale(Locale(identifier: "fr_BE"))
        let end = s.ended_at.flatMap(DateFmt.parse).map { $0.formatted(h) } ?? "…"
        return "\(day) · \(a.formatted(h)) → \(end)"
    }

    private func linkCard(title: String, icon: String, color: Color, url: String?, empty: String, action: String,
                          editing: Binding<Bool>, text: Binding<String>, canEdit: Bool,
                          save: @escaping (String) async throws -> Void, footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if canEdit && !editing.wrappedValue {
                    Button(url == nil ? "Ajouter" : "Modifier") { text.wrappedValue = url ?? ""; editing.wrappedValue = true }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.blue).lineLimit(1).fixedSize()
                }
            }
            if editing.wrappedValue {
                TextField("https://", text: text).input()
                HStack(spacing: 8) {
                    Button("Enregistrer") {
                        let v = text.wrappedValue
                        run { try await save(v); editing.wrappedValue = false }
                    }.buttonStyle(PrimaryButton())
                    Button("Annuler") { editing.wrappedValue = false }.buttonStyle(SecondaryButton())
                }
            } else if let url {
                Button { Links.open(url) } label: {
                    HStack(spacing: 8) {
                        Text(action).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(color)
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Text(url).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            } else {
                Text(empty).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 38)
            }
            if let footnote, !editing.wrappedValue {
                Text(footnote).font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 16)
    }

    private func info(_ label: String, _ value: String, color: Color = Theme.text) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(color).lineLimit(1)
        }
        .card(padding: 14)
    }

    private func run(_ op: @escaping () async throws -> Void) {
        busy = true
        Task { @MainActor in
            do { try await op() } catch { app.showToast("Erreur : \(error.localizedDescription)") }
            busy = false
        }
    }
}

// MARK: - Création / modification

struct MissionEditor: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore

    let mission: Mission?
    var onDone: () -> Void
    var onCancel: () -> Void
    var onDeleted: () -> Void = {}
    var presetDeadline: Date? = nil

    @State private var clientId: String = ""
    @State private var newClient = ""
    @State private var addingClient = false
    @State private var title = ""
    @State private var brief = ""
    @State private var budget = ""
    @State private var price = ""
    @State private var hasDeadline = true
    @State private var deadline = MissionEditor.defaultDeadline()
    @State private var rushes = ""
    @State private var memberIds: Set<String> = []
    @State private var files: [BriefFile] = []
    @State private var pendingFiles: [URL] = []
    @State private var removedFiles: [BriefFile] = []
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var didLoad = false
    /// Largeur de la fiche (transmise par PanelHost).
    @Environment(\.layoutWidth) private var sheetWidth

    static func defaultDeadline() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mission == nil ? "Nouvelle mission" : "Modifier la mission")
                    .font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Spacer()
                Button(action: onCancel) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28).background(Theme.card2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // 1. Quoi
                    EditorSection(number: 1, title: "La mission") {
                        FormField(label: "Client") {
                            if addingClient {
                                HStack(spacing: 8) {
                                    TextField("Nom du nouveau client", text: $newClient).input()
                                    Button("Annuler") { addingClient = false; newClient = "" }.buttonStyle(SecondaryButton())
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Picker("", selection: $clientId) {
                                        Text("Aucun client").tag("")
                                        ForEach(data.clients) { c in Text(c.name).tag(c.id) }
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: .infinity)
                                    Button("+ Nouveau client") { addingClient = true }.buttonStyle(SecondaryButton())
                                }
                            }
                        }
                        FormField(label: "Titre") {
                            TextField("Ex. Cover podcast #12", text: $title).input()
                        }
                    }

                    // 2. Qui
                    EditorSection(number: 2, title: "Qui monte ?") {
                        TeamPicker(selected: $memberIds)
                    }

                    // 3. Quand
                    EditorSection(number: 3, title: "Deadline") {
                        DeadlinePicker(date: $deadline, enabled: $hasDeadline)
                    }

                    // 4. Brief
                    EditorSection(number: 4, title: "Brief et rushes") {
                        FormField(label: "Consignes", hint: "Format, durée, références, ce que le monteur doit savoir.") {
                            MultilineInput(text: $brief, placeholder: "Optionnel", height: 110)
                        }
                        FormField(label: "Documents PDF") {
                            AttachmentsField(files: $files, pending: $pendingFiles, removed: $removedFiles)
                        }
                        FormField(label: "Lien des rushes", hint: "WeTransfer, Google Drive, Dropbox… Tu peux l'ajouter plus tard.") {
                            TextField("https://", text: $rushes).input()
                        }
                    }

                    // 5. Argent
                    EditorSection(number: 5, title: "Budget") {
                        HStack(alignment: .top, spacing: 14) {
                            FormField(label: "Budget montage (payé à l'équipe)", hint: "Réparti selon le temps de chacun") {
                                MoneyField(text: $budget)
                            }
                            FormField(label: "Prix client", hint: "Visible uniquement par toi") {
                                MoneyField(text: $price)
                            }
                        }
                    }
                }
                .layoutWidth(sheetWidth - 56)
                .padding(.horizontal, 28).padding(.vertical, 16)
            }

            Rectangle().fill(Theme.line).frame(height: 1)
            HStack(spacing: 10) {
                if mission != nil {
                    Button("Supprimer") { confirmDelete = true }.buttonStyle(SecondaryButton(danger: true))
                }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("Annuler", action: onCancel).buttonStyle(SecondaryButton()).keyboardShortcut(.cancelAction)
                Button(mission == nil ? "Créer la mission" : "Enregistrer") { save() }
                    .buttonStyle(PrimaryButton())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || saving)
                    .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .onAppear(perform: fill)
        .confirmationDialog("Supprimer cette mission ?", isPresented: $confirmDelete) {
            Button("Supprimer", role: .destructive) { delete() }
        } message: {
            Text("Le temps enregistré, les PDF et la répartition de cette mission seront aussi supprimés.")
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (!addingClient || !newClient.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private func fill() {
        guard !didLoad else { return }
        didLoad = true
        if let m = mission {
            clientId = m.client_id ?? ""
            title = m.title
            brief = m.brief ?? ""
            budget = m.editor_budget.map { formatNumber($0) } ?? ""
            price = data.finances[m.id]?.client_price.map { formatNumber($0) } ?? ""
            if let d = m.deadlineDate { deadline = d; hasDeadline = true } else { hasDeadline = false }
            rushes = m.rushes_url ?? ""
            memberIds = Set(data.memberIds(of: m.id))
            files = m.files
        } else {
            if let p = presetDeadline { deadline = p; hasDeadline = true }
            if let me = app.profile?.id { memberIds = [me] }
        }
    }

    private func formatNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v).replacingOccurrences(of: ".", with: ",")
    }

    private func save() {
        saving = true
        Task { @MainActor in
            do {
                var cid: String? = clientId.isEmpty ? nil : clientId
                if addingClient {
                    let name = newClient.trimmingCharacters(in: .whitespaces)
                    if let existing = data.clients.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        cid = existing.id
                    } else {
                        cid = try await data.createClient(name: name).id
                    }
                }
                let t = title.trimmingCharacters(in: .whitespaces)
                let b = brief.trimmingCharacters(in: .whitespacesAndNewlines)
                let r = rushes.trimmingCharacters(in: .whitespacesAndNewlines)
                let dl = hasDeadline ? DateFmt.iso(deadline) : nil
                let budgetValue = Money.parse(budget) ?? 0
                let priceValue = Money.parse(price)

                let missionId: String
                if let m = mission {
                    try await data.updateMission(m.id, MissionUpdate(
                        client_id: cid, title: t, brief: b.isEmpty ? nil : b,
                        editor_budget: budgetValue, deadline: dl, rushes_url: r.isEmpty ? nil : r
                    ), memberIds: Array(memberIds), clientPrice: priceValue)
                    missionId = m.id
                } else {
                    missionId = try await data.createMission(MissionInsert(
                        client_id: cid, title: t, brief: b.isEmpty ? nil : b,
                        editor_budget: budgetValue, deadline: dl,
                        rushes_url: r.isEmpty ? nil : r,
                        rushes_added_at: r.isEmpty ? nil : DateFmt.iso(Date())
                    ), memberIds: Array(memberIds), clientPrice: priceValue)
                }

                if !pendingFiles.isEmpty || !removedFiles.isEmpty {
                    await data.removeBriefFiles(removedFiles)
                    _ = try await data.uploadBriefFiles(missionId: missionId, urls: pendingFiles, keep: files)
                    await data.reload()
                }
                app.showToast(mission == nil ? "Mission créée" : "Mission enregistrée")
                saving = false
                onDone()
            } catch {
                saving = false
                app.showToast("Erreur : \(error.localizedDescription)")
            }
        }
    }

    private func delete() {
        guard let m = mission else { return }
        Task { @MainActor in
            do {
                await data.removeBriefFiles(m.files)
                try await data.deleteMission(m)
                app.showToast("Mission supprimée")
                onDeleted()
            } catch {
                app.showToast("Erreur : \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Éléments de l'éditeur

struct EditorSection<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("\(number)").font(.system(size: 11.5, weight: .bold)).foregroundStyle(Theme.blue)
                    .frame(width: 22, height: 22).background(Theme.blue.opacity(0.15), in: Circle())
                Text(title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 16) { content() }
        }
        .card(padding: 18)
    }
}

struct MoneyField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            TextField("0", text: $text).textFieldStyle(.plain).font(.system(size: 15, weight: .medium)).monospacedDigit()
            Text("€").foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).frame(height: 38)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.ink.opacity(0.08)))
    }
}

/// Choix de l'équipe : monteurs d'abord, puis admins.
struct TeamPicker: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @Binding var selected: Set<String>

    var body: some View {
        let editors = data.team.filter { $0.role == "editor" }
        let me = data.team.filter { $0.id == app.profile?.id }
        let admins = data.team.filter { $0.role == "admin" && $0.id != app.profile?.id }
        VStack(alignment: .leading, spacing: 12) {
            if !me.isEmpty {
                Text("Moi").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                grid(me)
                Text(soloHint).font(.system(size: 11.5)).foregroundStyle(Theme.muted.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if editors.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus").foregroundStyle(Theme.muted)
                    Text("Aucun monteur dans l'équipe pour l'instant. Ajoute-les dans l'onglet Équipe.")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Monteurs").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                grid(editors)
            }
            if !admins.isEmpty {
                Text("Admins").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                grid(admins)
            }
        }
    }

    private var soloHint: String {
        let mine = selected.contains(app.profile?.id ?? "")
        if mine && selected.count == 1 { return "Tu montes seul : tu touches 100 % du budget, sans pondération." }
        if mine { return "À plusieurs, ton temps de retouche compte ×1,5 dans la répartition." }
        return "Coche-toi si c'est toi qui fais le montage."
    }

    private func grid(_ people: [Profile]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(people) { p in
                let on = selected.contains(p.id)
                Button {
                    if on { selected.remove(p.id) } else { selected.insert(p.id) }
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(profile: p, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.id == app.profile?.id ? "Je monte moi-même" : p.displayName)
                                .font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text(openCount(p)).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: on ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(on ? Theme.blue : Theme.muted)
                    }
                    .padding(.horizontal, 10).frame(height: 48)
                    .background(on ? Theme.blue.opacity(0.12) : Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(on ? Theme.blue.opacity(0.6) : Theme.ink.opacity(0.08)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openCount(_ p: Profile) -> String {
        let n = data.members.filter { $0.user_id == p.id }.compactMap { data.mission($0.mission_id) }.filter(\.isOpen).count
        return n == 0 ? "Disponible" : "\(n) mission\(n > 1 ? "s" : "") en cours"
    }
}

/// Calendrier + heure, en grand.
struct DeadlinePicker: View {
    @Binding var date: Date
    @Binding var enabled: Bool
    @State private var month: Date
    /// Largeur utile de la section (fiche moins ses marges).
    @Environment(\.layoutWidth) private var width

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "fr_BE")
        c.firstWeekday = 2
        return c
    }

    init(date: Binding<Date>, enabled: Binding<Bool>) {
        _date = date
        _enabled = enabled
        let c = Calendar.current
        _month = State(initialValue: c.dateInterval(of: .month, for: date.wrappedValue)?.start ?? date.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Raccourcis
            // Les raccourcis passent à la ligne quand la fiche est étroite (jamais écrasés).
            FlowLayout(spacing: 6, lineSpacing: 6) {
                quick("Aujourd'hui", dayOffset: 0)
                quick("Demain", dayOffset: 1)
                quick("Après-demain", dayOffset: 2)
                quick("Lundi", weekday: 2)
                quick("Jeudi", weekday: 5)
                quick("Dans 1 sem.", dayOffset: 7)
                Toggle("Sans deadline", isOn: Binding(get: { !enabled }, set: { enabled = !$0 }))
                    .toggleStyle(.checkbox).font(.system(size: 12.5)).fixedSize()
                    .frame(height: 28).padding(.leading, 6)
            }

            if enabled {
                // Calendrier et heure côte à côte, ou l'un sous l'autre si la place manque.
                let side = width >= 620
                let layout = side
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 18))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                layout {
                    calendarView.frame(width: 300)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(dayLabel).font(.system(size: 20, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            Text("à \(timeLabel) · \(DateFmt.relative(date))").font(.system(size: 13.5)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Text("Heure").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(62), spacing: 6), count: 4), alignment: .leading, spacing: 6) {
                            ForEach([9, 10, 12, 14, 16, 18, 20, 23], id: \.self) { h in
                                hourChip(h)
                            }
                        }
                        HStack(spacing: 8) {
                            Picker("", selection: hourBinding) {
                                ForEach(0..<24, id: \.self) { h in Text(String(format: "%02d h", h)).tag(h) }
                            }
                            .labelsHidden().frame(width: 82)
                            Picker("", selection: minuteBinding) {
                                ForEach([0, 15, 30, 45, 59], id: \.self) { m in Text(String(format: "%02d", m)).tag(m) }
                            }
                            .labelsHidden().frame(width: 70)
                        }
                    }
                }
            }
        }
    }

    // MARK: calendrier

    private var calendarView: some View {
        let days = monthDays()
        return VStack(spacing: 10) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text(monthLabel).font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 4) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"].indices, id: \.self) { i in
                    Text(["L", "M", "M", "J", "V", "S", "D"][i]).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted)
                        .frame(height: 20)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { _, d in
                    if let d { dayCell(d) } else { Color.clear.frame(height: 36) }
                }
            }
        }
        .padding(12)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func dayCell(_ d: Date) -> some View {
        let selected = cal.isDate(d, inSameDayAs: date)
        let today = cal.isDateInToday(d)
        let past = d < cal.startOfDay(for: Date())
        return Button { setDay(d) } label: {
            Text("\(cal.component(.day, from: d))")
                .font(.system(size: 13, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Theme.onAccent : (past ? Theme.muted.opacity(0.6) : Theme.text))
                .frame(width: 36, height: 36)
                .background(selected ? Theme.blue : Color.clear, in: Circle())
                .overlay(Circle().stroke(today && !selected ? Theme.blue.opacity(0.7) : Color.clear, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func monthDays() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let weekday = cal.component(.weekday, from: first) // 1 = dimanche
        let offset = (weekday + 5) % 7
        var out: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            out.append(cal.date(byAdding: .day, value: day - 1, to: first))
        }
        return out
    }

    private func shiftMonth(_ n: Int) {
        month = cal.date(byAdding: .month, value: n, to: month) ?? month
    }

    private var monthLabel: String {
        let s = month.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var dayLabel: String {
        let s = date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_BE")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var timeLabel: String { String(format: "%02d:%02d", cal.component(.hour, from: date), cal.component(.minute, from: date)) }

    // MARK: modifications

    private func setDay(_ d: Date) {
        let h = cal.component(.hour, from: date), m = cal.component(.minute, from: date)
        date = cal.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
        enabled = true
    }

    private func setTime(hour: Int? = nil, minute: Int? = nil) {
        let h = hour ?? cal.component(.hour, from: date)
        let m = minute ?? cal.component(.minute, from: date)
        date = cal.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
    }

    private var hourBinding: Binding<Int> {
        Binding(get: { cal.component(.hour, from: date) }, set: { setTime(hour: $0) })
    }
    private var minuteBinding: Binding<Int> {
        Binding(get: {
            let m = cal.component(.minute, from: date)
            return [0, 15, 30, 45, 59].contains(m) ? m : 0
        }, set: { setTime(minute: $0) })
    }

    private func hourChip(_ h: Int) -> some View {
        let on = cal.component(.hour, from: date) == h && cal.component(.minute, from: date) == 0
        return Button { setTime(hour: h, minute: 0) } label: {
            Text(String(format: "%02d:00", h)).font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                .frame(width: 62, height: 30)
                .foregroundStyle(on ? Theme.onAccent : Theme.text)
                .background(on ? Theme.blue : Theme.card2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quick(_ label: String, dayOffset: Int? = nil, weekday: Int? = nil) -> some View {
        Button {
            var target = Date()
            if let dayOffset {
                target = cal.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            } else if let weekday {
                let next = cal.nextDate(after: Date(), matching: DateComponents(weekday: weekday), matchingPolicy: .nextTime)
                target = next ?? Date()
            }
            setDay(target)
            month = cal.dateInterval(of: .month, for: date)?.start ?? month
        } label: {
            Text(label).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                .padding(.horizontal, 10).frame(height: 28)
                .background(Theme.card2, in: Capsule())
                .overlay(Capsule().stroke(Theme.ink.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Zone de dépôt des PDF du brief.
struct AttachmentsField: View {
    @Binding var files: [BriefFile]
    @Binding var pending: [URL]
    @Binding var removed: [BriefFile]
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(files) { f in
                fileRow(name: f.name, isNew: false) {
                    files.removeAll { $0.id == f.id }
                    removed.append(f)
                }
            }
            ForEach(pending, id: \.self) { u in
                fileRow(name: u.lastPathComponent, isNew: true) {
                    pending.removeAll { $0 == u }
                }
            }
            Button(action: choose) {
                VStack(spacing: 6) {
                    Image(systemName: "doc.badge.plus").font(.system(size: 20)).foregroundStyle(Theme.blue)
                    Text("Glisse un PDF ici ou clique pour choisir").font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity).frame(height: 76)
                .background(hovering ? Theme.blue.opacity(0.08) : Theme.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(hovering ? Theme.blue : Theme.ink.opacity(0.18)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: [UTType.fileURL], isTargeted: $hovering) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url, url.pathExtension.lowercased() == "pdf" else { return }
                        DispatchQueue.main.async { if !pending.contains(url) { pending.append(url) } }
                    }
                }
                return true
            }
        }
    }

    private func fileRow(name: String, isNew: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext").foregroundStyle(Theme.red)
            Text(name).font(.system(size: 13)).lineLimit(1)
            if isNew { Pill(text: "à envoyer", color: Theme.blue) }
            Spacer()
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).frame(height: 38)
        .background(Theme.card2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            for u in panel.urls where !pending.contains(u) { pending.append(u) }
        }
    }
}


// MARK: - Statut côté monteur

enum ClientMessage {
    static func text(_ status: String) -> String {
        switch status {
        case "v1_delivered": return "La V1 de ta vidéo est prête"
        case "fix_delivered": return "Les corrections de ta vidéo sont prêtes"
        case "validated": return "Ta vidéo est finalisée"
        default: return "Ta vidéo avance"
        }
    }
}

/// Menu de statut du monteur : chaque choix prévient l'admin.
struct EditorStatusMenu: View {
    let current: String
    var onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(MissionStatus.editorChoices, id: \.self) { s in
                Button {
                    onPick(s)
                } label: {
                    if s == current { Label(label(s), systemImage: "checkmark") } else { Text(label(s)) }
                }
                .disabled(s == current)
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: MissionStatus.color(current))).frame(width: 8, height: 8)
                Text("Où j'en suis : \(MissionStatus.label(current))").font(.system(size: 13, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 14).frame(height: 34)
        .background(Theme.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Theme.blue.opacity(0.4)))
        .help("Change le statut : l'admin reçoit une notification")
    }

    private func label(_ s: String) -> String {
        switch s {
        case "editing": return "Je suis en train de monter"
        case "v1_delivered": return "J'ai livré la V1"
        case "fix_delivered": return "J'ai livré les corrections"
        default: return MissionStatus.label(s)
        }
    }
}
