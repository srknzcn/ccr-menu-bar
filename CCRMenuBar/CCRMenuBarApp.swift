import SwiftUI

@main
struct CCRMenuBarApp: App {
    @ObservedObject private var configManager = ConfigManager.shared
    @StateObject private var serverManager = ServerManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("CCR", systemImage: "arrow.triangle.branch") {
            MenuBarPopup(
                configManager: configManager,
                serverManager: serverManager,
                openSettings: { openWindow(id: "settings") }
            )
        }
        .menuBarExtraStyle(.window)

        Window("CCR Settings", id: "settings") {
            Text("Settings — coming next")
                .frame(width: 500, height: 400)
        }
        .defaultSize(width: 500, height: 400)
    }
}
