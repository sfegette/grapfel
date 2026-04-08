import SwiftUI

// MARK: - Conversation thread

/// Scrollable conversation thread — shows completed turns and the in-progress assistant response.
struct ConversationView: View {
    let history: [ChatMessage]
    let streamingContent: String
    let isLoading: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if history.isEmpty && !isLoading {
                        Text("start a conversation")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 28)
                    }

                    ForEach(history) { message in
                        MessageRow(message: message)
                    }

                    // In-progress assistant turn
                    if isLoading {
                        if streamingContent.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("thinking...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                        } else {
                            MessageRow(message: ChatMessage(role: .assistant, content: streamingContent))
                        }
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(12)
            }
            .onChange(of: history.count) {
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: streamingContent) {
                proxy.scrollTo("bottom")
            }
        }
        .background(.ultraThinMaterial, in: Rectangle())
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            Text(isUser ? "you" : "grapfel")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)

            Group {
                if isUser {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        MarkdownContent(text: message.content)
                            .padding(.horizontal, 10)
                            .padding(.top, 7)
                            .padding(.bottom, 2)

                        CopyButton(content: message.content)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 5)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(.purple.opacity(0.08)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(isUser ? .leading : .trailing, 40)
    }
}

// MARK: - Copy button

private struct CopyButton: View {
    let content: String
    @State private var copied = false

    var body: some View {
        HStack {
            Spacer()
            if copied {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                Button {
                    copy(content)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Copy as Markdown") {
                        copy(content)
                    }
                    Button("Copy as Code Block") {
                        copy("```markdown\n\(content)\n```")
                    }
                    Button("Copy as Plain Text") {
                        copy(stripMarkdown(content))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: copied)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private func stripMarkdown(_ text: String) -> String {
        var out = text
        // Remove fenced code blocks (keep content, drop fences + language tag)
        out = out.replacingOccurrences(of: #"```[^\n]*\n"#, with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "```", with: "")
        // Remove ATX headers — anchorsMatchLines requires NSRegularExpression directly
        if let re = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#, options: .anchorsMatchLines) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
        }
        // Remove bold / italic (**, *, __, _)
        out = out.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"__(.+?)__"#,     with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\*(.+?)\*"#,     with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(of: #"_(.+?)_"#,       with: "$1", options: .regularExpression)
        // Remove inline code backticks
        out = out.replacingOccurrences(of: #"`(.+?)`"#,       with: "$1", options: .regularExpression)
        // Remove strikethrough
        out = out.replacingOccurrences(of: #"~~(.+?)~~"#,     with: "$1", options: .regularExpression)
        return out
    }
}

// MARK: - Native Markdown renderer

/// Renders fenced code blocks with a monospace background; everything else via
/// AttributedString inline Markdown (bold, italic, inline code, strikethrough, links).
private struct MarkdownContent: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(segments(of: text)) { segment in
                if segment.isCode {
                    Text(segment.text)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Text(inlineMarkdown(segment.text))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: Fenced code block parser

    private struct Segment: Identifiable {
        let id = UUID()
        let text: String
        let isCode: Bool
    }

    private func segments(of source: String) -> [Segment] {
        var result: [Segment] = []
        var remaining = source

        while !remaining.isEmpty {
            guard let openRange = remaining.range(of: "```") else {
                // No more code fences — rest is prose
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { result.append(Segment(text: trimmed, isCode: false)) }
                break
            }

            // Prose before the opening fence
            let before = String(remaining[..<openRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty { result.append(Segment(text: before, isCode: false)) }

            remaining = String(remaining[openRange.upperBound...])

            // Strip optional language identifier on the first line (e.g. "swift\n")
            if let nl = remaining.firstIndex(of: "\n") {
                let lang = String(remaining[..<nl]).trimmingCharacters(in: .whitespaces)
                if !lang.isEmpty && lang.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "_" }) {
                    remaining = String(remaining[remaining.index(after: nl)...])
                }
            }

            // Find closing fence
            if let closeRange = remaining.range(of: "```") {
                let code = String(remaining[..<closeRange.lowerBound])
                    .trimmingCharacters(in: .newlines)
                if !code.isEmpty { result.append(Segment(text: code, isCode: true)) }
                remaining = String(remaining[closeRange.upperBound...])
                if remaining.hasPrefix("\n") { remaining = String(remaining.dropFirst()) }
            } else {
                // Unclosed fence — treat remainder as code
                let code = remaining.trimmingCharacters(in: .newlines)
                if !code.isEmpty { result.append(Segment(text: code, isCode: true)) }
                break
            }
        }

        return result.isEmpty ? [Segment(text: source, isCode: false)] : result
    }

    // MARK: Inline Markdown via AttributedString

    private func inlineMarkdown(_ raw: String) -> AttributedString {
        (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }
}
