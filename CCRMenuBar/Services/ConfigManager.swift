// CCRMenuBar/Services/ConfigManager.swift
import Foundation
import Combine

@MainActor
class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published var config: CCRConfig?
    @Published var errorMessage: String?

    private let configURL: URL
    private let writeQueue = DispatchQueue(label: "com.ccr.menubar.configwrite")
    private nonisolated(unsafe) var fileDescriptor: Int32 = -1
    private nonisolated(unsafe) var dispatchSource: DispatchSourceFileSystemObject?
    private var debounceTimer: Timer?
    private var isWriting = false

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configURL = home.appendingPathComponent(".claude-code-router/config.json")
        loadConfig()
        startWatching()
    }

    deinit {
        dispatchSource?.cancel()
        dispatchSource = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    func loadConfig() {
        do {
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            config = try decoder.decode(CCRConfig.self, from: data)
            errorMessage = nil
        } catch {
            config = nil
            errorMessage = "Failed to load config: \(error.localizedDescription)"
        }
    }

    func save() {
        guard let config = config else { return }
        isWriting = true
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(config)
                let tempURL = self.configURL.deletingLastPathComponent()
                    .appendingPathComponent(".config.json.tmp")
                try data.write(to: tempURL, options: .atomic)
                _ = try FileManager.default.replaceItemAt(self.configURL, withItemAt: tempURL)
                DispatchQueue.main.async {
                    self.isWriting = false
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWriting = false
                    self.errorMessage = "Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }

    func availableModels() -> [(provider: String, model: String)] {
        guard let config = config else { return [] }
        return config.Providers.flatMap { provider in
            provider.models.map { (provider: provider.name, model: $0) }
        }
    }

    func setRoute(_ route: RouterRoute, provider: String, model: String) {
        guard config != nil else { return }
        route.setValue("\(provider),\(model)", on: &config!.Router)
        save()
    }

    // MARK: - File Watching

    private func startWatching() {
        stopWatching()
        fileDescriptor = open(configURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )

        dispatchSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.debounceReload()
            if self.dispatchSource?.data.contains(.rename) == true {
                self.startWatching()
            }
        }

        dispatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        dispatchSource?.resume()
    }

    private func debounceReload() {
        debounceTimer?.invalidate()
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                guard !self.isWriting else { return }
                self.loadConfig()
            }
        }
    }

    private func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }
}
