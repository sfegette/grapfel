import XCTest

final class ChatViewModelTests: XCTestCase {
    private var tempDirectory: URL!
    private var historyFileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = try makeTemporaryDirectory()
        historyFileURL = tempDirectory.appendingPathComponent("conversation.json")

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: UserDefaultsKey.defaultTemperature)
        defaults.removeObject(forKey: UserDefaultsKey.defaultMaxTokens)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        historyFileURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testInitialState() {
        let vm = ChatViewModel(historyFileURL: historyFileURL)

        XCTAssertEqual(vm.prompt, "")
        XCTAssertTrue(vm.history.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.attachedFiles.isEmpty)
        XCTAssertEqual(vm.options, .defaults)
        XCTAssertEqual(vm.finishReason, .stop)
        XCTAssertNil(vm.responseAnnotation)
        XCTAssertNil(vm.lastUsage)
    }

    @MainActor
    func testSendWithEmptyPromptDoesNothing() async {
        let client = MockApfelAPIClient()
        let vm = ChatViewModel(apiClient: client, historyFileURL: historyFileURL)
        vm.prompt = "   "

        await vm.send()

        XCTAssertTrue(client.capturedMessages.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.history.isEmpty)
    }

    @MainActor
    func testSendNonStreamingAppendsAssistantResponseAndPersistsHistory() async throws {
        let client = MockApfelAPIClient()
        client.completeResult = CompletionResult(
            content: "Hello back",
            finishReason: .length,
            refusal: nil,
            usage: UsageInfo(promptTokens: 12, completionTokens: 34, totalTokens: 46)
        )

        let vm = ChatViewModel(apiClient: client, historyFileURL: historyFileURL)
        vm.options.streaming = false
        vm.prompt = "hello"

        await vm.send()

        XCTAssertEqual(vm.history.map { $0.role }, [.user, .assistant])
        XCTAssertEqual(vm.history.map { $0.content }, ["hello", "Hello back"])
        XCTAssertEqual(vm.finishReason, FinishReason.length)
        XCTAssertEqual(vm.responseAnnotation, "Response was truncated at the token limit.")
        XCTAssertEqual(vm.lastUsage, UsageInfo(promptTokens: 12, completionTokens: 34, totalTokens: 46))
        XCTAssertEqual(vm.usageAnnotation, "46 tokens")
        XCTAssertEqual(vm.prompt, "")
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.attachedFiles.isEmpty)

        let reloaded = ChatViewModel(historyFileURL: historyFileURL)
        XCTAssertEqual(reloaded.history.map { $0.content }, ["hello", "Hello back"])
    }

    @MainActor
    func testSendErrorAppendsErrorMessageAndClearsTransientState() async {
        let client = MockApfelAPIClient()
        client.completeError = TestError.expectedFailure

        let vm = ChatViewModel(apiClient: client, historyFileURL: historyFileURL)
        vm.options.streaming = false
        vm.prompt = "hello"
        vm.lastUsage = UsageInfo(promptTokens: 1, completionTokens: 1, totalTokens: 2)
        vm.responseAnnotation = "stale"

        await vm.send()

        XCTAssertEqual(vm.history.count, 2)
        XCTAssertEqual(vm.history[0].content, "hello")
        XCTAssertEqual(vm.history[1].content, "Error: Expected failure")
        XCTAssertEqual(vm.finishReason, FinishReason.stop)
        XCTAssertNil(vm.responseAnnotation)
        XCTAssertNil(vm.lastUsage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.prompt, "")
    }

    @MainActor
    func testClearHistoryResetsStateAndDeletesPersistedFile() throws {
        let existing = [
            ChatMessage(role: .user, content: "one"),
            ChatMessage(role: .assistant, content: "two"),
        ]
        try JSONEncoder().encode(existing).write(to: historyFileURL)

        let vm = ChatViewModel(historyFileURL: historyFileURL)
        vm.prompt = "pending"
        vm.streamingContent = "partial"
        vm.attachedFiles = [tempDirectory.appendingPathComponent("file.txt")]
        vm.finishReason = FinishReason.length
        vm.responseAnnotation = "annotation"
        vm.lastUsage = UsageInfo(promptTokens: 2, completionTokens: 3, totalTokens: 5)

        XCTAssertEqual(vm.history, existing)

        vm.clearHistory()

        XCTAssertTrue(vm.history.isEmpty)
        XCTAssertEqual(vm.prompt, "")
        XCTAssertEqual(vm.streamingContent, "")
        XCTAssertTrue(vm.attachedFiles.isEmpty)
        XCTAssertEqual(vm.finishReason, FinishReason.stop)
        XCTAssertNil(vm.responseAnnotation)
        XCTAssertNil(vm.lastUsage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFileURL.path))
    }

    @MainActor
    func testSendIncludesTruncatedAttachmentContentWhenBudgetExceeded() async throws {
        let client = MockApfelAPIClient()
        client.completeResult = CompletionResult(content: "done", finishReason: .stop, refusal: nil, usage: nil)

        let fileURL = tempDirectory.appendingPathComponent("huge.txt")
        let oversizedText = String(repeating: "a", count: ChatViewModel.fileContentCharBudget + 500)
        try writeFile(at: fileURL, contents: oversizedText)

        let vm = ChatViewModel(apiClient: client, historyFileURL: historyFileURL)
        vm.options.streaming = false
        vm.prompt = "summarize this"
        vm.attachedFiles = [fileURL]

        XCTAssertTrue(vm.attachedFilesExceedBudget)

        await vm.send()

        XCTAssertEqual(client.capturedMessages.count, 1)
        let sentContent = try XCTUnwrap(client.capturedMessages.first?.content)
        XCTAssertTrue(sentContent.contains("<file name=\"huge.txt\">"))
        XCTAssertTrue(sentContent.contains("[truncated]"))
        XCTAssertTrue(sentContent.hasSuffix("\n\nsummarize this"))
    }

    @MainActor
    func testSendStreamingCollectsTokensDoneEventAndUsage() async {
        let client = MockApfelAPIClient()
        let events: [StreamEvent] = [
            .token("Hel"),
            .token("lo"),
            .done(finishReason: FinishReason.contentFilter, refusal: "Filtered"),
            .usage(UsageInfo(promptTokens: 3, completionTokens: 4, totalTokens: 7)),
        ]
        client.streamEvents = events

        let vm = ChatViewModel(apiClient: client, historyFileURL: historyFileURL)
        vm.options.streaming = true
        vm.prompt = "hello"

        await vm.send()

        XCTAssertEqual(vm.history.count, 2)
        XCTAssertEqual(vm.history[1].content, "Hello")
        XCTAssertEqual(vm.finishReason, FinishReason.contentFilter)
        XCTAssertEqual(vm.lastUsage, UsageInfo(promptTokens: 3, completionTokens: 4, totalTokens: 7))
        XCTAssertNil(vm.responseAnnotation)
    }
}
