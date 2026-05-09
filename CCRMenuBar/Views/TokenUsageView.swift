// CCRMenuBar/Views/TokenUsageView.swift
import SwiftUI

struct TokenUsageView: View {
    @ObservedObject var usageService: TokenUsageService
    let openProjectUsage: () -> Void
    @State private var selectedUsageRange: UsageChartRange = .day
    @State private var selectedGrouping: UsageGrouping = .model

    private var displayStats: TokenStats {
        if shouldShowRangeControls {
            return visibleModelBreakdown.reduce(into: TokenStats()) { result, usage in
                result.inputTokens += usage.stats.inputTokens
                result.outputTokens += usage.stats.outputTokens
                result.providerPromptTokens += usage.stats.providerPromptTokens
                result.providerCacheReadTokens += usage.stats.providerCacheReadTokens
                result.providerCacheCreationTokens += usage.stats.providerCacheCreationTokens
                result.requestCount += usage.stats.requestCount
            }
        }
        return usageService.todayStats.requestCount > 0 ? usageService.todayStats : usageService.allTimeStats
    }

    private var displayCostUSD: Double? {
        if shouldShowRangeControls {
            let costs = visibleModelBreakdown.compactMap(\.costUSD)
            return costs.isEmpty ? nil : costs.reduce(0, +)
        }
        return usageService.todayStats.requestCount > 0 ? usageService.todayCostUSD : usageService.allTimeCostUSD
    }

    private var visibleModelBreakdown: [ModelUsage] {
        guard shouldShowRangeControls else { return usageService.modelBreakdown }
        return modelBreakdown(for: selectedUsageRange)
    }

    private var providerCostBreakdown: [ProviderCostUsage] {
        var providers: [String: (cost: Double, hasCost: Bool)] = [:]

        for usage in visibleModelBreakdown {
            let provider = usage.provider ?? "Unknown"
            guard let cost = usage.costUSD else {
                providers[provider] = providers[provider] ?? (0, false)
                continue
            }
            let existing = providers[provider] ?? (0, false)
            providers[provider] = (existing.cost + cost, true)
        }

        return providers.map { ProviderCostUsage(provider: $0.key, costUSD: $0.value.hasCost ? $0.value.cost : nil) }
            .sorted {
                switch ($0.costUSD, $1.costUSD) {
                case let (left?, right?) where left != right:
                    return left > right
                case (.some, nil):
                    return true
                case (nil, .some):
                    return false
                default:
                    return $0.provider.localizedCaseInsensitiveCompare($1.provider) == .orderedAscending
                }
            }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Summary pills
            HStack(spacing: 6) {
                TokenPill(label: "IN", value: displayStats.formattedInput, color: .blue) {
                    openProjectUsage()
                }
                    .frame(maxWidth: .infinity)
                TokenPill(label: "OUT", value: "~\(displayStats.formattedOutput)", color: .green) {
                    openProjectUsage()
                }
                    .frame(maxWidth: .infinity)
                TokenPill(label: "AVG", value: displayStats.formattedAverageProviderPrompt, color: .purple) {
                    openProjectUsage()
                }
                    .frame(maxWidth: .infinity)
                if let displayCostUSD {
                    TokenPill(label: "USD", value: formattedCost(displayCostUSD), color: .yellow)
                        .frame(maxWidth: .infinity)
                }
            }

            if usageService.liveGeneration.isVisible {
                liveGenerationRow(usageService.liveGeneration)
            }

            if shouldShowRangeControls {
                HStack(spacing: 6) {
                    Picker("", selection: $selectedUsageRange) {
                        ForEach(UsageChartRange.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    Picker("", selection: $selectedGrouping) {
                        ForEach(UsageGrouping.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)

                    Button {
                        usageService.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                    .help("Refresh usage")
                }
            }

            if !visibleModelBreakdown.isEmpty {
                VStack(spacing: 8) {
                    if selectedGrouping == .model {
                        ForEach(visibleModelBreakdown.prefix(5)) { usage in
                            modelUsageRow(usage)
                        }
                    } else {
                        ForEach(providerCostBreakdown.prefix(5)) { usage in
                            providerCostRow(usage)
                        }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 2)
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func liveGenerationRow(_ snapshot: LiveTokenGenerationSnapshot) -> some View {
        VStack(spacing: 4) {
            ForEach(Array(snapshot.models.prefix(4))) { model in
                HStack(spacing: 8) {
                    Circle()
                        .fill(snapshot.isActive ? Color.green : Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)

                    Image(systemName: "speedometer")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green.opacity(0.85))
                        .frame(width: 14)

                    Text("LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.green.opacity(0.8))

                    Text(liveContextLabel(model))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if model.requestCount > 1 {
                        Text("x\(model.requestCount)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))
                    }

                    Spacer(minLength: 6)

                    Text(formattedTokensPerSecond(model.tokensPerSecond))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("tok/s")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)

                    Text("~\(formatTokenCount(model.outputTokens))")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.08), in: Capsule())
            }

            if snapshot.models.count > 4 {
                Text("+\(snapshot.models.count - 4) more live models")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
            }
        }
        .help(snapshot.isActive ? "Estimated live output token generation" : "Last completed generation rate")
    }

    @ViewBuilder
    private func modelUsageRow(_ usage: ModelUsage) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "cpu")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(shortUsageName(usage))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.cyan.opacity(0.9))
                    .tracking(0.4)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    Text(usage.stats.formattedInput)
                        .foregroundStyle(.blue.opacity(0.75))

                    Text("/")
                        .foregroundStyle(.quaternary)

                    Text("~\(usage.stats.formattedOutput)")
                        .foregroundStyle(.green.opacity(0.75))

                    Text("(\(usage.stats.requestCount))")
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 9, design: .monospaced))
            }

            Spacer(minLength: 6)

            Text(costLabel(for: usage.costUSD))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(usage.costUSD == nil ? Color.secondary.opacity(0.45) : Color.yellow.opacity(0.9))
                .lineLimit(1)
                .help(costHelp(for: usage))
        }
    }

    @ViewBuilder
    private func providerCostRow(_ usage: ProviderCostUsage) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "server.rack")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 16)

            Text(shortName(usage.provider, limit: 22))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.orange.opacity(0.9))
                .tracking(0.4)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(costLabel(for: usage.costUSD))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(usage.costUSD == nil ? Color.secondary.opacity(0.45) : Color.yellow.opacity(0.9))
                .lineLimit(1)
        }
    }

    private var shouldShowRangeControls: Bool {
        !usageService.modelUsageSamples.isEmpty
    }

    private func modelBreakdown(for range: UsageChartRange) -> [ModelUsage] {
        let interval = range.interval()
        var models: [String: (provider: String, model: String, stats: TokenStats)] = [:]

        for sample in usageService.modelUsageSamples where interval.contains(sample.timestamp) {
            let key = "\(sample.provider)/\(sample.model)"
            var entry = models[key] ?? (sample.provider, sample.model, TokenStats())
            entry.stats.inputTokens += sample.stats.inputTokens
            entry.stats.outputTokens += sample.stats.outputTokens
            entry.stats.providerPromptTokens += sample.stats.providerPromptTokens
            entry.stats.providerCacheReadTokens += sample.stats.providerCacheReadTokens
            entry.stats.providerCacheCreationTokens += sample.stats.providerCacheCreationTokens
            entry.stats.requestCount += sample.stats.requestCount
            models[key] = entry
        }

        return models.values.map { entry in
            ModelUsage(
                provider: entry.provider,
                model: entry.model,
                stats: entry.stats,
                costUSD: usageService.estimatedCostUSD(provider: entry.provider, model: entry.model, stats: entry.stats)
            )
        }
        .sorted {
            switch ($0.costUSD, $1.costUSD) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let leftTokens = $0.stats.inputTokens + $0.stats.outputTokens
                let rightTokens = $1.stats.inputTokens + $1.stats.outputTokens
                if leftTokens != rightTokens {
                    return leftTokens > rightTokens
                }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            }
        }
    }

    private func shortUsageName(_ usage: ModelUsage) -> String {
        let provider = usage.provider.map { shortName($0, limit: 10) }
        let model = shortName(usage.model, limit: provider == nil ? 26 : 18)
        guard let provider else { return model }
        return "\(provider) / \(model)"
    }

    private func costLabel(for cost: Double?) -> String {
        guard let cost else {
            return usageService.pricingUpdatedAt == nil && usageService.pricingError == nil ? "..." : "N/A"
        }
        return formattedCost(cost)
    }

    private func costHelp(for usage: ModelUsage) -> String {
        if usage.costUSD != nil {
            return "Estimated spend from model token pricing"
        }
        if let pricingError = usageService.pricingError {
            return "Pricing unavailable: \(pricingError)"
        }
        if usageService.pricingUpdatedAt == nil {
            return "Loading model pricing"
        }
        return "No matching price for this provider/model"
    }

    private func formattedCost(_ cost: Double) -> String {
        if cost == 0 {
            return "$0.0000"
        }
        if cost < 0.0001 {
            return String(format: "$%.6f", cost)
        }
        if cost < 1 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    private func shortName(_ name: String, limit: Int) -> String {
        var short = name
            .replacingOccurrences(of: "claude-", with: "")
            .replacingOccurrences(of: "-20251001", with: "")
            .replacingOccurrences(of: "-20250514", with: "")
        if short.count > limit {
            short = String(short.prefix(limit))
        }
        return short
    }

    private func liveContextLabel(_ model: LiveModelTokenGeneration) -> String {
        let modelName = shortName(model.model, limit: 18)
        guard let provider = model.provider, provider != "Unknown" else {
            return modelName
        }
        return "\(shortName(provider, limit: 8)) / \(modelName)"
    }

    private func formattedTokensPerSecond(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

struct ProviderCostUsage: Identifiable {
    let provider: String
    let costUSD: Double?

    var id: String { provider }
}

struct ProjectUsageDetailView: View {
    let projects: [ProjectUsage]
    let refresh: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.blue)

                Text("Project Usage")
                    .font(.system(size: 15, weight: .bold))

                Spacer()

                Button {
                    refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Close")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                    Text("No project usage yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(projects) { project in
                            ProjectUsageRow(project: project)
                            Divider()
                                .padding(.leading, 14)
                        }
                    }
                }
            }
        }
        .frame(width: 640, height: 420)
    }
}

private struct ProjectUsageRow: View {
    let project: ProjectUsage

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: project.isGitRepository ? "arrow.triangle.branch" : "folder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(project.isGitRepository ? .green : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)

                Text(project.gitRoot ?? project.path ?? "Unknown path")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            metric(label: "AVG IN", value: project.stats.formattedAverageInput, color: .blue)
            metric(label: "AVG OUT", value: "~\(project.stats.formattedAverageOutput)", color: .green)
            metric(label: "AVG", value: project.stats.formattedAverageProviderPrompt, color: .purple)
            metric(label: "REQ", value: "\(project.stats.requestCount)", color: .gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func metric(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color.opacity(0.75))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: 54, alignment: .trailing)
    }
}

enum UsageGrouping: String, CaseIterable, Identifiable {
    case model
    case provider

    var id: String { rawValue }

    var label: String {
        switch self {
        case .model: return "Model"
        case .provider: return "Provider"
        }
    }
}

enum UsageChartRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Daily"
        case .week: return "Weekly"
        case .month: return "Monthly"
        }
    }

    func interval(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> DateInterval {
        switch self {
        case .day:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 1, to: start) ?? now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 7 * 24 * 3600)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 30 * 24 * 3600)
        }
    }
}

struct TokenPill: View {
    let label: String
    let value: String
    let color: Color
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color.opacity(0.7))

            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08), in: Capsule())
        .contentShape(Capsule())

        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
            .help("Open project usage")
        } else {
            content
        }
    }
}
