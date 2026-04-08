import SwiftUI
import AppKit

/// Central state for the panel: prompt, conversation history, options, file attachments.
/// @MainActor because all properties are read/written by SwiftUI on the main thread.
@Observable
@MainActor
class ChatViewModel {
    var prompt: String = ""
    var history: [ChatMessage] = []       // completed user + assistant turns
    var streamingContent: String = ""     // in-progress assistant text (streaming only)
    var isLoading: Bool = false
    var options: ApfelOptions
    var attachedFiles: [URL] = []

    private let apiClient = ApfelAPIClient()

    init() {
        let ud = UserDefaults.standard
        var opts = ApfelOptions.defaults
        if let t = ud.object(forKey: "defaultTemperature") as? Double { opts.temperature = t }
        if let m = ud.object(forKey: "defaultMaxTokens") as? Int      { opts.maxTokens = m }
        options = opts
        loadHistory()
    }

    // MARK: - Send

    func send() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isLoading = true
        streamingContent = ""
        prompt = ""

        // Append user turn first so it appears immediately in the UI
        history.append(ChatMessage(role: .user, content: trimmed))

        // Build message list: optional system prompt + full history (including new user turn)
        var messages: [ChatMessage] = []
        let sys = options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            messages.append(ChatMessage(role: .system, content: sys))
        }
        messages.append(contentsOf: history)

        do {
            let assistantContent: String
            if options.streaming {
                var accumulated = ""
                for try await chunk in apiClient.stream(messages: messages, options: options) {
                    accumulated += chunk
                    streamingContent = accumulated
                }
                assistantContent = accumulated
            } else {
                assistantContent = try await apiClient.complete(messages: messages, options: options)
            }
            history.append(ChatMessage(role: .assistant, content: assistantContent))
        } catch {
            history.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }

        streamingContent = ""
        isLoading = false
        attachedFiles = []
        saveHistory()
    }

    // MARK: - Conversation management

    func clearHistory() {
        history = []
        streamingContent = ""
        prompt = ""
        deleteHistoryFile()
    }

    // MARK: - Persistence

    private var historyFileURL: URL? {
        guard let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = support.appendingPathComponent("grapfel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation.json")
    }

    private func saveHistory() {
        guard let url = historyFileURL,
              let data = try? JSONEncoder().encode(history)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadHistory() {
        guard let url = historyFileURL,
              let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([ChatMessage].self, from: data)
        else { return }
        history = messages
    }

    private func deleteHistoryFile() {
        guard let url = historyFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - File picker

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
