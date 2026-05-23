import SwiftUI

// MARK: - Conversation thread

/// Scrollable conversation thread — shows completed turns and the in-progress assistant response.
struct ConversationView: View {
    let history: [ChatMessage]
    let streamingContent: String
    let isLoading: Bool
    var responseAnnotation: String? = nil
    var usageAnnotation: String? = nil
    var canRegenerate: Bool = false
    var onRegenerate: (() -> Void)? = nil
    var onEditLast: (() -> Void)? = nil

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if history.isEmpty && !isLoading {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                            Text("How can I help you today?")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Runs entirely on-device — private by default.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                            Text("Prompts and attachments go only to your local apfel server on 127.0.0.1. Conversation storage stays on this Mac unless you export it.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                        .padding(.horizontal, 24)
                        .accessibilityElement(children: .combine)
                    }

                    // Completed turns — use equatable wrapper so cells don't re-render
                    // when streamingContent changes; only the streaming bubble below changes.
                    ForEach(history, id: \.id) { message in
                        MessageRow(message: message)
                            .equatable()
                    }

                    // Footer: truncation/filter annotation + token usage + conversation controls
                    if !isLoading, history.last?.role == .assistant {
                        let parts = [responseAnnotation, usageAnnotation].compactMap { $0 }
                        if !parts.isEmpty || canRegenerate {
                            HStack(alignment: .center, spacing: 6) {
                                if !parts.isEmpty {
                                    Text(parts.joined(separator: " · "))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if canRegenerate {
                                    Button(action: { onEditLast?() }) {
                                        Image(systemName: "pencil")
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tertiary)
                                    .help("Edit last message")
                                    .accessibilityLabel("Edit last message")

                                    Button(action: { onRegenerate?() }) {
                                        Image(systemName: "arrow.clockwise")
                                    }
                                    .font(.caption2)
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tertiary)
                                    .help("Regenerate response")
                                    .accessibilityLabel("Regenerate response")
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.bottom, 2)
                        }
                    }

                    // In-progress assistant turn — rendered as plain Text while streaming
                    // to avoid per-token MarkdownSegmenter re-parsing churn. Markdown is
                    // only rendered for completed turns stored in `history`.
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
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Generating response")
                        } else {
                            StreamingBubble(content: streamingContent)
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
            .onAppear {
                // Defer one run-loop cycle so LazyVStack items are laid out before scrollTo
                DispatchQueue.main.async {
                    proxy.scrollTo("bottom")
                }
            }
        }
        .background(.ultraThinMaterial, in: Rectangle())
    }
}

// MARK: - Message row

/// Completed turn cell. Conforms to `Equatable` so callers can use `.equatable()`
/// to skip re-renders when only `streamingContent` (outside this cell) changes.
private struct MessageRow: View, Equatable {
    let message: ChatMessage

    nonisolated static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message.id == rhs.message.id && lhs.message.content == rhs.message.content
    }

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            Text(isUser ? "you" : "grapfel")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUser ? "You" : "grapfel"): \(message.content)")
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Streaming bubble

/// In-progress assistant response rendered as plain `Text` to avoid per-token
/// `MarkdownSegmenter` re-parsing. Markdown formatting is applied only once the
/// turn is complete and stored in `history` as a finished `MessageRow`.
private struct StreamingBubble: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("grapfel")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .accessibilityHidden(true)

            Text(content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(.purple.opacity(0.08)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Generating response: \(content)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Copy button

private struct CopyButton: View {
    let content: String
    @State private var copied = false

    private static let headerRegex = try? NSRegularExpression(pattern: #"^#{1,6}\s+"#, options: .anchorsMatchLines)

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
                .accessibilityLabel("Copy response")
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
        if let re = Self.headerRegex {
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
            ForEach(MarkdownSegmenter.segments(of: text)) { segment in
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

    // MARK: Inline Markdown via AttributedString

    private func inlineMarkdown(_ raw: String) -> AttributedString {
        (try? AttributedString(
            markdown: raw,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(raw)
    }
}
