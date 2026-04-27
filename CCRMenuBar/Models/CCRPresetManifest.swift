import Foundation

struct CCRPresetManifest: Codable {
    var name: String
    var version: String
    var Providers: [Provider]
    var Router: RouterConfig

    static func from(name: String, displayName: String, providers: [Provider], router: RouterConfig) -> CCRPresetManifest {
        CCRPresetManifest(name: name, version: "1.0.0", Providers: providers, Router: router)
    }
}
