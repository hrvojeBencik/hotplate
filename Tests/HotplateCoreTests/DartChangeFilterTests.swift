import XCTest
@testable import HotplateCore

final class DartChangeFilterTests: XCTestCase {
    func testDartInLib() { XCTAssertTrue(DartChangeFilter.isRelevant("/p/lib/main.dart")) }
    func testNonDart() { XCTAssertFalse(DartChangeFilter.isRelevant("/p/lib/notes.txt")) }
    func testDartTool() { XCTAssertFalse(DartChangeFilter.isRelevant("/p/.dart_tool/x/y.dart")) }
    func testBuildDir() { XCTAssertFalse(DartChangeFilter.isRelevant("/p/build/gen.dart")) }
    func testTempFiles() {
        XCTAssertFalse(DartChangeFilter.isRelevant("/p/lib/main.dart.swp"))
        XCTAssertFalse(DartChangeFilter.isRelevant("/p/lib/.main.dart.tmp"))
    }
}
