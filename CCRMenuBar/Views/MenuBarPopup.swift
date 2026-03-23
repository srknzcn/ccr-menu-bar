import SwiftUI

struct MenuBarPopup: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var serverManager: ServerManager
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Server Status
            ServerStatusView(serverManager: serverManager)
                .padding(.horizontal, 12)
                .padding(.top, 12)

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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 12)
                .padding(.top, 10)
            }

            // Section divider
            HStack(spacing: 6) {
                Text("ROUTES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(1)
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)

            // Router Section
            RouterSection(configManager: configManager)
                .padding(.horizontal, 8)

            // Footer divider
            Rectangle()
                .fill(.quaternary)
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
    }
}

struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
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
