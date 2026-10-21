import XCTest

final class FoundationModelIntegrationTests: XCTestCase {
    func testLiveNativeStreamingCompletion() async throws {
        #if !GRAPFEL_LIVE_MODEL_TEST
        throw XCTSkip("Add GRAPFEL_LIVE_MODEL_TEST to Swift compilation conditions to exercise Apple's on-device model.")
        #else
        var settings = GenerationSettings.defaults
        settings.temperature = 0
        settings.maxTokens = 64
        var content = ""
        var receivedDone = false

        for try await event in FoundationModelClient().stream(
            messages: [ChatMessage(role: .user, content: "Reply with a short greeting.")],
            settings: settings
        ) {
            switch event {
            case .token(let delta):
                content += delta
            case .replacement(let snapshot):
                content = snapshot
            case .done:
                receivedDone = true
            case .usage:
                break
            }
        }

        XCTAssertFalse(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertTrue(receivedDone)
        #endif
    }
}
