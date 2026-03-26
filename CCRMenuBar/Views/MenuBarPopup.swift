import SwiftUI

struct MenuBarPopup: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var serverManager: ServerManager
    @ObservedObject var tokenUsageService: TokenUsageService
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Server Status
            ServerStatusView(serverManager: serverManager)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            // Token Usage
            if tokenUsageService.allTimeStats.requestCount > 0 {
                HStack(spacing: 6) {
                    Text(tokenUsageService.todayStats.requestCount > 0 ? "TODAY'S USAGE" : "TOTAL USAGE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(1)
                    Rectangle()
                        .fill(.quaternary)
                        .frame(height: 0.5)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

                TokenUsageView(usageService: tokenUsageService)
                    .padding(.horizontal, 8)
                    .onAppear {
                        tokenUsageService.providers = configManager.config?.Providers ?? []
                        tokenUsageService.refresh()
                    }
            }

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

                Button {
                    configManager.loadConfig()
                    tokenUsageService.providers = configManager.config?.Providers ?? []
                    tokenUsageService.refresh()
                    serverManager.checkStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Spacer()

                // Save & Restart button
                SaveRestartButton(
                    isEnabled: configManager.hasUnsavedChanges,
                    action: {
                        configManager.saveAndRestart(serverManager: serverManager)
                    }
                )

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

struct SaveRestartButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var showDone = false

    var body: some View {
        Button {
            action()
            withAnimation(.easeInOut(duration: 0.2)) { showDone = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { showDone = false }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showDone ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 9, weight: .semibold))
                Text(showDone ? "Done" : "Save & Restart")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(showDone ? .green : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                showDone ? Color.green.opacity(0.2) :
                    (isEnabled ? (isHovered ? Color.blue.opacity(0.9) : Color.blue.opacity(0.75)) : Color.gray.opacity(0.2)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled && !showDone)
        .onHover { isHovered = $0 }
        .padding(.trailing, 6)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
        .animation(.easeInOut(duration: 0.2), value: showDone)
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
