import XCTest

final class GenerationSettingsTests: XCTestCase {
    func testDefaultsMatchExpectedValues() {
        let settings = GenerationSettings.defaults

        XCTAssertEqual(settings.temperature, 1.0)
        XCTAssertEqual(settings.topP, 1.0)
        XCTAssertEqual(settings.maxTokens, 2048)
        XCTAssertNil(settings.seed)
        XCTAssertTrue(settings.streaming)
        XCTAssertFalse(settings.jsonMode)
        XCTAssertEqual(settings.systemPrompt, "")
        XCTAssertFalse(settings.permissiveContentTransformations)
    }

    func testPermissiveTransformationsDefaultToStandardGuardrailsAndPreserveExplicitPreference() {
        let defaults = makeTestUserDefaults()

        PermissiveContentTransformationsPolicy.registerDefault(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: UserDefaultsKey.permissiveContentTransformations))

        defaults.set(true, forKey: UserDefaultsKey.permissiveContentTransformations)
        PermissiveContentTransformationsPolicy.registerDefault(in: defaults)
        XCTAssertTrue(defaults.bool(forKey: UserDefaultsKey.permissiveContentTransformations))

        defaults.set(false, forKey: UserDefaultsKey.permissiveContentTransformations)
        PermissiveContentTransformationsPolicy.registerDefault(in: defaults)
        XCTAssertFalse(defaults.bool(forKey: UserDefaultsKey.permissiveContentTransformations))
    }
}
