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
    @Published var presetNameMap: [String: String] = [:]  // display name → filesystem name

    private let presetsURL: URL
    private let ccrPresetsDir: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        presetsURL = home.appendingPathComponent(".claude-code-router/router-presets.json")
        ccrPresetsDir = home.appendingPathComponent(".claude-code-router/presets")
        loadPresets()
    }

    func loadPresets() {
        guard FileManager.default.fileExists(atPath: presetsURL.path) else {
            presets = []
            presetNameMap = [:]
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
        // Build baseline nameMap using sanitized names so switch API works
        // even before syncToCCRPresets is called
        if presetNameMap.isEmpty {
            var baseMap: [String: String] = [:]
            var usedNames = Set<String>()
            for preset in presets {
                var safeName = sanitizePresetName(preset.name)
                var candidate = safeName
                var counter = 2
                while usedNames.contains(candidate) {
                    candidate = "\(safeName)-\(counter)"
                    counter += 1
                }
                safeName = candidate
                usedNames.insert(safeName)
                baseMap[preset.name] = safeName
            }
            presetNameMap = baseMap
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

    // MARK: - CCR Directory Preset Export

    func sanitizePresetName(_ name: String) -> String {
        let lowered = name.lowercased()
        let cleaned = lowered.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : Character("-") }
        let result = String(cleaned)
            .components(separatedBy: "-").filter { !$0.isEmpty }.joined(separator: "-")
        return result.isEmpty ? "preset" : result
    }

    func syncToCCRPresets(providers: [Provider]) {
        let fm = FileManager.default

        // Ensure presets directory exists
        if !fm.fileExists(atPath: ccrPresetsDir.path) {
            try? fm.createDirectory(at: ccrPresetsDir, withIntermediateDirectories: true)
        }

        // Build current name map
        var newMap: [String: String] = [:]
        var usedNames = Set<String>()
        for preset in presets {
            var safeName = sanitizePresetName(preset.name)
            // Deduplicate
            var candidate = safeName
            var counter = 2
            while usedNames.contains(candidate) {
                candidate = "\(safeName)-\(counter)"
                counter += 1
            }
            safeName = candidate
            usedNames.insert(safeName)
            newMap[preset.name] = safeName
        }
        presetNameMap = newMap

        // Write each preset as manifest.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        for preset in presets {
            guard let safeName = newMap[preset.name] else { continue }
            let presetDir = ccrPresetsDir.appendingPathComponent(safeName)
            try? fm.createDirectory(at: presetDir, withIntermediateDirectories: true)

            let manifest = CCRPresetManifest.from(
                name: safeName,
                displayName: preset.name,
                providers: providersForCCRManifest(providers),
                router: preset.router
            )
            if let data = try? encoder.encode(manifest) {
                try? data.write(to: presetDir.appendingPathComponent("manifest.json"), options: .atomic)
            }
        }

        // Remove stale CCR preset directories
        let validNames = Set(newMap.values)
        if let contents = try? fm.contentsOfDirectory(atPath: ccrPresetsDir.path) {
            for dir in contents {
                if !validNames.contains(dir) {
                    try? fm.removeItem(at: ccrPresetsDir.appendingPathComponent(dir))
                }
            }
        }
    }

    func fileSystemName(for displayName: String) -> String? {
        presetNameMap[displayName]
    }

    func displayName(for fileSystemName: String) -> String? {
        presetNameMap.first(where: { $0.value == fileSystemName })?.key
    }

    private func providersForCCRManifest(_ providers: [Provider]) -> [Provider] {
        providers.map { provider in
            var normalized = provider
            if provider.name.lowercased() == "openai" {
                normalized.transformer = TransformerConfig(use: ["Anthropic"])
            }
            return normalized
        }
    }
}
