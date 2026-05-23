import Foundation

enum HomebrewInstaller {
    static let installCommand = "brew install apfel"

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
}
