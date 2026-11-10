import SwiftUI
import Supabase

struct TeamView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @State private var invites: [TeamInvite] = []
    @State private var email = ""
    @State private var role = "editor"
    @State private var clientId = ""
    @State private var busy = false
    @State private var toRemove: Profile?

    var body: some View {
        let members = data.profiles.filter { $0.active && $0.role != "none" }
        let pendingInvites = invites.filter { $0.accepted_at == nil }
        let outsiders = data.profiles.filter { $0.role == "none" }

        Page {
            PageHeader(kicker: "\(members.count) personne\(members.count > 1 ? "s" : "")", title: "Équipe")

            // Ajout
            VStack(alignment: .leading, spacing: 14) {
                Text("Ajouter quelqu'un").font(.system(size: 15, weight: .semibold))
                Text("Entre son adresse Gmail et choisis son rôle. Dès qu'il se connecte à Minima Studio avec ce compte Google, il a accès à son espace.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)

                HStack(spacing: 8) {
                    ForEach(Roles.assignable, id: \.self) { r in
                        RoleChoice(role: r, selected: role == r) { role = r }
                    }
                }

                HStack(spacing: 10) {
                    TextField("prenom@gmail.com", text: $email).input().onSubmit(invite)
                    if role == "client" {
                        Picker("", selection: $clientId) {
                            Text("Choisir le client…").tag("")
                            ForEach(data.clients) { c in Text(c.name).tag(c.id) }
                        }
                        .labelsHidden().frame(width: 220)
                    }
                    Button("Ajouter", action: invite).buttonStyle(PrimaryButton())
                        .disabled(!canInvite || busy)
                }
            }
            .card()

            SectionTitle(text: "Membres")
            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    let count = data.members.filter { $0.user_id == p.id }.compactMap { data.mission($0.mission_id) }.filter(\.isOpen).count
                    let live = data.liveSessions.contains { $0.user_id == p.id }
                    HStack(spacing: 12) {
                        AvatarView(profile: p, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(p.displayName).font(.system(size: 14, weight: .medium))
                                if live { Pill(text: "En train de monter", color: Theme.green) }
                            }
                            Text(p.email).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if p.role == "client" {
                            Text(data.client(p.client_id)?.name ?? "Client non défini").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        } else {
                            Text("\(count) mission\(count > 1 ? "s" : "") en cours").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        }
                        roleMenu(p)
                        if p.id != app.profile?.id {
                            Button("Retirer") { toRemove = p }.buttonStyle(SecondaryButton(danger: true))
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
            }
            .card(padding: 0)

            if !pendingInvites.isEmpty {
                SectionTitle(text: "Invitations en attente", trailing: "Pas encore connectés")
                VStack(spacing: 0) {
                    ForEach(Array(pendingInvites.enumerated()), id: \.element.id) { i, inv in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        HStack(spacing: 10) {
                            Image(systemName: "envelope").foregroundStyle(Theme.muted)
                            Text(inv.email).font(.system(size: 13.5))
                            Pill(text: Roles.label(inv.role ?? "editor"), color: Color(hex: Roles.color(inv.role ?? "editor")))
                            if inv.role == "client", let c = data.client(inv.client_id) {
                                Text(c.name).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text("Ajouté le \(DateFmt.short(inv.invited_at))").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            Button("Annuler") { cancelInvite(inv.email) }.buttonStyle(SecondaryButton())
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                }
                .card(padding: 0)
            }

            if !outsiders.isEmpty {
                SectionTitle(text: "Connexions hors équipe", trailing: "Comptes connectés sans invitation, ou retirés")
                VStack(spacing: 0) {
                    ForEach(Array(outsiders.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        HStack(spacing: 12) {
                            AvatarView(profile: p, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.displayName).font(.system(size: 13.5))
                                Text(p.email).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Menu("Accepter comme…") {
                                Button("Monteur") { change(p, to: "editor", client: nil) }
                                Button("Admin") { change(p, to: "admin", client: nil) }
                                Menu("Client") {
                                    ForEach(data.clients) { c in Button(c.name) { change(p, to: "client", client: c.id) } }
                                }
                            }
                            .menuStyle(.borderlessButton).fixedSize()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                    }
                }
                .card(padding: 0)
            }
        }
        .task { await loadInvites() }
        .confirmationDialog("Retirer \(toRemove?.displayName ?? "") de l'équipe ?", isPresented: Binding(get: { toRemove != nil }, set: { if !$0 { toRemove = nil } })) {
            Button("Retirer", role: .destructive) { if let p = toRemove { remove(p) } }
        } message: {
            Text("Il n'aura plus accès à l'app. Son historique de temps est conservé.")
        }
    }

    private var canInvite: Bool {
        email.contains("@") && (role != "client" || !clientId.isEmpty)
    }

    @ViewBuilder
    private func roleMenu(_ p: Profile) -> some View {
        if p.id == app.profile?.id {
            Pill(text: p.roleLabel, color: Color(hex: Roles.color(p.role)))
        } else {
            Menu {
                Button("Monteur") { change(p, to: "editor", client: nil) }
                Button("Admin") { change(p, to: "admin", client: nil) }
                Menu("Client") {
                    ForEach(data.clients) { c in Button(c.name) { change(p, to: "client", client: c.id) } }
                }
            } label: {
                Text(p.roleLabel)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color(hex: Roles.color(p.role)).opacity(0.15), in: Capsule())
            .help("Changer le rôle")
        }
    }

    private func loadInvites() async {
        do {
            let list: [TeamInvite] = try await supa.from("team_invites").select().order("invited_at", ascending: false).execute().value
            invites = list
        } catch {
            invites = []
        }
    }

    private func invite() {
        let e = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard canInvite else { return }
        busy = true
        Task { @MainActor in
            do {
                try await supa.from("team_invites")
                    .upsert(InviteInsert(email: e, role: role, client_id: role == "client" ? clientId : nil))
                    .execute()
                await loadInvites()
                await data.reload()
                email = ""
                let joined = data.profiles.contains { $0.email.lowercased() == e && $0.role != "none" }
                app.showToast(joined ? "Ajouté" : "Invitation enregistrée")
            } catch {
                app.showToast("Erreur : \(error.localizedDescription)")
            }
            busy = false
        }
    }

    private func change(_ p: Profile, to role: String, client: String?) {
        Task { @MainActor in
            do {
                try await data.setRole(p, role: role, clientId: client)
                await loadInvites()
                app.showToast("\(p.firstName) est maintenant \(Roles.label(role).lowercased())")
            } catch { app.showToast("Erreur : \(error.localizedDescription)") }
        }
    }

    private func cancelInvite(_ e: String) {
        Task { @MainActor in
            do {
                try await supa.from("team_invites").delete().eq("email", value: e).execute()
                await loadInvites()
            } catch { app.showToast("Erreur : \(error.localizedDescription)") }
        }
    }

    private func remove(_ p: Profile) {
        Task { @MainActor in
            do {
                try await supa.from("profiles").update(ProfileRoleUpdate(role: "none", active: false, client_id: nil)).eq("id", value: p.id).execute()
                try await supa.from("team_invites").delete().eq("email", value: p.email.lowercased()).execute()
                await loadInvites()
                await data.reload()
                app.showToast("\(p.firstName) a été retiré")
            } catch { app.showToast("Erreur : \(error.localizedDescription)") }
        }
    }
}

private struct RoleChoice: View {
    let role: String
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: Roles.color(role))).frame(width: 8, height: 8)
                    Text(Roles.label(role)).font(.system(size: 13.5, weight: .semibold))
                }
                Text(description).font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Theme.blue.opacity(0.12) : Theme.card2, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.blue.opacity(0.6) : Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var description: String {
        switch role {
        case "editor": return "Reçoit ses missions, voit ses gains et son temps."
        case "admin": return "Accès complet : finances, équipe, toutes les missions."
        default: return "Suit l'avancement de ses projets et dépose ses rushes."
        }
    }
}
