import Foundation

struct MarkdownSegment: Identifiable, Equatable {
    /// Stable identity derived from content so that `ForEach` can reuse views
    /// across re-segmentation calls instead of creating fresh nodes every token.
    var id: String { "\(isCode ? "code" : "text"):\(text)" }
    let text: String
    let isCode: Bool
}

enum MarkdownBlockKind: Equatable {
    case prose
    case heading(level: Int)
}

struct MarkdownBlock: Equatable {
    let text: String
    let kind: MarkdownBlockKind
}

enum MarkdownBlockParser {
    static func blocks(of source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var proseLines: [Substring] = []

        func flushProse() {
            let prose = proseLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .newlines)
            if !prose.isEmpty {
                blocks.append(MarkdownBlock(text: prose, kind: .prose))
            }
            proseLines.removeAll(keepingCapacity: true)
        }

        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if let heading = heading(from: line) {
                flushProse()
                blocks.append(heading)
            } else {
                proseLines.append(line)
            }
        }
        flushProse()

        return blocks.isEmpty
            ? [MarkdownBlock(text: source, kind: .prose)]
            : blocks
    }

    private static func heading(from line: Substring) -> MarkdownBlock? {
        var markerEnd = line.startIndex
        var level = 0
        while markerEnd < line.endIndex, line[markerEnd] == "#" {
            level += 1
            markerEnd = line.index(after: markerEnd)
        }

        guard (1...6).contains(level),
              markerEnd < line.endIndex,
              line[markerEnd].isWhitespace
        else { return nil }

        let title = line[markerEnd...]
            .drop(while: { $0.isWhitespace })
            .trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }
        return MarkdownBlock(text: title, kind: .heading(level: level))
    }
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
