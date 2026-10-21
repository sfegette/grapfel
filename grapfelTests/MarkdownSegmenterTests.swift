import XCTest

final class MarkdownSegmenterTests: XCTestCase {
    func testBlockParserExtractsATXHeadingLevels() {
        let blocks = MarkdownBlockParser.blocks(of: """
        Intro with **bold** text.

        ### Third-level heading
        Body text.
        ###### Sixth-level heading
        """)

        XCTAssertEqual(blocks, [
            MarkdownBlock(text: "Intro with **bold** text.", kind: .prose),
            MarkdownBlock(text: "Third-level heading", kind: .heading(level: 3)),
            MarkdownBlock(text: "Body text.", kind: .prose),
            MarkdownBlock(text: "Sixth-level heading", kind: .heading(level: 6)),
        ])
    }

    func testBlockParserKeepsIncompleteStreamingHeadingAsProse() {
        XCTAssertEqual(
            MarkdownBlockParser.blocks(of: "###"),
            [MarkdownBlock(text: "###", kind: .prose)]
        )
    }

    func testBlockParserDoesNotTreatSevenMarkersAsHeading() {
        XCTAssertEqual(
            MarkdownBlockParser.blocks(of: "####### Not a heading"),
            [MarkdownBlock(text: "####### Not a heading", kind: .prose)]
        )
    }

    func testSegmentsSplitProseAndFencedCodeBlock() {
        let source = """
        Before

        ```swift
        let x = 1
        ```

        After
        """

        let segments = MarkdownSegmenter.segments(of: source)

        XCTAssertEqual(segments.map(\.text), ["Before", "let x = 1", "After"])
        XCTAssertEqual(segments.map(\.isCode), [false, true, false])
    }

    func testSegmentsTreatUnclosedFenceAsCodeUntilEnd() {
        let source = """
        Intro
        ```json
        {"ok":true}
        """

        let segments = MarkdownSegmenter.segments(of: source)

        XCTAssertEqual(segments.map(\.text), ["Intro", #"{"ok":true}"#])
        XCTAssertEqual(segments.map(\.isCode), [false, true])
    }

    func testSegmentsReturnSingleProseSegmentWhenNoFenceExists() {
        let segments = MarkdownSegmenter.segments(of: "Just plain text")

        XCTAssertEqual(segments.map(\.text), ["Just plain text"])
        XCTAssertEqual(segments.map(\.isCode), [false])
    }
}
