import Foundation
import XCTest

final class MockApfelAPIClient: @unchecked Sendable, ApfelAPIClientProtocol {
    var completeResult = CompletionResult(content: "", finishReason: .stop, refusal: nil, usage: nil)
    var completeError: Error?
    var streamEvents: [StreamEvent] = []
    var streamError: Error?
    private(set) var capturedMessages: [ChatMessage] = []
    private(set) var capturedOptions: ApfelOptions?

    func complete(messages: [ChatMessage], options: ApfelOptions) async throws -> CompletionResult {
        capturedMessages = messages
        capturedOptions = options
        if let completeError { throw completeError }
        return completeResult
    }

    func stream(messages: [ChatMessage], options: ApfelOptions) -> AsyncThrowingStream<StreamEvent, Error> {
        capturedMessages = messages
        capturedOptions = options
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

final class ControlledStreamApfelAPIClient: @unchecked Sendable, ApfelAPIClientProtocol {
    private(set) var capturedMessages: [ChatMessage] = []
    private(set) var capturedOptions: ApfelOptions?
    var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
    var onStreamStarted: (() -> Void)?

    func complete(messages: [ChatMessage], options: ApfelOptions) async throws -> CompletionResult {
        capturedMessages = messages
        capturedOptions = options
        return CompletionResult(content: "", finishReason: .stop, refusal: nil, usage: nil)
    }

    func stream(messages: [ChatMessage], options: ApfelOptions) -> AsyncThrowingStream<StreamEvent, Error> {
        capturedMessages = messages
        capturedOptions = options

        return AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.onStreamStarted?()
        }
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
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

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
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

func requestBodyData(for request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }

    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    let bufferSize = 4096
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        guard read > 0 else { break }
        data.append(buffer, count: read)
    }

    return data.isEmpty ? nil : data
}
