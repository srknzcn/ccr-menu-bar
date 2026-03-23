import SwiftUI

struct ServerStatusView: View {
    @ObservedObject var serverManager: ServerManager
    @State private var pulseAnimation = false

    var body: some View {
        HStack(spacing: 12) {
            // Animated status indicator
            ZStack {
                if serverManager.isRunning {
                    Circle()
                        .fill(.green.opacity(0.25))
                        .frame(width: 28, height: 28)
                        .scaleEffect(pulseAnimation ? 1.4 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.5)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false), value: pulseAnimation)
                }
                Circle()
                    .fill(serverManager.isRunning ? .green : Color(.systemRed))
                    .frame(width: 10, height: 10)
                    .shadow(color: serverManager.isRunning ? .green.opacity(0.5) : .clear, radius: 4)
            }
            .frame(width: 28, height: 28)
            .onAppear { pulseAnimation = true }

            VStack(alignment: .leading, spacing: 1) {
                Text(serverManager.isRunning ? "Running" : "Stopped")
                    .font(.system(size: 13, weight: .semibold))
                Text("127.0.0.1:\(ConfigManager.shared.config?.PORT ?? 3456)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if !serverManager.ccrFound {
                Label("ccr not found", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 6) {
                    if serverManager.isRunning {
                        StatusButton(title: "Stop", icon: "stop.fill", color: .red) {
                            serverManager.stop()
                        }
                        StatusButton(title: "Restart", icon: "arrow.clockwise", color: .orange) {
                            serverManager.restart()
                        }
                    } else {
                        StatusButton(title: "Start", icon: "play.fill", color: .green) {
                            serverManager.start()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        }
        .overlay(alignment: .bottom) {
            if let error = serverManager.errorMessage {
                Text(error)
                    .font(.system(size: 9))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.red.opacity(0.1), in: Capsule())
                    .offset(y: 14)
            }
        }
    }
}

struct StatusButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(
                    isHovered ? color.opacity(0.18) : color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }
}
