import SwiftUI

struct PresetsTab: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var presetManager = PresetManager.shared
    @State private var selectedPresetName: String?

    var body: some View {
        HSplitView {
            // Preset sidebar
            VStack(spacing: 0) {
                List(selection: $selectedPresetName) {
                    ForEach(presetManager.presets) { preset in
                        PresetListRow(
                            preset: preset,
                            isActive: presetManager.selectedPresetName == preset.name
                        )
                        .tag(preset.name)
                    }
                }
                .listStyle(.sidebar)

                Divider()

                // Toolbar
                HStack(spacing: 12) {
                    Button { addPreset() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button { deleteSelected() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(selectedPresetName == nil ? .quaternary : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedPresetName == nil)

                    Button { importPreset() } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 180, maxWidth: 220)

            // Detail panel
            if let name = selectedPresetName,
               let index = presetManager.presets.firstIndex(where: { $0.name == name }) {
                presetDetail(index: index)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("Select a preset or create a new one")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private func presetDetail(index: Int) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Name field
                SettingsCard(title: "Preset", icon: "bookmark", color: .orange) {
                    SettingsRow(label: "Name") {
                        TextField("Preset name", text: Binding(
                            get: { presetManager.presets[index].name },
                            set: { newName in
                                let oldName = presetManager.presets[index].name
                                guard !newName.isEmpty, newName != oldName else { return }
                                guard !presetManager.presets.contains(where: { $0.name == newName }) else { return }
                                presetManager.presets[index].name = newName
                                selectedPresetName = newName
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }

                // Routes
                SettingsCard(title: "Routes", icon: "arrow.triangle.swap", color: .blue) {
                    ForEach(RouterRoute.allCases) { route in
                        PresetRouteRow(
                            route: route,
                            routerConfig: Binding(
                                get: { presetManager.presets[index].router },
                                set: { presetManager.presets[index].router = $0 }
                            ),
                            availableModels: configManager.availableModels()
                        )
                    }
                }

                // Actions
                HStack(spacing: 12) {
                    Spacer()

                    Button { exportPreset(at: index) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Export")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button { duplicatePreset(at: index) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                            Text("Duplicate")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button { savePreset(at: index) } label: {
                        Text("Save")
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

    // MARK: - Actions

    private func addPreset() {
        var name = "New Preset"
        var counter = 2
        while presetManager.presets.contains(where: { $0.name == name }) {
            name = "New Preset \(counter)"
            counter += 1
        }
        presetManager.savePreset(name: name, router: RouterConfig())
        selectedPresetName = name
    }

    private func deleteSelected() {
        guard let name = selectedPresetName else { return }
        presetManager.deletePreset(name: name)
        selectedPresetName = nil
        syncPresets()
    }

    private func savePreset(at index: Int) {
        let preset = presetManager.presets[index]
        presetManager.savePreset(name: preset.name, router: preset.router)
        syncPresets()
    }

    private func duplicatePreset(at index: Int) {
        let source = presetManager.presets[index]
        var name = "\(source.name) Copy"
        var counter = 2
        while presetManager.presets.contains(where: { $0.name == name }) {
            name = "\(source.name) Copy \(counter)"
            counter += 1
        }
        presetManager.savePreset(name: name, router: source.router)
        selectedPresetName = name
        syncPresets()
    }

    private func syncPresets() {
        if let providers = configManager.config?.Providers {
            presetManager.syncToCCRPresets(providers: providers)
        }
    }

    private func exportPreset(at index: Int) {
        let preset = presetManager.presets[index]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(preset) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let preset = try? JSONDecoder().decode(RouterPreset.self, from: data) else { return }
        var name = preset.name
        var counter = 2
        while presetManager.presets.contains(where: { $0.name == name }) {
            name = "\(preset.name) \(counter)"
            counter += 1
        }
        presetManager.savePreset(name: name, router: preset.router)
        selectedPresetName = name
        syncPresets()
    }
}

// MARK: - Sidebar Row

private struct PresetListRow: View {
    let preset: RouterPreset
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "bookmark.fill" : "bookmark")
                .font(.system(size: 10))
                .foregroundStyle(isActive ? .orange : .secondary)
                .frame(width: 22, height: 22)
                .background((isActive ? Color.orange : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                let routeCount = countConfiguredRoutes(preset.router)
                Text("\(routeCount) route\(routeCount == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func countConfiguredRoutes(_ router: RouterConfig) -> Int {
        [router.default, router.background, router.think, router.longContext, router.webSearch, router.image]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .count
    }
}

// MARK: - Route Row with Picker

struct PresetRouteRow: View {
    let route: RouterRoute
    @Binding var routerConfig: RouterConfig
    let availableModels: [(provider: String, model: String)]
    @State private var showPicker = false
    @State private var searchText = ""
    @State private var isHovered = false

    private var currentValue: String {
        route.getValue(from: routerConfig) ?? ""
    }

    private var providerName: String {
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return String(parts.first ?? "")
    }

    private var modelName: String {
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : currentValue
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: route.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(route.accentColor)
                .frame(width: 22, height: 22)
                .background(route.accentColor.opacity(isHovered ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 5))

            Text(route.displayName)
                .font(.system(size: 12, weight: .medium))
                .padding(.leading, 8)

            Spacer(minLength: 8)

            if !currentValue.isEmpty {
                // Clear button
                Button {
                    clearRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)

                Text(providerName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(route.accentColor.opacity(0.7), in: Capsule())

                Text(modelName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 5)
            } else {
                Text("not set")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            Button {
                searchText = ""
                showPicker = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isHovered ? Color.primary.opacity(0.04) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPicker, arrowEdge: .trailing) {
            PresetModelSearchPopover(
                models: availableModels,
                currentValue: currentValue,
                searchText: $searchText,
                onSelect: { provider, model in
                    route.setValue("\(provider),\(model)", on: &routerConfig)
                    showPicker = false
                }
            )
        }
    }

    private func clearRoute() {
        switch route {
        case .default: routerConfig.default = nil
        case .think: routerConfig.think = nil
        case .background: routerConfig.background = nil
        case .longContext: routerConfig.longContext = nil
        case .webSearch: routerConfig.webSearch = nil
        case .image: routerConfig.image = nil
        }
    }
}

// MARK: - Model Search Popover

private struct PresetModelSearchPopover: View {
    let models: [(provider: String, model: String)]
    let currentValue: String
    @Binding var searchText: String
    let onSelect: (String, String) -> Void

    private var filteredGroups: [(provider: String, models: [(provider: String, model: String)])] {
        let query = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? models : models.filter {
            $0.provider.lowercased().contains(query) || $0.model.lowercased().contains(query)
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.provider })
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { provider in
                (provider: provider,
                 models: (grouped[provider] ?? []).sorted {
                    $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
                 })
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.3))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if filteredGroups.isEmpty {
                            Text("No models found")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(Array(filteredGroups.enumerated()), id: \.element.provider) { index, group in
                                if index > 0 {
                                    Divider().padding(.horizontal, 10).padding(.vertical, 4)
                                }
                                Text(group.provider)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, index == 0 ? 6 : 2)
                                    .padding(.bottom, 2)
                                ForEach(group.models.indices, id: \.self) { idx in
                                    let item = group.models[idx]
                                    let value = "\(item.provider),\(item.model)"
                                    let isSelected = currentValue == value
                                    PresetModelRow(name: item.model, isSelected: isSelected) {
                                        onSelect(item.provider, item.model)
                                    }
                                    .id(value)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear {
                    if !currentValue.isEmpty {
                        proxy.scrollTo(currentValue, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 320)
        }
        .frame(width: 280)
    }
}

private struct PresetModelRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.blue)
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 14)
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isHovered ? Color.blue.opacity(0.1) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
