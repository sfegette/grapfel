import SwiftUI

/// Root view hosted inside the GrapfelPanel.
struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    private var serverState = ServerState.shared

    var body: some View {
        mainContent
            .frame(width: 420, height: 580)
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var mainContent: some View {
        switch serverState.status {
        case .starting:
            startingView
        case .binaryNotFound:
            SetupView(mode: .binaryNotFound)
        case .startFailed(let message):
            SetupView(mode: .startFailed(message))
        case .running:
            chatView
        }
    }

    private var startingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("Starting apfel…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chatView: some View {
        VStack(spacing: 0) {
            HeaderBar(hasHistory: !viewModel.history.isEmpty) {
                viewModel.clearHistory()
            }
            Divider()
            if serverState.isApfelOutdated && !serverState.isUpdateBannerDismissed,
               let version = serverState.apfelVersion {
                UpdateNudgeBanner(currentVersion: version) {
                    serverState.isUpdateBannerDismissed = true
                }
                Divider()
            }
            ConversationView(
                history: viewModel.history,
                streamingContent: viewModel.streamingContent,
                isLoading: viewModel.isLoading,
                responseAnnotation: viewModel.responseAnnotation,
                usageAnnotation: viewModel.usageAnnotation
            )
            Divider()
            OptionsPanel(options: $viewModel.options)
            Divider()
            PromptInputView(viewModel: viewModel)
        }
    }
}

// MARK: - Header bar

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

// MARK: - Update nudge banner

private struct UpdateNudgeBanner: View {
    let currentVersion: String
    let onDismiss: () -> Void
    @State private var isCopied = false

    private let upgradeCommand = "brew upgrade apfel"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("apfel \(currentVersion) is outdated — run")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(upgradeCommand, forType: .string)
                isCopied = true
                Task { try? await Task.sleep(for: .seconds(2)); isCopied = false }
            } label: {
                Text(upgradeCommand)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.07))
    }
}

#Preview {
    ContentView()
}
