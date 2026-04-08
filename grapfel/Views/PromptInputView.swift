import SwiftUI

struct PromptInputView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $viewModel.prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 160)
                .scrollContentBackground(.hidden)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Group {
                        if viewModel.prompt.isEmpty {
                            Text("prompt...")
                                .foregroundStyle(.tertiary)
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                .allowsHitTesting(false)
                        }
                    }
                )
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        // ⌘+Enter → insert newline
                        viewModel.prompt += "\n"
                        return .handled
                    }
                    // Enter → send (if prompt is non-empty and not already loading)
                    let trimmed = viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, !viewModel.isLoading else { return .handled }
                    Task { await viewModel.send() }
                    return .handled
                }

            HStack {
                Button(action: viewModel.pickFiles) {
                    Label("attach", systemImage: "paperclip")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !viewModel.attachedFiles.isEmpty {
                    Text("\(viewModel.attachedFiles.count) file(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: { Task { await viewModel.send() } }) {
                    Label("send", systemImage: "arrow.up.circle.fill")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            }
        }
        .padding(16)
    }
}
