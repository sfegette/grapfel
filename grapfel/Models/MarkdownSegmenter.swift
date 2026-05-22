import Foundation

struct MarkdownSegment: Identifiable, Equatable {
    /// Stable identity derived from content so that `ForEach` can reuse views
    /// across re-segmentation calls instead of creating fresh nodes every token.
    var id: String { "\(isCode ? "code" : "text"):\(text)" }
    let text: String
    let isCode: Bool
}

enum MarkdownSegmenter {
    static func segments(of source: String) -> [MarkdownSegment] {
        var result: [MarkdownSegment] = []
        var remaining = source

        while !remaining.isEmpty {
            guard let openRange = remaining.range(of: "```") else {
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(MarkdownSegment(text: trimmed, isCode: false)) }
                break
            }

            let before = String(remaining[..<openRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { result.append(MarkdownSegment(text: before, isCode: false)) }

            remaining = String(remaining[openRange.upperBound...])

            if let nl = remaining.firstIndex(of: "\n") {
                let lang = String(remaining[..<nl]).trimmingCharacters(in: .whitespaces)
                if !lang.isEmpty && lang.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" }) {
                    remaining = String(remaining[remaining.index(after: nl)...])
                }
            }

            if let closeRange = remaining.range(of: "```") {
                let code = String(remaining[..<closeRange.lowerBound])
                    .trimmingCharacters(in: .newlines)
                if !code.isEmpty { result.append(MarkdownSegment(text: code, isCode: true)) }
                remaining = String(remaining[closeRange.upperBound...])
                if remaining.hasPrefix("\n") { remaining = String(remaining.dropFirst()) }
            } else {
                let code = remaining.trimmingCharacters(in: .newlines)
                if !code.isEmpty { result.append(MarkdownSegment(text: code, isCode: true)) }
                break
            }
        }

        return result.isEmpty ? [MarkdownSegment(text: source, isCode: false)] : result
    }
}
