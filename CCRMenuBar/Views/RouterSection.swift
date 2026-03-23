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
    let models: [(provider: String, model: String)]
    let onSelect: (String, String) -> Void
    @State private var isHovered = false

    private var providerName: String {
        guard !currentValue.isEmpty else { return "" }
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return String(parts.first ?? "")
    }

    private var modelName: String {
        guard !currentValue.isEmpty else { return "Not set" }
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : currentValue
    }

    var body: some View {
        Menu {
            // Group models by provider
            let grouped = Dictionary(grouping: models, by: { $0.provider })
            let sortedProviders = grouped.keys.sorted()

            ForEach(sortedProviders, id: \.self) { provider in
                Section(provider) {
                    ForEach(grouped[provider] ?? [], id: \.model) { item in
                        let value = "\(item.provider),\(item.model)"
                        Button {
                            onSelect(item.provider, item.model)
                        } label: {
                            HStack {
                                Text(item.model)
                                if currentValue == value {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Route icon with accent background
                Image(systemName: route.icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(route.accentColor)
                    .frame(width: 26, height: 26)
                    .background(route.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text(route.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                    if !providerName.isEmpty {
                        Text(providerName)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Model name pill
                Text(modelName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(currentValue.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: Capsule())

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isHovered ? Color.primary.opacity(0.04) : .clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
        .onHover { isHovered = $0 }
    }
}
