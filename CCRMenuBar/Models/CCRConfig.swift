import Foundation

struct CCRConfig: Codable {
    var LOG: Bool?
    var LOG_LEVEL: String?
    var CLAUDE_PATH: String?
    var HOST: String?
    var PORT: Int?
    var APIKEY: String?
    var API_TIMEOUT_MS: String?
    var PROXY_URL: String?
    var transformers: AnyCodable?
    var Providers: [Provider]
    var Router: RouterConfig
    var StatusLine: AnyCodable?
    var CUSTOM_ROUTER_PATH: String?
    var NON_INTERACTIVE_MODE: Bool?
}

struct Provider: Codable, Identifiable, Hashable {
    var name: String
    var api_base_url: String
    var api_key: String
    var models: [String]
    var transformer: TransformerConfig?
    var daily_spend_limit_usd: Double?
    var thinking_disabled_models: [String]?
    var id: String { name }

    static func == (lhs: Provider, rhs: Provider) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct TransformerConfig: Codable {
    var use: [String]?
    // Preserve any extra per-model keys as raw JSON
    var extra: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case use
    }

    init(use: [String]? = nil) {
        self.use = use
        self.extra = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        use = try container.decodeIfPresent([String].self, forKey: .use)

        // Decode any extra keys (per-model overrides like "deepseek-chat": {...})
        let allKeys = try decoder.container(keyedBy: DynamicCodingKey.self)
        var extras: [String: AnyCodable] = [:]
        for key in allKeys.allKeys where key.stringValue != "use" {
            extras[key.stringValue] = try allKeys.decode(AnyCodable.self, forKey: key)
        }
        extra = extras.isEmpty ? nil : extras
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(use, forKey: .use)

        if let extra = extra {
            var dynamic = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in extra {
                try dynamic.encode(value, forKey: DynamicCodingKey(stringValue: key))
            }
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
    init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
}

enum BuiltInTransformer: String, CaseIterable, Identifiable {
    case Anthropic
    case OpenAI
    case deepseek
    case gemini
    case openrouter
    case groq
    case maxtoken
    case tooluse
    case reasoning
    case sampling
    case enhancetool
    case cleancache
    case vertexGemini = "vertex-gemini"
    case geminiCli = "gemini-cli"
    case qwenCli = "qwen-cli"
    case rovoCli = "rovo-cli"
    case chutesGlm = "chutes-glm"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .Anthropic: return "Anthropic"
        case .OpenAI: return "OpenAI"
        case .deepseek: return "DeepSeek"
        case .gemini: return "Gemini"
        case .openrouter: return "OpenRouter"
        case .groq: return "Groq"
        case .maxtoken: return "Max Token"
        case .tooluse: return "Tool Use"
        case .reasoning: return "Reasoning"
        case .sampling: return "Sampling"
        case .enhancetool: return "Enhance Tool"
        case .cleancache: return "Clean Cache"
        case .vertexGemini: return "Vertex Gemini"
        case .geminiCli: return "Gemini CLI"
        case .qwenCli: return "Qwen CLI"
        case .rovoCli: return "Rovo CLI"
        case .chutesGlm: return "Chutes GLM"
        }
    }
}

struct RouterConfig: Codable {
    var `default`: String?
    var background: String?
    var think: String?
    var longContext: String?
    var longContextThreshold: Int?
    var webSearch: String?
    var image: String?
}
