import SwiftUI

struct RouterSection: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        if let config = configManager.config {
            ForEach(RouterRoute.allCases) { route in
                let currentValue = route.getValue(from: config.Router) ?? ""
                let modelName = parseModelName(currentValue)

                Menu {
                    let models = configManager.availableModels()
                    ForEach(Array(models.enumerated()), id: \.offset) { _, item in
                        let value = "\(item.provider),\(item.model)"
                        Button {
                            configManager.setRoute(route, provider: item.provider, model: item.model)
                        } label: {
                            HStack {
                                Text("\(item.provider) / \(item.model)")
                                if currentValue == value {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(route.displayName)
                            .frame(width: 90, alignment: .leading)
                        Text(modelName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
            }
        } else {
            Text("Config not loaded")
                .foregroundStyle(.secondary)
        }
    }

    private func parseModelName(_ value: String) -> String {
        guard !value.isEmpty else { return "\u{2014}" }
        let parts = value.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : value
    }
}
