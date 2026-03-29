// CCRMenuBar/Services/PresetManager.swift
import Foundation
import Combine

struct RouterPreset: Codable, Identifiable {
    var name: String
    var router: RouterConfig

    var id: String { name }
}

@MainActor
class PresetManager: ObservableObject {
    @MainActor static let shared = PresetManager()

    @Published var presets: [RouterPreset] = []
    @Published var selectedPresetName: String?

    private let presetsURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        presetsURL = home.appendingPathComponent(".claude-code-router/router-presets.json")
        loadPresets()
    }

    func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsURL.path) else {
            presets = []
            return
        }
        do {
            let data = try Data(contentsOf: presetsURL)
            let dict = try JSONDecoder().decode([String: RouterConfig].self, from: data)
            presets = dict.map { RouterPreset(name: $0.key, router: $0.value) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            presets = []
        }
    }

    func savePreset(name: String, router: RouterConfig) {
        if let idx = presets.firstIndex(where: { $0.name == name }) {
            presets[idx].router = router
        } else {
            presets.append(RouterPreset(name: name, router: router))
            presets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        selectedPresetName = name
        persist()
    }

    func deletePreset(name: String) {
        presets.removeAll { $0.name == name }
        if selectedPresetName == name {
            selectedPresetName = nil
        }
        persist()
    }

    func matchCurrentConfig(_ router: RouterConfig) {
        if let match = presets.first(where: { routerConfigsEqual($0.router, router) }) {
            selectedPresetName = match.name
        } else {
            selectedPresetName = nil
        }
    }

    private func routerConfigsEqual(_ a: RouterConfig, _ b: RouterConfig) -> Bool {
        a.default == b.default &&
        a.background == b.background &&
        a.think == b.think &&
        a.longContext == b.longContext &&
        a.longContextThreshold == b.longContextThreshold &&
        a.webSearch == b.webSearch &&
        a.image == b.image
    }

    private func persist() {
        var dict: [String: RouterConfig] = [:]
        for preset in presets {
            dict[preset.name] = preset.router
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(dict)
            try data.write(to: presetsURL, options: .atomic)
        } catch {
            // Silent fail — non-critical
        }
    }
}
