import SwiftUI

struct ModelUnavailableView: View {
    let reason: ModelAvailabilityState.Reason
    private var modelState = ModelAvailabilityState.shared
    @Environment(\.openSettings) private var openSettings

    init(reason: ModelAvailabilityState.Reason) {
        self.reason = reason
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            Spacer()
            VStack(spacing: 18) {
                Image(systemName: iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)

                VStack(spacing: 8) {
                    Text(reason.title)
                        .font(.headline)
                    Text(reason.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Try Again") {
                    modelState.refresh()
                }
            }
            .padding(.horizontal, 34)
            Spacer()
        }
    }

    private var headerBar: some View {
        HStack {
            Image("StatusBarIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundStyle(.secondary)
            Text("grapfel")
                .font(.headline)
                .fontWeight(.semibold)
            Spacer()
            Button(action: { openSettings() }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var iconName: String {
        switch reason {
        case .deviceNotEligible:
            return "desktopcomputer.trianglebadge.exclamationmark"
        case .appleIntelligenceNotEnabled:
            return "apple.intelligence"
        case .modelNotReady:
            return "arrow.down.circle"
        }
    }
}
