// CCRMenuBar/Services/TokenUsageService.swift
import Foundation
import Combine

struct TokenStats: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var requestCount: Int = 0
    var providerPromptTokens: Int = 0
    var cacheSavingsTokens: Int = 0
    var providerCacheReadTokens: Int = 0
    var providerCacheCreationTokens: Int = 0
}

struct ModelUsage: Equatable, Identifiable {
    let provider: String?
    let model: String
    var stats: TokenStats
    var costUSD: Double?
    var id: String { "\(provider ?? "Unknown")/\(model)" }
}

struct ProviderUsage: Equatable, Identifiable {
    let provider: String
    var models: [ModelUsage]
    var totalStats: TokenStats
    var totalCostUSD: Double?
    var id: String { provider }
}

struct ModeUsage: Equatable, Identifiable {
    let mode: String
    var stats: TokenStats
    var id: String { mode }
}

struct ModelUsageSample: Equatable, Identifiable {
    let timestamp: Date
    let provider: String
    let model: String
    var stats: TokenStats
    let projectName: String?
    let projectPath: String?

    var id: String { "\(timestamp.timeIntervalSince1970)-\(provider)-\(model)-\(projectPath ?? "unknown")" }
}

struct ProjectUsage: Equatable, Identifiable {
    let name: String
    let path: String?
    let gitRoot: String?
    let isGitRepository: Bool
    var stats: TokenStats

    var id: String { path ?? name }
}

struct LiveModelTokenGeneration: Equatable, Identifiable {
    let provider: String?
    let model: String
    var outputTokens: Int
    var tokensPerSecond: Double
    var requestCount: Int

    var id: String { "\(provider ?? "Unknown")/\(model)" }
}

struct LiveTokenGenerationSnapshot: Equatable {
    var isActive = false
    var models: [LiveModelTokenGeneration] = []
    var updatedAt: Date?

    var outputTokens: Int {
        models.reduce(0) { $0 + $1.outputTokens }
    }

    var tokensPerSecond: Double {
        models.reduce(0) { $0 + $1.tokensPerSecond }
    }

    var isVisible: Bool {
        isActive && outputTokens > 0
    }
}

@MainActor
final class LiveTokenGenerationMeter: ObservableObject {
    static let shared = LiveTokenGenerationMeter()

    @Published private(set) var snapshot = LiveTokenGenerationSnapshot()

    private struct ActiveRequest {
        let context: ProxyUsageLogContext
        let provider: String?
        let model: String
        var outputTokens = 0
        var samples: [(date: Date, tokens: Int)] = []
    }

    private var activeRequests: [String: ActiveRequest] = [:]
    private let sampleWindow: TimeInterval = 3
    private let statusFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-code-router/ccr-live-status.json")
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {}

    nonisolated static func snapshot(fromStatusData data: Data, now: Date = Date()) -> LiveTokenGenerationSnapshot? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let isActive = json["isActive"] as? Bool ?? false
        let updatedAt = (json["updatedAt"] as? String).flatMap { rawValue -> Date? in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: rawValue)
        }

        guard isActive else { return nil }

        let modelItems = json["models"] as? [[String: Any]] ?? []
        let models = modelItems.compactMap { item -> LiveModelTokenGeneration? in
            guard let model = item["model"] as? String else { return nil }
            return LiveModelTokenGeneration(
                provider: item["provider"] as? String,
                model: model,
                outputTokens: item["outputTokens"] as? Int ?? 0,
                tokensPerSecond: item["tokensPerSecond"] as? Double ?? 0,
                requestCount: item["requestCount"] as? Int ?? 1
            )
        }

        guard !models.isEmpty else { return nil }
        return LiveTokenGenerationSnapshot(isActive: isActive, models: models, updatedAt: updatedAt ?? now)
    }

    nonisolated static func begin(context: ProxyUsageLogContext) {
        Task { @MainActor in
            shared.beginOnMain(context: context)
        }
    }

    nonisolated static func ingestChunk(requestId: String, data: Data) {
        let tokenDelta = estimatedOutputTokens(from: data)
        guard tokenDelta > 0 else { return }
        Task { @MainActor in
            shared.ingestOnMain(requestId: requestId, tokenDelta: tokenDelta)
        }
    }

    nonisolated static func finish(requestId: String, finalOutputTokens: Int? = nil) {
        Task { @MainActor in
            shared.finishOnMain(requestId: requestId, finalOutputTokens: finalOutputTokens)
        }
    }

    private func beginOnMain(context: ProxyUsageLogContext) {
        activeRequests[context.requestId] = ActiveRequest(
            context: context,
            provider: context.provider,
            model: context.liveModelName
        )
        publishActiveSnapshot()
        writeStatusFile()
    }

    private func ingestOnMain(requestId: String, tokenDelta: Int) {
        guard var request = activeRequests[requestId] else { return }
        let now = Date()
        request.outputTokens += tokenDelta
        request.samples.append((now, tokenDelta))
        request.samples.removeAll { now.timeIntervalSince($0.date) > sampleWindow }
        activeRequests[requestId] = request

        publishActiveSnapshot()
        writeStatusFile()
    }

    private func finishOnMain(requestId: String, finalOutputTokens: Int?) {
        guard let request = activeRequests.removeValue(forKey: requestId) else { return }
        let outputTokens = max(finalOutputTokens ?? request.outputTokens, request.outputTokens)
        let duration = max(Date().timeIntervalSince(request.context.startedAt), 0.25)
        let completedModel = LiveModelTokenGeneration(
            provider: request.provider,
            model: request.model,
            outputTokens: outputTokens,
            tokensPerSecond: Double(outputTokens) / duration,
            requestCount: 1
        )

        if activeRequests.isEmpty {
            snapshot = LiveTokenGenerationSnapshot(isActive: false, models: [completedModel], updatedAt: Date())
        } else {
            publishActiveSnapshot()
        }
        writeStatusFile(completedRequest: request, completedModel: completedModel)
    }

    private func publishActiveSnapshot() {
        let now = Date()
        var grouped: [String: LiveModelTokenGeneration] = [:]

        for request in activeRequests.values {
            let recentTokens = request.samples.reduce(0) { $0 + $1.tokens }
            let oldest = request.samples.first?.date ?? now
            let elapsed = max(now.timeIntervalSince(oldest), 0.25)
            let key = "\(request.provider ?? "Unknown")/\(request.model)"
            var entry = grouped[key] ?? LiveModelTokenGeneration(
                provider: request.provider,
                model: request.model,
                outputTokens: 0,
                tokensPerSecond: 0,
                requestCount: 0
            )
            entry.outputTokens += request.outputTokens
            entry.tokensPerSecond += Double(recentTokens) / elapsed
            entry.requestCount += 1
            grouped[key] = entry
        }

        snapshot = LiveTokenGenerationSnapshot(
            isActive: !activeRequests.isEmpty,
            models: grouped.values.sorted {
                if $0.tokensPerSecond != $1.tokensPerSecond {
                    return $0.tokensPerSecond > $1.tokensPerSecond
                }
                if $0.outputTokens != $1.outputTokens {
                    return $0.outputTokens > $1.outputTokens
                }
                return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
            },
            updatedAt: now
        )
    }

    private func writeStatusFile(completedRequest: ActiveRequest? = nil, completedModel: LiveModelTokenGeneration? = nil) {
        let now = Date()
        var sessionEntries: [[String: Any]] = []

        for request in activeRequests.values {
            sessionEntries.append(statusEntry(
                session: request.context.session,
                provider: request.provider,
                model: request.model,
                outputTokens: request.outputTokens,
                tokensPerSecond: tokensPerSecond(for: request, now: now),
                requestCount: 1
            ))
        }

        if let completedRequest, let completedModel {
            sessionEntries.append(statusEntry(
                session: completedRequest.context.session,
                provider: completedModel.provider,
                model: completedModel.model,
                outputTokens: completedModel.outputTokens,
                tokensPerSecond: completedModel.tokensPerSecond,
                requestCount: completedModel.requestCount
            ))
        }

        let modelEntries = snapshot.models.map { model in
            statusEntry(
                session: nil,
                provider: model.provider,
                model: model.model,
                outputTokens: model.outputTokens,
                tokensPerSecond: model.tokensPerSecond,
                requestCount: model.requestCount
            )
        }

        let payload: [String: Any] = [
            "isActive": snapshot.isActive,
            "updatedAt": isoFormatter.string(from: now),
            "outputTokens": snapshot.outputTokens,
            "tokensPerSecond": snapshot.tokensPerSecond,
            "sessions": sessionEntries,
            "models": modelEntries,
        ]

        do {
            try FileManager.default.createDirectory(
                at: statusFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: statusFileURL, options: .atomic)
        } catch {
            // Statusline export is best-effort; never block proxy streaming.
        }
    }

    private func statusEntry(
        session: String?,
        provider: String?,
        model: String,
        outputTokens: Int,
        tokensPerSecond: Double,
        requestCount: Int
    ) -> [String: Any] {
        [
            "session": session ?? NSNull(),
            "provider": provider ?? NSNull(),
            "model": model,
            "outputTokens": outputTokens,
            "tokensPerSecond": tokensPerSecond,
            "requestCount": requestCount,
        ]
    }

    private func tokensPerSecond(for request: ActiveRequest, now: Date) -> Double {
        let recentTokens = request.samples.reduce(0) { $0 + $1.tokens }
        let oldest = request.samples.first?.date ?? now
        let elapsed = max(now.timeIntervalSince(oldest), 0.25)
        return Double(recentTokens) / elapsed
    }

    nonisolated static func estimatedOutputTokens(from data: Data) -> Int {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            return data.isEmpty ? 0 : max(data.count / 4, 1)
        }

        var emittedCharacters = 0
        var sawSSEData = false
        for rawLine in text.components(separatedBy: .newlines) {
            guard rawLine.hasPrefix("data:") else { continue }
            sawSSEData = true
            let payload = rawLine.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard payload != "[DONE]",
                  let payloadData = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
                continue
            }
            emittedCharacters += emittedCharacterCount(in: json)
        }

        if emittedCharacters > 0 {
            return max(emittedCharacters / 4, 1)
        }
        return sawSSEData ? 0 : max(text.count / 4, 1)
    }

    private nonisolated static func emittedCharacterCount(in value: Any) -> Int {
        if let dict = value as? [String: Any] {
            var count = 0
            if let delta = dict["delta"] as? [String: Any] {
                count += (delta["text"] as? String)?.count ?? 0
                count += (delta["partial_json"] as? String)?.count ?? 0
            }
            if let contentBlock = dict["content_block"] as? [String: Any] {
                count += (contentBlock["text"] as? String)?.count ?? 0
            }
            return count + dict.values.reduce(0) { $0 + emittedCharacterCount(in: $1) }
        }
        if let array = value as? [Any] {
            return array.reduce(0) { $0 + emittedCharacterCount(in: $1) }
        }
        return 0
    }
}

private extension ProxyUsageLogContext {
    var liveModelName: String {
        model ?? requestModel ?? "Unknown"
    }
}

@MainActor
class TokenUsageService: ObservableObject {
    @Published var todayStats = TokenStats()
    @Published var allTimeStats = TokenStats()
    @Published var modelBreakdown: [ModelUsage] = []
    @Published var providerStats: [ProviderUsage] = []
    @Published var modeStats: [ModeUsage] = []
    @Published var modelUsageSamples: [ModelUsageSample] = []
    @Published var projectBreakdown: [ProjectUsage] = []
    @Published var todayCostUSD: Double?
    @Published var allTimeCostUSD: Double?
    @Published var todayProviderCostsUSD: [String: Double] = [:]
    @Published var pricingUpdatedAt: Date?
    @Published var pricingError: String?
    @Published var isPricingRefreshing = false
    @Published var liveGeneration = LiveTokenGenerationSnapshot()

    var providers: [Provider] = []
    var router: RouterConfig?

    private var timer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private let logsPath: String
    private var pricing: [ModelTokenPrice] = []
    private var priceLookupCache: [String: ModelTokenPrice] = [:]
    private var priceLookupMisses: Set<String> = []
    private var pricingFetchTask: Task<Void, Never>?
    private let pricingRefreshInterval: TimeInterval = ModelPricingService.cacheRefreshInterval
    private var lastPeriodicUsageRefresh = Date.distantPast
    private let usageFallbackRefreshInterval: TimeInterval = 30
    private let liveStatusFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-code-router/ccr-live-status.json")

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        logsPath = "\(home)/.claude-code-router/logs"
        LiveTokenGenerationMeter.shared.$snapshot
            .sink { [weak self] snapshot in
                self?.setLiveGeneration(snapshot)
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UsageLogStore.didAppendNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshUsageNow()
            }
            .store(in: &cancellables)
        refreshLiveGenerationFromStatusFile()
        parseLogs()
        startPolling()
        refreshPricingIfNeeded(force: true)
    }

    deinit {
        timer?.invalidate()
        pricingFetchTask?.cancel()
    }

    func refresh() {
        refreshUsageNow()
        refreshPricingIfNeeded(force: false)
    }

    func refreshPricingCache() {
        refreshPricingIfNeeded(force: true, forceCacheRefresh: true, allowStaleFallback: false)
    }

    func estimatedCostUSD(provider: String?, model: String, stats: TokenStats) -> Double? {
        costUSD(provider: provider, model: model, stats: stats)
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                let snapshot = LiveTokenGenerationMeter.shared.snapshot.isVisible
                    ? LiveTokenGenerationMeter.shared.snapshot
                    : (self.snapshotFromStatusFile() ?? LiveTokenGenerationMeter.shared.snapshot)
                self.setLiveGeneration(snapshot)
                if Date().timeIntervalSince(self.lastPeriodicUsageRefresh) >= self.usageFallbackRefreshInterval {
                    self.refreshUsageNow()
                    self.refreshPricingIfNeeded(force: false)
                }
            }
        }
    }

    private func refreshUsageNow() {
        lastPeriodicUsageRefresh = Date()
        refreshLiveGenerationFromStatusFile()
        parseLogs()
    }

    private func refreshLiveGenerationFromStatusFile() {
        if !LiveTokenGenerationMeter.shared.snapshot.isVisible,
           let statusSnapshot = snapshotFromStatusFile() {
            setLiveGeneration(statusSnapshot)
        }
    }

    private func setLiveGeneration(_ snapshot: LiveTokenGenerationSnapshot) {
        guard liveGeneration != snapshot else { return }
        liveGeneration = snapshot
    }

    private func snapshotFromStatusFile() -> LiveTokenGenerationSnapshot? {
        guard let data = try? Data(contentsOf: liveStatusFileURL) else { return nil }
        return LiveTokenGenerationMeter.snapshot(fromStatusData: data)
    }

    private func refreshPricingIfNeeded(
        force: Bool,
        forceCacheRefresh: Bool = false,
        allowStaleFallback: Bool = true
    ) {
        if pricingFetchTask != nil { return }
        if !force, let pricingUpdatedAt,
           Date().timeIntervalSince(pricingUpdatedAt) < pricingRefreshInterval {
            return
        }

        pricingFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.loadPricing(forceRefresh: forceCacheRefresh, allowStaleFallback: allowStaleFallback)
        }
    }

    private func loadPricing(forceRefresh: Bool, allowStaleFallback: Bool) async {
        isPricingRefreshing = true
        do {
            let prices = try await ModelPricingService.fetchPrices(
                forceRefresh: forceRefresh,
                allowStaleFallback: allowStaleFallback
            )
            pricing = prices
            priceLookupCache.removeAll()
            priceLookupMisses.removeAll()
            pricingUpdatedAt = Date()
            pricingError = nil
        } catch {
            pricingError = error.localizedDescription
        }

        isPricingRefreshing = false
        pricingFetchTask = nil
        parseLogs()
    }

    private func parseLogs() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: logsPath)) ?? []

        let today = todayPrefix()
        let logFiles = files.filter { $0.hasSuffix(".log") }.sorted()

        var allStats = TokenStats()
        var dayStats = TokenStats()

        // Track request metadata
        struct ReqInfo {
            let model: String
            let isToday: Bool
            let day: Date
            var timestamp: Date
            var mode: String = "default"
            var inputTokens: Int = 0
            var outputTokens: Int = 0
            var providerPromptTokens: Int = 0
            var providerCacheReadTokens: Int = 0
            var providerCacheCreationTokens: Int = 0
            var providerName: String?
            var providerUrl: String?
            var projectName: String?
            var projectPath: String?
            var gitRoot: String?
            var isGitRepository: Bool = false
            var promptCacheKey: String?
            var promptCacheCandidateTokens: Int = 0
        }
        var requests: [String: ReqInfo] = [:]

        // Build provider mapping
        var urlToProvider: [String: String] = [:]
        for provider in providers {
            urlToProvider[provider.api_base_url] = provider.name
        }

        for file in logFiles {
            let isToday = file.contains(today)
            let requestDay = Self.dayDate(fromLogFileName: file) ?? Date()
            let path = "\(logsPath)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

                let reqId = entry["reqId"] as? String
                let entryDate = Self.date(fromLogEntry: entry) ?? requestDay

                if let msg = entry["msg"] as? String, msg == "final request",
                   let rid = reqId, let url = entry["requestUrl"] as? String {
                    var info = requests[rid] ?? ReqInfo(model: "Unknown", isToday: isToday, day: requestDay, timestamp: entryDate)
                    info.providerUrl = url
                    requests[rid] = info
                }

                if let body = entry["data"] as? [String: Any],
                   let model = body["model"] as? String {
                    let messages = body["messages"] as? [[String: Any]] ?? []
                    let system = body["system"] as? [[String: Any]] ?? []
                    let input = max((estimateContentSize(messages) + estimateContentSize(system)) / 3, 1)
                    let mode = Self.detectMode(in: body, inputTokens: input, longContextThreshold: router?.longContextThreshold)

                    allStats.inputTokens += input
                    allStats.providerPromptTokens += input
                    allStats.requestCount += 1
                    if isToday {
                        dayStats.inputTokens += input
                        dayStats.providerPromptTokens += input
                        dayStats.requestCount += 1
                    }

                    if let rid = reqId {
                       var info = requests[rid] ?? ReqInfo(model: model, isToday: isToday, day: requestDay, timestamp: entryDate)
                       info.inputTokens = input
                       info.providerPromptTokens = input
                       info.timestamp = entryDate
                       info.mode = mode
                       // Eğer 'final request' daha önce geldiyse model adını güncelle
                       if info.model == "Unknown" {
                           // Yeniden oluştur çünkü struct immutable
                           requests[rid] = ReqInfo(model: model, isToday: isToday, day: info.day, timestamp: info.timestamp, mode: mode, inputTokens: input, outputTokens: info.outputTokens, providerPromptTokens: input, providerName: info.providerName, providerUrl: info.providerUrl)
                       } else {
                           requests[rid] = info
                       }
                    }
                }

                if let msg = entry["msg"] as? String, msg == "request completed",
                   let rid = reqId, var info = requests[rid],
                   let res = entry["res"] as? [String: Any],
                   let statusCode = res["statusCode"] as? Int, statusCode == 200,
                   let responseTime = entry["responseTime"] as? Double {
                    let output = Int(responseTime / 1000.0 * 50)
                    if output > 5 {
                        allStats.outputTokens += output
                        if info.isToday { dayStats.outputTokens += output }
                        info.outputTokens = output
                        requests[rid] = info
                    }
                }
            }
        }

        let storedEvents = UsageLogStore.fetchEvents()
        if !storedEvents.isEmpty {
            allStats = TokenStats()
            dayStats = TokenStats()
            requests.removeAll()

            for event in storedEvents where event.statusCode >= 200 && event.statusCode < 300 {
                let isToday = Calendar.autoupdatingCurrent.isDateInToday(event.startedAt)
                allStats.inputTokens += event.inputTokens
                allStats.outputTokens += event.outputTokens
                allStats.providerPromptTokens += event.providerPromptTokens
                allStats.providerCacheReadTokens += event.providerCacheReadTokens
                allStats.providerCacheCreationTokens += event.providerCacheCreationTokens
                allStats.requestCount += 1
                if isToday {
                    dayStats.inputTokens += event.inputTokens
                    dayStats.outputTokens += event.outputTokens
                    dayStats.providerPromptTokens += event.providerPromptTokens
                    dayStats.providerCacheReadTokens += event.providerCacheReadTokens
                    dayStats.providerCacheCreationTokens += event.providerCacheCreationTokens
                    dayStats.requestCount += 1
                }

                requests[event.requestId] = ReqInfo(
                    model: event.model ?? event.requestModel ?? "Unknown",
                    isToday: isToday,
                    day: Calendar.autoupdatingCurrent.startOfDay(for: event.startedAt),
                    timestamp: event.startedAt,
                    mode: event.route,
                    inputTokens: event.inputTokens,
                    outputTokens: event.outputTokens,
                    providerPromptTokens: event.providerPromptTokens,
                    providerCacheReadTokens: event.providerCacheReadTokens,
                    providerCacheCreationTokens: event.providerCacheCreationTokens,
                    providerName: event.provider ?? "Unknown",
                    providerUrl: nil,
                    projectName: event.projectName,
                    projectPath: event.projectPath,
                    gitRoot: event.gitRoot,
                    isGitRepository: event.isGitRepository,
                    promptCacheKey: event.promptCacheKey,
                    promptCacheCandidateTokens: event.promptCacheCandidateTokens
                )
            }
        }

        if allTimeStats != allStats {
            allTimeStats = allStats
        }
        if todayStats != dayStats {
            todayStats = dayStats
        }

        // Aggregate by Provider and Model
        let showTodayOnly = dayStats.requestCount > 0
        var providerData: [String: [String: TokenStats]] = [:] // provider -> (model -> stats)
        var modeData: [String: TokenStats] = [:]
        var projectData: [String: ProjectUsage] = [:]
        var seenCacheKeysByProject: [String: Set<String>] = [:]
        var usageSamples: [ModelUsageSample] = []
        var allCostUSD: Double?
        var dayCostUSD: Double?
        var todayProviderCostsUSD: [String: Double] = [:]

        // Helper to normalize URLs for better matching (localhost vs 127.0.0.1)
        func normalizeUrl(_ url: String) -> String {
            let low = url.lowercased()
                .replacingOccurrences(of: "localhost", with: "127.0.0.1")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "https://", with: "")

            // Sadece host ve port kısmını al (path'leri temizle)
            if let firstSlash = low.firstIndex(of: "/") {
                return String(low[..<firstSlash])
            }
            return low
        }

        let normalizedProviders = providers.map { (normalizeUrl($0.api_base_url), $0.name) }

        for (_, info) in requests {
            // Eğer istek "Unknown" modelindeyse (örneğin sadece favicon isteği gibi), işleme almayalım
            if info.model == "Unknown" { continue }

            var pName = info.providerName ?? "Unknown"
            if pName == "Unknown", let url = info.providerUrl {
                let normUrl = normalizeUrl(url)
                if let matched = normalizedProviders.first(where: { normUrl.hasPrefix($0.0) || $0.0.hasPrefix(normUrl) }) {
                    pName = matched.1
                } else {
                    pName = URL(string: url)?.host?.uppercased() ?? url.uppercased()
                }
            }

            let requestStats = TokenStats(
                inputTokens: info.inputTokens,
                outputTokens: info.outputTokens,
                requestCount: 1,
                providerPromptTokens: info.providerPromptTokens,
                providerCacheReadTokens: info.providerCacheReadTokens,
                providerCacheCreationTokens: info.providerCacheCreationTokens
            )
            if let requestCost = costUSD(provider: pName, model: info.model, stats: requestStats) {
                allCostUSD = (allCostUSD ?? 0) + requestCost
                if info.isToday {
                    dayCostUSD = (dayCostUSD ?? 0) + requestCost
                    todayProviderCostsUSD[pName, default: 0] += requestCost
                }
            }

            usageSamples.append(ModelUsageSample(
                timestamp: info.timestamp,
                provider: pName,
                model: info.model,
                stats: requestStats,
                projectName: info.projectName,
                projectPath: info.projectPath
            ))

            let projectName = info.projectName?.isEmpty == false ? info.projectName! : "Unknown Project"
            let projectKey = info.projectPath?.isEmpty == false ? info.projectPath! : projectName
            var cacheSavingsTokens = 0
            if let cacheKey = info.promptCacheKey,
               cacheKey.hasPrefix("prompt-v1:"),
               info.promptCacheCandidateTokens > 0 {
                var seenKeys = seenCacheKeysByProject[projectKey, default: []]
                if seenKeys.contains(cacheKey) {
                    cacheSavingsTokens = info.promptCacheCandidateTokens + info.outputTokens
                } else {
                    seenKeys.insert(cacheKey)
                    seenCacheKeysByProject[projectKey] = seenKeys
                }
            }
            var projectUsage = projectData[projectKey] ?? ProjectUsage(
                name: projectName,
                path: info.projectPath,
                gitRoot: info.gitRoot,
                isGitRepository: info.isGitRepository,
                stats: TokenStats()
            )
            projectUsage.stats.inputTokens += info.inputTokens
            projectUsage.stats.outputTokens += info.outputTokens
            projectUsage.stats.providerPromptTokens += info.providerPromptTokens
            projectUsage.stats.providerCacheReadTokens += info.providerCacheReadTokens
            projectUsage.stats.providerCacheCreationTokens += info.providerCacheCreationTokens
            projectUsage.stats.cacheSavingsTokens += cacheSavingsTokens
            projectUsage.stats.requestCount += 1
            projectData[projectKey] = projectUsage

            if showTodayOnly && !info.isToday { continue }

            var modeStats = modeData[info.mode, default: TokenStats()]
            modeStats.inputTokens += info.inputTokens
            modeStats.outputTokens += info.outputTokens
            modeStats.providerPromptTokens += info.providerPromptTokens
            modeStats.providerCacheReadTokens += info.providerCacheReadTokens
            modeStats.providerCacheCreationTokens += info.providerCacheCreationTokens
            modeStats.requestCount += 1
            modeData[info.mode] = modeStats

            var modelsInProvider = providerData[pName, default: [:]]
            var modelStats = modelsInProvider[info.model, default: TokenStats()]

            modelStats.inputTokens += info.inputTokens
            modelStats.outputTokens += info.outputTokens
            modelStats.providerPromptTokens += info.providerPromptTokens
            modelStats.providerCacheReadTokens += info.providerCacheReadTokens
            modelStats.providerCacheCreationTokens += info.providerCacheCreationTokens
            modelStats.requestCount += 1

            modelsInProvider[info.model] = modelStats
            providerData[pName] = modelsInProvider
        }

        let nextProviderStats = providerData.map { pName, models in
            let modelUsages = models.map {
                ModelUsage(
                    provider: pName,
                    model: $0.key,
                    stats: $0.value,
                    costUSD: costUSD(provider: pName, model: $0.key, stats: $0.value)
                )
            }
                .sorted { $0.stats.requestCount > $1.stats.requestCount }
            let total = modelUsages.reduce(into: TokenStats()) { res, m in
                res.inputTokens += m.stats.inputTokens
                res.outputTokens += m.stats.outputTokens
                res.providerPromptTokens += m.stats.providerPromptTokens
                res.providerCacheReadTokens += m.stats.providerCacheReadTokens
                res.providerCacheCreationTokens += m.stats.providerCacheCreationTokens
                res.requestCount += m.stats.requestCount
            }
            let costs = modelUsages.compactMap(\.costUSD)
            let totalCost = costs.isEmpty ? nil : costs.reduce(0, +)
            return ProviderUsage(provider: pName, models: modelUsages, totalStats: total, totalCostUSD: totalCost)
        }.sorted { $0.totalStats.requestCount > $1.totalStats.requestCount }

        let nextModelBreakdown = nextProviderStats.flatMap { $0.models }
            .sorted { $0.stats.requestCount > $1.stats.requestCount }

        let nextModeStats = modeData.map { ModeUsage(mode: $0.key, stats: $0.value) }
            .sorted { Self.modeSortIndex($0.mode) < Self.modeSortIndex($1.mode) }

        let nextModelUsageSamples = usageSamples
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return "\($0.provider)/\($0.model)".localizedCaseInsensitiveCompare("\($1.provider)/\($1.model)") == .orderedAscending
                }
                return $0.timestamp < $1.timestamp
            }
        let nextProjectBreakdown = projectData.values.sorted {
            if $0.stats.requestCount != $1.stats.requestCount {
                return $0.stats.requestCount > $1.stats.requestCount
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let nextAllTimeCostUSD = pricing.isEmpty ? nil : allCostUSD
        let nextTodayCostUSD = pricing.isEmpty ? nil : dayCostUSD
        let nextTodayProviderCostsUSD = pricing.isEmpty ? [:] : todayProviderCostsUSD

        if providerStats != nextProviderStats {
            providerStats = nextProviderStats
        }
        if modelBreakdown != nextModelBreakdown {
            modelBreakdown = nextModelBreakdown
        }
        if modeStats != nextModeStats {
            modeStats = nextModeStats
        }
        if modelUsageSamples != nextModelUsageSamples {
            modelUsageSamples = nextModelUsageSamples
        }
        if projectBreakdown != nextProjectBreakdown {
            projectBreakdown = nextProjectBreakdown
        }
        if allTimeCostUSD != nextAllTimeCostUSD {
            allTimeCostUSD = nextAllTimeCostUSD
        }
        if todayCostUSD != nextTodayCostUSD {
            todayCostUSD = nextTodayCostUSD
        }
        if todayProviderCostsUSD != nextTodayProviderCostsUSD {
            todayProviderCostsUSD = nextTodayProviderCostsUSD
        }
        SpendLimitNotificationService.notifyExceededLimits(
            providers: providers,
            todayCostsUSD: todayProviderCostsUSD
        )
    }

    private func costUSD(provider: String?, model: String, stats: TokenStats) -> Double? {
        let key = "\(provider ?? "Unknown")/\(model)"
        if let cached = priceLookupCache[key] {
            return cached.cost(for: stats)
        }
        if priceLookupMisses.contains(key) {
            return nil
        }

        guard let price = ModelPricingService.bestPrice(for: provider, model: model, in: pricing) else {
            priceLookupMisses.insert(key)
            return nil
        }
        priceLookupCache[key] = price
        return price.cost(for: stats)
    }

    private func estimateContentSize(_ items: [[String: Any]]) -> Int {
        var size = 0
        for item in items {
            if let text = item["text"] as? String {
                size += text.count
            }
            if let content = item["content"] as? [[String: Any]] {
                size += estimateContentSize(content)
            }
            if let content = item["content"] as? String {
                size += content.count
            }
        }
        return size
    }

    private func todayPrefix() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    nonisolated static func dayDate(fromLogFileName fileName: String) -> Date? {
        var digits = ""
        for character in fileName {
            if character.isNumber {
                digits.append(character)
                if digits.count == 8, let date = compactDayFormatter.date(from: digits) {
                    return date
                }
                if digits.count > 8 {
                    digits.removeFirst()
                }
            } else {
                digits.removeAll()
            }
        }
        return nil
    }

    nonisolated static func date(fromLogEntry entry: [String: Any]) -> Date? {
        if let milliseconds = entry["time"] as? Double {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        if let milliseconds = entry["time"] as? Int {
            return Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        }
        if let timestamp = entry["time"] as? String {
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: timestamp) {
                return date
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: timestamp)
        }
        return nil
    }

    nonisolated static func detectMode(in body: [String: Any], inputTokens: Int, longContextThreshold: Int?) -> String {
        if containsImage(in: body) { return "image" }
        if bodyRequestsThinking(body) { return "think" }
        if let threshold = longContextThreshold, threshold > 0, inputTokens >= threshold { return "longContext" }
        if looksLikeBackgroundRequest(body) { return "background" }
        if containsActiveWebSearchToolUse(in: body) { return "webSearch" }
        return "default"
    }

    private nonisolated static func bodyRequestsThinking(_ body: [String: Any]) -> Bool {
        guard let thinking = body["thinking"] as? [String: Any],
              let type = thinking["type"] as? String else {
            return false
        }
        return type.lowercased() != "disabled"
    }

    private nonisolated static func looksLikeBackgroundRequest(_ body: [String: Any]) -> Bool {
        flattenedStrings(in: body).contains { text in
            let lowered = text.lowercased()
            return lowered.contains("generate a concise, sentence-case title") ||
                lowered.contains("captures the main topic or goal of this coding session")
        }
    }

    private nonisolated static func containsImage(in value: Any) -> Bool {
        if let dict = value as? [String: Any] {
            if let type = dict["type"] as? String {
                let normalized = type.lowercased()
                if normalized == "image" || normalized == "image_url" || normalized == "input_image" {
                    return true
                }
            }
            if dict["image_url"] != nil { return true }
            if let mediaType = dict["media_type"] as? String, mediaType.lowercased().hasPrefix("image/") {
                return true
            }
            return dict.values.contains { containsImage(in: $0) }
        }
        if let array = value as? [Any] {
            return array.contains { containsImage(in: $0) }
        }
        return false
    }

    private nonisolated static func containsActiveWebSearchToolUse(in body: [String: Any]) -> Bool {
        if let toolChoice = body["tool_choice"] as? [String: Any],
           isWebSearchToolName(toolChoice["name"] as? String) {
            return true
        }

        guard let messages = body["messages"] as? [[String: Any]] else { return false }
        for message in messages {
            guard let content = message["content"] as? [[String: Any]] else { continue }
            for item in content {
                let type = item["type"] as? String
                if (type == "tool_use" || type == "server_tool_use"),
                   isWebSearchToolName(item["name"] as? String) {
                    return true
                }
            }
        }
        return false
    }

    private nonisolated static func isWebSearchToolName(_ name: String?) -> Bool {
        guard let name else { return false }
        let normalized = name.lowercased().replacingOccurrences(of: "_", with: "")
        return normalized == "websearch" || normalized == "webfetch"
    }

    private nonisolated static func flattenedStrings(in value: Any) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let dict = value as? [String: Any] {
            return dict.values.flatMap { flattenedStrings(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { flattenedStrings(in: $0) }
        }
        return []
    }

    private nonisolated static func modeSortIndex(_ mode: String) -> Int {
        ["default", "think", "background", "longContext", "webSearch", "image"].firstIndex(of: mode) ?? Int.max
    }

    private nonisolated static let compactDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()
}

extension TokenStats {
    var formattedInput: String { formatTokenCount(inputTokens) }
    var formattedOutput: String { formatTokenCount(outputTokens) }
    var formattedTotal: String { formatTokenCount(inputTokens + outputTokens) }
    var formattedAverageInput: String {
        guard requestCount > 0 else { return "0" }
        return formatTokenCount(Int((Double(inputTokens) / Double(requestCount)).rounded()))
    }
    var formattedAverageOutput: String {
        guard requestCount > 0 else { return "0" }
        return formatTokenCount(Int((Double(outputTokens) / Double(requestCount)).rounded()))
    }
    var formattedAverageProviderPrompt: String {
        guard requestCount > 0 else { return "0" }
        return formatTokenCount(Int((Double(providerPromptTokens) / Double(requestCount)).rounded()))
    }
    var formattedCacheSavings: String { formatTokenCount(cacheSavingsTokens) }
    var formattedProviderCacheRead: String { formatTokenCount(providerCacheReadTokens) }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
