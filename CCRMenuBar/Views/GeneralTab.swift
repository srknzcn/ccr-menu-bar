import SwiftUI

struct GeneralTab: View {
    @ObservedObject var configManager: ConfigManager
    @State private var showAPIKey = false
    @State private var showSaved = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if configManager.config != nil {
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
