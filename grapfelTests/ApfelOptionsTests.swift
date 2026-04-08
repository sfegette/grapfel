import XCTest
@testable import grapfel

final class ApfelOptionsTests: XCTestCase {

    func test_defaults_matchExpectedValues() {
        let opts = ApfelOptions.defaults
        XCTAssertEqual(opts.temperature, 1.0)
        XCTAssertEqual(opts.maxTokens, 2048)
        XCTAssertNil(opts.seed)
        XCTAssertFalse(opts.permissive)
        XCTAssertTrue(opts.streaming)
        XCTAssertEqual(opts.systemPrompt, "")
        XCTAssertEqual(opts.contextStrategy, .newestFirst)
        XCTAssertNil(opts.contextMaxTurns)
    }

    func test_contextStrategy_allCasesHaveRawValues() {
        // Ensure every strategy serializes to a valid apfel CLI value
        let expected = ["newest-first", "oldest-first", "sliding-window", "summarize", "strict"]
        let actual = ContextStrategy.allCases.map(\.rawValue)
        XCTAssertEqual(actual, expected)
    }

    func test_contextStrategy_displayNames_areLowercase() {
        for strategy in ContextStrategy.allCases {
            XCTAssertEqual(strategy.displayName, strategy.displayName.lowercased(),
                           "\(strategy.rawValue) display name should be lowercase")
        }
    }
}
