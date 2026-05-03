import Foundation

struct ModelTokenPrice: Codable, Equatable {
    let key: String
    let provider: String
    let baseModel: String?
    let inputCostPerToken: Double
    let outputCostPerToken: Double
    let source: Source

    enum Source: String, Codable {
        case openRouter
        case liteLLM
    }

    func cost(for stats: TokenStats) -> Double {
        Double(stats.inputTokens) * inputCostPerToken +
            Double(stats.outputTokens) * outputCostPerToken
    }
}

enum ModelPricingService {
    static let openRouterModelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    static let liteLLMRegistryURL = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    static let cacheRefreshInterval: TimeInterval = 24 * 60 * 60

    static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-code-router", isDirectory: true)
            .appendingPathComponent("ccr-menu-bar-pricing-cache.json")
    }

    static func fetchPrices(
        openRouterURL: URL = openRouterModelsURL,
        liteLLMURL: URL = liteLLMRegistryURL,
        cacheURL: URL = defaultCacheURL,
        now: Date = Date(),
        forceRefresh: Bool = false,
        allowStaleFallback: Bool = true
    ) async throws -> [ModelTokenPrice] {
        if !forceRefresh,
           let cache = try? readCache(from: cacheURL),
           now.timeIntervalSince(cache.fetchedAt) < cacheRefreshInterval {
            return cache.prices
        }

        let staleCache = try? readCache(from: cacheURL)

        do {
            let openRouterPrices = try await fetchOpenRouterPrices(from: openRouterURL)
            let liteLLMPrices = try await fetchLiteLLMPrices(from: liteLLMURL)
            let prices = openRouterPrices + liteLLMPrices
            try writeCache(PricingCache(fetchedAt: now, prices: prices), to: cacheURL)
            return prices
        } catch {
            if allowStaleFallback, let staleCache {
                return staleCache.prices
            }
            throw error
        }
    }

    static func parseOpenRouterPrices(from data: Data) throws -> [ModelTokenPrice] {
        let raw = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return raw.data.compactMap { model in
            guard let inputCost = model.pricing.prompt.value,
                  let outputCost = model.pricing.completion.value else {
                return nil
            }

            return ModelTokenPrice(
                key: "openrouter/\(model.id)",
                provider: "openrouter",
                baseModel: lastPathComponent(model.id),
                inputCostPerToken: inputCost,
                outputCostPerToken: outputCost,
                source: .openRouter
            )
        }
        .sorted { $0.key < $1.key }
    }

    static func parseLiteLLMPrices(from data: Data) throws -> [ModelTokenPrice] {
        let raw = try JSONDecoder().decode([String: LiteLLMRegistryEntry].self, from: data)
        return raw.keys.sorted().compactMap { key in
            guard let entry = raw[key],
                  let provider = entry.provider,
                  normalizeProvider(provider) != "openrouter",
                  let inputCost = entry.inputCostPerToken?.value,
                  let outputCost = entry.outputCostPerToken?.value else {
                return nil
            }

            return ModelTokenPrice(
                key: key,
                provider: provider,
                baseModel: entry.baseModel ?? lastPathComponent(key),
                inputCostPerToken: inputCost,
                outputCostPerToken: outputCost,
                source: .liteLLM
            )
        }
    }

    static func bestPrice(
        for provider: String?,
        model: String,
        in prices: [ModelTokenPrice]
    ) -> ModelTokenPrice? {
        guard !prices.isEmpty else { return nil }

        let normalizedProvider = normalizeProvider(provider)
        let normalizedModel = normalizeModel(model)
        guard !normalizedModel.isEmpty else { return nil }

        let candidateKeys = keyCandidates(provider: normalizedProvider, model: normalizedModel)

        let providerScoped: [ModelTokenPrice]
        if let normalizedProvider {
            providerScoped = prices.filter { normalizeProvider($0.provider) == normalizedProvider }
        } else {
            providerScoped = prices
        }
        guard !providerScoped.isEmpty else { return nil }

        if let exact = providerScoped.first(where: { candidateKeys.contains(normalizeKey($0.key)) }) {
            return exact
        }

        if let suffix = providerScoped.first(where: { price in
            let key = normalizeKey(price.key)
            return candidateKeys.contains { key.hasSuffix("/\($0)") }
        }) {
            return suffix
        }

        let comparableModel = comparableModelName(normalizedModel)
        if let base = providerScoped.first(where: { price in
            comparableModelName(price.baseModel ?? "") == comparableModel
        }) {
            return base
        }

        if let lastPath = providerScoped.first(where: { price in
            comparableModelName(lastPathComponent(price.key)) == comparableModel
        }) {
            return lastPath
        }

        return nil
    }

    private static func keyCandidates(provider: String?, model: String) -> Set<String> {
        var keys: Set<String> = [model]
        if let provider, !model.hasPrefix("\(provider)/") {
            keys.insert("\(provider)/\(model)")
        }
        return keys
    }

    private static func normalizeProvider(_ provider: String?) -> String? {
        guard let provider else { return nil }
        let lower = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, lower != "unknown" else { return nil }

        if lower.contains("openrouter") { return "openrouter" }
        if lower == "x-ai" || lower == "x_ai" || lower == "xai" { return "xai" }
        if lower == "z-ai" || lower == "z_ai" || lower == "zai" { return "zai" }
        if lower.contains("anthropic") || lower.contains("claude") { return "anthropic" }
        if lower.contains("openai") { return "openai" }
        if lower.contains("gemini") || lower == "google" { return "gemini" }
        if lower.contains("vertex") { return "vertex_ai" }
        if lower.contains("bedrock") { return "bedrock" }
        if lower.contains("azure") { return "azure" }
        if lower.contains("deepseek") { return "deepseek" }
        if lower.contains("groq") { return "groq" }
        if lower.contains("mistral") { return "mistral" }

        return lower
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func normalizeModel(_ model: String) -> String {
        let routeModel = model.split(separator: ",").last.map(String.init) ?? model
        return normalizeKey(routeModel)
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[0-9;]*m\]$"#, with: "", options: .regularExpression)
    }

    private static func comparableModelName(_ model: String) -> String {
        normalizeKey(model)
            .replacingOccurrences(of: ".", with: "-")
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func lastPathComponent(_ key: String) -> String {
        normalizeKey(key).split(separator: "/").last.map(String.init) ?? key
    }

    private static func fetchOpenRouterPrices(from url: URL) async throws -> [ModelTokenPrice] {
        let data = try await fetchData(from: url)
        return try parseOpenRouterPrices(from: data)
    }

    private static func fetchLiteLLMPrices(from url: URL) async throws -> [ModelTokenPrice] {
        let data = try await fetchData(from: url)
        return try parseLiteLLMPrices(from: data)
    }

    private static func fetchData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse,
           !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private static func readCache(from url: URL) throws -> PricingCache {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PricingCache.self, from: data)
    }

    private static func writeCache(_ cache: PricingCache, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(cache).write(to: url, options: .atomic)
    }
}

private struct PricingCache: Codable {
    let fetchedAt: Date
    let prices: [ModelTokenPrice]
}

private struct OpenRouterModelsResponse: Decodable {
    let data: [OpenRouterModel]
}

private struct OpenRouterModel: Decodable {
    let id: String
    let pricing: OpenRouterPricing
}

private struct OpenRouterPricing: Decodable {
    let prompt: FlexibleDouble
    let completion: FlexibleDouble
}

private struct LiteLLMRegistryEntry: Decodable {
    let provider: String?
    let baseModel: String?
    let inputCostPerToken: FlexibleDouble?
    let outputCostPerToken: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case provider = "litellm_provider"
        case baseModel = "base_model"
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
    }
}

private struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = nil
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = Double(stringValue)
        } else {
            value = nil
        }
    }
}
