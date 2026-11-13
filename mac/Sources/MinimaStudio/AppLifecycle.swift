import AppKit
import ServiceManagement
import UserNotifications

/// Garde la fenêtre principale en vie : le bouton rouge la cache, un clic sur l'icône du Dock la rouvre.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var appState: AppState?
    static weak var dataStore: DataStore?
    static weak var presenter: Presenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeMode.apply(ThemeMode.stored)
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        SystemNotifier.requestPermission()
        // Ouverture au démarrage du Mac activée d'office une première fois (le monteur peut la couper dans Mon compte).
        let d = UserDefaults.standard
        if !d.bool(forKey: "launchAtLoginDefaultSet") {
            try? LaunchAtLogin.set(true)
            d.set(true, forKey: "launchAtLoginDefaultSet")
        }
    }

    /// Mis à vrai juste avant une relance voulue (mise à jour, autorisation) : on quitte sans demander.
    static var forceQuit = false

    /// ⌘Q : on propose de garder l'app en fond pour que le chrono Premiere continue.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.forceQuit { return .terminateNow }
        // Extinction, redémarrage ou fermeture de session du Mac : on ne bloque jamais.
        if let ev = NSAppleEventManager.shared().currentAppleEvent,
           ev.attributeDescriptor(forKeyword: kAEQuitReason) != nil { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Garder Minima Studio en fond ?"
        alert.informativeText = "Si tu quittes, ton temps de montage dans Premiere ne sera plus compté par l'app. En fond, la fenêtre disparaît mais le chrono continue."
        alert.addButton(withTitle: "Garder en fond")
        alert.addButton(withTitle: "Quitter quand même")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn { return .terminateNow }
        for w in NSApp.windows where w.isVisible { w.orderOut(nil) }
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let a = Self.appState {
            if MiniWindow.shared.isVisible { MiniWindow.shared.hide(app: a) } else { a.showMainWindow() }
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Remplace l'action du bouton rouge (et de ⌘W) par « cacher la fenêtre ».
@MainActor
final class CloseHider: NSObject {
    static let shared = CloseHider()
    private var hooked = Set<ObjectIdentifier>()

    func hook(_ w: NSWindow) {
        guard !(w is NSPanel), !hooked.contains(ObjectIdentifier(w)) else { return }
        guard let b = w.standardWindowButton(.closeButton) else { return }
        hooked.insert(ObjectIdentifier(w))
        w.isReleasedWhenClosed = false
        b.target = self
        b.action = #selector(hide(_:))
    }

    @objc func hide(_ sender: Any?) {
        let w = (sender as? NSView)?.window ?? NSApp.keyWindow
        w?.orderOut(nil)
    }
}

/// Ouverture automatique au démarrage du Mac.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}


/// Affiche les bannières même quand l'app est au premier plan, et rouvre la fenêtre au clic.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if let a = AppDelegate.appState {
                if MiniWindow.shared.isVisible { MiniWindow.shared.hide(app: a) } else { a.showMainWindow() }
            }
            // Le clic sur la bannière macOS marque la notification comme lue et ouvre sa mission.
            let id = response.notification.request.identifier
            if let data = AppDelegate.dataStore, let n = data.notifications.first(where: { $0.id == id }) {
                await data.markRead(n)
                if let mid = n.mission_id { AppDelegate.presenter?.open(.existing(mid)) }
            }
        }
        completionHandler()
    }
}
