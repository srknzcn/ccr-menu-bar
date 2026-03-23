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
        let result = runShell("/usr/bin/which", arguments: ["ccr"])
        ccrFound = result.exitCode == 0
    }

    func checkStatus() {
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidString) {
            isRunning = kill(pid, 0) == 0
            return
        }
        let result = runShell("/usr/bin/curl", arguments: [
            "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--connect-timeout", "2",
            "http://127.0.0.1:\(port)/"
        ])
        isRunning = result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) != "000"
    }

    func start() { runCCR("start") }
    func stop() { runCCR("stop") }
    func restart() { runCCR("restart") }

    private func runCCR(_ command: String) {
        errorMessage = nil
        DispatchQueue.global().async { [weak self] in
            let result = self?.runShell("/usr/bin/env", arguments: ["ccr", command])
            DispatchQueue.main.async {
                if let result = result, result.exitCode != 0 {
                    self?.errorMessage = result.output.isEmpty ? "Command failed (exit \(result.exitCode))" : result.output
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

    nonisolated private func runShell(_ command: String, arguments: [String] = []) -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()

        // Run through login shell to get full PATH (nvm, homebrew, etc.)
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let fullCommand = ([command] + arguments)
            .map { $0.contains(" ") ? "'\($0)'" : $0 }
            .joined(separator: " ")
        process.arguments = ["-l", "-c", fullCommand]
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
