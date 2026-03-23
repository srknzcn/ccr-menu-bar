# CCR Menu Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS SwiftUI menu bar app for managing Claude Code Router — model selection, server control, and config editing.

**Architecture:** Single-process SwiftUI app using `MenuBarExtra` for the popup and a separate `Window` for settings. Two service objects (`ConfigManager`, `ServerManager`) handle all I/O. Config is read/written as JSON via `Codable` with `AnyCodable` for opaque fields.

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 14+ (Sonoma), Xcode project (Swift Package Manager for dependencies if needed)

**Spec:** `docs/superpowers/specs/2026-03-24-ccr-menu-bar-design.md`

---

## File Structure

```
CCRMenuBar/
├── CCRMenuBarApp.swift              # App entry point, MenuBarExtra + Settings Window scenes
├── Models/
│   ├── CCRConfig.swift              # All Codable structs (CCRConfig, Provider, RouterConfig)
│   ├── AnyCodable.swift             # Type-erased JSON wrapper for round-tripping unknown fields
│   └── RouterRoute.swift            # Enum for route types (default, think, background, etc.)
├── Services/
│   ├── ConfigManager.swift          # Read/write/watch config.json, serial queue for writes
│   └── ServerManager.swift          # CCR server start/stop/restart/status via Process
├── Views/
│   ├── MenuBarPopup.swift           # Main popup view combining all sections
│   ├── ServerStatusView.swift       # Server status indicator + control buttons
│   ├── RouterSection.swift          # Route list with model picker submenus
│   ├── SettingsView.swift           # Settings window with tab view
│   ├── ProvidersTab.swift           # Provider list + detail editor
│   └── GeneralTab.swift             # General config fields
└── Resources/
    └── Assets.xcassets/             # App icon assets
```

---

## Task 1: Xcode Project Setup

**Files:**
- Create: `CCRMenuBar/CCRMenuBarApp.swift`
- Create: `CCRMenuBar/Resources/Assets.xcassets`
- Create: `Package.swift`

- [ ] **Step 1: Create the Xcode project structure**

```bash
cd /Users/serkan/Desktop/ccr-menu-bar
mkdir -p CCRMenuBar/Models CCRMenuBar/Services CCRMenuBar/Views CCRMenuBar/Resources/Assets.xcassets
```

- [ ] **Step 2: Create the Swift Package structure**

Since we want to avoid Xcode GUI dependency, use a `Package.swift` for building:

```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CCRMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CCRMenuBar",
            path: "CCRMenuBar",
            resources: [.process("Resources")]
        )
    ]
)
```

- [ ] **Step 3: Create minimal app entry point**

```swift
// CCRMenuBar/CCRMenuBarApp.swift
import SwiftUI

@main
struct CCRMenuBarApp: App {
    var body: some Scene {
        MenuBarExtra("CCR", systemImage: "arrow.triangle.branch") {
            Text("CCR Menu Bar")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
cd /Users/serkan/Desktop/ccr-menu-bar
swift build
```

Expected: Builds successfully, no errors.

- [ ] **Step 5: Run and verify menu bar icon appears**

```bash
swift run &
```

Expected: A branch icon appears in the macOS menu bar. Clicking shows "CCR Menu Bar" text and Quit button.

- [ ] **Step 6: Commit**

```bash
git init
git add Package.swift CCRMenuBar/
git commit -m "feat: initial project setup with minimal menu bar app"
```

---

## Task 2: Data Models (AnyCodable, CCRConfig, RouterRoute)

**Files:**
- Create: `CCRMenuBar/Models/AnyCodable.swift`
- Create: `CCRMenuBar/Models/CCRConfig.swift`
- Create: `CCRMenuBar/Models/RouterRoute.swift`

- [ ] **Step 1: Create AnyCodable**

```swift
// CCRMenuBar/Models/AnyCodable.swift
import Foundation

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported type"))
        }
    }
}
```

- [ ] **Step 2: Create CCRConfig models**

```swift
// CCRMenuBar/Models/CCRConfig.swift
import Foundation

struct CCRConfig: Codable {
    var LOG: Bool?
    var LOG_LEVEL: String?
    var CLAUDE_PATH: String?
    var HOST: String?
    var PORT: Int?
    var APIKEY: String?
    var API_TIMEOUT_MS: String?
    var PROXY_URL: String?
    var transformers: AnyCodable?
    var Providers: [Provider]
    var Router: RouterConfig
    var StatusLine: AnyCodable?
    var CUSTOM_ROUTER_PATH: String?
    var NON_INTERACTIVE_MODE: Bool?
}

struct Provider: Codable, Identifiable, Hashable {
    var name: String
    var api_base_url: String
    var api_key: String
    var models: [String]
    var transformer: AnyCodable?
    var id: String { name }

    static func == (lhs: Provider, rhs: Provider) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct RouterConfig: Codable {
    var `default`: String?
    var background: String?
    var think: String?
    var longContext: String?
    var longContextThreshold: Int?
    var webSearch: String?
    var image: String?
}
```

- [ ] **Step 3: Create RouterRoute enum**

```swift
// CCRMenuBar/Models/RouterRoute.swift
import Foundation

enum RouterRoute: String, CaseIterable, Identifiable {
    case `default` = "default"
    case think = "think"
    case background = "background"
    case longContext = "longContext"
    case webSearch = "webSearch"
    case image = "image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .think: return "Think"
        case .background: return "Background"
        case .longContext: return "Long Context"
        case .webSearch: return "Web Search"
        case .image: return "Image"
        }
    }

    func getValue(from router: RouterConfig) -> String? {
        switch self {
        case .default: return router.default
        case .think: return router.think
        case .background: return router.background
        case .longContext: return router.longContext
        case .webSearch: return router.webSearch
        case .image: return router.image
        }
    }

    func setValue(_ value: String, on router: inout RouterConfig) {
        switch self {
        case .default: router.default = value
        case .think: router.think = value
        case .background: router.background = value
        case .longContext: router.longContext = value
        case .webSearch: router.webSearch = value
        case .image: router.image = value
        }
    }
}
```

- [ ] **Step 4: Build and verify models compile**

```bash
swift build
```

Expected: Builds successfully.

- [ ] **Step 5: Commit**

```bash
git add CCRMenuBar/Models/
git commit -m "feat: add data models (AnyCodable, CCRConfig, RouterRoute)"
```

---

## Task 3: ConfigManager Service

**Files:**
- Create: `CCRMenuBar/Services/ConfigManager.swift`

- [ ] **Step 1: Implement ConfigManager**

```swift
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
    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var debounceTimer: Timer?
    private var isWriting = false

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configURL = home.appendingPathComponent(".claude-code-router/config.json")
        loadConfig()
        startWatching()
    }

    deinit {
        stopWatching()
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
                try FileManager.default.moveItem(at: tempURL, to: self.configURL)
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
            queue: .main   // Use main queue to avoid @MainActor isolation issues
        )

        dispatchSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            // On rename, the file descriptor is stale — re-establish the watcher
            self.debounceReload()
            if self.dispatchSource?.data.contains(.rename) == true {
                self.startWatching()  // Re-open descriptor for new inode
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
            guard let self = self, !self.isWriting else { return }
            self.loadConfig()
        }
    }

    private func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build
```

Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add CCRMenuBar/Services/ConfigManager.swift
git commit -m "feat: add ConfigManager with file watching and atomic writes"
```

---

## Task 4: ServerManager Service

**Files:**
- Create: `CCRMenuBar/Services/ServerManager.swift`

- [ ] **Step 1: Implement ServerManager**

```swift
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
        // First try PID file
        if let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           let pid = Int32(pidString) {
            isRunning = kill(pid, 0) == 0
            return
        }
        // Fallback: try HTTP connection
        let result = runShell("/usr/bin/curl", arguments: [
            "-s", "-o", "/dev/null", "-w", "%{http_code}",
            "--connect-timeout", "2",
            "http://127.0.0.1:\(port)/"
        ])
        isRunning = result.exitCode == 0 && result.output.trimmingCharacters(in: .whitespacesAndNewlines) != "000"
    }

    func start() {
        runCCR("start")
    }

    func stop() {
        runCCR("stop")
    }

    func restart() {
        runCCR("restart")
    }

    private func runCCR(_ command: String) {
        errorMessage = nil
        DispatchQueue.global().async { [weak self] in
            let result = self?.runShell("/usr/bin/env", arguments: ["ccr", command])
            DispatchQueue.main.async {
                if let result = result, result.exitCode != 0 {
                    self?.errorMessage = result.output.isEmpty ? "Command failed (exit \(result.exitCode))" : result.output
                }
                // Give server a moment to start/stop, then check
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self?.checkStatus()
                }
            }
        }
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkStatus()
        }
    }

    private func runShell(_ command: String, arguments: [String] = []) -> (output: String, exitCode: Int32) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe

        // Inherit user's PATH for finding ccr
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
        }
        process.environment = env

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
```

- [ ] **Step 2: Build and verify**

```bash
swift build
```

Expected: Builds successfully.

- [ ] **Step 3: Commit**

```bash
git add CCRMenuBar/Services/ServerManager.swift
git commit -m "feat: add ServerManager with PID-based status checking"
```

---

## Task 5: Menu Bar Popup Views

**Files:**
- Create: `CCRMenuBar/Views/ServerStatusView.swift`
- Create: `CCRMenuBar/Views/RouterSection.swift`
- Create: `CCRMenuBar/Views/MenuBarPopup.swift`
- Modify: `CCRMenuBar/CCRMenuBarApp.swift`

- [ ] **Step 1: Create ServerStatusView**

```swift
// CCRMenuBar/Views/ServerStatusView.swift
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
```

- [ ] **Step 2: Create RouterSection**

```swift
// CCRMenuBar/Views/RouterSection.swift
import SwiftUI

struct RouterSection: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        if let config = configManager.config {
            ForEach(RouterRoute.allCases) { route in
                let currentValue = route.getValue(from: config.Router) ?? ""
                let modelName = parseModelName(currentValue)

                Menu {
                    let models = configManager.availableModels()
                    ForEach(Array(models.enumerated()), id: \.offset) { _, item in
                        let value = "\(item.provider),\(item.model)"
                        Button {
                            configManager.setRoute(route, provider: item.provider, model: item.model)
                        } label: {
                            HStack {
                                Text("\(item.provider) / \(item.model)")
                                if currentValue == value {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(route.displayName)
                            .frame(width: 90, alignment: .leading)
                        Text(modelName)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }
            }
        } else {
            Text("Config not loaded")
                .foregroundStyle(.secondary)
        }
    }

    private func parseModelName(_ value: String) -> String {
        guard !value.isEmpty else { return "—" }
        let parts = value.split(separator: ",", maxSplits: 1)
        return parts.count > 1 ? String(parts[1]) : value
    }
}
```

- [ ] **Step 3: Create MenuBarPopup**

```swift
// CCRMenuBar/Views/MenuBarPopup.swift
import SwiftUI

struct MenuBarPopup: View {
    @ObservedObject var configManager: ConfigManager
    @ObservedObject var serverManager: ServerManager
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ServerStatusView(serverManager: serverManager)

            Divider()
                .padding(.vertical, 4)

            if let error = configManager.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            RouterSection(configManager: configManager)
                .padding(.horizontal, 4)

            Divider()
                .padding(.vertical, 4)

            HStack {
                Button("Settings...") {
                    openSettings()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .frame(width: 320)
    }
}
```

- [ ] **Step 4: Update CCRMenuBarApp to use popup**

```swift
// CCRMenuBar/CCRMenuBarApp.swift
import SwiftUI

@main
struct CCRMenuBarApp: App {
    @StateObject private var configManager = ConfigManager.shared
    @StateObject private var serverManager = ServerManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("CCR", systemImage: "arrow.triangle.branch") {
            MenuBarPopup(
                configManager: configManager,
                serverManager: serverManager,
                openSettings: { openWindow(id: "settings") }
            )
        }
        .menuBarExtraStyle(.window)

        Window("CCR Settings", id: "settings") {
            Text("Settings — coming next")
                .frame(width: 500, height: 400)
        }
        .defaultSize(width: 500, height: 400)
    }
}
```

- [ ] **Step 5: Build and verify**

```bash
swift build
```

Expected: Builds successfully.

- [ ] **Step 6: Run and test popup**

```bash
swift run &
```

Expected: Menu bar icon shows. Clicking reveals server status, router assignments from config.json, and Settings/Quit buttons. Changing a route updates config.json.

- [ ] **Step 7: Commit**

```bash
git add CCRMenuBar/Views/ CCRMenuBar/CCRMenuBarApp.swift
git commit -m "feat: add menu bar popup with server status and router selection"
```

---

## Task 6: Settings Window — General Tab

**Files:**
- Create: `CCRMenuBar/Views/GeneralTab.swift`

- [ ] **Step 1: Create GeneralTab**

```swift
// CCRMenuBar/Views/GeneralTab.swift
import SwiftUI

struct GeneralTab: View {
    @ObservedObject var configManager: ConfigManager
    @State private var showAPIKey = false

    var body: some View {
        Form {
            if configManager.config != nil {
                Section("Server") {
                    TextField("Host", text: binding(\.HOST, default: "127.0.0.1"))
                    TextField("Port", value: Binding(
                        get: { configManager.config?.PORT ?? 3456 },
                        set: { configManager.config?.PORT = $0 }
                    ), format: .number)
                    TextField("API Timeout (ms)", text: binding(\.API_TIMEOUT_MS, default: ""))
                    TextField("Proxy URL", text: binding(\.PROXY_URL, default: ""))
                }

                Section("Paths") {
                    TextField("Claude Path", text: binding(\.CLAUDE_PATH, default: ""))
                }

                Section("Security") {
                    HStack {
                        if showAPIKey {
                            TextField("API Key", text: binding(\.APIKEY, default: ""))
                        } else {
                            SecureField("API Key", text: binding(\.APIKEY, default: ""))
                        }
                        Button(showAPIKey ? "Hide" : "Show") {
                            showAPIKey.toggle()
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Section("Logging") {
                    Toggle("Enable Logging", isOn: Binding(
                        get: { configManager.config?.LOG ?? false },
                        set: { configManager.config?.LOG = $0 }
                    ))
                    TextField("Log Level", text: binding(\.LOG_LEVEL, default: "info"))
                }

                Section("Router") {
                    TextField("Long Context Threshold", value: Binding(
                        get: { configManager.config?.Router.longContextThreshold ?? 60000 },
                        set: { configManager.config?.Router.longContextThreshold = $0 }
                    ), format: .number)
                }

                HStack {
                    Spacer()
                    Button("Save") {
                        configManager.save()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Config not loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding(_ keyPath: WritableKeyPath<CCRConfig, String?>, default defaultValue: String) -> Binding<String> {
        Binding(
            get: { configManager.config?[keyPath: keyPath] ?? defaultValue },
            set: { configManager.config?[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build
```

- [ ] **Step 3: Commit**

```bash
git add CCRMenuBar/Views/GeneralTab.swift
git commit -m "feat: add General settings tab"
```

---

## Task 7: Settings Window — Providers Tab

**Files:**
- Create: `CCRMenuBar/Views/ProvidersTab.swift`

- [ ] **Step 1: Create ProvidersTab**

```swift
// CCRMenuBar/Views/ProvidersTab.swift
import SwiftUI

struct ProvidersTab: View {
    @ObservedObject var configManager: ConfigManager
    @State private var selectedProvider: String?
    @State private var newModelName = ""
    @State private var showAPIKey = false

    var body: some View {
        HSplitView {
            // Provider list
            VStack {
                List(selection: $selectedProvider) {
                    ForEach(configManager.config?.Providers ?? []) { provider in
                        HStack {
                            Text(provider.name)
                            Spacer()
                            Text("\(provider.models.count) models")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .tag(provider.name)
                    }
                }

                HStack {
                    Button("+") { addProvider() }
                    Button("-") { removeSelectedProvider() }
                        .disabled(selectedProvider == nil)
                    Spacer()
                }
                .padding(8)
            }
            .frame(minWidth: 180)

            // Provider detail
            if let providerName = selectedProvider,
               let index = configManager.config?.Providers.firstIndex(where: { $0.name == providerName }) {
                providerDetail(index: index)
            } else {
                Text("Select a provider")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func providerDetail(index: Int) -> some View {
        Form {
            Section("Provider") {
                TextField("Name", text: Binding(
                    get: { configManager.config?.Providers[index].name ?? "" },
                    set: { configManager.config?.Providers[index].name = $0 }
                ))
                TextField("API Base URL", text: Binding(
                    get: { configManager.config?.Providers[index].api_base_url ?? "" },
                    set: { configManager.config?.Providers[index].api_base_url = $0 }
                ))
                HStack {
                    if showAPIKey {
                        TextField("API Key", text: Binding(
                            get: { configManager.config?.Providers[index].api_key ?? "" },
                            set: { configManager.config?.Providers[index].api_key = $0 }
                        ))
                    } else {
                        SecureField("API Key", text: Binding(
                            get: { configManager.config?.Providers[index].api_key ?? "" },
                            set: { configManager.config?.Providers[index].api_key = $0 }
                        ))
                    }
                    Button(showAPIKey ? "Hide" : "Show") {
                        showAPIKey.toggle()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section("Models") {
                ForEach(configManager.config?.Providers[index].models ?? [], id: \.self) { model in
                    HStack {
                        Text(model)
                        Spacer()
                        Button(role: .destructive) {
                            configManager.config?.Providers[index].models.removeAll { $0 == model }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    TextField("New model", text: $newModelName)
                        .onSubmit { addModel(at: index) }
                    Button("Add") { addModel(at: index) }
                        .disabled(newModelName.isEmpty)
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    configManager.save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
    }

    private func addModel(at index: Int) {
        guard !newModelName.isEmpty else { return }
        configManager.config?.Providers[index].models.append(newModelName)
        newModelName = ""
    }

    private func addProvider() {
        let newProvider = Provider(
            name: "new-provider",
            api_base_url: "",
            api_key: "",
            models: []
        )
        configManager.config?.Providers.append(newProvider)
        selectedProvider = newProvider.name
    }

    private func removeSelectedProvider() {
        guard let name = selectedProvider else { return }
        configManager.config?.Providers.removeAll { $0.name == name }
        selectedProvider = nil
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
swift build
```

- [ ] **Step 3: Commit**

```bash
git add CCRMenuBar/Views/ProvidersTab.swift
git commit -m "feat: add Providers settings tab"
```

---

## Task 8: Settings Window Assembly

**Files:**
- Create: `CCRMenuBar/Views/SettingsView.swift`
- Modify: `CCRMenuBar/CCRMenuBarApp.swift`

- [ ] **Step 1: Create SettingsView**

```swift
// CCRMenuBar/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @ObservedObject var configManager: ConfigManager

    var body: some View {
        TabView {
            ProvidersTab(configManager: configManager)
                .tabItem {
                    Label("Providers", systemImage: "server.rack")
                }

            GeneralTab(configManager: configManager)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(minWidth: 550, minHeight: 450)
    }
}
```

- [ ] **Step 2: Update CCRMenuBarApp to use SettingsView**

Replace the placeholder `Window` scene in `CCRMenuBarApp.swift`:

```swift
Window("CCR Settings", id: "settings") {
    SettingsView(configManager: configManager)
}
.defaultSize(width: 600, height: 500)
```

- [ ] **Step 3: Build and run full app**

```bash
swift build && swift run &
```

Expected: Full app works — menu bar popup with server status + router selection. Settings window opens with Providers and General tabs.

- [ ] **Step 4: Commit**

```bash
git add CCRMenuBar/Views/SettingsView.swift CCRMenuBar/CCRMenuBarApp.swift
git commit -m "feat: assemble settings window with Providers and General tabs"
```

---

## Task 9: Build macOS App Bundle

**Files:**
- Create: Build script or Makefile for producing .app bundle

- [ ] **Step 1: Create build script**

```bash
#!/bin/bash
# build-app.sh — Builds CCRMenuBar.app bundle
set -e

APP_NAME="CCR Menu Bar"
BUNDLE_ID="com.ccr.menubar"
BUILD_DIR=".build/release"

# Build release
swift build -c release

# Create .app bundle
APP_DIR="${APP_NAME}.app/Contents"
mkdir -p "${APP_DIR}/MacOS"
mkdir -p "${APP_DIR}/Resources"

# Copy binary
cp "${BUILD_DIR}/CCRMenuBar" "${APP_DIR}/MacOS/CCRMenuBar"

# Create Info.plist
cat > "${APP_DIR}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CCRMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>com.ccr.menubar</string>
    <key>CFBundleName</key>
    <string>CCR Menu Bar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
PLIST

echo "Built: ${APP_NAME}.app"
echo "To install: cp -r '${APP_NAME}.app' /Applications/"
```

- [ ] **Step 2: Build and verify .app bundle**

```bash
chmod +x build-app.sh
./build-app.sh
```

Expected: `CCR Menu Bar.app` is created in the project root.

- [ ] **Step 3: Test the .app bundle**

```bash
open "CCR Menu Bar.app"
```

Expected: App launches, menu bar icon appears, full functionality works.

- [ ] **Step 4: Commit**

```bash
git add build-app.sh
git commit -m "feat: add build script for macOS .app bundle"
```
