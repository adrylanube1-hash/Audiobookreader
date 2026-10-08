import XCTest
@testable import audiobookreader

final class TextChunkerTests: XCTestCase {
    func testPreservesParagraphsAndAvoidsTinyTail() {
        let paragraph = Array(repeating: "This is a complete sentence with useful words.", count: 30).joined(separator: " ")
        let chunks = TextChunker.split(paragraph + "\n\n" + paragraph)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 700 })
    }

    func testNormalizesVisualLineWraps() {
        XCTAssertEqual(TextChunker.normalize("First line\ncontinues here.\n\nNew paragraph."),
                       "First line continues here.\n\nNew paragraph.")
    }
}
