import SwiftUI

struct ServerStatusView: View {
    @ObservedObject var serverManager: ServerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(serverManager.isRunning ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(serverManager.isRunning ? "Running" : "Stopped")
                    .font(.headline)
                    .foregroundStyle(serverManager.isRunning ? .primary : .secondary)
            }

            if !serverManager.ccrFound {
                Text("ccr not found in PATH")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 8) {
                    if serverManager.isRunning {
                        Button("Stop") { serverManager.stop() }
                        Button("Restart") { serverManager.restart() }
                    } else {
                        Button("Start") { serverManager.start() }
                    }
                }
            }

            if let error = serverManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
