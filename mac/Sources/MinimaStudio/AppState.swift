import Foundation
import SwiftUI
import AppKit
import Supabase

enum Config {
    static let supabaseURL = URL(string: "https://jkfighpoftczgszgoidp.supabase.co")!
    static let supabaseKey = "sb_publishable_-DmB0APAPx5v6SnUdD8LMQ_jhyKFJUF"
    static let redirect = URL(string: "minimastudio://auth-callback")!
}

let supa = SupabaseClient(supabaseURL: Config.supabaseURL, supabaseKey: Config.supabaseKey)

/// Mode captures de mise en page (tests uniquement, jamais activé dans l'app) :
/// les vues n'appellent pas le réseau et affichent les données qu'on leur donne.
enum SnapshotMode {
    static var on = false
}

@MainActor
final class AppState: ObservableObject {
    @Published var session: Session?
    @Published var profile: Profile?
    @Published var loading = true
    @Published var signingIn = false
    @Published var authError: String?
    @Published var toast: String?

    /// Fenêtre principale (pour la cacher quand on passe en mode mini).
    weak var mainWindow: NSWindow?

    var isAdmin: Bool { profile?.role == "admin" && profile?.active == true }
    var isEditor: Bool { profile?.role == "editor" && profile?.active == true }
    var isClient: Bool { profile?.role == "client" && profile?.active == true }
    /// Admin ou monteur : ceux qui montent et dont le temps est suivi.
    var isTeam: Bool { isAdmin || isEditor }
    var isMember: Bool { guard let p = profile else { return false }; return p.active && p.role != "none" }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        }
    }

    /// `observeAuth: false` ne sert qu'aux captures de mise en page (aucun appel réseau).
    init(observeAuth: Bool = true) {
        if observeAuth { Task { await listen() } }
    }

    private func listen() async {
        for await (event, session) in supa.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .signedOut:
                let changed = session?.user.id != self.session?.user.id || profile == nil
                self.session = session
                if changed { await loadProfile() }
                loading = false
            default:
                self.session = session
            }
        }
    }

    func loadProfile() async {
        guard let s = session else { profile = nil; return }
        do {
            profile = try await supa.from("profiles")
                .select()
                .eq("id", value: s.user.id.uuidString.lowercased())
                .single()
                .execute()
                .value
        } catch {
            profile = nil
        }
    }

    func signIn() async {
        signingIn = true
        authError = nil
        do {
            _ = try await supa.auth.signInWithOAuth(
                provider: .google,
                redirectTo: Config.redirect,
                queryParams: [(name: "prompt", value: "select_account")]
            )
        } catch {
            let msg = error.localizedDescription
            if !msg.lowercased().contains("cancel") { authError = msg }
        }
        signingIn = false
    }

    func signOut() async {
        try? await supa.auth.signOut()
        profile = nil
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if toast == text { toast = nil }
        }
    }
}
