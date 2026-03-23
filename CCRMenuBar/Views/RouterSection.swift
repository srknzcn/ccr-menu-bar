import SwiftUI
import AppKit

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
        guard !currentValue.isEmpty else { return "" }
        let parts = currentValue.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : currentValue
    }

    private var isConfigured: Bool { !currentValue.isEmpty }

    var body: some View {
        Button {
            showMenu()
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
    }

    private func showMenu() {
        let menu = NSMenu()
        let grouped = Dictionary(grouping: models, by: { $0.provider })
        let sortedProviders = grouped.keys.sorted()

        for (i, provider) in sortedProviders.enumerated() {
            if i > 0 { menu.addItem(.separator()) }

            let header = NSMenuItem(title: provider.uppercased(), action: nil, keyEquivalent: "")
            header.isEnabled = false
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            header.attributedTitle = NSAttributedString(string: provider, attributes: attrs)
            menu.addItem(header)

            for item in (grouped[provider] ?? []) {
                let value = "\(item.provider),\(item.model)"
                let menuItem = NSMenuItem(title: item.model, action: #selector(RouteMenuTarget.menuItemClicked(_:)), keyEquivalent: "")
                menuItem.target = RouteMenuTarget.shared
                menuItem.representedObject = (item.provider, item.model, onSelect)
                if currentValue == value {
                    menuItem.state = .on
                }
                menu.addItem(menuItem)
            }
        }

        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: NSApp.keyWindow?.contentView ?? NSView())
        }
    }
}

// NSMenu target for handling clicks
class RouteMenuTarget: NSObject {
    static let shared = RouteMenuTarget()

    @objc func menuItemClicked(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? (String, String, (String, String) -> Void) else { return }
        let (provider, model, callback) = info
        callback(provider, model)
    }
}
