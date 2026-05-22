import XCTest

final class ApfelOptionsTests: XCTestCase {
    func testDefaultsMatchExpectedValues() {
        let opts = ApfelOptions.defaults

        XCTAssertEqual(opts.temperature, 1.0)
        XCTAssertEqual(opts.maxTokens, 2048)
        XCTAssertNil(opts.seed)
        XCTAssertTrue(opts.streaming)
        XCTAssertFalse(opts.jsonMode)
        XCTAssertEqual(opts.systemPrompt, "")
        XCTAssertEqual(opts.contextStrategy, .newestFirst)
        XCTAssertNil(opts.contextMaxTurns)
    }

    func testContextStrategyAllCasesHaveRawValues() {
        let expected = ["newest-first", "oldest-first", "sliding-window", "summarize", "strict"]
        XCTAssertEqual(ContextStrategy.allCases.map(\.rawValue), expected)
    }

    func testContextStrategyDisplayNamesAreLowercase() {
        for strategy in ContextStrategy.allCases {
            XCTAssertEqual(strategy.displayName, strategy.displayName.lowercased())
        }
    }
}
