import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    private let historyFileURL: URL?

    /// Character budget for all attached file content combined (~2 000 tokens).
    static let fileContentCharBudget = 8_000

    var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when the total size of attached files is likely to exceed the context budget.
    /// Uses filesystem metadata (no content read) so it's cheap to call reactively.
    var attachedFilesExceedBudget: Bool {
        let totalBytes = attachedFiles.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + size
        }
        return totalBytes > Self.fileContentCharBudget
    }

    init() {
        let ud = UserDefaults.standard
        var opts = ApfelOptions.defaults
        if let t = ud.object(forKey: UserDefaultsKey.defaultTemperature) as? Double { opts.temperature = t }
        if let m = ud.object(forKey: UserDefaultsKey.defaultMaxTokens) as? Int      { opts.maxTokens = m }
        options = opts

        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let dir = support.appendingPathComponent("grapfel", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            historyFileURL = dir.appendingPathComponent("conversation.json")
        } else {
            historyFileURL = nil
        }

        loadHistory()
    }

    // MARK: - Send

    func send() async {
        let trimmed = trimmedPrompt
        guard !trimmed.isEmpty else { return }

        let filesToAttach = attachedFiles

        isLoading = true
        streamingContent = ""
        prompt = ""

        // history stores the clean prompt — no file dumps shown in the UI
        history.append(ChatMessage(role: .user, content: trimmed))

        var messages: [ChatMessage] = []
        let sys = options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            messages.append(ChatMessage(role: .system, content: sys))
        }
        // Prior turns from history (clean), then current turn with file content injected
        messages.append(contentsOf: history.dropLast())
        messages.append(ChatMessage(role: .user, content: buildUserContent(prompt: trimmed, files: filesToAttach)))

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
        attachedFiles = []
        deleteHistoryFile()
    }

    // MARK: - Persistence

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
        panel.allowedContentTypes = [.text, .plainText, .rtf, .sourceCode, .json, .xml]
        panel.message = "Select text files to include with your message"
        if panel.runModal() == .OK {
            let newURLs = panel.urls.filter { !attachedFiles.contains($0) }
            attachedFiles.append(contentsOf: newURLs)
        }
    }

    func removeAttachedFile(_ url: URL) {
        attachedFiles.removeAll { $0 == url }
    }

    // MARK: - File reading

    private func buildUserContent(prompt: String, files: [URL]) -> String {
        guard !files.isEmpty else { return prompt }
        var remainingBudget = Self.fileContentCharBudget
        let blocks = files.compactMap { url -> String? in
            guard let rawText = readTextFile(url) else { return nil }
            let text: String
            if rawText.count > remainingBudget {
                let cutoff = rawText.index(rawText.startIndex, offsetBy: max(remainingBudget, 0))
                text = String(rawText[..<cutoff]) + "\n[truncated]"
                remainingBudget = 0
            } else {
                text = rawText
                remainingBudget -= rawText.count
            }
            return "<file name=\"\(url.lastPathComponent)\">\n\(text)\n</file>"
        }
        guard !blocks.isEmpty else { return prompt }
        return blocks.joined(separator: "\n\n") + "\n\n" + prompt
    }

    private func readTextFile(_ url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if url.pathExtension.lowercased() == "rtf",
           let attrStr = try? NSAttributedString(
               url: url,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil) {
            return attrStr.string
        }
        return try? String(contentsOf: url, encoding: .isoLatin1)
    }
}
