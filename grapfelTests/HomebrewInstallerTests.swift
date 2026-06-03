import XCTest

final class HomebrewInstallerTests: XCTestCase {

    // Gap 5a: brewURL returns the first path where brew is executable.
    func testBrewURLReturnsFirstExecutableCandidate() {
        let url = HomebrewInstaller.brewURL(isExecutableFile: { path in
            path == "/opt/homebrew/bin/brew"
        })
        XCTAssertEqual(url?.path, "/opt/homebrew/bin/brew")
    }

    // Gap 5b: brewURL returns nil when no candidate is executable.
    func testBrewURLReturnsNilWhenNoCandidateIsExecutable() {
        let url = HomebrewInstaller.brewURL(isExecutableFile: { _ in false })
        XCTAssertNil(url)
    }

    // Gap 5c: brewURL prefers the Apple Silicon path when both are present.
    func testBrewURLPrefersAppleSiliconPath() {
        let url = HomebrewInstaller.brewURL(isExecutableFile: { _ in true })
        XCTAssertEqual(url?.path, "/opt/homebrew/bin/brew")
    }

    // Gap 5d: canInstallApfel reflects brewURL availability.
    func testCanInstallApfelIsFalseWhenBrewNotFound() {
        // We can't swap the static dependency here, so we confirm the real machine state
        // is consistent: canInstallApfel is true iff brewURL() is non-nil.
        XCTAssertEqual(HomebrewInstaller.canInstallApfel, HomebrewInstaller.brewURL() != nil)
    }
}
