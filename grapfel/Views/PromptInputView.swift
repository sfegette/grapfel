import SwiftUI

struct PromptInputView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .padding(14)
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Group {
                        if viewModel.prompt.isEmpty {
                            Text("prompt...")
                                .foregroundStyle(.tertiary)
                                .padding(18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                )
                .accessibilityLabel("Message input")
                .accessibilityHint("Press Return to send. Press Command-Return to insert a newline.")
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        viewModel.prompt += "\n"
                        return .handled
                    }
                    guard !viewModel.trimmedPrompt.isEmpty, !viewModel.isLoading else { return .handled }
                    viewModel.beginSend()
                    return .handled
                }

            HStack(alignment: .center) {
                Button(action: viewModel.pickFiles) {
                    Label("attach", systemImage: "paperclip")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Attach files")

                if !viewModel.attachedFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.attachedFiles, id: \.self) { url in
                                AttachmentChip(filename: url.lastPathComponent) {
                                    viewModel.removeAttachedFile(url)
                                }
                            }
                        }
                    }
                }

                Spacer()
            }

            if viewModel.attachedFilesExceedBudget {
                Label(
                    "File(s) exceed context budget — content will be truncated before sending.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Warning: file contents exceed context budget and will be truncated before sending")
            }

            HStack(alignment: .center) {
                Spacer()

                if viewModel.isLoading {
                    Button(action: { viewModel.stopGeneration() }) {
                        Label("stop", systemImage: "stop.circle.fill")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("Stop generation")
                } else {
                    Button(action: { viewModel.beginSend() }) {
                        Label("send", systemImage: "arrow.up.circle.fill")
                            .font(.callout.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.trimmedPrompt.isEmpty)
                    .accessibilityLabel("Send message")
                    .accessibilityHint(viewModel.trimmedPrompt.isEmpty ? "Enter a message to enable" : "")
                }
            }
        }
        .padding(16)
    }
}

private struct AttachmentChip: View {
    let filename: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.caption2)
            Text(filename)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(filename)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
    }
}
