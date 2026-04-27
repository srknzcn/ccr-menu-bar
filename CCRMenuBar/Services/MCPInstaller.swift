import Foundation

@MainActor
class MCPInstaller: ObservableObject {
    @Published var mcpServerInstalled = false
    @Published var hookScriptExists = false
    @Published var hookRegistered = false
    var hookInstalled: Bool { hookScriptExists && hookRegistered }

    @Published var shellConfigured = false

    private let mcpServerURL: URL
    private let hookScriptURL: URL
    private let claudeSettingsURL: URL

    private static let hookCommand = "~/.claude/hooks/ccr-switch.sh"
    private static let shellMarkerBegin = "# >>> CCR Menu Bar >>>"
    private static let shellMarkerEnd   = "# <<< CCR Menu Bar <<<"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        mcpServerURL = home.appendingPathComponent(".claude-code-router/ccr-mcp-server.js")
        hookScriptURL = home.appendingPathComponent(".claude/hooks/ccr-switch.sh")
        claudeSettingsURL = home.appendingPathComponent(".claude/settings.json")
    }

    func installAll() {
        installMCPServer()
        installHook()
    }

    func checkInstallation() {
        let fm = FileManager.default
        mcpServerInstalled = fm.fileExists(atPath: mcpServerURL.path)
        hookScriptExists = fm.fileExists(atPath: hookScriptURL.path)
        hookRegistered = isHookRegistered()
        shellConfigured = isShellConfigured()
    }

    // MARK: - MCP Server

    func installMCPServer() {
        do {
            let dir = mcpServerURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try mcpServerScript.write(to: mcpServerURL, atomically: true, encoding: .utf8)
            mcpServerInstalled = true
        } catch {
            mcpServerInstalled = false
        }
    }

    // MARK: - Hook

    func installHook() {
        do {
            // Write hook script
            let dir = hookScriptURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try hookScript.write(to: hookScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)
            // Register in Claude Code settings
            registerHookInSettings()
            hookScriptExists = true
            hookRegistered = true
        } catch {
            hookScriptExists = FileManager.default.fileExists(atPath: hookScriptURL.path)
            hookRegistered = isHookRegistered()
        }
    }

    func uninstallHook() {
        try? FileManager.default.removeItem(at: hookScriptURL)
        unregisterHookFromSettings()
        hookScriptExists = false
        hookRegistered = false
    }

    func uninstallMCPServer() {
        try? FileManager.default.removeItem(at: mcpServerURL)
        mcpServerInstalled = false
    }

    // MARK: - Shell Config

    /// Display path of the RC file that will be written (e.g. "~/.zshrc")
    var shellRCDisplayPath: String {
        let full = shellRCURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return full.hasPrefix(home) ? "~" + full.dropFirst(home.count) : full
    }

    func installShellConfig() {
        let existing = (try? String(contentsOf: shellRCURL, encoding: .utf8)) ?? ""
        let newContent: String
        if existing.contains(Self.shellMarkerBegin) {
            newContent = replaceShellBlock(in: existing)
        } else {
            let separator = existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n"
            newContent = existing + separator + shellBlock
        }
        try? FileManager.default.createDirectory(
            at: shellRCURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? newContent.write(to: shellRCURL, atomically: true, encoding: .utf8)
        shellConfigured = true
    }

    func uninstallShellConfig() {
        guard let existing = try? String(contentsOf: shellRCURL, encoding: .utf8) else { return }
        let newContent = removeShellBlock(from: existing)
        try? newContent.write(to: shellRCURL, atomically: true, encoding: .utf8)
        shellConfigured = false
    }

    private func isShellConfigured() -> Bool {
        guard let content = try? String(contentsOf: shellRCURL, encoding: .utf8) else { return false }
        return content.contains(Self.shellMarkerBegin)
    }

    /// Resolves the user's login shell RC file.
    private var shellRCURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? ""
        if shell.hasSuffix("zsh") {
            return home.appendingPathComponent(".zshrc")
        } else if shell.hasSuffix("bash") {
            let profile = home.appendingPathComponent(".bash_profile")
            if FileManager.default.fileExists(atPath: profile.path) { return profile }
            return home.appendingPathComponent(".bashrc")
        } else if shell.hasSuffix("fish") {
            return home.appendingPathComponent(".config/fish/config.fish")
        }
        // Default: zsh (macOS default since Catalina)
        return home.appendingPathComponent(".zshrc")
    }

    private var shellBlock: String {
        "\n\(Self.shellMarkerBegin)\n" +
        #"export CCR_SESSION="${CCR_SESSION:-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-16)}""# + "\n" +
        "export ANTHROPIC_BASE_URL=\"http://localhost:3457/s/$CCR_SESSION\"\n" +
        "export ANTHROPIC_API_KEY=\"any-value\"\n" +
        "\(Self.shellMarkerEnd)\n"
    }

    private func replaceShellBlock(in content: String) -> String {
        removeShellBlock(from: content) + shellBlock
    }

    private func removeShellBlock(from content: String) -> String {
        let begin = Self.shellMarkerBegin
        let end   = Self.shellMarkerEnd
        guard let beginRange = content.range(of: begin),
              let endRange   = content.range(of: end, range: beginRange.upperBound..<content.endIndex) else {
            return content
        }
        // Trim the preceding newline(s) that separate the block from surrounding content
        var lo = beginRange.lowerBound
        while lo > content.startIndex {
            let prev = content.index(before: lo)
            if content[prev] == "\n" { lo = prev } else { break }
        }
        // Include the trailing newline after the end marker
        var hi = endRange.upperBound
        if hi < content.endIndex && content[hi] == "\n" {
            hi = content.index(after: hi)
        }
        return String(content[..<lo]) + String(content[hi...])
    }

    private func unregisterHookFromSettings() {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any],
              var promptSubmit = hooks["UserPromptSubmit"] as? [[String: Any]] else { return }

        let cmd = Self.hookCommand
        promptSubmit.removeAll { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String) == cmd }
        }

        hooks["UserPromptSubmit"] = promptSubmit
        settings["hooks"] = hooks

        guard let newData = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? newData.write(to: claudeSettingsURL, options: .atomic)
    }

    private func registerHookInSettings() {
        // Read existing settings or start fresh
        var settings: [String: Any]
        if let data = try? Data(contentsOf: claudeSettingsURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = parsed
        } else {
            settings = [:]
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var promptSubmit = hooks["UserPromptSubmit"] as? [[String: Any]] ?? []

        // Skip if already registered
        let cmd = Self.hookCommand
        let alreadyRegistered = promptSubmit.contains { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String) == cmd }
        }
        guard !alreadyRegistered else { return }

        // Prepend our entry so it runs first
        let hookEntry: [String: Any] = [
            "hooks": [["command": cmd, "timeout": 10, "type": "command"]],
            "matcher": ""
        ]
        promptSubmit.insert(hookEntry, at: 0)
        hooks["UserPromptSubmit"] = promptSubmit
        settings["hooks"] = hooks

        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }

        try? FileManager.default.createDirectory(
            at: claudeSettingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: claudeSettingsURL, options: .atomic)
    }

    private func isHookRegistered() -> Bool {
        guard let data = try? Data(contentsOf: claudeSettingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any],
              let promptSubmit = hooks["UserPromptSubmit"] as? [[String: Any]] else { return false }

        let cmd = Self.hookCommand
        return promptSubmit.contains { entry in
            guard let entryHooks = entry["hooks"] as? [[String: Any]] else { return false }
            return entryHooks.contains { ($0["command"] as? String) == cmd }
        }
    }

    // MARK: - Embedded Content

    // Raw string: closing delimiter at column 0 so heredoc content (column-0 Python lines) is preserved.
    private var hookScript: String {
#"""
#!/bin/bash
# CCR Menu Bar preset switcher hook
# ccm:          → show current preset
# ccm:list      → list all presets
# ccm:<name>    → direct switch (case-insensitive)

INPUT=$(cat)
PROMPT=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('prompt',''))" 2>/dev/null <<< "$INPUT")

[[ "$PROMPT" =~ ^ccm:(.*)$ ]] || exit 0

ARG=$(printf '%s' "${BASH_REMATCH[1]}" | python3 -c "import re,sys; s=sys.stdin.read(); s=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', s); s=re.sub(r'\[[0-?]*[ -/]*m\]?$', '', s); print(s.strip())")
BASE="http://127.0.0.1:3457"
MSG=""
DEBUG_LOG="$HOME/.claude-code-router/ccm-debug.log"

ccm_debug() {
    mkdir -p "$HOME/.claude-code-router" 2>/dev/null
    printf '[%s] hook %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" >> "$DEBUG_LOG" 2>/dev/null
}

ccm_debug "prompt=$PROMPT arg=$ARG CCR_SESSION=${CCR_SESSION:-nil} ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-nil}"

ccr_switch() {
    local preset="$1"
    local result
result=$(python3 - "$preset" "$CCR_SESSION" << 'PYEOF'
import json, os, re, sys, urllib.request
preset  = sys.argv[1]
session = sys.argv[2] if len(sys.argv) > 2 else ""
if not session:
    match = re.search(r"/s/([^/]+)", os.environ.get("ANTHROPIC_BASE_URL", ""))
    session = match.group(1) if match else ""
payload = {"preset": preset}
if session:
    payload["session"] = session
body    = json.dumps(payload).encode()
req     = urllib.request.Request("http://127.0.0.1:3457/_api/switch",
            data=body, headers={"Content-Type":"application/json"}, method="POST")
try:
    d = json.loads(urllib.request.urlopen(req, timeout=3).read())
    print(d.get("preset","?") if d.get("ok") else f"Error: {d.get('error')}")
except Exception as e:
    print(f"Error: {e}")
PYEOF
    )
    ccm_debug "switch_result=$result"
    MSG="Switched to: $result"
}

if [ -z "$ARG" ]; then
    CURRENT=$(curl -s "$BASE/_api/current" -H "X-CCR-Session: $CCR_SESSION" 2>/dev/null)
    PRESET=$(python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('preset') or 'default')" <<< "$CURRENT" 2>/dev/null)
    MSG="Current preset: $PRESET"

elif [ "$ARG" = "list" ]; then
    PRESETS_JSON=$(curl -s "$BASE/_api/presets" 2>/dev/null)
    MSG=$(python3 -c "
import json,sys
d=json.load(sys.stdin)
cur=d.get('current')
lines=[]
for p in d.get('presets',[]):
    mark = ' ←' if p['id']==cur else ''
    lines.append(f\"  {p['name']} [{p['id']}]{mark}\")
print('\\n'.join(lines))
" <<< "$PRESETS_JSON" 2>/dev/null)

else
    ccr_switch "$ARG"
fi

# Block the prompt — pass MSG as reason so user sees the result
MSG_JSON=$(printf '%s' "$MSG" | python3 -c "import json,re,sys; s=sys.stdin.read(); s=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', s); s=re.sub(r'\[[0-?]*[ -/]*m\]?$', '', s); print(json.dumps(s.strip()))")
printf '{"decision":"block","reason":%s}\n' "$MSG_JSON"
exit 0
"""#
    }

    private var mcpServerScript: String {
        """
        #!/usr/bin/env node
        // CCR Menu Bar — MCP Server for Claude Code preset switching
        // Auto-generated by CCR Menu Bar app. Do not edit manually.
        'use strict';

        const http = require('http');

        const PROXY_PORT = parseInt(process.env.CCR_PROXY_PORT || '3457', 10);
        const PROXY_HOST = '127.0.0.1';

        // --- MCP Protocol (JSON-RPC 2.0 with Content-Length framing) ---

        let inputBuffer = Buffer.alloc(0);

        function sendMessage(msg) {
          const json = JSON.stringify(msg);
          const header = `Content-Length: ${Buffer.byteLength(json)}\\r\\n\\r\\n`;
          process.stdout.write(header + json);
        }

        function sendResult(id, result) {
          sendMessage({ jsonrpc: '2.0', id, result });
        }

        function sendError(id, code, message) {
          sendMessage({ jsonrpc: '2.0', id, error: { code, message } });
        }

        function processInput() {
          while (true) {
            const headerEnd = inputBuffer.indexOf('\\r\\n\\r\\n');
            if (headerEnd === -1) break;

            const header = inputBuffer.slice(0, headerEnd).toString();
            const match = header.match(/Content-Length:\\s*(\\d+)/i);
            if (!match) {
              inputBuffer = inputBuffer.slice(headerEnd + 4);
              continue;
            }

            const contentLength = parseInt(match[1], 10);
            const messageStart = headerEnd + 4;
            if (inputBuffer.length < messageStart + contentLength) break;

            const body = inputBuffer.slice(messageStart, messageStart + contentLength).toString();
            inputBuffer = inputBuffer.slice(messageStart + contentLength);

            try {
              handleMessage(JSON.parse(body));
            } catch (e) {
              process.stderr.write('Parse error: ' + e.message + '\\n');
            }
          }
        }

        process.stdin.on('data', (chunk) => {
          inputBuffer = Buffer.concat([inputBuffer, chunk]);
          processInput();
        });

        process.stdin.on('end', () => process.exit(0));

        // --- Message Handling ---

        const TOOLS = [
          {
            name: 'switch_preset',
            description: 'Switch the active CCR routing preset. Changes which AI provider/model combination is used for subsequent API requests in this session.',
            inputSchema: {
              type: 'object',
              properties: {
                name: {
                  type: 'string',
                  description: 'Preset name to activate. Use "default" or empty string to use the base CCR config with no preset.'
                }
              },
              required: ['name']
            }
          },
          {
            name: 'list_presets',
            description: 'List all available CCR routing presets.',
            inputSchema: { type: 'object', properties: {} }
          },
          {
            name: 'current_preset',
            description: 'Show the currently active CCR routing preset.',
            inputSchema: { type: 'object', properties: {} }
          }
        ];

        function handleMessage(msg) {
          if (!msg.method) return; // response, ignore

          switch (msg.method) {
            case 'initialize':
              sendResult(msg.id, {
                protocolVersion: '2024-11-05',
                capabilities: { tools: {} },
                serverInfo: { name: 'ccr-presets', version: '1.0.0' }
              });
              break;

            case 'notifications/initialized':
              // No response needed
              break;

            case 'tools/list':
              sendResult(msg.id, { tools: TOOLS });
              break;

            case 'tools/call':
              handleToolCall(msg.id, msg.params.name, msg.params.arguments || {});
              break;

            default:
              if (msg.id) {
                sendError(msg.id, -32601, 'Method not found: ' + msg.method);
              }
          }
        }

        // --- Tool Implementations ---

        const agent = new http.Agent({ keepAlive: true });

        function httpRequest(method, path, body) {
          return new Promise((resolve, reject) => {
            const options = {
              hostname: PROXY_HOST,
              port: PROXY_PORT,
              path: path,
              method: method,
              headers: { 'Content-Type': 'application/json' },
              agent: agent,
              timeout: 2000
            };

            const req = http.request(options, (res) => {
              let data = '';
              res.on('data', (chunk) => { data += chunk; });
              res.on('end', () => {
                try {
                  resolve(JSON.parse(data));
                } catch {
                  resolve({ raw: data });
                }
              });
            });

            req.on('error', (err) => reject(err));
            req.on('timeout', () => { req.destroy(); reject(new Error('Request timeout')); });

            if (body) req.write(JSON.stringify(body));
            req.end();
          });
        }

        async function handleToolCall(id, toolName, args) {
          try {
            let result;
            switch (toolName) {
              case 'switch_preset':
                result = await httpRequest('POST', '/_api/switch', { preset: args.name || '' });
                if (result.ok) {
                  sendResult(id, {
                    content: [{ type: 'text', text: `Switched to preset: ${result.preset || 'default'}` }]
                  });
                } else {
                  sendResult(id, {
                    content: [{ type: 'text', text: `Failed: ${result.error || 'Unknown error'}` }],
                    isError: true
                  });
                }
                break;

              case 'list_presets':
                result = await httpRequest('GET', '/_api/presets');
                if (result.presets && result.presets.length > 0) {
                  const lines = result.presets.map(p => {
                    const active = p.id === result.current ? ' (active)' : '';
                    return `- ${p.name} [${p.id}]${active}`;
                  });
                  sendResult(id, {
                    content: [{ type: 'text', text: 'Available presets:\\n' + lines.join('\\n') }]
                  });
                } else {
                  sendResult(id, {
                    content: [{ type: 'text', text: 'No presets configured. Create presets in the CCR Menu Bar app.' }]
                  });
                }
                break;

              case 'current_preset':
                result = await httpRequest('GET', '/_api/current');
                sendResult(id, {
                  content: [{ type: 'text', text: result.preset ? `Current preset: ${result.preset}` : 'No preset active (using default CCR config)' }]
                });
                break;

              default:
                sendError(id, -32601, 'Unknown tool: ' + toolName);
            }
          } catch (err) {
            sendResult(id, {
              content: [{ type: 'text', text: `Error: ${err.message}. Is CCR Menu Bar app running?` }],
              isError: true
            });
          }
        }
        """
    }

}
