import XCTest
@testable import HotplateTUI

final class TextInputTests: XCTestCase {
    func testTypingAndCursorMovement() {
        var t = TextInput(text: "--flavor")
        XCTAssertEqual(t.cursor, 8)
        XCTAssertEqual(t.handle(.char(" ")), .editing)
        t.insert("dev")
        XCTAssertEqual(t.text, "--flavor dev")
        _ = t.handle(.home); _ = t.handle(.right); _ = t.handle(.delete)
        XCTAssertEqual(t.text, "-flavor dev")
        _ = t.handle(.end); _ = t.handle(.backspace)
        XCTAssertEqual(t.text, "-flavor de")
        _ = t.handle(.ctrl("a"))
        XCTAssertEqual(t.cursor, 0)
        _ = t.handle(.ctrl("e"))
        XCTAssertEqual(t.cursor, 10)
    }

    func testDeleteWordAndLine() {
        var t = TextInput(text: "--flavor dev  ")
        _ = t.handle(.ctrl("w"))
        XCTAssertEqual(t.text, "--flavor ")
        _ = t.handle(.ctrl("u"))
        XCTAssertEqual(t.text, "")
        XCTAssertEqual(t.cursor, 0)
    }

    func testSubmitAndCancel() {
        var t = TextInput(text: "x")
        XCTAssertEqual(t.handle(.enter), .submit)
        XCTAssertEqual(t.handle(.escape), .cancel)
        XCTAssertEqual(t.text, "x")
    }

    func testDrawShowsPromptAndText() {
        let t = TextInput(text: "--flavor dev")
        var buf = ScreenBuffer(width: 40, height: 1)
        t.draw(into: &buf, y: 0, prompt: "args: ")
        XCTAssertTrue(buf.text(row: 0).hasPrefix(" args: --flavor dev"))
    }
}
