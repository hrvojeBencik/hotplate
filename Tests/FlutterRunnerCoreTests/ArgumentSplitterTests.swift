import XCTest
@testable import FlutterRunnerCore

final class ArgumentSplitterTests: XCTestCase {
    func testEmpty() { XCTAssertEqual(ArgumentSplitter.split(""), []); XCTAssertEqual(ArgumentSplitter.split("   "), []) }
    func testSimple() {
        XCTAssertEqual(ArgumentSplitter.split("--flavor dev -t lib/main_dev.dart"), ["--flavor", "dev", "-t", "lib/main_dev.dart"])
    }
    func testDoubleQuotes() {
        XCTAssertEqual(ArgumentSplitter.split(#"--dart-define="API=a b" x"#), ["--dart-define=API=a b", "x"])
    }
    func testSingleQuotes() { XCTAssertEqual(ArgumentSplitter.split("'a b' c"), ["a b", "c"]) }
    func testEscapedSpace() { XCTAssertEqual(ArgumentSplitter.split(#"a\ b c"#), ["a b", "c"]) }
}
