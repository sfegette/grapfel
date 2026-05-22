import Foundation

/// Manages the lifecycle of `apfel --serve` as a background process.
actor ApfelServerManager {
    static let shared = ApfelServerManager()

    private var process: Process?
    private var port: Int { (userDefaults.object(forKey: UserDefaultsKey.serverPort) as? Int) ?? 11434 }
    private let session: URLSession
    private let userDefaults: UserDefaults
    private let candidateBinaryURLs: [URL]
    private let fileExists: @Sendable (String) -> Bool
    private let shellWhichCommand: @Sendable (String) -> String?
    private var intentionalStop = false
    private(set) var serverVersion: String? = nil

    init(
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        candidateBinaryURLs: [URL] = ApfelServerManager.defaultCandidateBinaryURLs(),
        fileExists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        shellWhichCommand: @escaping @Sendable (String) -> String? = ApfelServerManager.defaultShellWhich(_:)
    ) {
        self.session = session
        self.userDefaults = userDefaults
        self.candidateBinaryURLs = candidateBinaryURLs
        self.fileExists = fileExists
        self.shellWhichCommand = shellWhichCommand
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }
        intentionalStop = false

        // If something is already healthy on this port (e.g. orphaned process from
        // a previous Xcode debug session killed via SIGKILL), adopt it and skip spawn.
        if await healthCheck() { return }

        let binary = try findBinary()
        let p = Process()
        p.executableURL = binary
        var args = ["--serve", "--port", "\(port)"]
        if userDefaults.bool(forKey: UserDefaultsKey.apfelPermissive) {
            args.append("--permissive")
        }
        let mcpPaths = userDefaults.array(forKey: UserDefaultsKey.mcpServers) as? [String] ?? []
        for path in mcpPaths where !path.isEmpty {
            args += ["--mcp", path]
        }
        p.arguments = args
        p.terminationHandler = { [weak self] _ in
            Task { await self?.handleCrash() }
        }
        try p.run()
        process = p

        // Give the server a moment to bind
        try await Task.sleep(for: .milliseconds(500))
        guard await healthCheck() else {
            // Mark intentional so terminationHandler doesn't restart
            intentionalStop = true
            p.terminate()
            process = nil
            intentionalStop = false  // reset for future start() calls
            throw ApfelError.serverStartFailed
        }
    }

    func stop() {
        intentionalStop = true
        process?.terminate()
        process = nil
    }

    private func handleCrash() async {
        guard !intentionalStop else { return }
        process = nil
        // Back off 1 s before restart to avoid tight restart loops
        try? await Task.sleep(for: .seconds(1))
        try? await start()
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            if let health = try? JSONDecoder().decode(HealthResponse.self, from: data) {
                serverVersion = health.version
            }
            return true
        } catch {
            return false
        }
    }

    // MARK: - Binary discovery

    func findBinary() throws -> URL {
        // Check user-specified path override first
        let pathOverride = userDefaults.string(forKey: UserDefaultsKey.apfelBinaryPath) ?? ""
        if !pathOverride.isEmpty {
            let url = URL(fileURLWithPath: pathOverride)
            if fileExists(url.path) { return url }
            // Override set but not found — fall through to auto-detect
        }

        // Search order: app bundle → /usr/local/bin → /opt/homebrew/bin → `which apfel`
        for url in candidateBinaryURLs where fileExists(url.path) {
            return url
        }
        if let pathResult = shellWhichCommand("apfel") {
            return URL(fileURLWithPath: pathResult)
        }
        throw ApfelError.binaryNotFound
    }

    private static func defaultCandidateBinaryURLs() -> [URL] {
        [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/apfel"),
            URL(fileURLWithPath: "/usr/local/bin/apfel"),
            URL(fileURLWithPath: "/opt/homebrew/bin/apfel"),
        ]
    }

    private static func defaultShellWhich(_ name: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        let pipe = Pipe()
        p.standardOutput = pipe
        try? p.run()
        p.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.flatMap { $0.isEmpty ? nil : $0 }
    }
}

// MARK: - Health response

private struct HealthResponse: Decodable {
    let status: String
    let version: String?
}

// MARK: - Errors

enum ApfelError: LocalizedError {
    case binaryNotFound
    case serverStartFailed
    case requestFailed(String)
    case rateLimited
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "apfel binary not found. Install with: brew install apfel"
        case .serverStartFailed:
            return "apfel server failed to start. Check that port 11434 is available."
        case .requestFailed(let msg):
            return "Request failed: \(msg)"
        case .rateLimited:
            return "Apple Intelligence is busy — try again in a moment."
        case .modelUnavailable:
            return "Apple Intelligence is not available. Check that it's enabled in System Settings → Apple Intelligence & Siri."
        }
    }

    static func from(httpStatus: Int, message: String) -> ApfelError {
        switch httpStatus {
        case 429: return .rateLimited
        case 503: return .modelUnavailable
        default:  return .requestFailed(message)
        }
    }
}
