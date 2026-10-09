import XCTest
@testable import HotplateTUI

final class PickerTests: XCTestCase {
    private let items = [
        PickerItem(id: "ios1", title: "iPhone 16 Pro (emulator)", detail: "ios", isCurrent: false),
        PickerItem(id: "chrome", title: "Chrome", detail: "web-javascript", isCurrent: true),
        PickerItem(id: "macos", title: "macOS", detail: "darwin", isCurrent: false),
    ]

    func testStartsOnTheCurrentItem() {
        XCTAssertEqual(Picker(kind: .device, items: items).selected?.id, "chrome")
    }

    func testFilterMatchesTitleIdOrDetailIgnoringCase() {
        var p = Picker(kind: .device, items: items)
        p.type("I"); p.type("O"); p.type("S")
        XCTAssertEqual(p.filtered.map(\.id), ["ios1"])
        XCTAssertEqual(p.selected?.id, "ios1")
        p.backspace(); p.backspace(); p.backspace()
        XCTAssertEqual(p.filtered.count, 3)
        XCTAssertEqual(Picker(kind: .device, items: items, filter: "darwin").filtered.map(\.id), ["macos"])
    }

    func testMoveClampsAndEmptyHasNoSelection() {
        var p = Picker(kind: .device, items: items)
        p.move(by: 10)
        XCTAssertEqual(p.selected?.id, "macos")
        p.move(by: -10)
        XCTAssertEqual(p.selected?.id, "ios1")
        let empty = Picker(kind: .device, items: items, filter: "pixel")
        XCTAssertNil(empty.selected)
        XCTAssertEqual(Picker(kind: .device, items: []).emptyMessage, "No devices. Start one, then press Ctrl+R.")
    }

    func testSetItemsKeepsTheSelectedId() {
        var p = Picker(kind: .device, items: items)
        p.move(by: 1)
        p.setItems([PickerItem(id: "new", title: "New", detail: "", isCurrent: false)] + items)
        XCTAssertEqual(p.selected?.id, "macos")
    }

    func testMouseHitTesting() {
        let p = Picker(kind: .device, items: items)
        let size = TerminalSize(width: 80, height: 24)
        var buf = ScreenBuffer(width: 80, height: 24)
        p.draw(into: &buf, busy: false)
        let row = (0..<24).first { buf.text(row: $0).contains("macOS") }!
        let col = buf.text(row: row).range(of: "macOS")!.lowerBound.utf16Offset(in: buf.text(row: row))
        XCTAssertEqual(p.itemIndex(atX: col, y: row, in: size), 2)
        XCTAssertTrue(p.contains(x: col, y: row, in: size))
        XCTAssertFalse(p.contains(x: 0, y: 0, in: size))
        XCTAssertNil(p.itemIndex(atX: 0, y: 0, in: size))
    }

    func testDrawShowsTitleFilterAndBusy() {
        var p = Picker(kind: .device, items: items)
        p.type("c")
        var buf = ScreenBuffer(width: 80, height: 24)
        p.draw(into: &buf, busy: true)
        let all = (0..<24).map { buf.text(row: $0) }.joined(separator: "\n")
        XCTAssertTrue(all.contains("Devices · Refreshing…"))
        XCTAssertTrue(all.contains("› c"))
        XCTAssertTrue(all.contains("Chrome"))
    }
}
