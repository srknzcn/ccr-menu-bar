import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        TabView {
            ProvidersTab(configManager: configManager)
                .tabItem {
                    Label("Providers", systemImage: "server.rack")
                }

            GeneralTab(configManager: configManager)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(minWidth: 550, minHeight: 450)
    }
}
