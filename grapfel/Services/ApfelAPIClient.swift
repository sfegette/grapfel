import Foundation

/// HTTP client for apfel's OpenAI-compatible API at localhost:11434/v1.
protocol ApfelAPIClientProtocol: Sendable {
    func complete(messages: [ChatMessage], options: ApfelOptions) async throws -> CompletionResult
    func stream(messages: [ChatMessage], options: ApfelOptions) -> AsyncThrowingStream<StreamEvent, Error>
}

struct ApfelAPIClient: ApfelAPIClientProtocol {
    private let baseURL: URL
    private let session: URLSession

    init(port: Int = 11434, session: URLSession = .shared) {
        self.init(baseURL: URL(string: "http://127.0.0.1:\(port)/v1")!, session: session)
    }

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Non-streaming completion

    func complete(messages: [ChatMessage], options: ApfelOptions) async throws -> CompletionResult {
        let request = try buildRequest(messages: messages, options: options, stream: false)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if let apiError = try? JSONDecoder().decode(ApfelErrorResponse.self, from: data) {
                throw ApfelError.requestFailed(apiError.error.message)
            }
            throw ApfelError.requestFailed("HTTP \(http.statusCode)")
        }
        let decoder = snakeCaseDecoder()
        let completion = try decoder.decode(ChatCompletion.self, from: data)
        let choice = completion.choices.first
        let finishReason = FinishReason(choice?.finishReason)
        let content = choice?.message.content ?? ""
        let refusal = choice?.message.refusal
        let usage = completion.usage.map {
            UsageInfo(promptTokens: $0.promptTokens,
                      completionTokens: $0.completionTokens,
                      totalTokens: $0.totalTokens)
        }
        return CompletionResult(content: content, finishReason: finishReason,
                                refusal: refusal, usage: usage)
    }

    // MARK: - Streaming completion

    /// Yields `.token` text chunks, then `.done`, then optionally `.usage`.
    func stream(messages: [ChatMessage], options: ApfelOptions) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, options: options, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = Data()
                        for try await byte in bytes { body.append(byte) }
                        if let apiError = try? JSONDecoder().decode(ApfelErrorResponse.self, from: body) {
                            throw ApfelError.requestFailed(apiError.error.message)
                        }
                        throw ApfelError.requestFailed("HTTP \(http.statusCode)")
                    }

                    let decoder = snakeCaseDecoder()
                    var accumulatedRefusal: String? = nil

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(StreamChunk.self, from: data)
                        else { continue }

                        if let choice = chunk.choices.first {
                            if let content = choice.delta.content, !content.isEmpty {
                                continuation.yield(.token(content))
                            }
                            if let refusal = choice.delta.refusal, !refusal.isEmpty {
                                accumulatedRefusal = (accumulatedRefusal ?? "") + refusal
                            }
                            if let finishReasonStr = choice.finishReason {
                                continuation.yield(.done(
                                    finishReason: FinishReason(finishReasonStr),
                                    refusal: accumulatedRefusal
                                ))
                            }
                        }

                        if let u = chunk.usage {
                            continuation.yield(.usage(UsageInfo(
                                promptTokens: u.promptTokens,
                                completionTokens: u.completionTokens,
                                totalTokens: u.totalTokens
                            )))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Request building

    private func buildRequest(messages: [ChatMessage], options: ApfelOptions, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        var body: [String: Any] = [
            "model": "apple-foundationmodel",
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "temperature": options.temperature,
            "max_tokens": options.maxTokens,
            "stream": stream,
            "x_context_strategy": options.contextStrategy.rawValue,
        ]
        if stream {
            body["stream_options"] = ["include_usage": true]
        }
        if options.jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        if let seed = options.seed { body["seed"] = seed }
        if let maxTurns = options.contextMaxTurns { body["x_context_max_turns"] = maxTurns }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func snakeCaseDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

// MARK: - Result types

enum FinishReason: Equatable {
    case stop
    case length
    case contentFilter
    case toolCalls
    case unknown(String)

    init(_ raw: String?) {
        switch raw {
        case "stop":           self = .stop
        case "length":         self = .length
        case "content_filter": self = .contentFilter
        case "tool_calls":     self = .toolCalls
        case let s?:           self = .unknown(s)
        default:               self = .stop
        }
    }
}

struct UsageInfo: Equatable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

struct CompletionResult: Equatable {
    let content: String
    let finishReason: FinishReason
    let refusal: String?
    let usage: UsageInfo?
}

enum StreamEvent: Equatable {
    case token(String)
    case done(finishReason: FinishReason, refusal: String?)
    case usage(UsageInfo)
}

// MARK: - Response models

private struct ApfelErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String?
            let refusal: String?
        }
        let message: Message
        let finishReason: String?
    }
    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }
    let choices: [Choice]
    let usage: Usage?
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let refusal: String?
        }
        let delta: Delta
        let finishReason: String?
    }
    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
    }
    let choices: [Choice]
    let usage: Usage?
}
