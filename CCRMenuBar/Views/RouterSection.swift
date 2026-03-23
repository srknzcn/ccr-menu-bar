import SwiftUI

struct RouterSection: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        if let config = configManager.config {
            VStack(spacing: 6) {
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
        guard !currentValue.isEmpty else { return "" }
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
            // Left: icon + route name
            HStack(spacing: 8) {
                Image(systemName: route.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(route.accentColor)
                    .frame(width: 24, height: 24)
                    .background(route.accentColor.opacity(isHovered ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 6))

                Text(route.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 12)

            // Right: provider / model
            if isConfigured {
                HStack(spacing: 5) {
                    Text(providerName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(route.accentColor.opacity(0.6), in: Capsule())

                    Text(modelName)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)
            }

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.quaternary)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isHovered ? Color.primary.opacity(0.05) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}
