import Foundation

enum HomebrewError: LocalizedError {
    case brewNotFound
    case commandFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew not found. Install Homebrew first, then retry."
        case .commandFailed(let code):
            return "brew exited with status \(code)."
        }
    }
}

enum HomebrewInstaller {
    static let installCommand = "brew install apfel"
    static let upgradeCommand = "brew upgrade apfel"

    static func brewURL(
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return candidates
            .first(where: isExecutableFile)
            .map(URL.init(fileURLWithPath:))
    }

    static var canInstallApfel: Bool {
        brewURL() != nil
    }

    static func install(onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await run(["install", "apfel"], onOutput: onOutput)
    }

    static func upgrade(onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await run(["upgrade", "apfel"], onOutput: onOutput)
    }

    /// Returns the latest stable version available in the Homebrew tap, or nil on failure.
    static func latestAvailableVersion() async -> String? {
        guard let brew = brewURL() else { return nil }
        return await withCheckedContinuation { continuation in
            let p = Process()
            p.executableURL = brew
            p.arguments = ["info", "--json", "apfel"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                struct BrewInfo: Decodable {
                    struct Versions: Decodable { let stable: String }
                    let versions: Versions
                }
                let version = try? JSONDecoder().decode([BrewInfo].self, from: data).first?.versions.stable
                continuation.resume(returning: version)
            }
            try? p.run()
        }
    }

    // MARK: - Private

    private static func run(
        _ args: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws {
        guard let brew = brewURL() else { throw HomebrewError.brewNotFound }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let p = Process()
            p.executableURL = brew
            p.arguments = args
            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            let emit: @Sendable (FileHandle) -> Void = { fh in
                let data = fh.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                for line in text.components(separatedBy: "\n") where !line.isEmpty {
                    DispatchQueue.main.async { onOutput(line) }
                }
            }
            outPipe.fileHandleForReading.readabilityHandler = emit
            errPipe.fileHandleForReading.readabilityHandler = emit

            p.terminationHandler = { process in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HomebrewError.commandFailed(process.terminationStatus))
                }
            }

            do {
                try p.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
