import Foundation
import FoundationModels
import OSLog

protocol LanguageModelClientProtocol: Sendable {
    func complete(messages: [ChatMessage], settings: GenerationSettings) async throws -> CompletionResult
    func stream(messages: [ChatMessage], settings: GenerationSettings) -> AsyncThrowingStream<StreamEvent, Error>
}

struct FoundationModelClient: LanguageModelClientProtocol {
    func complete(messages: [ChatMessage], settings: GenerationSettings) async throws -> CompletionResult {
        let model = try availableModel(for: settings)
        let request = try await makeRequest(
            messages: messages,
            settings: settings,
            model: model
        )
        let session = LanguageModelSession(model: model, transcript: request.transcript)

        do {
            let response = try await session.respond(to: request.prompt, options: request.options)
            let usage = await usage(for: session.transcript, model: model)
            return CompletionResult(
                content: response.content,
                finishReason: finishReason(for: usage, request: request),
                refusal: nil,
                usage: usage
            )
        } catch let error as LanguageModelSession.GenerationError {
            throw await map(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw LocalModelError.requestFailed(error.localizedDescription)
        }
    }

    func stream(messages: [ChatMessage], settings: GenerationSettings) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let model = try availableModel(for: settings)
                    let request = try await makeRequest(
                        messages: messages,
                        settings: settings,
                        model: model
                    )
                    let session = LanguageModelSession(model: model, transcript: request.transcript)
                    var accumulated = ""

                    for try await snapshot in session.streamResponse(
                        to: request.prompt,
                        options: request.options
                    ) {
                        try Task.checkCancellation()
                        let current = snapshot.content
                        let delta: String
                        if current.hasPrefix(accumulated) {
                            delta = String(current.dropFirst(accumulated.count))
                        } else {
                            // Native streaming is cumulative. If a later snapshot corrects an
                            // earlier one, replace the displayed draft instead of appending a
                            // duplicate full response.
                            continuation.yield(.replacement(current))
                            accumulated = current
                            continue
                        }
                        accumulated = current
                        if !delta.isEmpty {
                            continuation.yield(.token(delta))
                        }
                    }

                    try Task.checkCancellation()
                    let usage = await usage(for: session.transcript, model: model)
                    continuation.yield(.done(
                        finishReason: finishReason(for: usage, request: request),
                        refusal: nil
                    ))
                    if let usage {
                        continuation.yield(.usage(usage))
                    }
                    continuation.finish()
                } catch let error as LanguageModelSession.GenerationError {
                    continuation.finish(throwing: await map(error))
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let error as LocalModelError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: LocalModelError.requestFailed(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func availableModel(for settings: GenerationSettings) throws -> SystemLanguageModel {
        let model = FoundationModelConfiguration.makeModel(
            permissiveContentTransformations: settings.permissiveContentTransformations
        )

        switch model.availability {
        case .available:
            return model
        case .unavailable(.deviceNotEligible):
            throw LocalModelError.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            throw LocalModelError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw LocalModelError.modelNotReady
        case .unavailable:
            throw LocalModelError.modelNotReady
        }
    }

    private func makeRequest(
        messages: [ChatMessage],
        settings: GenerationSettings,
        model: SystemLanguageModel
    ) async throws -> FoundationModelRequestBuilder.Request {
        let estimatedRequest = try FoundationModelRequestBuilder.makeRequest(
            messages: messages,
            settings: settings,
            contextSize: model.contextSize
        )
        guard #available(macOS 26.4, *) else { return estimatedRequest }

        do {
            let transcriptTokens = try await model.tokenCount(for: Array(estimatedRequest.transcript))
            let promptTokens = try await model.tokenCount(for: estimatedRequest.prompt)
            return try FoundationModelRequestBuilder.applyingExactInputTokenCount(
                transcriptTokens + promptTokens,
                to: estimatedRequest,
                settings: settings,
                contextSize: model.contextSize
            )
        } catch let error as LocalModelError {
            throw error
        } catch {
            // Token counting is an optimization. The conservative request remains safe on
            // systems where the tokenizer is temporarily unavailable.
            return estimatedRequest
        }
    }

    private func finishReason(
        for usage: UsageInfo?,
        request: FoundationModelRequestBuilder.Request
    ) -> FinishReason {
        FoundationModelCompletionStatus.finishReason(
            usage: usage,
            maximumResponseTokens: request.options.maximumResponseTokens
        )
    }

    private func map(_ error: LanguageModelSession.GenerationError) async -> LocalModelError {
        let mapped = await mapUnlogged(error)
        AppLog.model.error("Generation failed: \(mapped.diagnosticCode, privacy: .public)")
        return mapped
    }

    private func mapUnlogged(_ error: LanguageModelSession.GenerationError) async -> LocalModelError {
        switch error {
        case .exceededContextWindowSize:
            return .contextWindowExceeded
        case .rateLimited:
            return .rateLimited
        case .concurrentRequests:
            return .concurrentRequest
        case .guardrailViolation:
            return .contentFiltered(nil)
        case .refusal(let refusal, _):
            let explanation = try? await refusal.explanation
            return .contentFiltered(explanation?.content)
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguageOrLocale
        default:
            return .requestFailed(error.localizedDescription)
        }
    }

    private func usage(
        for transcript: Transcript,
        model: SystemLanguageModel
    ) async -> UsageInfo? {
        guard #available(macOS 26.4, *), !transcript.isEmpty else { return nil }
        let entries = Array(transcript)
        guard case .response = entries.last else { return nil }

        do {
            let promptTokens = try await model.tokenCount(for: entries.dropLast())
            let completionTokens = try await model.tokenCount(for: entries.suffix(1))
            return UsageInfo(
                promptTokens: promptTokens,
                completionTokens: completionTokens,
                totalTokens: promptTokens + completionTokens
            )
        } catch {
            return nil
        }
    }
}

enum FoundationModelConfiguration {
    static func makeModel(permissiveContentTransformations: Bool) -> SystemLanguageModel {
        let guardrails: SystemLanguageModel.Guardrails = permissiveContentTransformations
            ? .permissiveContentTransformations
            : .default
        return SystemLanguageModel(useCase: .general, guardrails: guardrails)
    }
}

enum FoundationModelCompletionStatus {
    static func finishReason(
        usage: UsageInfo?,
        maximumResponseTokens: Int?
    ) -> FinishReason {
        guard let maximumResponseTokens else { return .stop }
        guard let completionTokens = usage?.completionTokens else {
            // Exact token counts arrived in macOS 26.4. On earlier systems, or if token
            // counting fails, the framework does not expose whether the limit was reached.
            return .unknown("completionStatusUnavailable")
        }
        return completionTokens >= maximumResponseTokens ? .length : .stop
    }
}

enum FoundationModelRequestBuilder {
    struct Request {
        let transcript: Transcript
        let prompt: String
        let options: FoundationModels.GenerationOptions
    }

    /// A conservative conversion factor leaves room for transcript metadata and languages
    /// that tokenize more densely than typical English prose.
    private static let charactersPerEstimatedToken = 3
    private static let contextSafetyMargin = 64
    private static let minimumResponseTokens = 128

    static func makeRequest(
        messages: [ChatMessage],
        settings: GenerationSettings,
        contextSize: Int
    ) throws -> Request {
        guard let currentIndex = messages.lastIndex(where: { $0.role == .user }) else {
            throw LocalModelError.invalidConversation
        }
        guard currentIndex == messages.index(before: messages.endIndex) else {
            throw LocalModelError.invalidConversation
        }

        var instructionParts = messages
            .filter { $0.role == .system }
            .map(\.content)
        if settings.jsonMode {
            instructionParts.append("Return exactly one valid JSON value with no Markdown fencing or explanatory text.")
        }
        let instructions = instructionParts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        let prompt = messages[currentIndex].content
        let fixedCharacters = instructions.count + prompt.count
        let maximumInputTokens = contextSize - minimumResponseTokens - contextSafetyMargin
        let fixedEstimatedTokens = estimatedTokens(forCharacterCount: fixedCharacters)
        guard maximumInputTokens > 0, fixedEstimatedTokens <= maximumInputTokens else {
            throw LocalModelError.contextWindowExceeded
        }

        let historyCharacterBudget = max(
            0,
            maximumInputTokens * charactersPerEstimatedToken - fixedCharacters
        )
        let history = selectNewestCompleteTurns(
            from: Array(messages[..<currentIndex]).filter { $0.role != .system },
            characterBudget: historyCharacterBudget
        )

        var entries: [Transcript.Entry] = []
        if !instructions.isEmpty {
            entries.append(.instructions(.init(
                segments: [.text(.init(content: instructions))],
                toolDefinitions: []
            )))
        }
        for message in history {
            let segments: [Transcript.Segment] = [.text(.init(content: message.content))]
            switch message.role {
            case .user:
                entries.append(.prompt(.init(segments: segments)))
            case .assistant:
                entries.append(.response(.init(assetIDs: [], segments: segments)))
            case .system:
                break
            }
        }

        let estimatedInputTokens = estimatedTokens(
            forCharacterCount: fixedCharacters + history.reduce(0) { $0 + $1.content.count }
        )
        let availableResponseTokens = contextSize - estimatedInputTokens - contextSafetyMargin
        guard availableResponseTokens >= minimumResponseTokens else {
            throw LocalModelError.contextWindowExceeded
        }

        return Request(
            transcript: Transcript(entries: entries),
            prompt: prompt,
            options: generationOptions(
                for: settings,
                maximumResponseTokens: min(settings.maxTokens, availableResponseTokens)
            )
        )
    }

    static func generationOptions(
        for settings: GenerationSettings,
        maximumResponseTokens: Int? = nil
    ) -> FoundationModels.GenerationOptions {
        let sampling: FoundationModels.GenerationOptions.SamplingMode?
        if settings.topP < 1 || settings.seed != nil {
            sampling = .random(
                probabilityThreshold: min(max(settings.topP, 0.05), 1),
                seed: settings.seed.map { UInt64(truncatingIfNeeded: $0) }
            )
        } else {
            sampling = nil
        }

        return FoundationModels.GenerationOptions(
            sampling: sampling,
            temperature: settings.temperature,
            maximumResponseTokens: maximumResponseTokens ?? settings.maxTokens
        )
    }

    static func applyingExactInputTokenCount(
        _ inputTokens: Int,
        to request: Request,
        settings: GenerationSettings,
        contextSize: Int
    ) throws -> Request {
        let availableResponseTokens = contextSize - inputTokens - contextSafetyMargin
        guard availableResponseTokens >= minimumResponseTokens else {
            throw LocalModelError.contextWindowExceeded
        }
        return Request(
            transcript: request.transcript,
            prompt: request.prompt,
            options: generationOptions(
                for: settings,
                maximumResponseTokens: min(settings.maxTokens, availableResponseTokens)
            )
        )
    }

    private static func estimatedTokens(forCharacterCount count: Int) -> Int {
        max(1, (count + charactersPerEstimatedToken - 1) / charactersPerEstimatedToken)
    }

    private static func selectNewestCompleteTurns(
        from messages: [ChatMessage],
        characterBudget: Int
    ) -> [ChatMessage] {
        var turns: [[ChatMessage]] = []
        var currentTurn: [ChatMessage] = []

        for message in messages {
            if message.role == .user {
                if currentTurn.count == 2 {
                    turns.append(currentTurn)
                }
                currentTurn = [message]
            } else if message.role == .assistant, currentTurn.count == 1 {
                currentTurn.append(message)
                turns.append(currentTurn)
                currentTurn = []
            }
        }

        var selected: [[ChatMessage]] = []
        var usedCharacters = 0
        for turn in turns.reversed() {
            let turnCharacters = turn.reduce(0) { $0 + $1.content.count }
            guard usedCharacters + turnCharacters <= characterBudget else { break }
            selected.append(turn)
            usedCharacters += turnCharacters
        }
        return selected.reversed().flatMap { $0 }
    }
}

enum FinishReason: Equatable {
    case stop
    case length
    case contentFilter
    case toolCalls
    case unknown(String)
}

struct UsageInfo: Equatable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

struct CompletionResult: Equatable, Sendable {
    let content: String
    let finishReason: FinishReason
    let refusal: String?
    let usage: UsageInfo?
}

enum StreamEvent: Equatable, Sendable {
    case token(String)
    case replacement(String)
    case done(finishReason: FinishReason, refusal: String?)
    case usage(UsageInfo)
}

enum LocalModelError: LocalizedError, Equatable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case rateLimited
    case concurrentRequest
    case contextWindowExceeded
    case contentFiltered(String?)
    case unsupportedLanguageOrLocale
    case invalidConversation
    case requestFailed(String)

    /// Stable, content-free label safe to log and share.
    var diagnosticCode: String {
        switch self {
        case .deviceNotEligible: "deviceNotEligible"
        case .appleIntelligenceNotEnabled: "appleIntelligenceNotEnabled"
        case .modelNotReady: "modelNotReady"
        case .rateLimited: "rateLimited"
        case .concurrentRequest: "concurrentRequest"
        case .contextWindowExceeded: "contextWindowExceeded"
        case .contentFiltered: "contentFiltered"
        case .unsupportedLanguageOrLocale: "unsupportedLanguageOrLocale"
        case .invalidConversation: "invalidConversation"
        case .requestFailed: "requestFailed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .deviceNotEligible:
            return "This Mac does not support Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled in System Settings."
        case .modelNotReady:
            return "Apple Intelligence is still preparing its on-device model."
        case .rateLimited:
            return "Apple Intelligence is busy — try again in a moment."
        case .concurrentRequest:
            return "Apple Intelligence is already responding to another request."
        case .contextWindowExceeded:
            return "This request is too large for the on-device model's context window."
        case .contentFiltered(let explanation):
            return explanation ?? "The response was blocked by the on-device content policy."
        case .unsupportedLanguageOrLocale:
            return "The current language or locale is not supported by the on-device model."
        case .invalidConversation:
            return "The conversation did not contain a final user message."
        case .requestFailed(let message):
            return message
        }
    }
}
