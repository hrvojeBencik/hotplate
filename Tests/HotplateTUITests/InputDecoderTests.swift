import XCTest
@testable import HotplateTUI

final class InputDecoderTests: XCTestCase {
    private func decode(_ s: String) -> [InputEvent] {
        var d = InputDecoder()
        return d.feed(Array(s.utf8))
    }

    func testPrintableAndControlKeys() {
        XCTAssertEqual(decode("rR"), [.key(.char("r")), .key(.char("R"))])
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0x03, 0x0D, 0x7F, 0x09, 0x0C]),
                       [.key(.ctrl("c")), .key(.enter), .key(.backspace), .key(.tab), .key(.ctrl("l"))])
    }

    func testCursorAndEditingKeys() {
        XCTAssertEqual(decode("\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[D"), [.key(.up), .key(.down), .key(.right), .key(.left)])
        XCTAssertEqual(decode("\u{1B}OA\u{1B}OB"), [.key(.up), .key(.down)])
        XCTAssertEqual(decode("\u{1B}[5~\u{1B}[6~\u{1B}[3~"), [.key(.pageUp), .key(.pageDown), .key(.delete)])
        XCTAssertEqual(decode("\u{1B}[H\u{1B}[F\u{1B}[1~\u{1B}[4~"), [.key(.home), .key(.end), .key(.home), .key(.end)])
    }

    func testSequenceSplitAcrossReads() {
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0x1B, 0x5B]), [])
        XCTAssertFalse(d.hasPendingEscape)
        XCTAssertEqual(d.feed([0x41]), [.key(.up)])
    }

    func testLoneEscapeWaitsForFlush() {
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0x1B]), [])
        XCTAssertTrue(d.hasPendingEscape)
        XCTAssertEqual(d.flushEscape(), [.key(.escape)])
        XCTAssertFalse(d.hasPendingEscape)
        XCTAssertEqual(d.flushEscape(), [])
    }

    func testUTF8SplitAcrossReads() {
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0xC5]), [])
        XCTAssertEqual(d.feed([0xBE]), [.key(.char("ž"))])
    }

    func testSGRMouse() {
        XCTAssertEqual(decode("\u{1B}[<0;10;5M"), [.mouse(MouseEvent(button: .left, x: 9, y: 4, pressed: true))])
        XCTAssertEqual(decode("\u{1B}[<0;10;5m"), [.mouse(MouseEvent(button: .left, x: 9, y: 4, pressed: false))])
        XCTAssertEqual(decode("\u{1B}[<64;3;3M"), [.mouse(MouseEvent(button: .wheelUp, x: 2, y: 2, pressed: true))])
        XCTAssertEqual(decode("\u{1B}[<65;3;3M"), [.mouse(MouseEvent(button: .wheelDown, x: 2, y: 2, pressed: true))])
        XCTAssertEqual(decode("\u{1B}[<32;1;1M"), [], "motion is ignored")
    }

    func testBracketedPaste() {
        XCTAssertEqual(decode("\u{1B}[200~hello\nr\u{1B}[201~q"), [.paste("hello\nr"), .key(.char("q"))])
        var d = InputDecoder()
        XCTAssertEqual(d.feed(Array("\u{1B}[200~abc\u{1B}[20".utf8)), [])
        XCTAssertEqual(d.feed(Array("1~".utf8)), [.paste("abc")])
    }
}
