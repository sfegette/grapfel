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
    var finishReason: FinishReason = .stop
    var responseAnnotation: String? = nil // shown below last assistant response
    var lastUsage: UsageInfo? = nil

    var usageAnnotation: String? {
        lastUsage.map { "\($0.totalTokens) tokens" }
    }

    private let apiClient: any ApfelAPIClientProtocol
    private let conversationStore: ConversationStore
    private let historyFileURL: URL?
    private let fileTextReader: (URL) -> String?
    private var sendTask: Task<Void, Never>?
    private var displayedConversationID: UUID?

    /// Character budget for all attached file content combined (~2 000 tokens).
    static let fileContentCharBudget = 8_000

    var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }

    var canRegenerate: Bool {
        !isLoading && history.count >= 2 && history.last?.role == .assistant
    }

    func beginSend() {
        sendTask = Task { await send() }
    }

    func stopGeneration() {
        sendTask?.cancel()
    }

    func regenerate() {
        guard canRegenerate else { return }
        history.removeLast()
        let userContent = history.last?.content ?? ""
        history.removeLast()
        prompt = userContent
        sendTask = Task { await send() }
    }

    func editLast() {
        guard canRegenerate else { return }
        history.removeLast()
        let userContent = history.last?.content ?? ""
        history.removeLast()
        prompt = userContent
    }

    /// True when the total size of attached files is likely to exceed the context budget.
    /// Uses filesystem metadata (no content read) so it's cheap to call reactively.
    var attachedFilesExceedBudget: Bool {
        let totalBytes = attachedFiles.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + size
        }
        return totalBytes > Self.fileContentCharBudget
    }

    init(
        apiClient: any ApfelAPIClientProtocol = ApfelAPIClient(),
        conversationStore: ConversationStore = .shared,
        historyFileURL: URL? = nil,
        fileTextReader: @escaping (URL) -> String? = ChatViewModel.defaultReadTextFile
    ) {
        self.apiClient = apiClient
        self.conversationStore = conversationStore
        self.historyFileURL = historyFileURL
        self.fileTextReader = fileTextReader

        let ud = UserDefaults.standard
        var opts = ApfelOptions.defaults
        if let t = ud.object(forKey: UserDefaultsKey.defaultTemperature) as? Double { opts.temperature = t }
        if let m = ud.object(forKey: UserDefaultsKey.defaultMaxTokens) as? Int      { opts.maxTokens = m }
        options = opts

        if historyFileURL != nil {
            loadHistory()
        } else {
            displayedConversationID = conversationStore.activeID
            history = conversationStore.active?.messages ?? []
        }
    }

    func loadConversation(_ record: ConversationRecord) {
        sendTask?.cancel()
        displayedConversationID = record.id
        history = record.messages
        streamingContent = ""
        prompt = ""
        attachedFiles = []
        isLoading = false
        finishReason = .stop
        responseAnnotation = nil
        lastUsage = nil
    }

    // MARK: - Send

    func send() async {
        let trimmed = trimmedPrompt
        guard !trimmed.isEmpty else { return }

        let targetConversationID: UUID? = if historyFileURL != nil {
            nil
        } else {
            displayedConversationID ?? conversationStore.activeID
        }
        let filesToAttach = attachedFiles
        var workingHistory = history
        var accumulatedAssistantContent = ""

        let isDisplayingTargetConversation: () -> Bool = {
            self.historyFileURL != nil || targetConversationID == nil || self.displayedConversationID == targetConversationID
        }

        isLoading = true
        streamingContent = ""
        prompt = ""

        // history stores the clean prompt — no file dumps shown in the UI
        workingHistory.append(ChatMessage(role: .user, content: trimmed))
        history = workingHistory
        saveHistory(workingHistory, activeConversationID: targetConversationID)

        var messages: [ChatMessage] = []
        let sys = options.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sys.isEmpty {
            messages.append(ChatMessage(role: .system, content: sys))
        }
        // Prior turns from history (clean), then current turn with file content injected
        messages.append(contentsOf: workingHistory.dropLast())
        messages.append(ChatMessage(role: .user, content: buildUserContent(prompt: trimmed, files: filesToAttach)))

        do {
            let assistantContent: String
            if options.streaming {
                var streamRefusal: String? = nil
                for try await event in apiClient.stream(messages: messages, options: options) {
                    switch event {
                    case .token(let chunk):
                        accumulatedAssistantContent += chunk
                        if isDisplayingTargetConversation() {
                            streamingContent = accumulatedAssistantContent
                        }
                    case .done(let reason, let refusal):
                        if isDisplayingTargetConversation() {
                            finishReason = reason
                        }
                        streamRefusal = refusal
                    case .usage(let info):
                        if isDisplayingTargetConversation() {
                            lastUsage = info
                        }
                    }
                }
                assistantContent = accumulatedAssistantContent.isEmpty && finishReason == .contentFilter
                    ? (streamRefusal ?? "[Content filtered by on-device policy]")
                    : accumulatedAssistantContent
            } else {
                let result = try await apiClient.complete(messages: messages, options: options)
                if isDisplayingTargetConversation() {
                    finishReason = result.finishReason
                    lastUsage = result.usage
                }
                assistantContent = result.content.isEmpty && result.finishReason == .contentFilter
                    ? (result.refusal ?? "[Content filtered by on-device policy]")
                    : result.content
            }
            if isDisplayingTargetConversation() {
                responseAnnotation = finishReason == .length
                    ? "Response was truncated at the token limit."
                    : nil
            }
            workingHistory.append(ChatMessage(role: .assistant, content: assistantContent))
        } catch ApfelError.rateLimited {
            if isDisplayingTargetConversation() {
                finishReason = .stop
                responseAnnotation = nil
                lastUsage = nil
            }
            workingHistory.append(ChatMessage(role: .assistant, content: "Apple Intelligence is busy — try again in a moment."))
        } catch ApfelError.modelUnavailable {
            if isDisplayingTargetConversation() {
                finishReason = .stop
                responseAnnotation = nil
                lastUsage = nil
            }
            workingHistory.append(ChatMessage(role: .assistant, content: "Apple Intelligence is not available. Check that it's enabled in System Settings → Apple Intelligence & Siri."))
        } catch is CancellationError {
            if !accumulatedAssistantContent.isEmpty {
                workingHistory.append(ChatMessage(role: .assistant, content: accumulatedAssistantContent))
                saveHistory(workingHistory, activeConversationID: targetConversationID)
            } else if workingHistory.last?.role == .user {
                workingHistory.removeLast()
                saveHistory(workingHistory, activeConversationID: targetConversationID)
            }
            if isDisplayingTargetConversation() {
                history = workingHistory
            }
            streamingContent = ""
            isLoading = false
            attachedFiles = []
            return
        } catch {
            if isDisplayingTargetConversation() {
                finishReason = .stop
                responseAnnotation = nil
                lastUsage = nil
            }
            workingHistory.append(ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)"))
        }

        if isDisplayingTargetConversation() {
            history = workingHistory
        }
        streamingContent = ""
        isLoading = false
        attachedFiles = []
        saveHistory(workingHistory, activeConversationID: targetConversationID)
    }

    // MARK: - Conversation management

    func clearHistory() {
        history = []
        streamingContent = ""
        prompt = ""
        attachedFiles = []
        finishReason = .stop
        responseAnnotation = nil
        lastUsage = nil
        deleteHistoryFile()
    }

    // MARK: - Persistence

    nonisolated private static func defaultHistoryFileURL() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let dir = support.appendingPathComponent("grapfel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversation.json")
    }

    private func saveHistory(_ historyToSave: [ChatMessage], activeConversationID: UUID? = nil) {
        if let url = historyFileURL {
            guard let data = try? JSONEncoder().encode(historyToSave) else { return }
            try? data.write(to: url, options: .atomic)
        } else {
            saveToStore(historyToSave, activeConversationID: activeConversationID)
        }
    }

    private func saveToStore(_ historyToSave: [ChatMessage], activeConversationID: UUID?) {
        let recordID = activeConversationID ?? conversationStore.activeID
        guard let recordID,
              var record = conversationStore.conversations.first(where: { $0.id == recordID }) else { return }
        if record.name == "New conversation",
           let first = historyToSave.first(where: { $0.role == .user }) {
            record.name = ConversationTitleFormatter.title(for: first.content)
        }
        record.messages = historyToSave
        record.updatedAt = Date()
        conversationStore.save(record)
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
            guard let rawText = fileTextReader(url) else { return nil }
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

    nonisolated private static func defaultReadTextFile(_ url: URL) -> String? {
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
