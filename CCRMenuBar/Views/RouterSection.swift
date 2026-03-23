import SwiftUI

struct RouterSection: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        if let config = configManager.config {
            VStack(spacing: 2) {
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
        guard !currentValue.isEmpty else { return "Not configured" }
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : currentValue
    }

    private var isConfigured: Bool {
        !currentValue.isEmpty
    }

    var body: some View {
        Menu {
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
            routeLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .onHover { isHovered = $0 }
    }

    private var routeLabel: some View {
        HStack(spacing: 0) {
            // Left: icon
            Image(systemName: route.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(route.accentColor)
                .frame(width: 28, height: 28)
                .background(route.accentColor.opacity(isHovered ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 7))

            // Middle: route name + model
            VStack(alignment: .leading, spacing: 2) {
                Text(route.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    if isConfigured {
                        Text(providerName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(route.accentColor.opacity(0.5), in: Capsule())

                        Text(modelName)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text("Not configured")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                }
            }
            .padding(.leading, 10)

            Spacer(minLength: 8)

            // Right: chevron
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovered ? Color.primary.opacity(0.06) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
