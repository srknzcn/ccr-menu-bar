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

@MainActor
class TokenUsageService: ObservableObject {
    @Published var todayStats = TokenStats()
    @Published var allTimeStats = TokenStats()
    @Published var modelBreakdown: [ModelUsage] = []

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
        var byModel: [String: TokenStats] = [:]

        // Track request-to-model mapping for attributing response data
        var reqModelMap: [String: String] = [:]

        for file in logFiles {
            let isToday = file.contains(today)
            let path = "\(logsPath)/\(file)"
            guard let data = fm.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                guard let lineData = line.data(using: .utf8),
                      let entry = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

                let reqId = entry["reqId"] as? String

                // Parse request bodies for input token estimation
                if let body = entry["data"] as? [String: Any],
                   let model = body["model"] as? String {
                    let messages = body["messages"] as? [[String: Any]] ?? []
                    let system = body["system"] as? [[String: Any]] ?? []

                    // Estimate tokens: ~3-4 chars per token average
                    let msgSize = estimateContentSize(messages) + estimateContentSize(system)
                    let estimatedInputTokens = max(msgSize / 3, 1)

                    allStats.inputTokens += estimatedInputTokens
                    allStats.requestCount += 1

                    byModel[model, default: TokenStats()].inputTokens += estimatedInputTokens
                    byModel[model, default: TokenStats()].requestCount += 1

                    if isToday {
                        dayStats.inputTokens += estimatedInputTokens
                        dayStats.requestCount += 1
                    }

                    if let rid = reqId {
                        reqModelMap[rid] = model
                    }
                }

                // Parse response completion for output token estimation
                if let msg = entry["msg"] as? String, msg == "request completed",
                   let res = entry["res"] as? [String: Any],
                   let statusCode = res["statusCode"] as? Int, statusCode == 200,
                   let responseTime = entry["responseTime"] as? Double {
                    // Heuristic: streaming response at ~40-60 tokens/sec
                    let estimatedOutput = Int(responseTime / 1000.0 * 50)
                    if estimatedOutput > 5 { // filter out quick non-streaming requests
                        allStats.outputTokens += estimatedOutput

                        if isToday {
                            dayStats.outputTokens += estimatedOutput
                        }

                        // Attribute to model if we tracked the request
                        if let rid = reqId, let model = reqModelMap[rid] {
                            byModel[model, default: TokenStats()].outputTokens += estimatedOutput
                        }
                    }
                }
            }
        }

        allTimeStats = allStats
        todayStats = dayStats
        modelBreakdown = byModel
            .map { ModelUsage(model: $0.key, stats: $0.value) }
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
