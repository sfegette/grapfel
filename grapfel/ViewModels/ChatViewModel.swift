import SwiftUI
import AppKit

/// Central state for the popover: prompt, response, options, file attachments.
@Observable
class ChatViewModel {
    var prompt: String = ""
    var response: String = ""
    var isLoading: Bool = false
    var options: ApfelOptions = .defaults
    var attachedFiles: [URL] = []

    // TODO: Phase 2/3 — inject real service
    // private let apiClient = ApfelAPIClient()

    func send() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        await MainActor.run {
            isLoading = true
            response = ""
        }

        // TODO: Phase 3 — replace stub with real streaming call
        // Stub: echo the prompt back with a delay to test UI wiring
        try? await Task.sleep(for: .seconds(0.5))
        await MainActor.run {
            response = "[ stub response — Phase 3 will wire up apfel ]\n\nYou said: \(trimmed)"
            isLoading = false
            prompt = ""
            attachedFiles = []
        }
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            attachedFiles = panel.urls
        }
    }
}
