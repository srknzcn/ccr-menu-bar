// CCRMenuBar/Services/ServerManager.swift
import Foundation
import Combine

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var ccrFound = true

    private var timer: Timer?
    private let pidPath: String
    private var port: Int { ConfigManager.shared.config?.PORT ?? 3456 }

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        pidPath = "\(home)/.claude-code-router/.claude-code-router.pid"
        checkCCRExists()
        checkStatus()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func checkCCRExists() {
        let result = shell("which ccr")
        ccrFound = result.exitCode == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func checkStatus() {
        // First try PID file
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidString) {
            isRunning = kill(pid, 0) == 0
            return
        }
        // Fallback: HTTP check
        let result = shell("curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 http://127.0.0.1:\(port)/")
        isRunning = result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) != "000"
    }

    func start() { runCCR("start") }
    func stop() { runCCR("stop") }
    func restart() { runCCR("restart") }

    private func runCCR(_ command: String) {
        errorMessage = nil
        DispatchQueue.global().async { [weak self] in
            let result = self?.shell("ccr \(command)")
            DispatchQueue.main.async {
                if let result = result, result.exitCode != 0 {
                    let msg = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.errorMessage = msg.isEmpty ? "Command failed (exit \(result.exitCode))" : msg
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.checkStatus()
                }
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.checkStatus()
            }
        }
    }

    /// Run a command through login shell to get full user PATH (nvm, homebrew, etc.)
    nonisolated private func shell(_ command: String) -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (output, process.terminationStatus)
        } catch {
            return (error.localizedDescription, -1)
        }
    }
}
