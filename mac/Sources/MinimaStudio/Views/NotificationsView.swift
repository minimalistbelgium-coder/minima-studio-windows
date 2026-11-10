import SwiftUI

/// Cloche de la barre latérale avec le nombre de notifications non lues.
struct NotificationBell: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var app: AppState
    @EnvironmentObject var presenter: Presenter
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: data.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(data.unreadCount > 0 ? Theme.text : Theme.muted)
                    .frame(width: 28, height: 28)
                    .background(Theme.card2, in: Circle())
                if data.unreadCount > 0 {
                    Text("\(min(data.unreadCount, 9))").font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Theme.red, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .help("Notifications")
        .popover(isPresented: $open, arrowEdge: .trailing) {
            NotificationsPanel { open = false }
                .environmentObject(data)
                .environmentObject(app)
                .environmentObject(presenter)
        }
    }
}

struct NotificationsPanel: View {
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var app: AppState
    @EnvironmentObject var presenter: Presenter
    var onClose: () -> Void
    @State private var allowed = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !allowed {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash").foregroundStyle(Theme.amber)
                    Text("Les notifications macOS sont coupées pour Minima Studio.").font(.system(size: 12)).foregroundStyle(Theme.text2)
                    Spacer()
                    Button("Activer") { SystemNotifier.openSettings() }.buttonStyle(SecondaryButton())
                }
                .padding(12)
                .background(Theme.amber.opacity(0.1))
            }
            HStack {
                Text("Notifications").font(.system(size: 14, weight: .semibold))
                Spacer()
                if data.unreadCount > 0 {
                    Button("Tout marquer lu") { Task { @MainActor in await data.markAllRead() } }
                        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.blue)
                }
            }
            .padding(14)
            Rectangle().fill(Theme.line).frame(height: 1)
            ScrollView {
                VStack(spacing: 0) {
                    if data.notifications.isEmpty {
                        Text("Rien de neuf pour l'instant.").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(30)
                    }
                    ForEach(data.notifications) { n in
                        row(n)
                        Rectangle().fill(Theme.line).frame(height: 1)
                    }
                }
            }
        }
        .frame(width: 360, height: 420)
        .task { allowed = await SystemNotifier.isAuthorized() }
        .foregroundStyle(Theme.text)
    }

    private func row(_ n: AppNotification) -> some View {
        let mission = n.mission_id.flatMap { data.mission($0) }
        let canTellClient = app.isAdmin && n.kind == "status" && !n.handled
            && (n.status == "v1_delivered" || n.status == "fix_delivered")
            && mission.map { data.hasClientAccount($0) } == true
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { @MainActor in await data.markRead(n) }
                if let id = n.mission_id { presenter.open(.existing(id)); onClose() }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(n.isRead ? Color.clear : Theme.blue).frame(width: 7, height: 7).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(n.title).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.leading)
                        if let b = n.body { Text(b).font(.system(size: 12)).foregroundStyle(Theme.text2).lineLimit(2) }
                        Text(DateFmt.relativeTime(n.created_at)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canTellClient, let m = mission {
                HStack(spacing: 8) {
                    Button("Prévenir le client") {
                        Task { @MainActor in
                            do {
                                let k = try await data.notifyClient(m.id, message: ClientMessage.text(n.status ?? ""))
                                app.showToast(k > 0 ? "Client prévenu" : "Aucun compte client")
                            } catch { app.showToast("Erreur : \(error.localizedDescription)") }
                        }
                    }
                    .buttonStyle(PrimaryButton())
                    Button("Non merci") { Task { @MainActor in await data.dismissNotification(n) } }
                        .buttonStyle(SecondaryButton())
                }
                .controlSize(.small)
                .padding(.leading, 17)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

extension DateFmt {
    static func relativeTime(_ s: String) -> String {
        guard let d = parse(s) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_BE")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}
