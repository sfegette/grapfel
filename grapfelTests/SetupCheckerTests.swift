import XCTest

final class SetupCheckerTests: XCTestCase {
    func testIsHomebrewInstalledChecksKnownPaths() {
        XCTAssertTrue(
            SetupChecker.isHomebrewInstalled { path in
                path == "/opt/homebrew/bin/brew"
            }
        )

        XCTAssertFalse(
            SetupChecker.isHomebrewInstalled { _ in false }
        )
    }
}
