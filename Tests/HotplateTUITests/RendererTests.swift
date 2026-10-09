import XCTest
@testable import HotplateTUI

final class RendererTests: XCTestCase {
    private let esc = "\u{1B}"

    func testFirstFrameClearsAndDrawsEverything() {
        var b = ScreenBuffer(width: 2, height: 1)
        b.put("ab", x: 0, y: 0)
        var r = Renderer()
        XCTAssertEqual(r.render(b), "\(esc)[0m\(esc)[2J\(esc)[1;1H\(esc)[0mab\(esc)[0m")
    }

    func testUnchangedFrameEmitsNothing() {
        var b = ScreenBuffer(width: 2, height: 1)
        b.put("ab", x: 0, y: 0)
        var r = Renderer()
        _ = r.render(b)
        XCTAssertEqual(r.render(b), "")
    }

    func testOneChangedCellMovesOnceAndWritesOnce() {
        var b = ScreenBuffer(width: 3, height: 2)
        b.put("abc", x: 0, y: 0)
        var r = Renderer()
        _ = r.render(b)
        b.put("X", x: 1, y: 1)
        XCTAssertEqual(r.render(b), "\(esc)[2;2H\(esc)[0mX\(esc)[0m")
    }

    func testStyleChangeIsEmitted() {
        var b = ScreenBuffer(width: 1, height: 1)
        b.put("A", x: 0, y: 0)
        var r = Renderer()
        _ = r.render(b)
        b.put("A", x: 0, y: 0, style: Style(fg: .red, bold: true))
        XCTAssertEqual(r.render(b), "\(esc)[1;1H\(esc)[0;1;31mA\(esc)[0m")
    }

    func testRendersWideCharacterOnce() {
        var b = ScreenBuffer(width: 3, height: 1)
        b.put("界", x: 0, y: 0)
        var r = Renderer()
        XCTAssertEqual(r.render(b), "\(esc)[0m\(esc)[2J\(esc)[1;1H\(esc)[0m界 \(esc)[0m")
    }

    func testResizeOrInvalidateRedrawsFully() {
        var r = Renderer()
        _ = r.render(ScreenBuffer(width: 2, height: 1))
        XCTAssertTrue(r.render(ScreenBuffer(width: 3, height: 1)).hasPrefix("\(esc)[0m\(esc)[2J"))
        r.invalidate()
        XCTAssertTrue(r.render(ScreenBuffer(width: 3, height: 1)).hasPrefix("\(esc)[0m\(esc)[2J"))
    }
}
