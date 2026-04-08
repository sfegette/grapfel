import SwiftUI

/// Root view hosted inside the GrapfelPanel.
struct ContentView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(hasHistory: !viewModel.history.isEmpty) {
                viewModel.clearHistory()
            }
            Divider()
            ConversationView(
                history: viewModel.history,
                streamingContent: viewModel.streamingContent,
                isLoading: viewModel.isLoading
            )
            Divider()
            OptionsPanel(options: $viewModel.options)
            Divider()
            PromptInputView(viewModel: viewModel)
        }
        .frame(width: 420, height: 580)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .opacity(0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct HeaderBar: View {
    @Environment(\.openSettings) private var openSettings
    let hasHistory: Bool
    let onClear: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text("grapfel")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            if hasHistory {
                Button(action: onClear) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .help("New conversation")
                .transition(.opacity)
            }
            Button(action: { openSettings() }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
        }
        .animation(.easeInOut(duration: 0.15), value: hasHistory)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    ContentView()
}
