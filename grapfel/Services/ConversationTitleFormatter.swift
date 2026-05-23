import Foundation

struct ConversationTitleFormatter {
    static let maxLength = 40

    static func title(for text: String) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.count > maxLength else { return normalized }

        let cutoff = normalized.index(normalized.startIndex, offsetBy: maxLength)
        let prefix = String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToBoundary = prefix[..<(prefix.lastIndex(of: " ") ?? prefix.endIndex)]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedToBoundary.isEmpty {
            return prefix + "…"
        }

        return trimmedToBoundary + "…"
    }
}
