import SwiftUI
import AppKit

struct SetupView: View {
    enum Mode: Equatable {
        case binaryNotFound
        case binaryInvalid(String)
        case startFailed(String)
    }

    let mode: Mode
    private var serverState = ServerState.shared
    @State private var isCopied = false
    @State private var isRetrying = false
    @Environment(\.openSettings) private var openSettings

    init(mode: Mode) {
        self.mode = mode
    }

    private let installCommand = "brew install apfel"

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
        case .binaryNotFound:
            binaryNotFoundContent
        case .binaryInvalid(let reason):
            binaryInvalidContent(reason)
        case .startFailed(let message):
            startFailedContent(message)
        }
    }

    private var binaryNotFoundContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            VStack(spacing: 8) {
                Text("apfel not installed")
                    .font(.headline)
                Text("grapfel requires apfel to run on-device AI.\nInstall it with Homebrew, then click Retry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            commandRow

            HStack(spacing: 12) {
                Button("Open Terminal") {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    )
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)

                retryButton
            }
        }
        .padding(.horizontal, 32)
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

    private var commandRow: some View {
        HStack(spacing: 8) {
            Text(installCommand)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(installCommand, forType: .string)
                isCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    isCopied = false
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
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
