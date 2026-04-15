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
                        }
                    }
                )
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        viewModel.prompt += "\n"
                        return .handled
                    }
                    guard !viewModel.trimmedPrompt.isEmpty, !viewModel.isLoading else { return .handled }
                    Task { await viewModel.send() }
                    return .handled
                }

            HStack(alignment: .center) {
                Button(action: viewModel.pickFiles) {
                    Label("attach", systemImage: "paperclip")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

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
            }

            HStack(alignment: .center) {
                Spacer()

                Button(action: { Task { await viewModel.send() } }) {
                    Label("send", systemImage: "arrow.up.circle.fill")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.trimmedPrompt.isEmpty || viewModel.isLoading)
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
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
        .foregroundStyle(.secondary)
    }
}
