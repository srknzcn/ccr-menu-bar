import SwiftUI
import AppKit

struct IntegrationsTab: View {
    @ObservedObject var mcpInstaller: MCPInstaller
    @State private var hookFeedback: FeedbackState = .none
    @State private var mcpFeedback: FeedbackState = .none
    @State private var shellFeedback: FeedbackState = .none

    enum FeedbackState { case none, success, failure }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hookCard
                mcpCard
                shellCard
            }
            .padding(24)
        }
        .onAppear { mcpInstaller.checkInstallation() }
    }

    // MARK: - ccm: Hook Card

    private var hookCard: some View {
        SettingsCard(title: "ccm: Hook", icon: "terminal", color: .orange) {
            Text("Intercepts **ccm:** commands at the Claude Code prompt for instant preset switching — no slash commands or MCP tools required.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            IntegrationStatusRow(
                label: "Hook script",
                detail: "~/.claude/hooks/ccr-switch.sh",
                isActive: mcpInstaller.hookScriptExists,
                isMonospaced: true
            )
            IntegrationStatusRow(
                label: "Claude settings",
                detail: mcpInstaller.hookRegistered ? "Registered in ~/.claude/settings.json" : "Not registered",
                isActive: mcpInstaller.hookRegistered
            )

            HStack(spacing: 8) {
                Spacer()
                feedbackLabel(hookFeedback)
                if mcpInstaller.hookInstalled {
                    IntegrationActionButton(title: "Reinstall", style: .secondary) {
                        mcpInstaller.installHook()
                        mcpInstaller.checkInstallation()
                        showFeedback({ hookFeedback = $0 }, success: mcpInstaller.hookInstalled)
                    }
                    IntegrationActionButton(title: "Uninstall", style: .destructive) {
                        mcpInstaller.uninstallHook()
                        showFeedback({ hookFeedback = $0 }, success: true)
                    }
                } else {
                    IntegrationActionButton(title: "Install", style: .primary) {
                        mcpInstaller.installHook()
                        mcpInstaller.checkInstallation()
                        showFeedback({ hookFeedback = $0 }, success: mcpInstaller.hookInstalled)
                    }
                }
            }
            .padding(.top, 4)

            usageBox(lines: ["ccm:        — show active preset", "ccm:list    — list all presets", "ccm:<name>  — switch to preset"])
        }
    }

    // MARK: - MCP Server Card

    private var mcpCard: some View {
        SettingsCard(title: "MCP Server", icon: "cpu", color: .blue) {
            Text("Provides **switch_preset**, **list_presets**, and **current_preset** tools directly inside Claude Code sessions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            IntegrationStatusRow(
                label: "Server script",
                detail: "~/.claude-code-router/ccr-mcp-server.js",
                isActive: mcpInstaller.mcpServerInstalled,
                isMonospaced: true
            )

            HStack(spacing: 8) {
                Spacer()
                feedbackLabel(mcpFeedback)
                if mcpInstaller.mcpServerInstalled {
                    IntegrationActionButton(title: "Reinstall", style: .secondary) {
                        mcpInstaller.installMCPServer()
                        mcpInstaller.checkInstallation()
                        showFeedback({ mcpFeedback = $0 }, success: mcpInstaller.mcpServerInstalled)
                    }
                    IntegrationActionButton(title: "Uninstall", style: .destructive) {
                        mcpInstaller.uninstallMCPServer()
                        showFeedback({ mcpFeedback = $0 }, success: true)
                    }
                } else {
                    IntegrationActionButton(title: "Install", style: .primary) {
                        mcpInstaller.installMCPServer()
                        mcpInstaller.checkInstallation()
                        showFeedback({ mcpFeedback = $0 }, success: mcpInstaller.mcpServerInstalled)
                    }
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("To register with Claude Code, add to ~/.claude/settings.json:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                CodeBlock(text: mcpSettingsSnippet, copyable: true)
            }
        }
    }

    // MARK: - Shell Setup Card

    private var shellCard: some View {
        SettingsCard(title: "Shell Setup", icon: "apple.terminal", color: .green) {
            Text("Adds **ccm code** for launching Claude Code through the proxy while leaving plain **claude** on the default Anthropic login.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)

            IntegrationStatusRow(
                label: "RC file",
                detail: mcpInstaller.shellRCDisplayPath,
                isActive: mcpInstaller.shellConfigured,
                isMonospaced: true
            )
            IntegrationStatusRow(
                label: "Status",
                detail: mcpInstaller.shellConfigured ? "Block present" : "Not configured",
                isActive: mcpInstaller.shellConfigured
            )

            HStack(spacing: 8) {
                Spacer()
                feedbackLabel(shellFeedback)
                if mcpInstaller.shellConfigured {
                    IntegrationActionButton(title: "Update", style: .secondary) {
                        mcpInstaller.installShellConfig()
                        showFeedback({ shellFeedback = $0 }, success: mcpInstaller.shellConfigured)
                    }
                    IntegrationActionButton(title: "Remove", style: .destructive) {
                        mcpInstaller.uninstallShellConfig()
                        showFeedback({ shellFeedback = $0 }, success: true)
                    }
                } else {
                    IntegrationActionButton(title: "Add to \(mcpInstaller.shellRCDisplayPath)", style: .primary) {
                        mcpInstaller.installShellConfig()
                        showFeedback({ shellFeedback = $0 }, success: mcpInstaller.shellConfigured)
                    }
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Block written to RC file:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                CodeBlock(text: zshrcSnippet, copyable: true)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func feedbackLabel(_ state: FeedbackState) -> some View {
        switch state {
        case .success:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .scale))
        case .failure:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red)
                .transition(.opacity.combined(with: .scale))
        case .none:
            EmptyView()
        }
    }

    private func showFeedback(_ setter: @escaping (FeedbackState) -> Void, success: Bool) {
        withAnimation { setter(success ? .success : .failure) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { setter(.none) }
        }
    }

    private func usageBox(lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private var mcpSettingsSnippet: String {
        """
        {
          "mcpServers": {
            "ccr-presets": {
              "command": "node",
              "args": ["~/.claude-code-router/ccr-mcp-server.js"]
            }
          }
        }
        """
    }

    private var zshrcSnippet: String {
        """
        unset ANTHROPIC_BASE_URL
        [[ "$ANTHROPIC_API_KEY" == "any-value" ]] && unset ANTHROPIC_API_KEY

        ccm() {
          if [[ "$1" == "code" ]]; then
            shift
            local session="${CCR_SESSION:-$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' | cut -c1-16)}"
            CCR_SESSION="$session" \\
            ANTHROPIC_BASE_URL="http://localhost:3457/s/$session" \\
            ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-any-value}" \\
            claude "$@"
          else
            command ccr "$@"
          fi
        }
        """
    }
}

// MARK: - IntegrationStatusRow

private struct IntegrationStatusRow: View {
    let label: String
    let detail: String
    var isActive: Bool
    var isMonospaced: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)

            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)

            Text(detail)
                .font(isMonospaced ? .system(size: 11, design: .monospaced) : .system(size: 12))
                .foregroundStyle(isActive ? .primary : .secondary)

            Spacer()
        }
    }
}

// MARK: - IntegrationActionButton

private struct IntegrationActionButton: View {
    enum Style { case primary, secondary, destructive }

    let title: String
    let style: Style
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(backgroundColor)
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return .primary
        case .destructive: return .red
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:   return .blue.opacity(isHovered ? 0.85 : 1)
        case .secondary: return .primary.opacity(isHovered ? 0.1 : 0.06)
        case .destructive: return .red.opacity(isHovered ? 0.15 : 0.08)
        }
    }
}

// MARK: - CodeBlock

private struct CodeBlock: View {
    let text: String
    var copyable: Bool = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(copied ? .green : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .padding([.top, .trailing], 8)
            }

            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, copyable ? 4 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
