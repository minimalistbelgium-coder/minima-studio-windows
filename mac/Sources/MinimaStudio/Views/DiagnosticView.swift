import SwiftUI
import AppKit

/// Fenêtre « Diagnostic du chrono » : montre ce que Minima Studio voit de Premiere.
@MainActor
enum DiagnosticWindow {
    private static var window: NSWindow?

    static func show(tracker: Tracker) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Diagnostic du chrono"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: DiagnosticView().environmentObject(tracker).preferredColorScheme(.dark))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct DiagnosticView: View {
    @EnvironmentObject var tracker: Tracker
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Diagnostic du chrono").font(.system(size: 20, weight: .semibold))
                Muted("Ouvre ton projet dans Premiere, mets Premiere au premier plan quelques secondes, puis reviens ici.")

                VStack(spacing: 0) {
                    row("Puce du Mac", arch)
                    row("Version de l'app", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
                    row("Autorisation Accessibilité", tracker.axTrusted ? "OK" : "Non accordée", ok: tracker.axTrusted)
                    row("Premiere ouvert", tracker.premiereOpen ? "Oui (\(tracker.premiereBundle ?? ""))" : "Non", ok: tracker.premiereOpen)
                    row("Premiere au premier plan", tracker.premiereFront ? "Oui" : "Non")
                    row("Projet détecté", tracker.projectName ?? "Aucun", ok: tracker.projectName != nil)
                    row("Mission liée", tracker.mission?.title ?? (tracker.unlinkedProject != nil ? "Projet pas encore associé" : "Aucune"),
                        ok: tracker.mission != nil)
                }
                .card(padding: 14)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Titres lus dans les fenêtres de Premiere").font(.system(size: 13.5, weight: .semibold))
                    if tracker.seenTitles.isEmpty {
                        Muted(tracker.axTrusted ? "Rien de lu. Premiere est-il ouvert avec un projet ?" : "Impossible de lire sans l'autorisation Accessibilité.")
                    }
                    ForEach(tracker.seenTitles, id: \.self) { t in
                        Text(t).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text2).textSelection(.enabled)
                    }
                }
                .card(padding: 14)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Si l'autorisation ne marche pas").font(.system(size: 13.5, weight: .semibold))
                    Muted("Après une réinstallation, macOS garde parfois une ancienne autorisation. Ce bouton l'efface et la redemande. Active ensuite Minima Studio dans la fenêtre qui s'ouvre, puis relance l'app.", size: 12)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Réinitialiser l'autorisation") { tracker.resetAccessibility() }.buttonStyle(PrimaryButton())
                        Button("Relancer l'app") { Tracker.relaunch() }.buttonStyle(SecondaryButton())
                    }
                }
                .card(padding: 14)

                Button(copied ? "Copié" : "Copier le diagnostic") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                    copied = true
                }
                .buttonStyle(SecondaryButton())
                Muted("Tu peux coller ce diagnostic dans un message à Claude.", size: 11.5)
            }
            .padding(22)
        }
        .frame(minWidth: 480, minHeight: 480)
        .background(Theme.bg)
    }

    private var arch: String {
        var sysinfo = utsname(); uname(&sysinfo)
        let m = withUnsafePointer(to: &sysinfo.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        return m == "x86_64" ? "Intel (x86_64)" : (m == "arm64" ? "Apple Silicon (arm64)" : m)
    }

    private var report: String {
        """
        Minima Studio \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"), \(arch)
        Accessibilité : \(tracker.axTrusted)
        Premiere ouvert : \(tracker.premiereOpen) \(tracker.premiereBundle ?? "")
        Premier plan : \(tracker.premiereFront)
        Projet : \(tracker.projectName ?? "aucun")
        Mission : \(tracker.mission?.title ?? "aucune")
        Titres : \(tracker.seenTitles.joined(separator: " | "))
        """
    }

    private func row(_ label: String, _ value: String, ok: Bool? = nil) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            if let ok { Circle().fill(ok ? Theme.green : Theme.red).frame(width: 7, height: 7) }
            Text(value).font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 7)
    }
}
