import SwiftUI

/// Root view hosted inside the menubar popover.
struct ContentView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()
            PromptInputView(viewModel: viewModel)
            Divider()
            OptionsPanel(options: $viewModel.options)
            Divider()
            ResponseView(text: viewModel.response, isLoading: viewModel.isLoading)
        }
        .frame(width: 420, height: 580)
        // TODO: Phase 8 — apply .glassEffect() here
    }
}

private struct HeaderBar: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
            Text("grapfel")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button(action: { openSettings() }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

#Preview {
    ContentView()
}
