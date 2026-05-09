import SwiftUI
import AppKit

struct ProvidersTab: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var tokenUsageService: TokenUsageService
    @State private var selectedProvider: String?
    @State private var activeModelInputProvider: String?
    @State private var modelDrafts: [String: String] = [:]
    @State private var showAPIKey = false
    @State private var showSaved = false
    @State private var fetchedModels: [String: [String]] = [:]
    @State private var loadingModelProvider: String?
    @State private var modelFetchMessages: [String: String] = [:]

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
        .onAppear {
            syncUsageContext()
            tokenUsageService.refresh()
        }
        .onChange(of: selectedProvider) {
            activeModelInputProvider = nil
        }
    }

    @ViewBuilder
    private func providerDetail(index: Int) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Provider info card
                SettingsCard(title: "Provider", icon: "cloud", color: .blue) {
                    SettingsRow(label: "Preset") {
                        Picker("Preset", selection: Binding(
                            get: { ProviderPreset.matching(configManager.config?.Providers[index])?.id },
                            set: { presetID in
                                applyPreset(id: presetID, at: index)
                            }
                        )) {
                            Text("Custom").tag(String?.none)
                            Divider()
                            ForEach(ProviderPreset.all) { preset in
                                Text(preset.displayName).tag(String?.some(preset.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
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

                SettingsCard(title: "Daily Spend Limit", icon: "bell.badge", color: .yellow) {
                    SettingsRow(label: "Limit") {
                        HStack(spacing: 8) {
                            Text("$")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            TextField("Disabled", text: dailyLimitBinding(for: index))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                            Text("USD/day")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(todaySpendLabel(for: configManager.config?.Providers[index].name ?? ""))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
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
                            ModelRow(
                                model: model,
                                thinkingDisabled: isThinkingDisabled(providerIndex: index, model: model),
                                onToggleThinking: {
                                    setThinkingDisabled(
                                        providerIndex: index,
                                        model: model,
                                        disabled: !isThinkingDisabled(providerIndex: index, model: model)
                                    )
                                },
                                onDelete: {
                                    configManager.config?.Providers[index].models.removeAll { $0 == model }
                                    setThinkingDisabled(providerIndex: index, model: model, disabled: false)
                                }
                            )
                        }
                    }

                    let providerName = configManager.config?.Providers[index].name ?? ""
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if activeModelInputProvider == providerName {
                                ModelComboBoxField(
                                    text: modelDraftBinding(for: providerName),
                                    suggestions: modelSuggestions(for: index),
                                    onSubmit: { addModel(at: index) }
                                )
                                Button {
                                    addModel(at: index)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(modelDraft(for: providerName).isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                                }
                                .buttonStyle(.plain)
                                .disabled(modelDraft(for: providerName).isEmpty)
                                .help("Add model")

                                Button {
                                    cancelModelInput(for: providerName)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Cancel")
                            } else {
                                Button {
                                    activeModelInputProvider = providerName
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .semibold))
                                        Text("Add Model")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                fetchModels(at: index)
                            } label: {
                                if loadingModelProvider == providerName {
                                    ProgressView()
                                        .controlSize(.small)
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "arrow.clockwise.circle")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(loadingModelProvider != nil || providerPreset(at: index)?.modelSource == nil)
                            .help(providerPreset(at: index)?.modelSource == nil ? "Remote model fetch is not configured for this provider" : "Fetch available models")
                        }

                        if let message = modelFetchMessages[providerName] {
                            Text(message)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
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
                        syncUsageContext()
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
        guard let providerName = configManager.config?.Providers[index].name else { return }
        let model = modelDraft(for: providerName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return }
        guard configManager.config?.Providers[index].models.contains(model) == false else {
            modelDrafts[providerName] = ""
            activeModelInputProvider = nil
            return
        }
        configManager.config?.Providers[index].models.append(model)
        modelDrafts[providerName] = ""
        activeModelInputProvider = nil
        configManager.hasUnsavedChanges = true
    }

    private func modelDraft(for providerName: String) -> String {
        modelDrafts[providerName] ?? ""
    }

    private func modelDraftBinding(for providerName: String) -> Binding<String> {
        Binding(
            get: { modelDrafts[providerName] ?? "" },
            set: { modelDrafts[providerName] = $0 }
        )
    }

    private func cancelModelInput(for providerName: String) {
        modelDrafts[providerName] = ""
        activeModelInputProvider = nil
    }

    private func isThinkingDisabled(providerIndex index: Int, model: String) -> Bool {
        configManager.config?.Providers[index].thinking_disabled_models?.contains(model) == true
    }

    private func setThinkingDisabled(providerIndex index: Int, model: String, disabled: Bool) {
        guard configManager.config != nil else { return }
        var disabledModels = configManager.config?.Providers[index].thinking_disabled_models ?? []
        disabledModels.removeAll { $0 == model }
        if disabled {
            disabledModels.append(model)
        }
        configManager.config?.Providers[index].thinking_disabled_models = disabledModels.isEmpty ? nil : disabledModels
        configManager.hasUnsavedChanges = true
    }

    private func dailyLimitBinding(for index: Int) -> Binding<String> {
        Binding(
            get: {
                guard let value = configManager.config?.Providers[index].daily_spend_limit_usd else { return "" }
                return Self.limitFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
            },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
                configManager.config?.Providers[index].daily_spend_limit_usd = trimmed.isEmpty
                    ? nil
                    : (Self.limitFormatter.number(from: trimmed)?.doubleValue ?? Double(normalized))
            }
        )
    }

    private func todaySpendLabel(for provider: String) -> String {
        guard let cost = tokenUsageService.todayProviderCostsUSD[provider] else {
            return "$0 today"
        }
        return "\(Self.formattedCost(cost)) today"
    }

    private func syncUsageContext() {
        tokenUsageService.providers = configManager.config?.Providers ?? []
        tokenUsageService.router = configManager.config?.Router
    }

    private func addProvider() {
        let preset = ProviderPreset.openRouter
        let newProvider = preset.provider()
        configManager.config?.Providers.append(newProvider)
        selectedProvider = newProvider.name
        activeModelInputProvider = nil
        fetchedModels[newProvider.name] = nil
        modelFetchMessages[newProvider.name] = nil
        configManager.hasUnsavedChanges = true
    }

    private func removeSelectedProvider() {
        guard let name = selectedProvider else { return }
        configManager.config?.Providers.removeAll { $0.name == name }
        modelDrafts[name] = nil
        fetchedModels[name] = nil
        modelFetchMessages[name] = nil
        if activeModelInputProvider == name {
            activeModelInputProvider = nil
        }
        selectedProvider = nil
        configManager.hasUnsavedChanges = true
    }

    private func applyPreset(id presetID: String?, at index: Int) {
        guard let presetID,
              let preset = ProviderPreset.all.first(where: { $0.id == presetID }),
              configManager.config != nil else {
            return
        }

        let existingAPIKey = configManager.config?.Providers[index].api_key ?? ""
        configManager.config?.Providers[index].name = uniqueProviderName(preset.providerName, replacing: index)
        configManager.config?.Providers[index].api_base_url = preset.apiBaseURL
        configManager.config?.Providers[index].api_key = existingAPIKey
        configManager.config?.Providers[index].transformer = TransformerConfig(use: preset.transformers)
        if configManager.config?.Providers[index].models.isEmpty == true {
            configManager.config?.Providers[index].models = preset.defaultModels
        }
        selectedProvider = configManager.config?.Providers[index].name
        activeModelInputProvider = nil
        fetchedModels[configManager.config?.Providers[index].name ?? ""] = nil
        modelFetchMessages[configManager.config?.Providers[index].name ?? ""] = preset.modelSource == nil ? "Remote model list is not available for this preset." : nil
        configManager.hasUnsavedChanges = true
    }

    private func uniqueProviderName(_ baseName: String, replacing index: Int) -> String {
        guard let providers = configManager.config?.Providers else { return baseName }
        let existing = Set(providers.enumerated().compactMap { offset, provider in
            offset == index ? nil : provider.name
        })
        guard existing.contains(baseName) else { return baseName }

        var suffix = 2
        while existing.contains("\(baseName)-\(suffix)") {
            suffix += 1
        }
        return "\(baseName)-\(suffix)"
    }

    private func providerPreset(at index: Int) -> ProviderPreset? {
        ProviderPreset.matching(configManager.config?.Providers[index])
    }

    private func modelSuggestions(for index: Int) -> [String] {
        let existing = Set(configManager.config?.Providers[index].models ?? [])
        let presetDefaults = providerPreset(at: index)?.defaultModels ?? []
        let providerName = configManager.config?.Providers[index].name ?? ""
        return Array(Set((fetchedModels[providerName] ?? []) + presetDefaults))
            .filter { !existing.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func fetchModels(at index: Int) {
        guard let provider = configManager.config?.Providers[index] else { return }
        guard let preset = ProviderPreset.matching(provider),
              let source = preset.modelSource else {
            modelFetchMessages[provider.name] = "Remote model list is not available for this provider."
            return
        }

        loadingModelProvider = provider.name
        modelFetchMessages[provider.name] = nil
        Task {
            do {
                let models = try await ProviderModelFetcher.fetchModels(for: provider, source: source)
                await MainActor.run {
                    fetchedModels[provider.name] = models
                    modelFetchMessages[provider.name] = models.isEmpty ? "No models returned." : "\(models.count) models loaded."
                    loadingModelProvider = nil
                }
            } catch {
                await MainActor.run {
                    modelFetchMessages[provider.name] = "Could not load models: \(error.localizedDescription)"
                    loadingModelProvider = nil
                }
            }
        }
    }

    private static let limitFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static func formattedCost(_ cost: Double) -> String {
        if cost < 0.0001 {
            return String(format: "$%.6f", cost)
        }
        if cost < 1 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
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
    let thinkingDisabled: Bool
    let onToggleThinking: () -> Void
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
            Button(action: onToggleThinking) {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 9))
                    Text(thinkingDisabled ? "Think Off" : "Think On")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(thinkingDisabled ? Color.orange : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(
                    thinkingDisabled ? Color.orange.opacity(0.14) : Color.secondary.opacity(0.10),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .help(thinkingDisabled ? "Thinking disabled for this model" : "Disable thinking for this model")

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

struct ModelComboBoxField: NSViewRepresentable {
    @Binding var text: String
    let suggestions: [String]
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 20
        comboBox.hasVerticalScroller = true
        comboBox.isEditable = true
        comboBox.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        comboBox.placeholderString = "Model name (e.g. gpt-5)"
        comboBox.target = context.coordinator
        comboBox.action = #selector(Coordinator.selectionChanged(_:))
        comboBox.delegate = context.coordinator
        reload(comboBox, with: suggestions, matching: text)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        reload(comboBox, with: suggestions, matching: text)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func reload(_ comboBox: NSComboBox, with suggestions: [String], matching query: String) {
        let filteredSuggestions = filtered(suggestions, matching: query)
        let currentItems = (0..<comboBox.numberOfItems).compactMap { comboBox.itemObjectValue(at: $0) as? String }
        guard currentItems != filteredSuggestions else { return }
        comboBox.removeAllItems()
        comboBox.addItems(withObjectValues: filteredSuggestions)
        comboBox.noteNumberOfItemsChanged()
    }

    private func filtered(_ suggestions: [String], matching query: String) -> [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return suggestions }
        return suggestions.filter {
            $0.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ModelComboBoxField

        init(parent: ModelComboBoxField) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSComboBox) {
            parent.text = sender.stringValue
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
            parent.reload(comboBox, with: parent.suggestions, matching: comboBox.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.text = control.stringValue
            parent.onSubmit()
            return true
        }
    }
}

struct ProviderPreset: Identifiable, Hashable {
    enum ModelSource: Hashable {
        case openAICompatibleModels
        case anthropicModels
        case openRouterModels
        case ollamaTags
    }

    let id: String
    let displayName: String
    let providerName: String
    let apiBaseURL: String
    let transformers: [String]
    let defaultModels: [String]
    let modelSource: ModelSource?

    static let openRouter = ProviderPreset(
        id: "openrouter",
        displayName: "OpenRouter",
        providerName: "openrouter",
        apiBaseURL: "https://openrouter.ai/api/v1",
        transformers: ["OpenAI"],
        defaultModels: ["anthropic/claude-sonnet-4", "openai/gpt-5", "google/gemini-2.5-pro"],
        modelSource: .openRouterModels
    )

    static let all: [ProviderPreset] = [
        openRouter,
        ProviderPreset(
            id: "openai",
            displayName: "OpenAI",
            providerName: "openai",
            apiBaseURL: "https://api.openai.com/v1",
            transformers: ["OpenAI"],
            defaultModels: ["gpt-5", "gpt-5-mini", "gpt-4o"],
            modelSource: .openAICompatibleModels
        ),
        ProviderPreset(
            id: "anthropic",
            displayName: "Anthropic",
            providerName: "anthropic",
            apiBaseURL: "https://api.anthropic.com/v1",
            transformers: ["Anthropic"],
            defaultModels: ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"],
            modelSource: .anthropicModels
        ),
        ProviderPreset(
            id: "ollama",
            displayName: "Ollama",
            providerName: "ollama",
            apiBaseURL: "http://localhost:11434",
            transformers: ["OpenAI"],
            defaultModels: ["llama3.3", "qwen3", "gemma3"],
            modelSource: .ollamaTags
        ),
        ProviderPreset(
            id: "gemini",
            displayName: "Gemini",
            providerName: "gemini",
            apiBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            transformers: ["gemini"],
            defaultModels: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"],
            modelSource: .openAICompatibleModels
        ),
        ProviderPreset(
            id: "groq",
            displayName: "Groq",
            providerName: "groq",
            apiBaseURL: "https://api.groq.com/openai/v1",
            transformers: ["OpenAI"],
            defaultModels: ["llama-3.3-70b-versatile", "openai/gpt-oss-120b"],
            modelSource: .openAICompatibleModels
        ),
        ProviderPreset(
            id: "deepseek",
            displayName: "DeepSeek",
            providerName: "deepseek",
            apiBaseURL: "https://api.deepseek.com/v1",
            transformers: ["deepseek"],
            defaultModels: ["deepseek-chat", "deepseek-reasoner"],
            modelSource: .openAICompatibleModels
        )
    ]

    static func matching(_ provider: Provider?) -> ProviderPreset? {
        guard let provider else { return nil }
        let name = provider.name.lowercased()
        let baseURL = provider.api_base_url.lowercased()
        return all.first { preset in
            name == preset.providerName || baseURL == preset.apiBaseURL.lowercased()
        }
    }

    func provider() -> Provider {
        Provider(
            name: providerName,
            api_base_url: apiBaseURL,
            api_key: "",
            models: defaultModels,
            transformer: TransformerConfig(use: transformers)
        )
    }
}

enum ProviderModelFetcher {
    static func fetchModels(for provider: Provider, source: ProviderPreset.ModelSource) async throws -> [String] {
        let url = modelURL(baseURL: provider.api_base_url, source: source)
        var request = URLRequest(url: url, timeoutInterval: 20)

        switch source {
        case .anthropicModels:
            request.setValue(provider.api_key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openAICompatibleModels, .openRouterModels:
            if !provider.api_key.isEmpty {
                request.setValue("Bearer \(provider.api_key)", forHTTPHeaderField: "Authorization")
            }
        case .ollamaTags:
            break
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProviderModelFetchError.httpStatus(http.statusCode)
        }

        switch source {
        case .ollamaTags:
            return try JSONDecoder().decode(OllamaTagsResponse.self, from: data).models.map(\.name).sorted()
        case .openAICompatibleModels, .openRouterModels, .anthropicModels:
            return try JSONDecoder().decode(ModelsResponse.self, from: data).data.map(\.id).sorted()
        }
    }

    private static func modelURL(baseURL: String, source: ProviderPreset.ModelSource) -> URL {
        var components = URLComponents(url: normalizedBaseURL(baseURL, source: source), resolvingAgainstBaseURL: false)!

        switch source {
        case .ollamaTags:
            components.path = appendPath("api/tags", to: components.path)
        case .openRouterModels:
            components.path = appendPath("models", to: components.path)
            components.queryItems = [URLQueryItem(name: "output_modalities", value: "all")]
        case .openAICompatibleModels, .anthropicModels:
            components.path = appendPath("models", to: components.path)
        }

        return components.url!
    }

    private static func normalizedBaseURL(_ baseURL: String, source: ProviderPreset.ModelSource) -> URL {
        let fallback = source == .ollamaTags ? "http://localhost:11434" : "https://api.openai.com/v1"
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: raw.isEmpty ? fallback : raw) ?? URLComponents(string: fallback)!

        let endpointSuffixes = [
            "/chat/completions",
            "/completions",
            "/messages",
            "/responses",
            "/models",
            "/api/tags"
        ]
        for suffix in endpointSuffixes where components.path.hasSuffix(suffix) {
            components.path.removeLast(suffix.count)
            break
        }

        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func appendPath(_ path: String, to basePath: String) -> String {
        let normalizedBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !normalizedBase.isEmpty else { return "/\(path)" }
        return "/\(normalizedBase)/\(path)"
    }
}

enum ProviderModelFetchError: LocalizedError {
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            return "HTTP \(status)"
        }
    }
}

struct ModelsResponse: Decodable {
    struct Model: Decodable {
        let id: String
    }

    let data: [Model]
}

struct OllamaTagsResponse: Decodable {
    struct Model: Decodable {
        let name: String
    }

    let models: [Model]
}
