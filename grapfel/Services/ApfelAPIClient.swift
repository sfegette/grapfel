import Foundation

/// HTTP client for apfel's OpenAI-compatible API at localhost:11434/v1.
struct ApfelAPIClient {
    private let baseURL: URL
    private let session: URLSession

    init(port: Int = 11434, session: URLSession = .shared) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)/v1")!
        self.session = session
    }

    // MARK: - Non-streaming completion

    func complete(messages: [ChatMessage], options: ApfelOptions) async throws -> String {
        let request = try buildRequest(messages: messages, options: options, stream: false)
        let (data, _) = try await session.data(for: request)
        let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
        return completion.choices.first?.message.content ?? ""
    }

    // MARK: - Streaming completion

    /// Yields text chunks as they arrive via SSE.
    func stream(messages: [ChatMessage], options: ApfelOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, options: options, stream: true)
                    let (bytes, _) = try await session.bytes(for: request)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        if let data = payload.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let delta = chunk.choices.first?.delta.content {
                            continuation.yield(delta)
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
        ]
        if let seed = options.seed { body["seed"] = seed }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Response models

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let role: String; let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}
