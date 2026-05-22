import SwiftUI

private let chatWidth: CGFloat = 420
private let sidebarWidth: CGFloat = 200
private let panelHeight: CGFloat = 580
private let expandBy: CGFloat = sidebarWidth + 1   // sidebar + divider

struct ContentView: View {
    @State private var viewModel = ChatViewModel()
    @State private var sidebarVisible = false
    private var serverState = ServerState.shared
    private var store = ConversationStore.shared

    var body: some View {
        // The panel is always (chatWidth + expandBy) wide. The left expandBy pts are
        // transparent when the sidebar is hidden — the chat area never moves or resizes.
        ZStack(alignment: .trailing) {
            // Size-setter: keeps the ZStack at full panel width so the chat area stays
            // right-anchored. No visual, no hit-testing.
            Color.clear
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                if sidebarVisible {
                    SidebarView()
                        .transition(.move(edge: .leading))
                    Divider()
                        .transition(.opacity)
                }
                mainContent
                    .frame(width: chatWidth, height: panelHeight)
            }
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .opacity(0.75)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(width: chatWidth + expandBy, height: panelHeight)
        .onChange(of: store.activeID) { (_: UUID?, newID: UUID?) in
            guard let newID,
                  let record = store.conversations.first(where: { $0.id == newID })
            else { return }
            viewModel.loadConversation(record)
        }
    }

    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.25)) {
            sidebarVisible.toggle()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch serverState.status {
        case .starting:
            startingView
        case .binaryNotFound:
            SetupView(mode: .binaryNotFound)
        case .binaryInvalid(let reason):
            SetupView(mode: .binaryInvalid(reason))
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
            HeaderBar(sidebarVisible: sidebarVisible, onToggleSidebar: toggleSidebar) {
                store.createAndActivate()
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
                usageAnnotation: viewModel.usageAnnotation,
                canRegenerate: viewModel.canRegenerate,
                onRegenerate: { viewModel.regenerate() },
                onEditLast: { viewModel.editLast() }
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
    let sidebarVisible: Bool
    let onToggleSidebar: () -> Void
    let onNewConversation: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggleSidebar) {
                Image(systemName: "line.3.horizontal")
            }
            .buttonStyle(.plain)
            .help("Conversations")
            .accessibilityLabel(sidebarVisible ? "Hide conversations" : "Show conversations")

            Image(systemName: "sparkles")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("grapfel")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button(action: onNewConversation) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .help("New conversation")
            .accessibilityLabel("New conversation")
            Button(action: { openSettings() }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
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
