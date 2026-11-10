import Foundation
import UserNotifications
import AppKit

/// Affiche les nouvelles notifications dans le centre de notifications de macOS.
enum SystemNotifier {
    private static let key = "postedNotificationIds"

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// true si macOS autorise les bannières de Minima Studio.
    static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    static func openSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(u)
        }
    }

    static func post(_ list: [AppNotification]) {
        let defaults = UserDefaults.standard
        var posted = Set(defaults.stringArray(forKey: key) ?? [])
        // Premier lancement : on ne rejoue pas l'historique.
        let firstRun = defaults.object(forKey: key) == nil
        for n in list where !posted.contains(n.id) {
            posted.insert(n.id)
            if firstRun { continue }
            if let d = DateFmt.parse(n.created_at), Date().timeIntervalSince(d) > 86_400 { continue }
            let c = UNMutableNotificationContent()
            c.title = n.title
            if let b = n.body { c.body = b }
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: n.id, content: c, trigger: nil))
        }
        defaults.set(Array(posted.suffix(300)), forKey: key)
    }
}
