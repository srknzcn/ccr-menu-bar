import Foundation

enum RouterRoute: String, CaseIterable, Identifiable {
    case `default` = "default"
    case think = "think"
    case background = "background"
    case longContext = "longContext"
    case webSearch = "webSearch"
    case image = "image"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: return "Default"
        case .think: return "Think"
        case .background: return "Background"
        case .longContext: return "Long Context"
        case .webSearch: return "Web Search"
        case .image: return "Image"
        }
    }

    func getValue(from router: RouterConfig) -> String? {
        switch self {
        case .default: return router.default
        case .think: return router.think
        case .background: return router.background
        case .longContext: return router.longContext
        case .webSearch: return router.webSearch
        case .image: return router.image
        }
    }

    func setValue(_ value: String, on router: inout RouterConfig) {
        switch self {
        case .default: router.default = value
        case .think: router.think = value
        case .background: router.background = value
        case .longContext: router.longContext = value
        case .webSearch: router.webSearch = value
        case .image: router.image = value
        }
    }
}
