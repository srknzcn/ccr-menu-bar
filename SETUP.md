# CCR Menu Bar — Full Setup Guide

Complete installation and configuration guide for a fresh macOS machine.

---

## Table of Contents

1. [System Requirements](#1-system-requirements)
2. [Install Node.js](#2-install-nodejs)
3. [Install Claude Code Router (CCR)](#3-install-claude-code-router-ccr)
4. [Configure CCR](#4-configure-ccr)
5. [Install CCR Menu Bar App](#5-install-ccr-menu-bar-app)
6. [First Launch & Gatekeeper](#6-first-launch--gatekeeper)
7. [App Overview](#7-app-overview)
8. [Configure Providers](#8-configure-providers)
9. [Configure Routes](#9-configure-routes)
10. [Presets](#10-presets)
11. [Proxy Service & Per-Session Routing](#11-proxy-service--per-session-routing)
12. [Claude Code Integration](#12-claude-code-integration)
13. [ccm: Hook Commands](#13-ccm-hook-commands)
14. [MCP Server Integration](#14-mcp-server-integration)
15. [Token Usage Tracking](#15-token-usage-tracking)
16. [Settings Window](#16-settings-window)
17. [Troubleshooting](#17-troubleshooting)
18. [File Reference](#18-file-reference)

---

## 1. System Requirements

| Requirement | Minimum |
|---|---|
| macOS | **14.0 Sonoma** or later |
| Node.js | **18+** (22 LTS recommended) |
| Claude Code | Any recent version |
| Xcode (source build only) | 16.0+ |

---

## 2. Install Node.js

CCR is a Node.js application. Install Node via **nvm** (recommended — the app auto-detects nvm paths) or any other method.

### Option A — nvm (recommended)

```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

# Reload shell
source ~/.zshrc

# Install Node 22 LTS
nvm install 22
nvm use 22
nvm alias default 22

# Verify
node --version   # v22.x.x
npm --version    # 10.x.x
```

### Option B — Homebrew

```bash
brew install node
```

### Option C — Direct download

Download from [nodejs.org](https://nodejs.org) and run the installer.

---

## 3. Install Claude Code Router (CCR)

```bash
npm install -g claude-code-router
```

If using nvm, always install global packages **after** setting your default node version (`nvm alias default 22`).

Verify installation:

```bash
ccr --version   # should print 2.0.x
which ccr       # e.g. /Users/you/.nvm/versions/node/v22.x.x/bin/ccr
```

**Paths the menu bar app scans for the `ccr` binary (in order):**

1. `~/.nvm/versions/node/*/bin/ccr` (newest version first)
2. `/usr/local/bin/ccr`
3. `/opt/homebrew/bin/ccr`
4. `~/.bun/bin/ccr`
5. `~/.local/bin/ccr`
6. Shell fallback: `zsh -i -l -c 'which ccr'`

If `ccr` is not found, the app will show an error — ensure it's in one of these locations.

---

## 4. Configure CCR

CCR reads `~/.claude-code-router/config.json`. You can create this file manually or through the CCR Menu Bar app (recommended). If CCR has never been run, create the directory first:

```bash
mkdir -p ~/.claude-code-router
```

### Minimal config.json example

```json
{
  "LOG": true,
  "LOG_LEVEL": "info",
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "Providers": [
    {
      "name": "anthropic",
      "api_base_url": "https://api.anthropic.com/v1",
      "api_key": "sk-ant-YOUR_KEY_HERE",
      "models": ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"],
      "transformer": {
        "use": ["Anthropic"]
      }
    }
  ],
  "Router": {
    "default": "anthropic,claude-sonnet-4-5",
    "background": "anthropic,claude-haiku-4-5",
    "think": "anthropic,claude-opus-4-5",
    "longContext": "anthropic,claude-sonnet-4-5",
    "longContextThreshold": 60000,
    "webSearch": "anthropic,claude-sonnet-4-5",
    "image": "anthropic,claude-sonnet-4-5"
  }
}
```

The app reads and writes this file live — any changes you make via the GUI are saved here immediately.

### Multiple providers example

```json
{
  "LOG": true,
  "HOST": "127.0.0.1",
  "PORT": 3456,
  "Providers": [
    {
      "name": "anthropic",
      "api_base_url": "https://api.anthropic.com/v1",
      "api_key": "sk-ant-...",
      "models": ["claude-opus-4-5", "claude-sonnet-4-5", "claude-haiku-4-5"],
      "transformer": { "use": ["Anthropic"] }
    },
    {
      "name": "gemini",
      "api_base_url": "https://generativelanguage.googleapis.com/v1beta/openai",
      "api_key": "AIza...",
      "models": ["gemini-2.5-pro", "gemini-2.0-flash"],
      "transformer": { "use": ["gemini"] }
    },
    {
      "name": "openrouter",
      "api_base_url": "https://openrouter.ai/api/v1",
      "api_key": "sk-or-...",
      "models": ["deepseek/deepseek-r1", "meta-llama/llama-3.3-70b-instruct"],
      "transformer": { "use": ["OpenAI"] }
    }
  ],
  "Router": {
    "default": "anthropic,claude-sonnet-4-5",
    "background": "gemini,gemini-2.0-flash",
    "think": "anthropic,claude-opus-4-5",
    "longContext": "gemini,gemini-2.5-pro",
    "longContextThreshold": 60000,
    "webSearch": "anthropic,claude-sonnet-4-5",
    "image": "anthropic,claude-sonnet-4-5"
  }
}
```

---

## 5. Install CCR Menu Bar App

### Option A — Download pre-built release

1. Go to [Releases](https://github.com/srknzcn/ccr-menu-bar/releases)
2. Download `CCR.Menu.Bar.app.zip`
3. Unzip and drag `CCR Menu Bar.app` to `/Applications`

### Option B — Build from source

**Prerequisites:** Xcode 16+ and XcodeGen

```bash
# Install XcodeGen (one-time)
brew install xcodegen

# Clone the repo
git clone https://github.com/srknzcn/ccr-menu-bar.git
cd ccr-menu-bar

# Build
chmod +x build-app.sh
./build-app.sh

# Install
cp -r "build/CCR Menu Bar.app" /Applications/
```

Build output: `build/CCR Menu Bar.app`

Alternatively, open in Xcode:

```bash
xcodegen generate
open CCRMenuBar.xcodeproj
```

Then build with ⌘B and run with ⌘R.

---

## 6. First Launch & Gatekeeper

The app is **not notarized** by Apple. On first launch, macOS will block it with _"cannot be opened because the developer cannot be verified."_

**To bypass Gatekeeper:**

1. Right-click `CCR Menu Bar.app` in Finder
2. Select **Open** from the context menu
3. Click **Open** in the dialog

You only need to do this once. After that, the app opens normally.

Alternatively from Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/CCR Menu Bar.app"
```

---

## 7. App Overview

After launch, a branch icon (`⎇`) appears in the menu bar:

- **White icon** — CCR server is stopped
- **Green icon** — CCR server is running

Click the icon to open the popup:

```
┌─────────────────────────────────────────┐
│  ● CCR Server  127.0.0.1:3456    [Start] │
│  ● Proxy       :3457    Preset: default  │
│                                          │
│  ~ 12.3K in  ~ 2.1K out  47 reqs        │
│    anthropic/claude-sonnet-4-5  ▼        │
│                                          │
│  Default    anthropic  claude-sonnet-4-5 │
│  Think      anthropic  claude-opus-4-5   │
│  Background gemini     gemini-2.0-flash  │
│  Long Ctx   gemini     gemini-2.5-pro    │
│  Web Search anthropic  claude-sonnet-4-5 │
│  Image      anthropic  claude-sonnet-4-5 │
│                                          │
│  [⚙ Settings] [↺] [Preset ▼] [Save & ↺]│
└─────────────────────────────────────────┘
```

---

## 8. Configure Providers

Open **Settings → Providers** tab.

### Add a provider

1. Click **+** in the provider list sidebar
2. Enter provider name (e.g. `anthropic`, `gemini`, `openrouter`)
3. Enter API base URL (e.g. `https://api.anthropic.com/v1`)
4. Enter API key
5. Add models with the **+ Model** button
6. Assign transformers from the dropdown (see table below)

### Available transformers

| Transformer | Use for |
|---|---|
| `Anthropic` | Anthropic API (claude.ai models) |
| `OpenAI` | OpenAI-compatible APIs (OpenRouter, Together, etc.) |
| `gemini` | Google Gemini API |
| `deepseek` | DeepSeek API |
| `openrouter` | OpenRouter-specific features |
| `groq` | Groq API |
| `vertex-gemini` | Google Vertex AI (Gemini) |
| `gemini-cli` | Gemini CLI integration |
| `qwen-cli` | Qwen/Alibaba CLI |
| `rovo-cli` | Atlassian Rovo |
| `chutes-glm` | Chutes GLM |
| `maxtoken` | Override max tokens |
| `tooluse` | Tool call format conversion |
| `reasoning` | Reasoning/thinking token handling |
| `sampling` | Sampling parameter normalization |
| `enhancetool` | Enhanced tool use |
| `cleancache` | Clear context cache |

Multiple transformers can be stacked — they apply in order.

---

## 9. Configure Routes

CCR routes different request types to different providers. All 6 routes are visible in the main popup.

| Route | When CCR uses it |
|---|---|
| **Default** | Standard Claude Code requests |
| **Think** | Extended thinking requests (`claude --think`) |
| **Background** | Background agentic tasks |
| **Long Context** | Requests exceeding the long context threshold |
| **Web Search** | Requests requiring web access |
| **Image** | Requests with image input |

Route format in `config.json`: `"providerName,modelName"`

Example: `"anthropic,claude-opus-4-5"`

### Changing a route

Click any route row to open the **searchable model picker**:

- Providers are listed alphabetically; models within each provider are also sorted alphabetically
- Type in the search box to filter by provider name or model name
- The currently selected model is scrolled into view and marked with a checkmark
- Click a model to select it — the popover closes immediately

### Apply route changes

After changing routes in the popup, click **Save & Restart**. This:
1. Writes the updated `config.json`
2. Restarts the CCR server with the new config
3. Re-syncs all preset directories to `~/.claude-code-router/presets/`

---

## 10. Presets

Presets are **named snapshots of your router configuration** — they let you quickly switch between different provider/model combinations.

### Save a preset

1. Configure routes to your desired setup
2. Click the **Preset ▼** dropdown
3. Select **Save as preset…**
4. Enter a name and confirm

### Switch presets

Click the **Preset ▼** dropdown and select a preset name. The routes update immediately.

### Update an existing preset

1. Modify the routes
2. Click **Preset ▼** → hover over the preset name → **Update**

### Delete a preset

Click **Preset ▼** → hover over the preset name → **Delete**

### How presets work internally

Each preset is stored in two places:

1. **`~/.claude-code-router/router-presets.json`** — the app's own storage
   ```json
   {
     "My Gemini Preset": {
       "default": "gemini,gemini-2.5-pro",
       "background": "gemini,gemini-2.0-flash",
       ...
     }
   }
   ```

2. **`~/.claude-code-router/presets/{safe-name}/manifest.json`** — CCR preset directories

   CCR reads these and registers each as a separate routing namespace:
   `POST /preset/{safe-name}/v1/messages`

   The safe name is derived from the display name: lowercase, non-alphanumeric characters replaced with hyphens.
   Example: `"My Gemini Preset"` → `my-gemini-preset`

---

## 11. Proxy Service & Per-Session Routing

The app runs an **HTTP reverse proxy on port 3457** that sits between Claude Code and CCR. This enables per-session preset switching without restarting CCR.

### How the proxy works

```
Claude Code (port 3457)
    ↓
CCR Menu Bar Proxy (:3457)
    ↓ if preset active: prepends /preset/{name}/
    ↓
CCR Server (:3456)
    ↓
AI Provider API
```

The proxy starts automatically when the app launches. Status is shown in the popup:
```
● Proxy  :3457  Preset: default
```

### Proxy control API

The proxy exposes a local API for preset management:

```bash
# Show current preset
curl http://127.0.0.1:3457/_api/current

# List all presets
curl http://127.0.0.1:3457/_api/presets

# Switch preset (global)
curl -X POST http://127.0.0.1:3457/_api/switch \
  -H 'Content-Type: application/json' \
  -d '{"preset":"my-gemini-preset"}'

# Switch preset for a specific session
curl -X POST http://127.0.0.1:3457/_api/switch \
  -H 'Content-Type: application/json' \
  -d '{"preset":"my-gemini-preset","session":"abc123"}'

# Reset to default
curl -X POST http://127.0.0.1:3457/_api/switch \
  -H 'Content-Type: application/json' \
  -d '{"preset":""}'
```

The `preset` field accepts display names, filesystem names, or case-insensitive variants.

---

## 12. Claude Code Integration

To route Claude Code's API calls through CCR Menu Bar:

### Step 1 — Set ANTHROPIC_BASE_URL

#### Automatic (recommended)

Open **Settings → Integrations → Shell Setup** and click **Add to ~/.zshrc** (or the equivalent for your shell). The app writes the per-session block shown below and detects your login shell automatically.

#### Manual

Add to `~/.zshrc` (or `~/.bash_profile`):

##### Option A — Global routing (simplest)

Points Claude Code directly to CCR. No per-session isolation.

```bash
export ANTHROPIC_BASE_URL="http://localhost:3456"
export ANTHROPIC_API_KEY="any-value"  # CCR handles the real key
```

##### Option B — Per-session routing via proxy (recommended)

Each terminal window gets a unique session ID. Preset switches only affect the current window.

```bash
# Generate a unique session ID for each new terminal
export CCR_SESSION="${CCR_SESSION:-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-16)}"

# Point to the proxy with session token in the path
export ANTHROPIC_BASE_URL="http://localhost:3457/s/$CCR_SESSION"
export ANTHROPIC_API_KEY="any-value"
```

After adding these manually, reload your shell:

```bash
source ~/.zshrc
```

### Step 2 — Start the server

Click **Start** in the CCR Menu Bar popup, or from Terminal:

```bash
ccr start
```

### Step 3 — Verify

```bash
# Check the proxy is running
curl http://127.0.0.1:3457/_api/current
# → {"preset":null,"presetId":null}

# Check CCR is running
curl http://127.0.0.1:3456/
# → some response (not "connection refused")
```

### Step 4 — Run Claude Code

```bash
claude
```

All API calls from Claude Code will now route through CCR → your configured providers.

---

## 13. ccm: Hook Commands

The `ccm:` hook lets you switch presets directly from the Claude Code CLI prompt — without leaving the session.

### Install the hook

#### Automatic (recommended)

Open **Settings → Integrations → ccm: Hook** and click **Install**. The app writes the hook script to `~/.claude/hooks/ccr-switch.sh` and registers it in `~/.claude/settings.json` automatically.

The hook is also installed automatically on every app launch to keep it up to date.

#### Manual

##### Step 1 — Create the hook script

```bash
mkdir -p ~/.claude/hooks
```

Save the following as `~/.claude/hooks/ccr-switch.sh`:

```bash
#!/bin/bash
# CCR Menu Bar preset switcher hook
# ccm:          → show current preset (stderr)
# ccm:list      → list all presets (stderr)
# ccm:<name>    → direct switch (case-insensitive)

INPUT=$(cat)
PROMPT=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null <<< "$INPUT")

[[ "$PROMPT" =~ ^ccm:(.*)$ ]] || exit 0

ARG="${BASH_REMATCH[1]}"
BASE="http://127.0.0.1:3457"

ccr_switch() {
    local preset="$1"
    python3 - "$preset" "$CCR_SESSION" << 'PYEOF'
import json, sys, urllib.request
preset  = sys.argv[1]
session = sys.argv[2] if len(sys.argv) > 2 else ""
body    = json.dumps({"preset": preset, "session": session}).encode()
req     = urllib.request.Request("http://127.0.0.1:3457/_api/switch",
            data=body, headers={"Content-Type":"application/json"}, method="POST")
try:
    d = json.loads(urllib.request.urlopen(req, timeout=3).read())
    print("Switched to:", d.get("preset","?") if d.get("ok") else f"Error: {d.get('error')}")
except Exception as e:
    print("Error:", e)
PYEOF
}

if [ -z "$ARG" ]; then
    # ccm: → show current preset
    CURRENT=$(curl -s "$BASE/_api/current" -H "X-CCR-Session: $CCR_SESSION" 2>/dev/null)
    PRESET=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('preset') or 'default')" <<< "$CURRENT" 2>/dev/null)
    echo "Current preset: $PRESET" >&2

elif [ "$ARG" = "list" ]; then
    # ccm:list → list all presets
    PRESETS_JSON=$(curl -s "$BASE/_api/presets" 2>/dev/null)
    python3 -c "
import json,sys
d=json.load(sys.stdin)
cur=d.get('current')
for p in d.get('presets',[]):
    mark = ' <' if p['id']==cur else ''
    print(f\"  {p['name']}{mark}\")
" <<< "$PRESETS_JSON" >&2

else
    # ccm:<name> → direct switch
    ccr_switch "$ARG" >&2
fi

exit 2
```

Make it executable:

```bash
chmod +x ~/.claude/hooks/ccr-switch.sh
```

##### Step 2 — Register the hook in Claude Code settings

Edit `~/.claude/settings.json` and add the `UserPromptSubmit` hook:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "command": "~/.claude/hooks/ccr-switch.sh",
            "timeout": 10,
            "type": "command"
          }
        ],
        "matcher": ""
      }
    ]
  }
}
```

If `settings.json` already has other hooks, add this entry to the existing `UserPromptSubmit` array.

---

### Usage

Type these at the Claude Code prompt — they are intercepted by the hook and never sent to the model:

| Command | Action |
|---|---|
| `ccm:` | Show active preset for this session |
| `ccm:list` | List all available presets (active preset marked with `<`) |
| `ccm:my-gemini-preset` | Switch to preset named "my-gemini-preset" (case-insensitive) |
| `ccm:default` | Reset to default CCR config (no preset) |

The hook uses `exit 2` to prevent the command from being sent as a prompt to Claude. Output appears in the terminal via stderr. If `CCR_SESSION` is set (see section 12), switching is session-scoped.

---

## 14. MCP Server Integration

The app writes an MCP server script at `~/.claude-code-router/ccr-mcp-server.js` on every launch to keep it up to date. You can also force a reinstall from **Settings → Integrations → MCP Server → Install**.

This is a self-contained Node.js MCP server (zero npm dependencies) that exposes three tools to Claude Code:

| Tool | Description |
|---|---|
| `switch_preset` | Switch to a named preset |
| `list_presets` | List all available presets |
| `current_preset` | Show the active preset |

### Register the MCP server with Claude Code

Add to `~/.claude/settings.json` under `mcpServers`:

```json
{
  "mcpServers": {
    "ccr-presets": {
      "command": "node",
      "args": ["/Users/YOUR_USERNAME/.claude-code-router/ccr-mcp-server.js"]
    }
  }
}
```

Replace `YOUR_USERNAME` with your macOS username.

After registering, Claude Code can use the tools directly. For example, you can ask:
> "Switch to the Gemini preset"

Claude will call `switch_preset` with the appropriate preset name.

**Note:** The MCP server is re-written by the app on every launch to keep it up to date. Manual edits to the `.js` file will be overwritten.

---

## 15. Token Usage Tracking

The popup shows approximate token consumption parsed from CCR log files (`~/.claude-code-router/logs/*.log`).

- **Input tokens** — estimated from request body size (~3 chars per token)
- **Output tokens** — estimated from response time (~50 tokens/second)
- **Requests** — count of API calls

Stats refresh every 30 seconds. Today's stats are shown by default; all-time totals if today has no data.

**Note:** These are estimates, not exact counts. CCR does not expose a usage API. Values are marked with `~` in the UI.

---

## 16. Settings Window

Open with the **⚙ Settings** button in the popup.

### General tab

| Setting | Description |
|---|---|
| **Host** | CCR listen address (default: `127.0.0.1`) |
| **Port** | CCR listen port (default: `3456`) |
| **API Timeout** | Request timeout in milliseconds (default: `180000`) |
| **Proxy URL** | Outbound HTTP proxy for CCR (optional) |
| **Claude Binary Path** | Path to the `claude` binary (optional, auto-detected) |
| **API Key** | Global fallback API key (shown masked) |
| **Logging** | Enable/disable CCR log output |
| **Log Level** | `error` / `warn` / `info` / `debug` |
| **Long Context Threshold** | Token count that triggers the Long Context route |
| **Launch at Login** | Start CCR Menu Bar automatically at system login |

### Providers tab

Left sidebar shows all configured providers. Select one to edit:

- **Name** — Provider identifier (must match transformer expectations)
- **API Base URL** — Provider's API endpoint
- **API Key** — Provider-specific key (overrides global)
- **Models** — List of model IDs for this provider (add/remove with + and -)
- **Transformers** — Middleware applied to requests/responses for this provider

### Integrations tab

Manages all Claude Code integration components with install/uninstall controls:

#### ccm: Hook

| Item | Description |
|---|---|
| Hook script | `~/.claude/hooks/ccr-switch.sh` — status dot shows if file exists |
| Claude settings | Status dot shows if the hook is registered in `~/.claude/settings.json` |
| **Install** | Writes the hook script, sets executable permissions, registers in settings.json |
| **Reinstall** | Overwrites the hook script and re-registers (useful after app updates) |
| **Uninstall** | Removes the script file and unregisters from settings.json |

#### MCP Server

| Item | Description |
|---|---|
| Server script | `~/.claude-code-router/ccr-mcp-server.js` — status dot shows if file exists |
| **Install** | Writes the MCP server script |
| **Reinstall** | Overwrites with the latest version |
| **Uninstall** | Removes the script file |

The JSON snippet shown in this card is what you need to add to `~/.claude/settings.json` to register the MCP server with Claude Code.

#### Shell Setup

| Item | Description |
|---|---|
| RC file | Auto-detected from `$SHELL` (`.zshrc`, `.bash_profile`, or `config.fish`) |
| Status | Shows whether the CCR block is present in the RC file |
| **Add to ~/.zshrc** | Appends the `CCR_SESSION` + `ANTHROPIC_BASE_URL` block |
| **Update** | Replaces the existing block with the current version |
| **Remove** | Cleanly removes the block from the RC file |

The block written to the RC file is shown in the card for reference.

---

## 17. Troubleshooting

### CCR server won't start

```bash
# Check if ccr is found
which ccr

# Try starting manually
ccr start

# Check for port conflict
lsof -i :3456
```

If the menu bar shows "ccr not found", the binary is not in any of the searched paths. Install via nvm or ensure the install directory is covered.

### Proxy not running

The proxy starts automatically on app launch. If port 3457 is already in use:

```bash
lsof -i :3457
```

Kill the conflicting process or change the proxy port in the app (not currently exposed in UI — restart the app instead).

### Config file not loading

```bash
cat ~/.claude-code-router/config.json | python3 -m json.tool
```

If this fails, the JSON is malformed. Fix it or delete the file and reconfigure via the app.

### Preset switch not working (ccm: hook)

1. Confirm the proxy is running: `curl http://127.0.0.1:3457/_api/current`
2. Confirm the hook is executable: `ls -la ~/.claude/hooks/ccr-switch.sh`
3. Confirm the hook is registered in `~/.claude/settings.json`
4. Confirm the hook timeout is at least `10` (not `5`) in settings.json

### ccm: command passed to model instead of intercepted

The hook timed out (5s default is too short). Ensure `"timeout": 10` is set for the hook entry in `settings.json`.

### Claude Code not routing through CCR

Check that `ANTHROPIC_BASE_URL` is set:

```bash
echo $ANTHROPIC_BASE_URL
# should be http://localhost:3457/s/$CCR_SESSION  (or http://localhost:3456)
```

If empty, add the export to `~/.zshrc` and reload: `source ~/.zshrc`

### Token stats show 0

CCR logging must be enabled. In Settings → General, turn on **Logging** and set level to `info`. Restart CCR. Stats appear after the first requests complete.

---

## 18. File Reference

### App-managed files

| File | Purpose |
|---|---|
| `~/.claude-code-router/config.json` | CCR main configuration (read/write) |
| `~/.claude-code-router/router-presets.json` | Preset storage for the menu bar app |
| `~/.claude-code-router/presets/{name}/manifest.json` | CCR preset directories (auto-synced) |
| `~/.claude-code-router/ccr-mcp-server.js` | MCP server script (auto-written at launch) |
| `~/.claude-code-router/.claude-code-router.pid` | CCR process ID (written by CCR) |
| `~/.claude-code-router/logs/*.log` | CCR NDJSON log files (read for token stats) |

### User-managed files

| File | Purpose |
|---|---|
| `~/.claude/settings.json` | Claude Code settings (hooks, MCP servers) |
| `~/.claude/hooks/ccr-switch.sh` | `ccm:` command hook script |
| `~/.zshrc` | Shell environment (ANTHROPIC_BASE_URL, CCR_SESSION) |

### CCR preset name sanitization

Display names are converted to filesystem-safe names:

| Display name | Filesystem name |
|---|---|
| `My Gemini Setup` | `my-gemini-setup` |
| `Claude (Opus + Sonnet)` | `claude-opus-sonnet` |
| `GPT-4o Fast` | `gpt-4o-fast` |

Names are lowercased, non-alphanumeric characters become hyphens, consecutive hyphens are collapsed, leading/trailing hyphens are removed.

---

## Quick Start Checklist

```
[ ] macOS 14+ running
[ ] Node.js 18+ installed (nvm recommended)
[ ] claude-code-router installed: npm install -g claude-code-router
[ ] ~/.claude-code-router/config.json created with at least one provider
[ ] CCR Menu Bar.app installed in /Applications
[ ] First launch: right-click → Open (Gatekeeper bypass)
[ ] CCR server started via menu bar popup
[ ] Providers configured in Settings → Providers
[ ] Routes assigned in main popup (click any row → searchable picker)
[ ] Settings → Integrations → Shell Setup → Add to ~/.zshrc
[ ] source ~/.zshrc  (or open a new terminal)
[ ] Settings → Integrations → ccm: Hook → Install  (optional)
[ ] Register MCP server in ~/.claude/settings.json  (optional, see §14)
[ ] claude  ← test it works
```
