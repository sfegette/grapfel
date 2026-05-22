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

    func stop() async {
        intentionalStop = true
        if let p = process {
            // We spawned this process — terminate it directly.
            p.terminate()
            process = nil
        } else {
            // We adopted an external process — find it by port and terminate it.
            await killProcessOnPort(port, signal: SIGTERM)
        }
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

    // MARK: - Port-based process kill

    /// Finds the PID listening on `port` via `lsof -ti tcp:<port>`, sends `signal`,
    /// waits up to `gracePeriod` for it to exit, then sends SIGKILL.
    private func killProcessOnPort(_ port: Int, signal: Int32, gracePeriod: Duration = .seconds(3)) async {
        guard let pid = pidListeningOnPort(port) else { return }
        kill(pid, signal)

        // Poll for up to gracePeriod; if still alive, force-kill.
        let deadline = ContinuousClock.now + gracePeriod
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(200))
            if kill(pid, 0) != 0 { return }  // process is gone
        }
        // Grace period elapsed — force kill.
        kill(pid, SIGKILL)
    }

    /// Returns the PID of the process listening on the given TCP port, or nil.
    private func pidListeningOnPort(_ port: Int) -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        p.arguments = ["-ti", "tcp:\(port)"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()  // suppress lsof error output
        try? p.run()
        p.waitUntilExit()
        let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // lsof may return multiple PIDs (one per file descriptor); use the first.
        let firstLine = raw.split(separator: "\n").first.map(String.init) ?? raw
        return pid_t(firstLine)
    }

    // MARK: - Binary discovery

    func findBinary() throws -> URL {
        // Check user-specified path override first
        let pathOverride = userDefaults.string(forKey: UserDefaultsKey.apfelBinaryPath) ?? ""
        if !pathOverride.isEmpty {
            let url = URL(fileURLWithPath: pathOverride)
            // Override is set — validate strictly; do not fall through to auto-detect.
            try validateBinary(at: url)
            return url
        }

        // Search order: app bundle → /usr/local/bin → /opt/homebrew/bin → `which apfel`
        for url in candidateBinaryURLs {
            if (try? validateBinary(at: url)) != nil { return url }
        }
        if let pathResult = shellWhichCommand("apfel") {
            let url = URL(fileURLWithPath: pathResult)
            try validateBinary(at: url)
            return url
        }
        throw ApfelError.binaryNotFound
    }

    /// Validates that the file at `url` exists and is executable.
    /// Throws `ApfelError.binaryInvalid` if the file exists but fails validation,
    /// or `ApfelError.binaryNotFound` if the file does not exist at all.
    func validateBinary(at url: URL) throws {
        let fm = FileManager.default
        let path = url.path
        guard fm.fileExists(atPath: path) else { throw ApfelError.binaryNotFound }
        guard fm.isExecutableFile(atPath: path) else {
            throw ApfelError.binaryInvalid("not executable: \(path)")
        }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: path, isDirectory: &isDir)
        if isDir.boolValue { throw ApfelError.binaryInvalid("path is a directory: \(path)") }
        // Best-effort Mach-O check — reject shell scripts named "apfel", allow Rosetta.
        if let fileType = shellFileType(at: path) {
            guard fileType.contains("Mach-O") || fileType.contains("executable") else {
                throw ApfelError.binaryInvalid("not a Mach-O executable (\(fileType)): \(path)")
            }
        }
    }

    private func shellFileType(at path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        p.arguments = [path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    case binaryInvalid(String)
    case serverStartFailed
    case requestFailed(String)
    case rateLimited
    case modelUnavailable

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "apfel binary not found. Install with: brew install apfel"
        case .binaryInvalid(let reason):
            return "apfel binary is invalid: \(reason)"
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
