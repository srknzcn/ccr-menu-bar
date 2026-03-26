// CCRMenuBar/Views/TokenUsageView.swift
import SwiftUI

struct ProviderUsage: Identifiable {
    let provider: String
    var models: [ModelUsage]
    var totalStats: TokenStats
    var id: String { provider }
}

struct TokenUsageView: View {
    @ObservedObject var usageService: TokenUsageService
    var providers: [Provider] = []

    private var displayStats: TokenStats {
        usageService.todayStats.requestCount > 0 ? usageService.todayStats : usageService.allTimeStats
    }

    private var providerBreakdown: [ProviderUsage] {
        // Build model → provider mapping from config
        var modelToProvider: [String: String] = [:]
        for provider in providers {
            for model in provider.models {
                modelToProvider[model] = provider.name
            }
        }

        // Group model usage by provider
        var byProvider: [String: [ModelUsage]] = [:]
        for usage in usageService.modelBreakdown {
            let providerName = modelToProvider[usage.model] ?? "Unknown"
            byProvider[providerName, default: []].append(usage)
        }

        return byProvider.map { name, models in
            let total = models.reduce(into: TokenStats()) { result, m in
                result.inputTokens += m.stats.inputTokens
                result.outputTokens += m.stats.outputTokens
                result.requestCount += m.stats.requestCount
            }
            return ProviderUsage(
                provider: name,
                models: models.sorted { $0.stats.requestCount > $1.stats.requestCount },
                totalStats: total
            )
        }
        .sorted { $0.totalStats.requestCount > $1.totalStats.requestCount }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Summary pills
            HStack(spacing: 0) {
                TokenPill(label: "IN", value: displayStats.formattedInput, color: .blue)
                Spacer()
                TokenPill(label: "OUT", value: "~\(displayStats.formattedOutput)", color: .green)
                Spacer()
                TokenPill(label: "REQS", value: "\(displayStats.requestCount)", color: .orange)
            }

            // Per-provider/model breakdown
            if !providerBreakdown.isEmpty {
                VStack(spacing: 6) {
                    ForEach(providerBreakdown) { providerUsage in
                        VStack(spacing: 2) {
                            // Provider header
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 4))
                                    .foregroundStyle(providerColor(providerUsage.provider))

                                Text(providerUsage.provider.uppercased())
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(providerColor(providerUsage.provider).opacity(0.9))
                                    .tracking(0.5)

                                Spacer()

                                Text(providerUsage.totalStats.formattedInput)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.blue.opacity(0.6))

                                Text("/")
                                    .foregroundStyle(.quaternary)
                                    .font(.system(size: 8))

                                Text("~\(providerUsage.totalStats.formattedOutput)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.6))

                                Text("(\(providerUsage.totalStats.requestCount))")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                            }

                            // Model rows under provider
                            ForEach(providerUsage.models.prefix(3)) { usage in
                                HStack(spacing: 6) {
                                    Text(shortModelName(usage.model))
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .padding(.leading, 10)

                                    Spacer()

                                    Text(usage.stats.formattedInput)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.blue.opacity(0.8))

                                    Text("/")
                                        .foregroundStyle(.quaternary)
                                        .font(.system(size: 9))

                                    Text("~\(usage.stats.formattedOutput)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.green.opacity(0.8))

                                    Text("(\(usage.stats.requestCount))")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        }
    }

    private func shortModelName(_ name: String) -> String {
        var short = name
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
            .replacingOccurrences(of: "-20250514", with: "")
        if short.count > 20 {
            short = String(short.prefix(20))
        }
        return short
    }

    private func providerColor(_ name: String) -> Color {
        let lowered = name.lowercased()
        if lowered.contains("anthropic") { return .purple }
        if lowered.contains("openai") { return .green }
        if lowered.contains("google") || lowered.contains("gemini") || lowered.contains("vertex") { return .blue }
        if lowered.contains("deepseek") { return .cyan }
        if lowered.contains("openrouter") { return .orange }
        if lowered.contains("groq") { return .red }
        // Hash-based fallback
        let colors: [Color] = [.pink, .indigo, .mint, .teal, .yellow]
        let hash = abs(name.hashValue) % colors.count
        return colors[hash]
    }
}

struct TokenPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color.opacity(0.7))

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.08), in: Capsule())
    }
}
