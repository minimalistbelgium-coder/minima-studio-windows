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
            return app.isAdmin ? "Validée par le client. Passe-la en « Payée » quand le paiement arrive." : "Validée par le client. Bravo !"
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
                Button("Marquer payée") { run { try await data.setStatus(mission, "paid") } }.buttonStyle(SecondaryButton())
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
