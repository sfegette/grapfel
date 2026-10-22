import XCTest
@testable import grapfel

final class DiagnosticsReportTests: XCTestCase {
    func testReportListsVersionsAndErrorLines() {
        let report = DiagnosticsReport.build(errorLines: ["2026-01-01T00:00:00Z [model] Generation failed: rateLimited"])
        XCTAssertTrue(report.contains("Grapfel diagnostics"))
        XCTAssertTrue(report.contains("macOS:"))
        XCTAssertTrue(report.contains("Generation failed: rateLimited"))
    }

    func testReportWithoutErrorsSaysNone() {
        let report = DiagnosticsReport.build(errorLines: [])
        XCTAssertTrue(report.contains("none"))
    }

    func testDiagnosticCodeCarriesNoContent() {
        XCTAssertEqual(LocalModelError.contentFiltered("secret prompt text").diagnosticCode, "contentFiltered")
        XCTAssertEqual(LocalModelError.requestFailed("secret").diagnosticCode, "requestFailed")
    }
}
