import XCTest

final class ApfelServerManagerTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFindBinaryPrefersUserOverrideWhenItExists() async throws {
        let defaults = makeTestUserDefaults()
        let overrideURL = URL(fileURLWithPath: "/tmp/custom-apfel")
        defaults.set(overrideURL.path, forKey: UserDefaultsKey.apfelBinaryPath)

        let manager = ApfelServerManager(
            userDefaults: defaults,
            candidateBinaryURLs: [URL(fileURLWithPath: "/tmp/candidate-apfel")],
            fileExists: { $0 == overrideURL.path },
            isExecutableFile: { $0 == overrideURL.path },
            fileIsDirectory: { _ in false },
            fileTypeProvider: { _ in "Mach-O 64-bit executable arm64" },
            shellWhichCommand: { _ in
                XCTFail("shellWhich should not be called when override exists")
                return nil
            }
        )

        let binary = try await manager.findBinary()
        XCTAssertEqual(binary, overrideURL)
    }

    func testFindBinaryUsesCandidateSearchOrderBeforeShellWhich() async throws {
        let defaults = makeTestUserDefaults()
        let first = URL(fileURLWithPath: "/tmp/first-apfel")
        let second = URL(fileURLWithPath: "/tmp/second-apfel")

        let manager = ApfelServerManager(
            userDefaults: defaults,
            candidateBinaryURLs: [first, second],
            fileExists: { $0 == second.path },
            isExecutableFile: { $0 == second.path },
            fileIsDirectory: { _ in false },
            fileTypeProvider: { _ in "Mach-O 64-bit executable arm64" },
            shellWhichCommand: { _ in
                return "/tmp/which-apfel"
            }
        )

        let binary = try await manager.findBinary()
        XCTAssertEqual(binary, second)
    }

    func testFindBinaryFallsBackToShellWhich() async throws {
        let defaults = makeTestUserDefaults()
        let shellPath = "/tmp/which-apfel"
        let manager = ApfelServerManager(
            userDefaults: defaults,
            candidateBinaryURLs: [],
            fileExists: { $0 == shellPath },
            isExecutableFile: { $0 == shellPath },
            fileIsDirectory: { _ in false },
            fileTypeProvider: { _ in "Mach-O 64-bit executable arm64" },
            shellWhichCommand: { _ in shellPath }
        )

        let binary = try await manager.findBinary()
        XCTAssertEqual(binary.path, shellPath)
    }

    func testHealthCheckSuccessReturnsTrueAndStoresVersion() async {
        let session = makeMockSession()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:11434/health")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = #"{"status":"ok","version":"0.9.1"}"#.data(using: .utf8)!
            return (response, data)
        }

        let manager = ApfelServerManager(session: session, userDefaults: makeTestUserDefaults())

        let healthy = await manager.healthCheck()

        XCTAssertTrue(healthy)
        let version = await manager.serverVersion
        XCTAssertEqual(version, "0.9.1")
    }

    func testHealthCheckFailureReturnsFalse() async {
        let session = makeMockSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let manager = ApfelServerManager(session: session, userDefaults: makeTestUserDefaults())

        let healthy = await manager.healthCheck()

        XCTAssertFalse(healthy)
        let version = await manager.serverVersion
        XCTAssertNil(version)
    }

    func testHealthCheckRejectsUnexpectedPayload() async {
        let session = makeMockSession()
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(#"{"ok":true}"#.utf8))
        }

        let manager = ApfelServerManager(session: session, userDefaults: makeTestUserDefaults())

        let healthy = await manager.healthCheck()

        XCTAssertFalse(healthy)
        let version = await manager.serverVersion
        XCTAssertNil(version)
    }
}
