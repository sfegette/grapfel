import SwiftUI
import AppKit

/// Central state for the popover: prompt, response, options, file attachments.
/// @MainActor because all properties are read/written by SwiftUI on the main thread.
@Observable
@MainActor
class ChatViewModel {
    var prompt: String = ""
    var response: String = ""
    var isLoading: Bool = false
    var options: ApfelOptions = .defaults
    var attachedFiles: [URL] = []

    private let apiClient = ApfelAPIClient()

    func send() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        response = ""
        prompt = ""

        var messages: [ChatMessage] = []
        let sys = options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            messages.append(ChatMessage(role: .system, content: sys))
        }
        messages.append(ChatMessage(role: .user, content: trimmed))

        do {
            if options.streaming {
                for try await chunk in apiClient.stream(messages: messages, options: options) {
                    response += chunk
                }
            } else {
                response = try await apiClient.complete(messages: messages, options: options)
            }
        } catch {
            response = "Error: \(error.localizedDescription)"
        }

        isLoading = false
        attachedFiles = []
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
