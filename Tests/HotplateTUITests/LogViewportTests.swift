import XCTest
import HotplateCore
@testable import HotplateTUI

final class LogViewportTests: XCTestCase {
    private let g = LogViewport.gutter

    private func lines(_ texts: [String], kinds: [LogKind]? = nil, firstId: Int = 0) -> [LogLine] {
        texts.enumerated().map { i, t in LogLine(id: firstId + i, text: t, kind: kinds?[i] ?? .normal, time: Date(timeIntervalSince1970: 0)) }
    }

    private func numbered(_ n: Int, firstId: Int = 0) -> [LogLine] { lines((0..<n).map { "line \($0 + firstId)" }, firstId: firstId) }

    func testWrapsLongLinesUnderTheText() {
        var v = LogViewport()
        v.update(lines: lines([String(repeating: "0123456789", count: 2) + "01234"]), width: g + 10, height: 5)
        XCTAssertEqual(v.rows.map(\.text), ["0123456789", "0123456789", "01234"])
        XCTAssertEqual(v.rows.map(\.isFirst), [true, false, false])
        XCTAssertEqual(v.rows.map(\.startOffset), [0, 10, 20])
    }

    func testVeryLongLineWrapsWithoutLosingCharacters() {
        var v = LogViewport()
        v.update(lines: lines([String(repeating: "x", count: 20_000)]), width: g + 100, height: 10)
        XCTAssertEqual(v.rows.count, 200)
        XCTAssertEqual(v.rows.last?.startOffset, 19_900)
        XCTAssertEqual(v.rows.map(\.text.count).reduce(0, +), 20_000)
    }

    func testFollowKeepsTheBottomVisible() {
        var v = LogViewport()
        v.update(lines: numbered(30), width: 80, height: 10)
        XCTAssertEqual(v.top, 20)
        v.update(lines: numbered(35), width: 80, height: 10)
        XCTAssertEqual(v.top, 25)
        XCTAssertEqual(v.visibleRows.last?.lineId, 34)
    }

    func testScrollingUpStopsFollowAndBottomResumesIt() {
        var v = LogViewport()
        v.update(lines: numbered(30), width: 80, height: 10)
        v.scroll(by: -3)
        XCTAssertFalse(v.follow)
        XCTAssertEqual(v.top, 17)
        v.update(lines: numbered(40), width: 80, height: 10)
        XCTAssertEqual(v.top, 17, "view stays where the user put it")
        v.scrollToBottom()
        XCTAssertTrue(v.follow)
        XCTAssertEqual(v.top, 30)
    }

    func testScrollPositionInsideAWrappedLineSurvivesUpdates() {
        var v = LogViewport()
        let long = String(repeating: "y", count: 50)
        v.update(lines: lines([long] + (0..<20).map { "l\($0)" }), width: g + 10, height: 5)
        v.scrollToTop()
        v.scroll(by: 2)
        XCTAssertEqual(v.rows[v.top].startOffset, 20)
        v.update(lines: lines([long] + (0..<21).map { "l\($0)" }), width: g + 10, height: 5)
        XCTAssertEqual(v.rows[v.top].startOffset, 20)
    }

    func testHitFindsLinkOnAWrappedRow() throws {
        var v = LogViewport()
        v.update(lines: lines(["aaaaaaaaaa(package:app/x.dart:3:1)"]), width: g + 10, height: 5)
        let hit = try XCTUnwrap(v.hit(row: 1, column: g + 1))
        XCTAssertEqual(hit.lineId, 0)
        XCTAssertEqual(hit.link?.location, "package:app/x.dart")
        XCTAssertEqual(hit.link?.line, 3)
        XCTAssertNil(v.hit(row: 0, column: g)?.link)
        XCTAssertNil(v.hit(row: 0, column: 2)?.link, "the gutter is not a link")
        XCTAssertNil(v.hit(row: 9, column: g), "below the last row")
    }

    func testSanitizesAnsiAndTabsKeepingLinkColumns() throws {
        XCTAssertEqual(LogText.sanitize("\u{1B}[31mError\u{1B}[0m\tat x\r"), "Error    at x")
        var v = LogViewport()
        v.update(lines: lines(["\u{1B}[31mError\u{1B}[0m\tat lib/main.dart:5"]), width: g + 80, height: 5)
        XCTAssertEqual(v.entry(0)?.text, "Error    at lib/main.dart:5")
        let hit = try XCTUnwrap(v.hit(row: 0, column: g + 12))
        XCTAssertEqual(hit.link?.location, "lib/main.dart")
        XCTAssertEqual(hit.link?.line, 5)
    }

    func testSelectScrollsIntoViewAndStopsFollow() {
        var v = LogViewport()
        v.update(lines: numbered(30), width: 80, height: 10)
        v.select(lineId: 3)
        XCTAssertEqual(v.selectedLineId, 3)
        XCTAssertEqual(v.top, 3)
        XCTAssertFalse(v.follow)
        v.moveSelection(by: -1)
        XCTAssertEqual(v.selectedLineId, 2)
        XCTAssertEqual(v.top, 2)
        v.moveSelection(by: -5)
        XCTAssertEqual(v.selectedLineId, 0)
    }

    func testSelectionIsClearedWhenItsLineIsTrimmed() {
        var v = LogViewport()
        v.update(lines: numbered(10), width: 80, height: 5)
        v.select(lineId: 1)
        v.update(lines: numbered(10, firstId: 5), width: 80, height: 5)
        XCTAssertNil(v.selectedLineId)
    }

    func testLastLinkLinePrefersTheNewestError() {
        var v = LogViewport()
        v.update(lines: lines(["see lib/a.dart:1", "Error at lib/b.dart:2", "see lib/c.dart:3", "plain"],
                              kinds: [.normal, .error, .normal, .normal]), width: 80, height: 10)
        XCTAssertEqual(v.lastLinkLine(), 1)
        XCTAssertEqual(v.linkLine(from: nil, forward: false), 2)
        XCTAssertEqual(v.linkLine(from: 2, forward: false), 1)
        XCTAssertEqual(v.linkLine(from: 0, forward: true), 1)
        XCTAssertNil(v.linkLine(from: 2, forward: true))
    }

    func testSearchFindsMatchesAndWraps() {
        var v = LogViewport()
        v.update(lines: lines(["alpha", "Beta", "gamma", "beta again"]), width: 80, height: 10)
        v.setSearch("beta")
        XCTAssertEqual(v.searchMatch(from: nil, forward: false), 3)
        XCTAssertEqual(v.searchMatch(from: 3, forward: false), 1)
        XCTAssertEqual(v.searchMatch(from: 3, forward: true), 1, "wraps around")
        v.setSearch("")
        XCTAssertNil(v.searchQuery)
        XCTAssertNil(v.searchMatch(from: nil, forward: true))
    }
}
