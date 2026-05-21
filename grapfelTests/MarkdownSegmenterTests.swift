import XCTest

final class MarkdownSegmenterTests: XCTestCase {
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
