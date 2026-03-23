import SwiftUI

struct GeneralTab: View {
    @ObservedObject var configManager: ConfigManager
    @State private var showAPIKey = false

    var body: some View {
        Form {
            if configManager.config != nil {
                Section("Server") {
                    TextField("Host", text: binding(\.HOST, default: "127.0.0.1"))
                    TextField("Port", value: Binding(
                        get: { configManager.config?.PORT ?? 3456 },
                        set: { configManager.config?.PORT = $0 }
                    ), format: .number)
                    TextField("API Timeout (ms)", text: binding(\.API_TIMEOUT_MS, default: ""))
                    TextField("Proxy URL", text: binding(\.PROXY_URL, default: ""))
                }

                Section("Paths") {
                    TextField("Claude Path", text: binding(\.CLAUDE_PATH, default: ""))
                }

                Section("Security") {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: binding(\.APIKEY, default: ""))
                        } else {
                            SecureField("API Key", text: binding(\.APIKEY, default: ""))
                        }
                        Button(showAPIKey ? "Hide" : "Show") {
                            showAPIKey.toggle()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section("Logging") {
                    Toggle("Enable Logging", isOn: Binding(
                        get: { configManager.config?.LOG ?? false },
                        set: { configManager.config?.LOG = $0 }
                    ))
                    TextField("Log Level", text: binding(\.LOG_LEVEL, default: "info"))
                }

                Section("Router") {
                    TextField("Long Context Threshold", value: Binding(
                        get: { configManager.config?.Router.longContextThreshold ?? 60000 },
                        set: { configManager.config?.Router.longContextThreshold = $0 }
                    ), format: .number)
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        configManager.save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Config not loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding(_ keyPath: WritableKeyPath<CCRConfig, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { configManager.config?[keyPath: keyPath] ?? defaultValue },
            set: { configManager.config?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}
