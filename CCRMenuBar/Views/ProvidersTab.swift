import SwiftUI

struct ProvidersTab: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedProvider: String?
    @State private var newModelName = ""
    @State private var showAPIKey = false
    @State private var showSaved = false

    var body: some View {
        HSplitView {
            // Provider sidebar
            VStack(spacing: 0) {
                List(selection: $selectedProvider) {
                    ForEach(configManager.config?.Providers ?? []) { provider in
                        ProviderListRow(provider: provider)
                            .tag(provider.name)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                HStack(spacing: 12) {
                    Button {
                        addProvider()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        removeSelectedProvider()
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedProvider == nil ? .quaternary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedProvider == nil)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Provider detail
            if let providerName = selectedProvider,
               let index = configManager.config?.Providers.firstIndex(where: { $0.name == providerName }) {
                providerDetail(index: index)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("Select a provider")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func providerDetail(index: Int) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Provider info card
                SettingsCard(title: "Provider", icon: "cloud", color: .blue) {
                    SettingsRow(label: "Name") {
                        TextField("provider-name", text: Binding(
                            get: { configManager.config?.Providers[index].name ?? "" },
                            set: {
                                configManager.config?.Providers[index].name = $0
                                selectedProvider = $0
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    SettingsRow(label: "API Base URL") {
                        TextField("https://api.example.com/...", text: Binding(
                            get: { configManager.config?.Providers[index].api_base_url ?? "" },
                            set: { configManager.config?.Providers[index].api_base_url = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    SettingsRow(label: "API Key") {
                        HStack(spacing: 8) {
                            Group {
                                if showAPIKey {
                                    TextField("sk-...", text: Binding(
                                        get: { configManager.config?.Providers[index].api_key ?? "" },
                                        set: { configManager.config?.Providers[index].api_key = $0 }
                                    ))
                                } else {
                                    SecureField("sk-...", text: Binding(
                                        get: { configManager.config?.Providers[index].api_key ?? "" },
                                        set: { configManager.config?.Providers[index].api_key = $0 }
                                    ))
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

                // Models card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.purple)
                            .frame(width: 24, height: 24)
                            .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        Text("Models")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("\(configManager.config?.Providers[index].models.count ?? 0)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.5), in: Capsule())
                    }

                    VStack(spacing: 4) {
                        ForEach(configManager.config?.Providers[index].models ?? [], id: \.self) { model in
                            ModelRow(model: model) {
                                configManager.config?.Providers[index].models.removeAll { $0 == model }
                            }
                        }
                    }

                    // Add model
                    HStack(spacing: 8) {
                        TextField("Model name (e.g. gpt-4o)", text: $newModelName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addModel(at: index) }
                        Button {
                            addModel(at: index)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(newModelName.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(newModelName.isEmpty)
                    }
                    .padding(.top, 4)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                // Transformer card
                TransformerCard(
                    transformer: Binding(
                        get: { configManager.config?.Providers[index].transformer ?? TransformerConfig() },
                        set: { configManager.config?.Providers[index].transformer = $0 }
                    )
                )

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
            }
            .padding(24)
        }
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

struct ProviderListRow: View {
    let provider: Provider

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(provider.models.count) model\(provider.models.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct TransformerCard: View {
    @Binding var transformer: TransformerConfig
    @State private var showAddMenu = false

    private var activeTransformers: [String] {
        transformer.use ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.teal)
                    .frame(width: 24, height: 24)
                    .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                Text("Transformers")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(activeTransformers.count)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5), in: Capsule())
            }

            if activeTransformers.isEmpty {
                Text("No transformers configured")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .italic()
                    .padding(.vertical, 4)
                    .padding(.leading, 32)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(activeTransformers.enumerated()), id: \.offset) { idx, name in
                        TransformerRow(name: name, displayName: BuiltInTransformer(rawValue: name)?.displayName ?? name) {
                            var list = transformer.use ?? []
                            list.remove(at: idx)
                            transformer.use = list.isEmpty ? nil : list
                        }
                    }
                }
            }

            // Add transformer
            Menu {
                ForEach(BuiltInTransformer.allCases) { t in
                    Button {
                        var list = transformer.use ?? []
                        list.append(t.rawValue)
                        transformer.use = list
                    } label: {
                        HStack {
                            Text(t.displayName)
                            if activeTransformers.contains(t.rawValue) {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10))
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Add Transformer")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.teal)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.teal.opacity(0.1), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .padding(.leading, 28)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct TransformerRow: View {
    let name: String
    let displayName: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 9))
                .foregroundStyle(.teal)
            Text(displayName)
                .font(.system(size: 12, weight: .medium))
            if displayName != name {
                Text(name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isHovered ? Color.primary.opacity(0.04) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

struct ModelRow: View {
    let model: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack {
            Image(systemName: "cpu")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(model)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
            Spacer()
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isHovered ? Color.primary.opacity(0.04) : .clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
