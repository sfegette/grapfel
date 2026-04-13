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
                .disabled(viewModel.trimmedPrompt.isEmpty || viewModel.isLoading)
            }
        }
        .padding(16)
    }
}
