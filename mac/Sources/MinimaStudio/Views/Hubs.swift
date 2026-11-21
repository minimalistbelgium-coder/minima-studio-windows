import SwiftUI

// Pages regroupées de la nouvelle navigation : chaque entrée du menu répond à une question,
// et ses anciennes pages deviennent des onglets posés au-dessus du titre.

private struct PageTabsKey: EnvironmentKey { static let defaultValue: AnyView? = nil }

extension EnvironmentValues {
    /// Onglets affichés par PageHeader au-dessus du titre de la page.
    var pageTabs: AnyView? {
        get { self[PageTabsKey.self] }
        set { self[PageTabsKey.self] = newValue }
    }
}

/// Missions : le même contenu en liste ou en calendrier.
struct MissionsHub<L: View>: View {
    @AppStorage("missionsLayout") private var layout = "list"
    @ViewBuilder var list: () -> L

    var body: some View {
        Group {
            if layout == "cal" { AgendaView() } else { list() }
        }
        .environment(\.pageTabs, AnyView(ChipPicker(selection: $layout, options: [
            .init(value: "list", label: "Liste"),
            .init(value: "cal", label: "Calendrier"),
        ])))
    }
}

/// Finances : l'argent, et le temps de montage qui explique la rentabilité.
struct FinancesHub: View {
    @State private var tab = "money"

    var body: some View {
        Group {
            if tab == "time" { TimeView() } else { FinancesView() }
        }
        .environment(\.pageTabs, AnyView(ChipPicker(selection: $tab, options: [
            .init(value: "money", label: "Finances"),
            .init(value: "time", label: "Temps de montage"),
        ])))
    }
}

/// Réglages : tout ce qui se configure, au même endroit.
struct SettingsHub: View {
    @State private var tab = "team"

    var body: some View {
        Group {
            switch tab {
            case "clients": ClientsView()
            case "connect": AppsStatsView(connectionsOnly: true)
            case "updates": UpdatesView()
            default: TeamView()
            }
        }
        .environment(\.pageTabs, AnyView(ChipPicker(selection: $tab, options: [
            .init(value: "team", label: "Équipe"),
            .init(value: "clients", label: "Clients"),
            .init(value: "connect", label: "Connexions"),
            .init(value: "updates", label: "Mises à jour"),
        ])))
    }
}
