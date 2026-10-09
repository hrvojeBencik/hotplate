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
        HelpOverlay.draw(into: &buf)
        let all = (0..<40).map { buf.text(row: $0) }.joined()
        XCTAssertTrue(all.contains("Keyboard shortcuts"))
        XCTAssertTrue(all.contains("Hot restart"))
    }
}
