import Foundation
import XCTest

final class MockLanguageModelClient: @unchecked Sendable, LanguageModelClientProtocol {
    var completeResult = CompletionResult(content: "", finishReason: .stop, refusal: nil, usage: nil)
    var completeError: Error?
    var streamEvents: [StreamEvent] = []
    var streamError: Error?
    private(set) var capturedMessages: [ChatMessage] = []
    private(set) var capturedSettings: GenerationSettings?

    func complete(messages: [ChatMessage], settings: GenerationSettings) async throws -> CompletionResult {
        capturedMessages = messages
        capturedSettings = settings
        if let completeError { throw completeError }
        return completeResult
    }

    func stream(messages: [ChatMessage], settings: GenerationSettings) -> AsyncThrowingStream<StreamEvent, Error> {
        capturedMessages = messages
        capturedSettings = settings
        let events = streamEvents
        let error = streamError

        return AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(event)
            }

            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }
}

final class ControlledStreamLanguageModelClient: @unchecked Sendable, LanguageModelClientProtocol {
    private(set) var capturedMessages: [ChatMessage] = []
    private(set) var capturedSettings: GenerationSettings?
    var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    var onStreamStarted: (() -> Void)?

    func complete(messages: [ChatMessage], settings: GenerationSettings) async throws -> CompletionResult {
        capturedMessages = messages
        capturedSettings = settings
        return CompletionResult(content: "", finishReason: .stop, refusal: nil, usage: nil)
    }

    func stream(messages: [ChatMessage], settings: GenerationSettings) -> AsyncThrowingStream<StreamEvent, Error> {
        capturedMessages = messages
        capturedSettings = settings

        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.onStreamStarted?()
        }
    }
}

enum TestError: LocalizedError {
    case expectedFailure

    var errorDescription: String? {
        switch self {
        case .expectedFailure:
            return "Expected failure"
        }
    }
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeFile(at url: URL, contents: String) throws {
    guard let data = contents.data(using: .utf8) else {
        throw TestError.expectedFailure
    }
    try data.write(to: url)
}

func makeTestUserDefaults() -> UserDefaults {
    let suiteName = "grapfel-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
