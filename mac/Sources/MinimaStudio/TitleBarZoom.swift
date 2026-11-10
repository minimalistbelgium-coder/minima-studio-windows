import AppKit

/// La barre de titre est masquée (le contenu remonte jusqu'en haut) : on refait donc à la main
/// le double-clic sur le haut de la fenêtre, en suivant le réglage de macOS
/// (Réglages Système > Bureau et Dock > « Double-cliquer sur la barre de titre »).
@MainActor
enum TitleBarZoom {
    private static var monitor: Any?
    /// Hauteur de la zone qui se comporte comme une barre de titre.
    static let height: CGFloat = 32

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2,
                  let w = event.window, !(w is NSPanel),
                  let content = w.contentView else { return event }
            let fromTop = content.bounds.height - event.locationInWindow.y
            guard fromTop >= 0 && fromTop <= height else { return event }
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": w.miniaturize(nil)
            case "None": break
            default: w.zoom(nil)
            }
            return nil
        }
    }
}
