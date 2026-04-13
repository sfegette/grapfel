import Foundation

/// Manages the lifecycle of `apfel --serve` as a background process.
actor ApfelServerManager {
    static let shared: ApfelServerManager = {
        let port = (UserDefaults.standard.object(forKey: UserDefaultsKey.serverPort) as? Int) ?? 11434
        return ApfelServerManager(port: port)
    }()

    private var process: Process?
    private let port: Int
    private var intentionalStop = false

    init(port: Int = 11434) {
        self.port = port
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
        p.arguments = ["--serve", "--port", "\(port)"]
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
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Binary discovery

    func findBinary() throws -> URL {
        // Check user-specified path override first
        let pathOverride = UserDefaults.standard.string(forKey: UserDefaultsKey.apfelBinaryPath) ?? ""
        if !pathOverride.isEmpty {
            let url = URL(fileURLWithPath: pathOverride)
            if FileManager.default.fileExists(atPath: url.path) { return url }
            // Override set but not found — fall through to auto-detect
        }

        // Search order: app bundle → /usr/local/bin → /opt/homebrew/bin → `which apfel`
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/apfel"),
            URL(fileURLWithPath: "/usr/local/bin/apfel"),
            URL(fileURLWithPath: "/opt/homebrew/bin/apfel"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        if let pathResult = shellWhich("apfel") {
            return URL(fileURLWithPath: pathResult)
        }
        throw ApfelError.binaryNotFound
    }

    private func shellWhich(_ name: String) -> String? {
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

enum ApfelError: LocalizedError {
    case binaryNotFound
    case serverStartFailed
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "apfel binary not found. Install with: brew tap Arthur-Ficial/tap && brew install apfel"
        case .serverStartFailed:
            return "apfel server failed to start. Check that port 11434 is available."
        case .requestFailed(let msg):
            return "Request failed: \(msg)"
        }
    }
}
