import SwiftUI

struct RouterSection: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        if let config = configManager.config {
            VStack(spacing: 4) {
                ForEach(RouterRoute.allCases) { route in
                    let currentValue = route.getValue(from: config.Router) ?? ""
                    RouteRow(
                        route: route,
                        currentValue: currentValue,
                        models: configManager.availableModels(),
                        onSelect: { provider, model in
                            configManager.setRoute(route, provider: provider, model: model)
                        },
                        onToggleThinking: { provider, model, disabled in
                            configManager.setThinkingDisabled(provider: provider, model: model, disabled: disabled)
                        }
                    )
                }
            }
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Config not loaded")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

struct RouteRow: View {
    let route: RouterRoute
    let currentValue: String
    let models: [(provider: String, model: String, thinkingDisabled: Bool)]
    let onSelect: (String, String) -> Void
    let onToggleThinking: (String, String, Bool) -> Void
    @State private var isHovered = false
    @State private var showPicker = false
    @State private var searchText = ""

    private var providerName: String {
        guard !currentValue.isEmpty else { return "" }
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return String(parts.first ?? "")
    }

    private var modelName: String {
        guard !currentValue.isEmpty else { return "" }
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : currentValue
    }

    private var isConfigured: Bool { !currentValue.isEmpty }

    var body: some View {
        Button {
            searchText = ""
            showPicker = true
        } label: {
            HStack(spacing: 0) {
                // LEFT: icon + route name
                Image(systemName: route.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(route.accentColor)
                    .frame(width: 22, height: 22)
                    .background(route.accentColor.opacity(isHovered ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 5))

                Text(route.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.leading, 8)

                Spacer(minLength: 8)

                // RIGHT: provider / model
                if isConfigured {
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

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.quaternary)
                    .padding(.leading, 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHovered ? Color.primary.opacity(0.06) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .popover(isPresented: $showPicker, arrowEdge: .trailing) {
            ModelSearchPopover(
                models: models,
                currentValue: currentValue,
                searchText: $searchText,
                onSelect: { provider, model in
                    onSelect(provider, model)
                    showPicker = false
                },
                onToggleThinking: { provider, model, disabled in
                    onToggleThinking(provider, model, disabled)
                }
            )
        }
    }
}

// MARK: - Model Search Popover

private struct ModelSearchPopover: View {
    let models: [(provider: String, model: String, thinkingDisabled: Bool)]
    let currentValue: String
    @Binding var searchText: String
    let onSelect: (String, String) -> Void
    let onToggleThinking: (String, String, Bool) -> Void

    private var filteredGroups: [(provider: String, models: [(provider: String, model: String, thinkingDisabled: Bool)])] {
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
            // Search field
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

            // Model list
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

                                // Provider header
                                Text(group.provider)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.top, index == 0 ? 6 : 2)
                                    .padding(.bottom, 2)

                                // Models
                                ForEach(group.models.indices, id: \.self) { idx in
                                    let item = group.models[idx]
                                    let value = "\(item.provider),\(item.model)"
                                    let isSelected = currentValue == value
                                    RouteModelRow(
                                        name: item.model,
                                        isSelected: isSelected,
                                        action: {
                                            onSelect(item.provider, item.model)
                                        },
                                        thinkingDisabled: item.thinkingDisabled,
                                        onToggleThinking: {
                                            onToggleThinking(item.provider, item.model, !item.thinkingDisabled)
                                        }
                                    )
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

// MARK: - Model Row

private struct RouteModelRow: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    let thinkingDisabled: Bool
    let onToggleThinking: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
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
            }
            .buttonStyle(.plain)

            Button(action: onToggleThinking) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(thinkingDisabled ? .white : .clear)
                    .frame(width: 18, height: 18)
                    .background(thinkingDisabled ? Color.orange : Color.secondary.opacity(0.16), in: RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 9))
                            .foregroundStyle(thinkingDisabled ? .white : .secondary)
                    }
            }
            .buttonStyle(.plain)
            .help(thinkingDisabled ? "Thinking disabled for this model" : "Disable thinking for this model")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isHovered ? Color.blue.opacity(0.1) : .clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}
