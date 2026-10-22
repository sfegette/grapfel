import AppKit
import Foundation
import OSLog

enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.brilliantmindworks.grapfel"
    static let model = Logger(subsystem: subsystem, category: "model")
}

/// A short, user-initiated report for pasting into a support issue. Nothing is sent anywhere:
/// it is built locally and copied to the clipboard. It never includes prompts, responses,
/// attachments, or file paths — only versions, the model's availability, and the app's own
/// recent error codes from this launch.
enum DiagnosticsReport {
    static func build(now: Date = Date(), errorLines: [String]? = nil) -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let lines = errorLines ?? recentErrorLines()

        var report = [
            "Grapfel diagnostics",
            "Date: \(ISO8601DateFormatter().string(from: now))",
            "App: \(version) (\(build))",
            "macOS: \(os)",
            "Architecture: \(architecture)",
            "Recent errors (this launch):"
        ]
        report += lines.isEmpty ? ["  none"] : lines.map { "  \($0)" }
        return report.joined(separator: "\n")
    }

    @MainActor
    static func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(build(), forType: .string)
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    /// Error-level entries this process wrote under the app's subsystem, newest last.
    private static func recentErrorLines(limit: Int = 50) -> [String] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let predicate = NSPredicate(format: "subsystem == %@", AppLog.subsystem)
        guard let entries = try? store.getEntries(matching: predicate) else { return [] }
        let formatter = ISO8601DateFormatter()
        let lines = entries.compactMap { $0 as? OSLogEntryLog }
            .filter { $0.level == .error || $0.level == .fault }
            .map { "\(formatter.string(from: $0.date)) [\($0.category)] \($0.composedMessage)" }
        return Array(lines.suffix(limit))
    }
}
