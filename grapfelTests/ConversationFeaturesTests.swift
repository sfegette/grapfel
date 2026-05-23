import XCTest

final class ConversationFeaturesTests: XCTestCase {
    func testConversationTitleFormatterTrimsAtWordBoundary() {
        let title = ConversationTitleFormatter.title(
            for: "This is a longer first prompt that should trim cleanly at a word boundary."
        )

        XCTAssertEqual(title, "This is a longer first prompt that…")
    }

    func testConversationTitleFormatterCollapsesWhitespace() {
        let title = ConversationTitleFormatter.title(
            for: "   Multi-line\n\nprompt   with   extra spacing   "
        )

        XCTAssertEqual(title, "Multi-line prompt with extra spacing")
    }

    func testConversationTitleFormatterDoesNotTruncateAtFortyCharacters() {
        let title = ConversationTitleFormatter.title(
            for: "1234567890123456789012345678901234567890"
        )

        XCTAssertEqual(title, "1234567890123456789012345678901234567890")
    }

    func testConversationExporterMarkdownIncludesMessageRoles() {
        let record = ConversationRecord(
            name: "Example",
            messages: [
                ChatMessage(role: .system, content: "Follow the style guide."),
                ChatMessage(role: .user, content: "Write a changelog."),
                ChatMessage(role: .assistant, content: "Here is the changelog."),
            ]
        )

        let markdown = ConversationExporter.markdown(for: record)

        XCTAssertTrue(markdown.contains("# Example"))
        XCTAssertTrue(markdown.contains("**System:**\n\nFollow the style guide."))
        XCTAssertTrue(markdown.contains("**You:**\n\nWrite a changelog."))
        XCTAssertTrue(markdown.contains("**grapfel:**\n\nHere is the changelog."))
    }

    func testConversationExporterArchiveIncludesSchemaAndMessages() throws {
        let records = [
            ConversationRecord(
                name: "One",
                messages: [ChatMessage(role: .user, content: "Hello")]
            ),
        ]

        let data = try ConversationExporter.archiveData(for: records)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(json.contains("\"name\" : \"One\""))
        XCTAssertTrue(json.contains("\"content\" : \"Hello\""))
    }

    func testConversationExporterArchiveRoundTripsViaJSONDecoder() throws {
        let records = [
            ConversationRecord(
                name: "Round Trip",
                messages: [
                    ChatMessage(role: .user, content: "Prompt"),
                    ChatMessage(role: .assistant, content: "Reply"),
                ]
            ),
        ]

        let data = try ConversationExporter.archiveData(for: records)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(ExportArchiveProbe.self, from: data)

        XCTAssertEqual(payload.schemaVersion, 1)
        XCTAssertEqual(payload.conversations.first?.name, "Round Trip")
        XCTAssertEqual(payload.conversations.first?.messages.count, 2)
    }
}

private struct ExportArchiveProbe: Decodable {
    let schemaVersion: Int
    let conversations: [ConversationRecord]
}
