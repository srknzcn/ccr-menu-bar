// CCRMenuBar/Services/ServerManager.swift
import Foundation
import Combine
import AppKit

@MainActor
class ServerManager: ObservableObject {
    @Published var isRunning = false
    @Published var errorMessage: String?
    @Published var ccrFound = true
    @Published var claudeFound = true
    @Published var isInstallingCCR = false

    private var timer: Timer?
    private let pidPath: String
    private var port: Int { ConfigManager.shared.config?.PORT ?? 3456 }
    private static let claudeCodeInstallURL = URL(string: "https://code.claude.com/docs/en/quickstart")!

    /// Resolved full path to ccr binary, found once at init
    private var ccrPath: String?
    private var claudePath: String?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        pidPath = "\(home)/.claude-code-router/.claude-code-router.pid"
        resolveCCRPath()
        resolveClaudePath()
        checkStatus()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    /// Find ccr binary path by sourcing user's shell profile
    private func resolveCCRPath() {
        if let path = resolveBinaryPath(
            name: "ccr",
            commonPaths: [
                "/usr/local/bin/ccr",
                "/opt/homebrew/bin/ccr",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.bun/bin/ccr",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/ccr",
            ]
        ) {
            ccrPath = path
            ccrFound = true
            return
        }

        ccrPath = nil
        ccrFound = false
    }

    private func resolveClaudePath() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let path = resolveBinaryPath(
            name: "claude",
            commonPaths: [
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "\(home)/.claude/local/claude",
                "\(home)/.bun/bin/claude",
                "\(home)/.local/bin/claude",
            ]
        ) {
            claudePath = path
            claudeFound = true
            return
        }

        claudePath = nil
        claudeFound = false
    }

    private func resolveBinaryPath(name: String, commonPaths: [String]) -> String? {
        // Try common nvm/node paths first (fast, no shell spawn)
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Check nvm directory for npm-installed binaries.
        let nvmBase = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            let sorted = versions.sorted().reversed() // newest first
            for version in sorted {
                let path = "\(nvmBase)/\(version)/bin/\(name)"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }

        // Check other common paths
        for path in commonPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Last resort: interactive login shell
        let result = shell("command -v \(name)")
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.exitCode == 0 && !path.isEmpty && FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    func openClaudeCodeInstallGuide() {
        NSWorkspace.shared.open(Self.claudeCodeInstallURL)
    }

    func checkStatus() {
        // First try PID file
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidString) {
            isRunning = kill(pid, 0) == 0
            return
        }
        // Fallback: HTTP check
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "2", "http://127.0.0.1:\(port)/"]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            isRunning = process.terminationStatus == 0 && output != "000"
        } catch {
            isRunning = false
        }
    }

    func start() { runCCR("start") }
    func stop() { runCCR("stop") }
    func restart() { runCCR("restart") }

    func installCCRAndStart() {
        guard !isInstallingCCR else { return }
        isInstallingCCR = true
        errorMessage = "Installing CCR..."

        DispatchQueue.global().async { [weak self] in
            let installResult: (output: String, exitCode: Int32) = self?.shell("npm install -g @musistudio/claude-code-router")
                ?? (output: "Install failed", exitCode: -1)

            DispatchQueue.main.async {
                guard let self = self else { return }

                if installResult.exitCode != 0 {
                    self.isInstallingCCR = false
                    let msg = installResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.errorMessage = msg.isEmpty ? "CCR install failed (exit \(installResult.exitCode))" : msg
                    self.resolveCCRPath()
                    return
                }

                self.resolveCCRPath()
                guard self.ccrFound else {
                    self.isInstallingCCR = false
                    self.errorMessage = "CCR installed, but ccr binary not found in PATH"
                    return
                }

                self.errorMessage = nil
                self.runCCR("start") {
                    self.isInstallingCCR = false
                }
            }
        }
    }

    private func runCCR(_ command: String, completion: (() -> Void)? = nil) {
        guard let ccr = ccrPath else {
            errorMessage = "ccr not found"
            completion?()
            return
        }
        errorMessage = nil
        let ccrCopy = ccr
        DispatchQueue.global().async { [weak self] in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: ccrCopy)
            process.arguments = [command]
            process.standardOutput = pipe
            process.standardError = pipe

            // Pass minimal env needed for node
            var env: [String: String] = [:]
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = (URL(fileURLWithPath: ccrCopy).deletingLastPathComponent().path) + ":/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
            env["USER"] = NSUserName()
            process.environment = env

            var output = ""
            var exitCode: Int32 = -1
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                output = String(data: data, encoding: .utf8) ?? ""
                exitCode = process.terminationStatus
            } catch {
                output = error.localizedDescription
                exitCode = -1
            }

            DispatchQueue.main.async {
                if exitCode != 0 {
                    let msg = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.errorMessage = msg.isEmpty ? "Command failed (exit \(exitCode))" : msg
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.checkStatus()
                    completion?()
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

    /// Run command through interactive login shell (fallback for PATH resolution)
    nonisolated private func shell(_ command: String) -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-i", "-l", "-c", command]
        process.standardOutput = pipe
        process.standardError = pipe
        // Ensure HOME is set
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "USER": NSUserName()
        ]

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            // Strip terminal escape sequences from interactive shell
            let clean = output.replacingOccurrences(of: "\\]\\d+;[^\\\\]*\\\\", with: "", options: .regularExpression)
            return (clean, process.terminationStatus)
        } catch {
            return (error.localizedDescription, -1)
        }
    }
}
