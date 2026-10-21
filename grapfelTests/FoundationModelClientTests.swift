import FoundationModels
import XCTest

final class FoundationModelClientTests: XCTestCase {
    func testCompletionStatusIsUnknownWhenUsageCannotBeMeasured() {
        XCTAssertEqual(
            FoundationModelCompletionStatus.finishReason(
                usage: nil,
                maximumResponseTokens: 128
            ),
            .unknown("completionStatusUnavailable")
        )
    }

    func testCompletionStatusReportsLengthAtResponseLimit() {
        XCTAssertEqual(
            FoundationModelCompletionStatus.finishReason(
                usage: UsageInfo(promptTokens: 20, completionTokens: 128, totalTokens: 148),
                maximumResponseTokens: 128
            ),
            .length
        )
    }

    func testCompletionStatusReportsStopBelowResponseLimit() {
        XCTAssertEqual(
            FoundationModelCompletionStatus.finishReason(
                usage: UsageInfo(promptTokens: 20, completionTokens: 64, totalTokens: 84),
                maximumResponseTokens: 128
            ),
            .stop
        )
    }

    func testRequestMapsConversationAndGenerationSettings() throws {
        var settings = GenerationSettings.defaults
        settings.temperature = 0.4
        settings.topP = 0.8
        settings.maxTokens = 900
        settings.seed = 42

        let request = try FoundationModelRequestBuilder.makeRequest(
            messages: [
                ChatMessage(role: .system, content: "Be concise."),
                ChatMessage(role: .user, content: "First"),
                ChatMessage(role: .assistant, content: "Answer"),
                ChatMessage(role: .user, content: "Second"),
            ],
            settings: settings,
            contextSize: 4096
        )

        XCTAssertEqual(request.prompt, "Second")
        XCTAssertEqual(request.options.temperature, 0.4)
        XCTAssertEqual(request.options.maximumResponseTokens, 900)
        XCTAssertEqual(
            request.options.sampling,
            .random(probabilityThreshold: 0.8, seed: 42)
        )

        let entries = Array(request.transcript)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(text(from: entries[0]), "Be concise.")
        XCTAssertEqual(text(from: entries[1]), "First")
        XCTAssertEqual(text(from: entries[2]), "Answer")
    }

    func testJSONModeAddsExplicitInstruction() throws {
        var settings = GenerationSettings.defaults
        settings.jsonMode = true

        let request = try FoundationModelRequestBuilder.makeRequest(
            messages: [ChatMessage(role: .user, content: "Give me a status")],
            settings: settings,
            contextSize: 4096
        )

        let instructions = try XCTUnwrap(Array(request.transcript).first)
        XCTAssertTrue(text(from: instructions)?.contains("valid JSON") == true)
    }

    func testLargePromptDownshiftsMaximumResponseTokens() throws {
        var settings = GenerationSettings.defaults
        settings.maxTokens = 2048
        let largePrompt = String(repeating: "a", count: 9_000)

        let request = try FoundationModelRequestBuilder.makeRequest(
            messages: [ChatMessage(role: .user, content: largePrompt)],
            settings: settings,
            contextSize: 4096
        )

        let responseLimit = try XCTUnwrap(request.options.maximumResponseTokens)
        XCTAssertLessThan(responseLimit, settings.maxTokens)
        XCTAssertGreaterThanOrEqual(responseLimit, 128)
    }

    func testExactTokenCountDownshiftsMaximumResponseTokens() throws {
        var settings = GenerationSettings.defaults
        settings.maxTokens = 2048
        let request = try FoundationModelRequestBuilder.makeRequest(
            messages: [ChatMessage(role: .user, content: "status")],
            settings: settings,
            contextSize: 4096
        )

        let adjusted = try FoundationModelRequestBuilder.applyingExactInputTokenCount(
            3_500,
            to: request,
            settings: settings,
            contextSize: 4096
        )

        XCTAssertEqual(adjusted.options.maximumResponseTokens, 532)
    }

    func testExactTokenCountRejectsInputThatCannotLeaveResponseFloor() throws {
        let request = try FoundationModelRequestBuilder.makeRequest(
            messages: [ChatMessage(role: .user, content: "status")],
            settings: .defaults,
            contextSize: 4096
        )

        XCTAssertThrowsError(try FoundationModelRequestBuilder.applyingExactInputTokenCount(
            3_905,
            to: request,
            settings: .defaults,
            contextSize: 4096
        )) { error in
            XCTAssertEqual(error as? LocalModelError, .contextWindowExceeded)
        }
    }

    func testNewestCompleteTurnsAreRetainedWhenHistoryExceedsContext() throws {
        var messages: [ChatMessage] = []
        for index in 0..<8 {
            messages.append(ChatMessage(role: .user, content: "old-\(index)-" + String(repeating: "x", count: 900)))
            messages.append(ChatMessage(role: .assistant, content: "answer-\(index)-" + String(repeating: "y", count: 900)))
        }
        messages.append(ChatMessage(role: .user, content: "current"))

        let request = try FoundationModelRequestBuilder.makeRequest(
            messages: messages,
            settings: .defaults,
            contextSize: 4096
        )

        let retained = Array(request.transcript).compactMap(text(from:))
        XCTAssertFalse(retained.contains { $0.hasPrefix("old-0-") })
        XCTAssertTrue(retained.contains { $0.hasPrefix("old-7-") })
        XCTAssertTrue(retained.contains { $0.hasPrefix("answer-7-") })
    }

    func testPromptThatCannotFitThrowsContextError() {
        let prompt = String(repeating: "x", count: 20_000)

        XCTAssertThrowsError(try FoundationModelRequestBuilder.makeRequest(
            messages: [ChatMessage(role: .user, content: prompt)],
            settings: .defaults,
            contextSize: 4096
        )) { error in
            XCTAssertEqual(error as? LocalModelError, .contextWindowExceeded)
        }
    }

    private func text(from entry: Transcript.Entry) -> String? {
        let segments: [Transcript.Segment]
        switch entry {
        case .instructions(let value): segments = value.segments
        case .prompt(let value): segments = value.segments
        case .response(let value): segments = value.segments
        default: return nil
        }
        guard case .text(let text)? = segments.first else { return nil }
        return text.content
    }
}
