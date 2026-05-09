import SwiftUI
import AppKit

@main
struct CCRMenuBarApp: App {
    @ObservedObject private var configManager = ConfigManager.shared
    @StateObject private var serverManager = ServerManager()
    @StateObject private var tokenUsageService = TokenUsageService()
    @StateObject private var presetManager = PresetManager.shared
    @StateObject private var proxyService = ProxyService()
    @StateObject private var mcpInstaller = MCPInstaller()
    @StateObject private var updateService = UpdateService.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        // Start proxy and install MCP files at app launch (not onAppear, which requires popup open)
        let proxy = ProxyService()
        let installer = MCPInstaller()
        _proxyService = StateObject(wrappedValue: proxy)
        _mcpInstaller = StateObject(wrappedValue: installer)

        Task { @MainActor in
            SpendLimitNotificationService.requestAuthorization()
            proxy.start()
            installer.installAll()
            Self.scheduleShellConfigPromptIfNeeded(installer)
            if let providers = ConfigManager.shared.config?.Providers {
                PresetManager.shared.syncToCCRPresets(providers: providers)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra("CCR", systemImage: "arrow.triangle.branch") {
            MenuBarPopup(
                configManager: configManager,
                serverManager: serverManager,
                tokenUsageService: tokenUsageService,
                presetManager: presetManager,
                proxyService: proxyService,
                openSettings: {
                    if let w = NSApp.windows.first(where: { $0.title == "CCR Settings" }) {
                        w.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        openWindow(id: "settings")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                },
                openProjectUsage: {
                    if let w = NSApp.windows.first(where: { $0.title == "Project Usage" }) {
                        if w.isMiniaturized {
                            w.deminiaturize(nil)
                        }
                        w.makeKeyAndOrderFront(nil)
                        NSApp.activate(ignoringOtherApps: true)
                    } else {
                        openWindow(id: "project-usage")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            )
            .onAppear { updateMenuBarIcon() }
            .onReceive(serverManager.$isRunning) { _ in updateMenuBarIcon() }
        }
        .menuBarExtraStyle(.window)

        Window("CCR Settings", id: "settings") {
            SettingsView(
                configManager: configManager,
                mcpInstaller: mcpInstaller,
                tokenUsageService: tokenUsageService,
                updateService: updateService
            )
        }
        .defaultSize(width: 760, height: 600)

        Window("Project Usage", id: "project-usage") {
            ProjectUsageDetailView(projects: tokenUsageService.projectBreakdown) {
                tokenUsageService.refresh()
            }
        }
        .defaultSize(width: 560, height: 420)
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

    private static func scheduleShellConfigPromptIfNeeded(_ installer: MCPInstaller) {
        guard installer.needsShellConfigInstall() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            promptForShellConfigIfNeeded(installer)
        }
    }

    private static func promptForShellConfigIfNeeded(_ installer: MCPInstaller) {
        guard installer.needsShellConfigInstall() else { return }

        let alert = NSAlert()
        alert.messageText = "CCR Menu Bar shell command is not configured"
        alert.informativeText = """
        CCR Menu Bar can add a ccm code command to \(installer.shellRCDisplayPath) so Claude Code routes through the local proxy only when launched through ccm.

        Add or update the CCR block now?
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Add / Update")
        alert.addButton(withTitle: "Not Now")

        if alert.runModal() == .alertFirstButtonReturn {
            installer.installShellConfig()
            installer.checkInstallation()
        }
    }
}
