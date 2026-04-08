import XCTest

final class GrapfelUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Smoke test: app launches without crashing.
    func test_appLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        // App is a menubar agent (LSUIElement) — no main window, just verify it runs
        XCTAssertEqual(app.state, .runningForeground)
    }
}
