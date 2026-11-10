import SwiftUI
import AppKit

struct AppLogo: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

struct LoginView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 22) {
                AppLogo(size: 84)
                VStack(spacing: 8) {
                    Text("Minima Studio").font(.system(size: 30, weight: .semibold))
                    Text("Missions, deadlines et temps de montage de l'équipe.")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task { @MainActor in await app.signIn() }
                } label: {
                    HStack(spacing: 10) {
                        if app.signingIn { ProgressView().controlSize(.small) }
                        Text(app.signingIn ? "Connexion…" : "Continuer avec Google")
                    }
                    .frame(width: 260)
                }
                .buttonStyle(PrimaryButton())
                .disabled(app.signingIn)
                .padding(.top, 8)

                if let err = app.authError {
                    Text(err).font(.system(size: 12.5)).foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center).frame(maxWidth: 380)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 44).padding(.vertical, 40)
            .glassCard(radius: 28)
            .padding(.horizontal, 24)
            Spacer()
            Text("Minimalist Belgium").font(.system(size: 12)).foregroundStyle(Theme.muted).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { ThemeToggle(compact: true).padding(.top, 14).padding(.trailing, 18) }
    }
}

struct PendingView: View {
    @EnvironmentObject var app: AppState
    @State private var checking = false

    var body: some View {
        VStack(spacing: 18) {
            AppLogo(size: 64)
            Text("Accès en attente").font(.system(size: 24, weight: .semibold))
            Text("Ton compte \(app.profile?.email ?? app.session?.user.email ?? "") n'est pas encore dans l'équipe.\nDemande à Gaston de t'ajouter, puis clique sur Réessayer.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
            HStack(spacing: 10) {
                Button {
                    Task { @MainActor in checking = true; await app.loadProfile(); checking = false }
                } label: { Text(checking ? "Vérification…" : "Réessayer") }
                .buttonStyle(PrimaryButton())
                Button("Se déconnecter") { Task { @MainActor in await app.signOut() } }
                    .buttonStyle(SecondaryButton())
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 44).padding(.vertical, 40)
        .glassCard(radius: 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) { ThemeToggle(compact: true).padding(.top, 14).padding(.trailing, 18) }
    }
}
