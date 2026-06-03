import SwiftUI
import AppKit

struct SetupView: View {
    enum Mode: Equatable {
        case homebrewNotFound
        case binaryNotFound
        case binaryInvalid(String)
        case startFailed(String)
    }

    let mode: Mode
    private var serverState = ServerState.shared
    @State private var isRetrying = false
    @State private var isInstalling = false
    @State private var installLines: [String] = []
    @State private var installError: String? = nil
    @Environment(\.openSettings) private var openSettings

    init(mode: Mode) {
        self.mode = mode
    }

    private let installCommand = HomebrewInstaller.installCommand
    private let homebrewURL = URL(string: "https://brew.sh")!

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            Spacer()
            errorContent
            Spacer()
        }
    }

    private var headerBar: some View {
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

    @ViewBuilder
    private var errorContent: some View {
        switch mode {
        case .homebrewNotFound:
            homebrewNotFoundContent
        case .binaryNotFound:
            binaryNotFoundContent
        case .binaryInvalid(let reason):
            binaryInvalidContent(reason)
        case .startFailed(let message):
            startFailedContent(message)
        }
    }

    private var homebrewNotFoundContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Homebrew not installed")
                    .font(.headline)
                Text("grapfel uses Homebrew to install apfel, which provides the local Apple Intelligence server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Install Homebrew first, then return here and click Retry.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Open brew.sh") {
                    NSWorkspace.shared.open(homebrewURL)
                }

                retryButton
            }
        }
        .padding(.horizontal, 32)
    }

    private var binaryNotFoundContent: some View {
        VStack(spacing: 16) {
            if isInstalling || !installLines.isEmpty {
                installProgressContent
            } else {
                binaryNotFoundIdleContent
            }
        }
        .padding(.horizontal, 32)
    }

    private var binaryNotFoundIdleContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("apfel not installed")
                    .font(.headline)
                if let error = installError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Homebrew is installed, but apfel is not.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: 12) {
                Button {
                    runInstall()
                } label: {
                    Text(installError == nil ? "Install apfel" : "Try Again")
                }

                Button("Open Terminal") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(installCommand, forType: .string)
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    )
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("Copies the install command and opens Terminal.")

                retryButton
            }
        }
    }

    private var installProgressContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                if isInstalling {
                    ProgressView().controlSize(.small)
                    Text("Installing apfel…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text("Install complete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(installLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line)
                        }
                    }
                    .padding(6)
                }
                .frame(height: 140)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                .onChange(of: installLines.count) { _, _ in
                    if let last = installLines.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func runInstall() {
        installLines = []
        installError = nil
        isInstalling = true
        Task {
            do {
                try await HomebrewInstaller.install { line in
                    Task { @MainActor in self.installLines.append(line) }
                }
                isInstalling = false
                await serverState.retry()
            } catch {
                installError = error.localizedDescription
                isInstalling = false
            }
        }
    }

    private func binaryInvalidContent(_ reason: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("apfel binary invalid")
                    .font(.headline)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Check Settings to verify the binary path, or clear the override to auto-detect.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            retryButton
        }
        .padding(.horizontal, 32)
    }

    private func startFailedContent(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("Server failed to start")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            retryButton
        }
        .padding(.horizontal, 32)
    }


    private var retryButton: some View {
        Button {
            isRetrying = true
            Task {
                await serverState.retry()
                isRetrying = false
            }
        } label: {
            if isRetrying {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Starting...")
                        .font(.caption)
                }
            } else {
                Text("Retry")
            }
        }
        .disabled(isRetrying)
    }
}
