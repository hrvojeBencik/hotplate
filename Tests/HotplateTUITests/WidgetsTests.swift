import XCTest
import HotplateCore
@testable import HotplateTUI

final class WidgetsTests: XCTestCase {
    func testStatusBarShowsProjectStateDeviceConfigAndAuto() {
        var buf = ScreenBuffer(width: 100, height: 1)
        StatusBar.draw(StatusInfo(project: "my_app", state: .running, statusText: "Running", flutterMissing: false,
                                  device: "iPhone 16 Pro", config: "dev", autoReload: true), into: &buf)
        let row = buf.text(row: 0)
        for part in ["Hotplate", "my_app", "● Running", "iPhone 16 Pro", "cfg: dev", "↻ auto"] {
            XCTAssertTrue(row.contains(part), part)
        }
    }

    func testStatusBarFlagsMissingFlutterAndCustomConfig() {
        var buf = ScreenBuffer(width: 100, height: 1)
        StatusBar.draw(StatusInfo(project: nil, state: .idle, statusText: "Idle", flutterMissing: true,
                                  device: nil, config: nil, autoReload: false), into: &buf)
        let row = buf.text(row: 0)
        XCTAssertTrue(row.contains("● flutter not found"))
        XCTAssertTrue(row.contains("cfg: custom"))
        XCTAssertFalse(row.contains("↻"))
    }

    func testLogPaneDrawsTimeTextAndSelection() {
        var v = LogViewport()
        let time = Date(timeIntervalSince1970: 0)
        v.update(lines: [LogLine(id: 0, text: "hello lib/main.dart:3", kind: .error, time: time)], width: 60, height: 3)
        v.select(lineId: 0)
        var buf = ScreenBuffer(width: 60, height: 5)
        LogPane.draw(v, into: &buf, top: 2)
        let row = buf.text(row: 2)
        XCTAssertTrue(row.hasPrefix("▶" + LogPane.timeFormatter.string(from: time)))
        XCTAssertTrue(row.contains("hello lib/main.dart:3"))
        XCTAssertTrue(buf[LogViewport.gutter + 6, 2].style.underline, "the link is underlined")
        XCTAssertTrue(buf[LogViewport.gutter, 2].style.inverse, "the selected line is highlighted")
    }

    func testHelpListsEveryBinding() {
        XCTAssertTrue(HelpOverlay.lines.contains { $0.contains("Hot reload") })
        XCTAssertTrue(HelpOverlay.lines.contains { $0.contains("Shift") })
        var buf = ScreenBuffer(width: 120, height: 40)
        HelpOverlay.draw(into: &buf, scroll: 0)
        let all = (0..<40).map { buf.text(row: $0) }.joined()
        XCTAssertTrue(all.contains("Keyboard shortcuts"))
        XCTAssertTrue(all.contains("Hot restart"))
    }

    func testHelpScrollingAt60x12() {
        let size = TerminalSize(width: 60, height: 12)
        let maxScroll = HelpOverlay.maxScroll(for: size)
        XCTAssertGreaterThan(maxScroll, 0, "Should need scrolling at 60×12")

        var buf = ScreenBuffer(width: 60, height: 12)
        HelpOverlay.draw(into: &buf, scroll: 0)
        let firstScroll = (0..<12).map { buf.text(row: $0) }.joined()
        XCTAssertTrue(firstScroll.contains("Hot reload"), "First scroll should show Hot reload")

        var buf2 = ScreenBuffer(width: 60, height: 12)
        HelpOverlay.draw(into: &buf2, scroll: maxScroll)
        let lastScroll = (0..<12).map { buf2.text(row: $0) }.joined()
        XCTAssertTrue(lastScroll.contains("Shift"), "Last scroll should show Shift+drag note")
    }

    func testHelpFitsAt120x40() {
        let size = TerminalSize(width: 120, height: 40)
        let maxScroll = HelpOverlay.maxScroll(for: size)
        XCTAssertEqual(maxScroll, 0, "Should fit without scrolling at 120×40")

        var buf = ScreenBuffer(width: 120, height: 40)
        HelpOverlay.draw(into: &buf, scroll: 0)
        let all = (0..<40).map { buf.text(row: $0) }.joined()
        XCTAssertTrue(all.contains("Hot reload"))
        XCTAssertTrue(all.contains("Shift"))
    }

    func testStatusBarAt60ColumnsWithLongNames() {
        var buf = ScreenBuffer(width: 60, height: 1)
        StatusBar.draw(StatusInfo(project: "my_long_project_name", state: .running, statusText: "Running",
                                  flutterMissing: false, device: "Pixel 8 Pro API 34 emulator-5554",
                                  config: "development", autoReload: true), into: &buf)
        let row = buf.text(row: 0)
        XCTAssertTrue(row.contains("● Running"), "Status should be visible")
        XCTAssertTrue(row.contains("↻ auto"), "Auto reload should be visible")
        XCTAssertTrue(row.contains("…"), "Truncated text should have ellipsis")
        XCTAssertLessThanOrEqual(CharWidth.of(row.trimmingCharacters(in: .whitespaces)), 60)
    }

    func testStatusBarAt60WithFlutterMissingAndAutoReload() {
        var buf = ScreenBuffer(width: 60, height: 1)
        StatusBar.draw(StatusInfo(project: "my_long_project_name", state: .idle, statusText: "Idle",
                                  flutterMissing: true, device: "Pixel 8 Pro API 34 emulator-5554",
                                  config: "development", autoReload: true), into: &buf)
        let row = buf.text(row: 0)
        XCTAssertTrue(row.contains("● flutter not found"), "Flutter missing should be visible")
        XCTAssertTrue(row.contains("↻ auto"), "Auto reload should be visible")
        XCTAssertLessThanOrEqual(CharWidth.of(row.trimmingCharacters(in: .whitespaces)), 60)
    }

    func testStatusBarAt60WithLongStatusText() {
        var buf = ScreenBuffer(width: 60, height: 1)
        StatusBar.draw(StatusInfo(project: "my_long_project_name", state: .restarting, statusText: "Hot restarting…",
                                  flutterMissing: false, device: "Pixel 8 Pro API 34 emulator-5554",
                                  config: "development", autoReload: true), into: &buf)
        let row = buf.text(row: 0)
        XCTAssertTrue(row.contains("● Hot restarting"), "Status should be visible")
        XCTAssertTrue(row.contains("↻ auto"), "Auto reload should be visible")
        XCTAssertLessThanOrEqual(CharWidth.of(row.trimmingCharacters(in: .whitespaces)), 60)
    }

    func testStatusBarAt30ColumnsDoesntCrash() {
        var buf = ScreenBuffer(width: 30, height: 1)
        StatusBar.draw(StatusInfo(project: "my_long_project_name", state: .running, statusText: "Running",
                                  flutterMissing: false, device: "Pixel 8 Pro API 34 emulator-5554",
                                  config: "development", autoReload: true), into: &buf)
        let row = buf.text(row: 0)
        // Should still contain status indicator even if very narrow
        XCTAssertTrue(row.contains("●"), "Status indicator should be present")
        XCTAssertLessThanOrEqual(CharWidth.of(row.trimmingCharacters(in: .whitespaces)), 30)
    }
}
