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
    var transformer: AnyCodable?
    var id: String { name }

    static func == (lhs: Provider, rhs: Provider) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
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
