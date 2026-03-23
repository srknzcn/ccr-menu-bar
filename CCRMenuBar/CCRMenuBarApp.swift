import SwiftUI
import AppKit

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
            .onAppear { updateMenuBarIcon() }
            .onReceive(serverManager.$isRunning) { _ in updateMenuBarIcon() }
        }
        .menuBarExtraStyle(.window)

        Window("CCR Settings", id: "settings") {
            SettingsView(configManager: configManager)
        }
        .defaultSize(width: 760, height: 600)
    }

    private func updateMenuBarIcon() {
        DispatchQueue.main.async {
            guard let button = NSApp.windows
                .compactMap({ $0 as? NSPanel })
                .first(where: { $0.className.contains("StatusBar") || $0.title == "CCR" })?
                .contentView?.superview?.superview as? NSStatusBarButton ?? findStatusButton()
            else { return }

            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            let image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "CCR")?
                .withSymbolConfiguration(config)

            if serverManager.isRunning {
                button.image = image
                button.contentTintColor = .systemGreen
            } else {
                button.image = image
                button.contentTintColor = nil  // default/white
            }
        }
    }

    private func findStatusButton() -> NSStatusBarButton? {
        // Find the status item button by checking all status bar windows
        for window in NSApp.windows {
            if let button = window.contentView?.superview as? NSStatusBarButton {
                return button
            }
        }
        return nil
    }
}
