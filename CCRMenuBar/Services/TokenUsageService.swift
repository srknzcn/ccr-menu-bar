// CCRMenuBar/Services/TokenUsageService.swift
import Foundation
import Combine

struct TokenStats {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var requestCount: Int = 0
}

struct ModelUsage: Identifiable {
    let model: String
    var stats: TokenStats
    var id: String { model }
}

struct ProviderUsage: Identifiable {
    let provider: String
    var models: [ModelUsage]
    var totalStats: TokenStats
    var id: String { provider }
}

@MainActor
class TokenUsageService: ObservableObject {
    @Published var todayStats = TokenStats()
    @Published var allTimeStats = TokenStats()
    @Published var modelBreakdown: [ModelUsage] = []
    @Published var providerStats: [ProviderUsage] = []

    var providers: [Provider] = []

    private var timer: Timer?
    private let logsPath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        logsPath = "\(home)/.claude-code-router/logs"
        parseLogs()
        startPolling()
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        parseLogs()
    }

    private func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.parseLogs()
            }
        }
    }

    private func parseLogs() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: logsPath) else { return }

        let today = todayPrefix()
        let logFiles = files.filter { $0.hasSuffix(".log") }.sorted()

        var allStats = TokenStats()
        var dayStats = TokenStats()

        // Track request metadata
        struct ReqInfo {
            let model: String
            let isToday: Bool
            var inputTokens: Int = 0
            var outputTokens: Int = 0
            var providerUrl: String?
        }
        var requests: [String: ReqInfo] = [:]

        // Build provider mapping
        var urlToProvider: [String: String] = [:]
        for provider in providers {
            urlToProvider[provider.api_base_url] = provider.name
        }

        for file in logFiles {
            let isToday = file.contains(today)
            let path = "\(logsPath)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

                let reqId = entry["reqId"] as? String

                if let msg = entry["msg"] as? String, msg == "final request",
                   let rid = reqId, let url = entry["requestUrl"] as? String {
                    var info = requests[rid] ?? ReqInfo(model: "Unknown", isToday: isToday)
                    info.providerUrl = url
                    requests[rid] = info
                }

                if let body = entry["data"] as? [String: Any],
                   let model = body["model"] as? String {
                    let messages = body["messages"] as? [[String: Any]] ?? []
                    let system = body["system"] as? [[String: Any]] ?? []
                    let input = max(estimateContentSize(messages) + estimateContentSize(system) / 3, 1)

                    allStats.inputTokens += input
                    allStats.requestCount += 1
                    if isToday {
                        dayStats.inputTokens += input
                        dayStats.requestCount += 1
                    }

                    if let rid = reqId {
                       var info = requests[rid] ?? ReqInfo(model: model, isToday: isToday)
                       info.inputTokens = input
                       // Eğer 'final request' daha önce geldiyse model adını güncelle
                       if info.model == "Unknown" {
                           // Yeniden oluştur çünkü struct immutable
                           requests[rid] = ReqInfo(model: model, isToday: isToday, inputTokens: input, outputTokens: info.outputTokens, providerUrl: info.providerUrl)
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

        allTimeStats = allStats
        todayStats = dayStats

        // Aggregate by Provider and Model
        let showTodayOnly = dayStats.requestCount > 0
        var providerData: [String: [String: TokenStats]] = [:] // provider -> (model -> stats)

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
            if showTodayOnly && !info.isToday { continue }

            var pName = "Unknown"
            if let url = info.providerUrl {
                let normUrl = normalizeUrl(url)
                if let matched = normalizedProviders.first(where: { normUrl.hasPrefix($0.0) || $0.0.hasPrefix(normUrl) }) {
                    pName = matched.1
                } else {
                    pName = URL(string: url)?.host?.uppercased() ?? url.uppercased()
                }
            }

            var modelsInProvider = providerData[pName, default: [:]]
            var modelStats = modelsInProvider[info.model, default: TokenStats()]

            modelStats.inputTokens += info.inputTokens
            modelStats.outputTokens += info.outputTokens
            modelStats.requestCount += 1

            modelsInProvider[info.model] = modelStats
            providerData[pName] = modelsInProvider
        }

        self.providerStats = providerData.map { pName, models in
            let modelUsages = models.map { ModelUsage(model: $0.key, stats: $0.value) }
                .sorted { $0.stats.requestCount > $1.stats.requestCount }
            let total = modelUsages.reduce(into: TokenStats()) { res, m in
                res.inputTokens += m.stats.inputTokens
                res.outputTokens += m.stats.outputTokens
                res.requestCount += m.stats.requestCount
            }
            return ProviderUsage(provider: pName, models: modelUsages, totalStats: total)
        }.sorted { $0.totalStats.requestCount > $1.totalStats.requestCount }

        self.modelBreakdown = self.providerStats.flatMap { $0.models }
            .sorted { $0.stats.requestCount > $1.stats.requestCount }
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
}

extension TokenStats {
    var formattedInput: String { formatTokenCount(inputTokens) }
    var formattedOutput: String { formatTokenCount(outputTokens) }
    var formattedTotal: String { formatTokenCount(inputTokens + outputTokens) }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
