import XCTest
@testable import CCRMenuBar

final class PresetManagerTests: XCTestCase {
    func testPresetManifestNameUsesCCRNamespaceName() {
        let router = RouterConfig(default: "openrouter,openai/gpt-5.5")
        let manifest = CCRPresetManifest.from(name: "gpt-5-5", displayName: "gpt-5.5", providers: [], router: router)

        XCTAssertEqual(manifest.name, "gpt-5-5")
    }
}
