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
                        .fill(.green.opacity(0.3))
                        .frame(width: 24, height: 24)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: pulseAnimation)
                }
                Circle()
                    .fill(serverManager.isRunning ? .green : Color(.systemRed))
                    .frame(width: 10, height: 10)
            }
            .frame(width: 24, height: 24)
            .onAppear { pulseAnimation = true }

            VStack(alignment: .leading, spacing: 2) {
                Text("CCR Server")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(serverManager.isRunning ? "Running" : "Stopped")
                    .font(.system(size: 13, weight: .semibold))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if let error = serverManager.errorMessage {
                VStack {
                    Spacer()
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.red.opacity(0.1), in: Capsule())
                }
                .padding(.bottom, -16)
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
                .frame(width: 26, height: 26)
                .background(
                    isHovered ? color.opacity(0.15) : color.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(title)
    }
}
