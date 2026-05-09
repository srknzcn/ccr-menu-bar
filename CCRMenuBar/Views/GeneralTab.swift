import SwiftUI
import ServiceManagement

struct GeneralTab: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var tokenUsageService: TokenUsageService
    @ObservedObject var updateService: UpdateService
    @State private var showAPIKey = false
    @State private var showSaved = false
    @State private var showPricingRefreshed = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if configManager.config != nil {
                    SettingsCard(title: "App", icon: "app.badge", color: .indigo) {
                        SettingsRow(label: "Launch at Login") {
                            Toggle("", isOn: $launchAtLogin)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .onChange(of: launchAtLogin) { _, newValue in
                                    do {
                                        if newValue {
                                            try SMAppService.mainApp.register()
                                        } else {
                                            try SMAppService.mainApp.unregister()
                                        }
                                    } catch {
                                        launchAtLogin = SMAppService.mainApp.status == .enabled
                                    }
                                }
                        }

                        SettingsRow(label: "Version") {
                            Text(appVersionText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        SettingsRow(label: "Updates") {
                            HStack(spacing: 8) {
                                Button {
                                    updateService.checkForUpdates()
                                } label: {
                                    Label("Check for Updates", systemImage: "arrow.down.circle")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .disabled(!updateService.canCheckForUpdates)

                                Text("Checks every hour")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    SettingsCard(title: "Server", icon: "server.rack", color: .blue) {
                        SettingsRow(label: "Host") {
                            TextField("127.0.0.1", text: binding(\.HOST, default: "127.0.0.1"))
                                .textFieldStyle(.roundedBorder)
                        }
                        SettingsRow(label: "Port") {
                            TextField("3456", value: Binding(
                                get: { configManager.config?.PORT ?? 3456 },
                                set: { configManager.config?.PORT = $0 }
                            ), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        }
                        SettingsRow(label: "API Timeout") {
                            HStack(spacing: 6) {
                                TextField("600000", text: binding(\.API_TIMEOUT_MS, default: ""))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                Text("ms")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        SettingsRow(label: "Proxy URL") {
                            TextField("http://...", text: binding(\.PROXY_URL, default: ""))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    SettingsCard(title: "Paths", icon: "folder", color: .orange) {
                        SettingsRow(label: "Claude Binary") {
                            TextField("/usr/local/bin/claude", text: binding(\.CLAUDE_PATH, default: ""))
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    SettingsCard(title: "Pricing Cache", icon: "dollarsign.circle", color: .yellow) {
                        SettingsRow(label: "Last Updated") {
                            Text(pricingUpdatedText)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        SettingsRow(label: "Cache") {
                            HStack(spacing: 8) {
                                Button {
                                    tokenUsageService.refreshPricingCache()
                                    withAnimation { showPricingRefreshed = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        withAnimation { showPricingRefreshed = false }
                                    }
                                } label: {
                                    Label(
                                        tokenUsageService.isPricingRefreshing ? "Refreshing..." : "Refresh Pricing Cache",
                                        systemImage: "arrow.clockwise"
                                    )
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                                }
                                .buttonStyle(.plain)
                                .disabled(tokenUsageService.isPricingRefreshing)

                                if showPricingRefreshed && tokenUsageService.pricingError == nil {
                                    Label("Refresh started", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.green)
                                        .transition(.opacity.combined(with: .scale))
                                }
                            }
                        }

                        if let pricingError = tokenUsageService.pricingError {
                            SettingsRow(label: "Status") {
                                Text(pricingError)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.red)
                                    .lineLimit(2)
                            }
                        }
                    }

                    SettingsCard(title: "Security", icon: "lock.shield", color: .red) {
                        SettingsRow(label: "API Key") {
                            HStack(spacing: 8) {
                                Group {
                                    if showAPIKey {
                                        TextField("sk-...", text: binding(\.APIKEY, default: ""))
                                    } else {
                                        SecureField("sk-...", text: binding(\.APIKEY, default: ""))
                                    }
                                }
                                .textFieldStyle(.roundedBorder)

                                Button {
                                    showAPIKey.toggle()
                                } label: {
                                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    SettingsCard(title: "Logging", icon: "doc.text", color: .green) {
                        SettingsRow(label: "Enable") {
                            Toggle("", isOn: Binding(
                                get: { configManager.config?.LOG ?? false },
                                set: { configManager.config?.LOG = $0 }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        SettingsRow(label: "Level") {
                            Picker("", selection: Binding(
                                get: { configManager.config?.LOG_LEVEL ?? "info" },
                                set: { configManager.config?.LOG_LEVEL = $0 }
                            )) {
                                ForEach(["fatal", "error", "warn", "info", "debug", "trace"], id: \.self) { level in
                                    Text(level).tag(level)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }

                    SettingsCard(title: "Router", icon: "arrow.triangle.branch", color: .purple) {
                        SettingsRow(label: "Long Context Threshold") {
                            HStack(spacing: 6) {
                                TextField("60000", value: Binding(
                                    get: { configManager.config?.Router.longContextThreshold ?? 60000 },
                                    set: { configManager.config?.Router.longContextThreshold = $0 }
                                ), format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                Text("tokens")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }

                    // Save button
                    HStack {
                        Spacer()
                        if showSaved {
                            Label("Saved", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.green)
                                .transition(.opacity.combined(with: .scale))
                        }
                        Button {
                            configManager.save()
                            withAnimation { showSaved = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showSaved = false }
                            }
                        } label: {
                            Text("Save Changes")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                } else {
                    ContentUnavailableView("Config Not Loaded", systemImage: "exclamationmark.triangle", description: Text("Check that ~/.claude-code-router/config.json exists"))
                }
            }
            .padding(24)
        }
    }

    private func binding(_ keyPath: WritableKeyPath<CCRConfig, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { configManager.config?[keyPath: keyPath] ?? defaultValue },
            set: { configManager.config?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private var pricingUpdatedText: String {
        guard let date = tokenUsageService.pricingUpdatedAt else {
            return "Not loaded"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        if let build, !build.isEmpty {
            return "\(version) (\(build))"
        }

        return version
    }
}

// MARK: - Reusable Settings Components

struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(spacing: 10) {
                content
            }
            .padding(.leading, 32)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
            content
        }
    }
}
