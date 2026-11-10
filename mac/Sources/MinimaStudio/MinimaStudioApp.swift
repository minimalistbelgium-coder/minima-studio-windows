import SwiftUI
import AppKit

@main
struct MinimaStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState()
    @StateObject private var data = DataStore()
    @StateObject private var tracker = Tracker()
    @StateObject private var updater = Updater()
    @StateObject private var presenter = Presenter()

    var body: some Scene {
        WindowGroup("Minima Studio") {
            RootView()
                .environmentObject(app)
                .environmentObject(data)
                .environmentObject(tracker)
                .environmentObject(updater)
                .environmentObject(presenter)
                .frame(minWidth: 860, minHeight: 580)
                .preferredColorScheme(.dark)
                .tint(Theme.blue)
                .background(WindowAccessor { w in
                    guard !(w is NSPanel) else { return }
                    app.mainWindow = w
                    CloseHider.shared.hook(w)
                    TitleBarZoom.install()
                    AppDelegate.appState = app
                    AppDelegate.dataStore = data
                    AppDelegate.presenter = presenter
                })
                .onOpenURL { url in
                    Task { _ = try? await supa.auth.session(from: url) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .windowArrangement) {
                Button("Fenêtre principale") { app.showMainWindow() }
                    .keyboardShortcut("0", modifiers: [.command])
            }
            CommandMenu("Chrono") {
                Button("Mode mini") { MiniWindow.shared.show(app: app, data: data, tracker: tracker) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Agrandir la fenêtre") { MiniWindow.shared.hide(app: app) }
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var data: DataStore
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var updater: Updater

    var body: some View {
        Group {
            if app.loading {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if app.session == nil {
                LoginView()
            } else if !app.isMember {
                PendingView()
            } else {
                ShellView()
            }
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) { ToastView() }
        .task(id: "\(app.profile?.id ?? "-")|\(app.profile?.role ?? "-")") {
            await setup()
        }
    }

    private func setup() async {
        guard let p = app.profile, app.isMember else {
            tracker.configure(data: data, userId: nil, isAdmin: false, enabled: false)
            return
        }
        await data.load(admin: app.isAdmin)
        data.startAutoRefresh()
        tracker.configure(data: data, userId: p.id, isAdmin: app.isAdmin, enabled: app.isTeam)
        updater.start()
    }
}
