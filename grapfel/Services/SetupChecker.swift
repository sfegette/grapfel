import Foundation

enum SetupChecker {
    static func isHomebrewInstalled(
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        isExecutableFile("/opt/homebrew/bin/brew") || isExecutableFile("/usr/local/bin/brew")
    }
}
