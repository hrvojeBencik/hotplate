import XCTest
@testable import HotplateTUI

final class KeyBindingsTests: XCTestCase {
    func testNoKeyIsBoundTwice() {
        let keys = KeyBindings.normal.flatMap(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testEveryBindingIsDocumented() {
        for b in KeyBindings.normal {
            XCTAssertFalse(b.help.isEmpty, "\(b.action)")
            XCTAssertFalse(b.keyLabel.isEmpty, "\(b.action)")
        }
    }

    func testCoreKeys() {
        XCTAssertEqual(KeyBindings.action(for: .ctrl("c")), .quit)
        XCTAssertEqual(KeyBindings.action(for: .char("q")), .quit)
        XCTAssertEqual(KeyBindings.action(for: .char("r")), .reload)
        XCTAssertEqual(KeyBindings.action(for: .char("R")), .restart)
        XCTAssertEqual(KeyBindings.action(for: .char("K")), .clearLog)
        XCTAssertEqual(KeyBindings.action(for: .char("k")), .lineUp)
        XCTAssertEqual(KeyBindings.action(for: .enter), .enter)
        XCTAssertNil(KeyBindings.action(for: .char("z")))
    }

    func testFooterFitsAndEndsWithHelp() {
        for width in [60, 80, 120, 200] {
            for running in [false, true] {
                let items = KeyBindings.footerItems(width: width, isRunning: running)
                let rendered = " " + items.map { "\($0.key) \($0.label)" }.joined(separator: "  ")
                XCTAssertLessThanOrEqual(CharWidth.of(rendered), width)
                XCTAssertEqual(items.last, FooterItem(key: "?", label: "help"))
            }
        }
    }

    func testFooterLeadsWithRunOrStop() {
        XCTAssertEqual(KeyBindings.footerItems(width: 120, isRunning: false).first, FooterItem(key: "⏎", label: "run"))
        XCTAssertEqual(KeyBindings.footerItems(width: 120, isRunning: true).first, FooterItem(key: "s", label: "stop"))
    }
}
