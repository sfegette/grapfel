import Foundation

/// Manages the lifecycle of `apfel --serve` as a background process.
/// Phase 2 implementation.
actor ApfelServerManager {
    static let shared = ApfelServerManager()

    private var process: Process?
    private let port: Int

    init(port: Int = 11434) {
        self.port = port
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRunning else { return }
        let binary = try findBinary()
        let p = Process()
        p.executableURL = binary
        p.arguments = ["--serve", "--port", "\(port)", "--quiet"]
        try p.run()
        process = p

        // Give the server a moment to bind
        try await Task.sleep(for: .milliseconds(500))
        guard await healthCheck() else {
            p.terminate()
            process = nil
            throw ApfelError.serverStartFailed
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "http://localhost:\(port)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Binary discovery

    func findBinary() throws -> URL {
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/apfel"),
            URL(fileURLWithPath: "/usr/local/bin/apfel"),
            URL(fileURLWithPath: "/opt/homebrew/bin/apfel"),
        ]
        // Also try `which apfel` via shell
        if let pathResult = shellWhich("apfel") {
            candidates.first.map { _ in } // just to use the result below
            return URL(fileURLWithPath: pathResult)
        }
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            return url
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
