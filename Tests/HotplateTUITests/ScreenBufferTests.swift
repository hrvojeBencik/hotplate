import XCTest
@testable import HotplateTUI

final class ScreenBufferTests: XCTestCase {
    func testPutClipsAtRightEdgeAndMaxWidth() {
        var b = ScreenBuffer(width: 5, height: 1)
        XCTAssertEqual(b.put("abcdefg", x: 1, y: 0), 4)
        XCTAssertEqual(b.text(row: 0), " abcd")
        XCTAssertEqual(b.put("xyz", x: 0, y: 0, maxWidth: 2), 2)
        XCTAssertEqual(b.text(row: 0), "xybcd")
    }

    func testWideCharacterIsNotSplitAtRightEdge() {
        var b = ScreenBuffer(width: 3, height: 1)
        XCTAssertEqual(b.put("ab界", x: 0, y: 0), 2)
        XCTAssertEqual(b.text(row: 0), "ab ")
        var c = ScreenBuffer(width: 4, height: 1)
        XCTAssertEqual(c.put("🔥x", x: 0, y: 0), 3)
        XCTAssertEqual(c.text(row: 0), "🔥x ")
        XCTAssertEqual(c[1, 0].width, 0)
    }

    func testOutOfBoundsWritesAreIgnored() {
        var b = ScreenBuffer(width: 3, height: 1)
        XCTAssertEqual(b.put("a", x: 0, y: 5), 0)
        XCTAssertEqual(b.put("a", x: -1, y: 0), 0)
        b.fill(x: 2, y: 0, width: 10, style: Style(inverse: true))
        XCTAssertTrue(b[2, 0].style.inverse)
    }

    func testCharWidths() {
        XCTAssertEqual(CharWidth.of("a"), 1)
        XCTAssertEqual(CharWidth.of("界"), 2)
        XCTAssertEqual(CharWidth.of("🔥"), 2)
        XCTAssertEqual(CharWidth.of("●"), 1)
        XCTAssertEqual(CharWidth.of("▶"), 1)
        XCTAssertEqual(CharWidth.of("\u{0301}"), 0)
        XCTAssertEqual(CharWidth.truncate("abcdef", to: 4), "abc…")
        XCTAssertEqual(CharWidth.truncate("abc", to: 4), "abc")
    }
}
