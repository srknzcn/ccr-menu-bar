import SwiftUI

struct MenuBarPopup: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var serverManager: ServerManager
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Claude Code Router")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("v1.0")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Server Status Card
            ServerStatusView(serverManager: serverManager)
                .padding(.horizontal, 12)

            // Config error
            if let error = configManager.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 10))
                        .lineLimit(2)
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            // Section label
            HStack {
                Text("MODEL ROUTING")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            // Router Section
            RouterSection(configManager: configManager)
                .padding(.horizontal, 8)

            // Footer
            HStack(spacing: 0) {
                FooterButton(title: "Settings", icon: "gearshape") {
                    openSettings()
                }
                Spacer()
                FooterButton(title: "Quit", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: 340)
    }
}

struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isHovered ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isHovered ? Color.primary.opacity(0.06) : .clear,
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
