# CCR Menu Bar — Design Spec

## Overview

A native macOS SwiftUI menu bar application for managing Claude Code Router (CCR). Provides quick access to router model assignments, server control, and full configuration editing.

## Target

- macOS 14+ (Sonoma)
- SwiftUI with `MenuBarExtra`
- Reads/writes `~/.claude-code-router/config.json` directly

## Architecture

```
┌─────────────────────────────────┐
│         Menu Bar Icon           │
│      (SF Symbol: arrow.triangle.branch) │
└──────────┬──────────────────────┘
           │ click
           ▼
┌─────────────────────────────────┐
│        Popup View               │
│  ┌───────────────────────────┐  │
│  │ Server Status             │  │
│  │ ● Running  [Stop][Restart]│  │
│  └───────────────────────────┘  │
│  ┌───────────────────────────┐  │
│  │ Router Assignments        │  │
│  │ default  → glm-5-turbo  ▸│  │
│  │ think    → claude-opus  ▸│  │
│  │ background → mimo-v2    ▸│  │
│  │ longCtx  → claude-opus  ▸│  │
│  │ webSearch → mimo-v2     ▸│  │
│  └───────────────────────────┘  │
│  ─────────────────────────────  │
│  [⚙ Settings...]     [Quit]    │
└─────────────────────────────────┘
```

## Data Model

### Config (Codable)

```swift
struct CCRConfig: Codable {
    var LOG: Bool?
    var LOG_LEVEL: String?
    var CLAUDE_PATH: String?
    var HOST: String?
    var PORT: Int?
    var APIKEY: String?
    var API_TIMEOUT_MS: String?
    var PROXY_URL: String?
    var transformers: AnyCodable?       // Preserved as raw JSON — not edited by UI
    var Providers: [Provider]
    var Router: RouterConfig
    var StatusLine: AnyCodable?         // Preserved as raw JSON — not edited by UI
    var CUSTOM_ROUTER_PATH: String?
    var NON_INTERACTIVE_MODE: Bool?
}

// AnyCodable: a type-erased wrapper that decodes any JSON value
// and re-encodes it identically. Used for fields the app must
// round-trip but does not need to interpret (transformers, StatusLine).

struct Provider: Codable, Identifiable {
    var name: String
    var api_base_url: String
    var api_key: String
    var models: [String]
    var transformer: AnyCodable?        // Preserved as raw JSON
    var id: String { name }
}

struct RouterConfig: Codable {
    var `default`: String?     // "provider,model"
    var background: String?
    var think: String?
    var longContext: String?
    var longContextThreshold: Int?
    var webSearch: String?
    var image: String?
}
```

### Available Models

Derived from `Providers` array — flatten all provider+model combinations into a list:
```
[("anthropic", "claude-opus-4-6"), ("openrouter", "z-ai/glm-5-turbo"), ...]
```

## Components

### 1. Menu Bar Popup (MenuBarExtra)

**Server Status Section:**
- Shows running/stopped state via green/red circle indicator
- Server status determined by checking PID file at `~/.claude-code-router/.claude-code-router.pid` and verifying the process exists (via `kill(pid, 0)`). Falls back to attempting HTTP connection to `http://127.0.0.1:<PORT>/` if PID file is absent. Checked every 10 seconds.
- Buttons: Start / Stop / Restart — execute `ccr start`, `ccr stop`, `ccr restart` via `Process`
- If `ccr` binary is not found in PATH, show a warning in the status section with instructions
- Shell command errors (non-zero exit) are shown as brief inline error text below the buttons

**Router Section:**
- Lists each route type (default, think, background, longContext, webSearch, image)
- Shows current assignment as "model-name" (truncated if long)
- Clicking a route opens a submenu/picker listing all available provider+model combos
- Selecting a combo updates `Router` in config.json and saves
- `longContextThreshold` is not shown here (editable in Settings > General)

**Footer:**
- "Settings..." opens the Settings window
- "Quit" terminates the app

### 2. Settings Window

Separate `Window` scene, opened on demand.

**Providers Tab:**
- List of providers with name and model count
- Select a provider to see/edit its details
- Add/remove models from a provider
- Add/remove providers

**General Tab:**
- Toggle fields: LOG
- Text fields: LOG_LEVEL, API_TIMEOUT_MS, PROXY_URL, HOST, PORT, CLAUDE_PATH, longContextThreshold
- Secure fields: APIKEY (uses `SecureField`, masked by default with reveal toggle)
- Provider `api_key` fields in Providers tab also use `SecureField`
- Save button writes config.json

### 3. ConfigManager (ObservableObject)

Singleton service that:
- Reads config.json on app launch
- Watches file for external changes (via `DispatchSource.makeFileSystemObjectSource`)
- Provides `@Published var config: CCRConfig`
- Writes changes atomically (write to temp file, then rename)
- Exposes helper methods:
  - `availableModels() -> [(provider: String, model: String)]`
  - `setRoute(_ route: String, provider: String, model: String)`
  - `save()`

### 4. ServerManager (ObservableObject)

Manages CCR server state:
- `@Published var isRunning: Bool`
- `start()`, `stop()`, `restart()` — runs shell commands via `Process`
- `checkStatus()` — periodic status check
- Uses `/usr/bin/env ccr` to locate the binary

## File Structure

```
CCRMenuBar/
├── CCRMenuBarApp.swift          # App entry, MenuBarExtra scene
├── Views/
│   ├── MenuBarPopup.swift       # Main popup content
│   ├── RouterSection.swift      # Router route list + picker
│   ├── ServerStatusView.swift   # Server status + controls
│   ├── SettingsView.swift       # Settings window container
│   ├── ProvidersTab.swift       # Provider management tab
│   └── GeneralTab.swift         # General settings tab
├── Models/
│   ├── CCRConfig.swift          # Codable config structs
│   └── RouterRoute.swift        # Route type enum
├── Services/
│   ├── ConfigManager.swift      # Config read/write/watch
│   └── ServerManager.swift      # Server start/stop/status
└── Resources/
    └── Assets.xcassets          # App icon
```

## Behavior Details

- **Config path:** `~/.claude-code-router/config.json` (hardcoded, standard CCR location)
- **Route format:** `"provider,model"` string — split on first comma to get provider name and model name
- **File watching:** Detect external config changes (e.g., from `ccr model` CLI) and reload
- **Error handling:** Show inline error in popup if config.json is missing or malformed. Alerts use a helper window (since `MenuBarExtra` with `LSUIElement` has limited alert support).
- **Write safety:** All config writes go through a serial `DispatchQueue` to prevent race conditions with file watcher reloads. File watcher debounces reloads (200ms delay).
- **Menu bar icon:** SF Symbol `arrow.triangle.branch` — indicates routing
- **App type:** Menu bar only (no dock icon) — set `LSUIElement = true` in Info.plist

## Out of Scope

- Custom transformer management (complex, rarely changed — preserved as raw JSON via AnyCodable)
- StatusLine configuration (preserved as raw JSON via AnyCodable)
- Preset management (use CLI)
- Log viewer
- Keychain integration for API keys (future enhancement)
- Auto-update mechanism
