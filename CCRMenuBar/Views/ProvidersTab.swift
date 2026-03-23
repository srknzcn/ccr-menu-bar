import SwiftUI

struct ProvidersTab: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedProvider: String?
    @State private var newModelName = ""
    @State private var showAPIKey = false

    var body: some View {
        HSplitView {
            VStack {
                List(selection: $selectedProvider) {
                    ForEach(configManager.config?.Providers ?? []) { provider in
                        HStack {
                            Text(provider.name)
                            Spacer()
                            Text("\(provider.models.count) models")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .tag(provider.name)
                    }
                }

                HStack {
                    Button("+") { addProvider() }
                    Button("-") { removeSelectedProvider() }
                        .disabled(selectedProvider == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 180)

            if let providerName = selectedProvider,
               let index = configManager.config?.Providers.firstIndex(where: { $0.name == providerName }) {
                providerDetail(index: index)
            } else {
                Text("Select a provider")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func providerDetail(index: Int) -> some View {
        Form {
            Section("Provider") {
                TextField("Name", text: Binding(
                    get: { configManager.config?.Providers[index].name ?? "" },
                    set: { configManager.config?.Providers[index].name = $0 }
                ))
                TextField("API Base URL", text: Binding(
                    get: { configManager.config?.Providers[index].api_base_url ?? "" },
                    set: { configManager.config?.Providers[index].api_base_url = $0 }
                ))
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: Binding(
                            get: { configManager.config?.Providers[index].api_key ?? "" },
                            set: { configManager.config?.Providers[index].api_key = $0 }
                        ))
                    } else {
                        SecureField("API Key", text: Binding(
                            get: { configManager.config?.Providers[index].api_key ?? "" },
                            set: { configManager.config?.Providers[index].api_key = $0 }
                        ))
                    }
                    Button(showAPIKey ? "Hide" : "Show") {
                        showAPIKey.toggle()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Models") {
                ForEach(configManager.config?.Providers[index].models ?? [], id: \.self) { model in
                    HStack {
                        Text(model)
                        Spacer()
                        Button(role: .destructive) {
                            configManager.config?.Providers[index].models.removeAll { $0 == model }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("New model", text: $newModelName)
                        .onSubmit { addModel(at: index) }
                    Button("Add") { addModel(at: index) }
                        .disabled(newModelName.isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    configManager.save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
    }

    private func addModel(at index: Int) {
        guard !newModelName.isEmpty else { return }
        configManager.config?.Providers[index].models.append(newModelName)
        newModelName = ""
    }

    private func addProvider() {
        let newProvider = Provider(
            name: "new-provider",
            api_base_url: "",
            api_key: "",
            models: []
        )
        configManager.config?.Providers.append(newProvider)
        selectedProvider = newProvider.name
    }

    private func removeSelectedProvider() {
        guard let name = selectedProvider else { return }
        configManager.config?.Providers.removeAll { $0.name == name }
        selectedProvider = nil
    }
}
