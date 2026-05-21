import XCTest

final class ApfelAPIClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testCompleteBuildsExpectedRequestAndDecodesResponse() async throws {
        let session = makeMockSession()
        let client = ApfelAPIClient(baseURL: URL(string: "http://127.0.0.1:9999/v1")!, session: session)
        let options = ApfelOptions(
            temperature: 0.4,
            maxTokens: 123,
            seed: 42,
            streaming: false,
            jsonMode: true,
            systemPrompt: "",
            contextStrategy: .summarize,
            contextMaxTurns: 8
        )

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:9999/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertNil(request.value(forHTTPHeaderField: "Accept"))

            let body = try XCTUnwrap(requestBodyData(for: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["model"] as? String, "apple-foundationmodel")
            XCTAssertEqual(json["temperature"] as? Double, 0.4)
            XCTAssertEqual(json["max_tokens"] as? Int, 123)
            XCTAssertEqual(json["stream"] as? Bool, false)
            XCTAssertEqual(json["seed"] as? Int, 42)
            XCTAssertEqual(json["x_context_strategy"] as? String, "summarize")
            XCTAssertEqual(json["x_context_max_turns"] as? Int, 8)
            XCTAssertEqual((json["response_format"] as? [String: String])?["type"], "json_object")

            let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
            XCTAssertEqual(messages, [["role": "user", "content": "Hello"]])

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
            {
              "choices": [
                {
                  "message": { "role": "assistant", "content": "World", "refusal": null },
                  "finish_reason": "stop"
                }
              ],
              "usage": {
                "prompt_tokens": 10,
                "completion_tokens": 20,
                "total_tokens": 30
              }
            }
            """.data(using: .utf8)!
            return (response, data)
        }

        let result = try await client.complete(
            messages: [ChatMessage(role: .user, content: "Hello")],
            options: options
        )

        XCTAssertEqual(result, CompletionResult(
            content: "World",
            finishReason: .stop,
            refusal: nil,
            usage: UsageInfo(promptTokens: 10, completionTokens: 20, totalTokens: 30)
        ))
    }

    func testCompleteDecodesAPIErrorPayload() async {
        let session = makeMockSession()
        let client = ApfelAPIClient(baseURL: URL(string: "http://127.0.0.1:9999/v1")!, session: session)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            let data = #"{"error":{"message":"boom"}}"#.data(using: .utf8)!
            return (response, data)
        }

        do {
            _ = try await client.complete(messages: [ChatMessage(role: .user, content: "Hello")], options: .defaults)
            XCTFail("Expected request failure")
        } catch let error as ApfelError {
            switch error {
            case .requestFailed(let message):
                XCTAssertEqual(message, "boom")
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStreamEmitsTokenDoneAndUsageEvents() async throws {
        let session = makeMockSession()
        let client = ApfelAPIClient(baseURL: URL(string: "http://127.0.0.1:9999/v1")!, session: session)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")

            let body = try XCTUnwrap(requestBodyData(for: request))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(json["stream"] as? Bool, true)
            XCTAssertEqual((json["stream_options"] as? [String: Bool])?["include_usage"], true)

            let payload = """
            data: {"choices":[{"delta":{"content":"Hel"},"finish_reason":null}]}

            data: {"choices":[{"delta":{"content":"lo"},"finish_reason":null}]}

            data: {"choices":[{"delta":{"refusal":"Filtered"},"finish_reason":"content_filter"}]}

            data: {"choices":[],"usage":{"prompt_tokens":1,"completion_tokens":2,"total_tokens":3}}

            data: [DONE]

            """

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, payload.data(using: .utf8)!)
        }

        var events: [StreamEvent] = []
        for try await event in client.stream(
            messages: [ChatMessage(role: .user, content: "Hello")],
            options: .defaults
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [
            .token("Hel"),
            .token("lo"),
            .done(finishReason: .contentFilter, refusal: "Filtered"),
            .usage(UsageInfo(promptTokens: 1, completionTokens: 2, totalTokens: 3)),
        ])
    }
}
