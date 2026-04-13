import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var mcpInstaller: MCPInstaller
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                TabButton(title: "Providers", icon: "server.rack", isSelected: selectedTab == 0) {
                    selectedTab = 0
                }
                TabButton(title: "General", icon: "gearshape", isSelected: selectedTab == 1) {
                    selectedTab = 1
                }
                TabButton(title: "Integrations", icon: "puzzlepiece.extension", isSelected: selectedTab == 2) {
                    selectedTab = 2
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            // Tab content
            Group {
                switch selectedTab {
                case 0:
                    ProvidersTab(configManager: configManager)
                case 2:
                    IntegrationsTab(mcpInstaller: mcpInstaller)
                default:
                    GeneralTab(configManager: configManager)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }
}

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : .clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
