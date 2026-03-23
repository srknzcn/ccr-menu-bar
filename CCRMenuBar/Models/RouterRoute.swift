import Foundation
import SwiftUI

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

    var icon: String {
        switch self {
        case .default: return "cpu"
        case .think: return "brain.head.profile"
        case .background: return "gearshape.2"
        case .longContext: return "text.book.closed"
        case .webSearch: return "globe"
        case .image: return "photo"
        }
    }

    var accentColor: Color {
        switch self {
        case .default: return .blue
        case .think: return .purple
        case .background: return .gray
        case .longContext: return .orange
        case .webSearch: return .green
        case .image: return .pink
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
