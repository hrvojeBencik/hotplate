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

    // MARK: relative to a package root

    func testRelativeLibAndOtherFoldersAreRelevant() {
        XCTAssertTrue(DartChangeFilter.isRelevant(relativePath: "lib/main.dart"))
        XCTAssertTrue(DartChangeFilter.isRelevant(relativePath: "ui/widgets/button.dart"))
        XCTAssertTrue(DartChangeFilter.isRelevant(relativePath: "main.dart"))
        XCTAssertTrue(DartChangeFilter.isRelevant(relativePath: "lib/test/helpers.dart"), "test/ only counts at the package root")
        XCTAssertTrue(DartChangeFilter.isRelevant(relativePath: "lib/features/ios/picker.dart"))
        XCTAssertTrue(DartChangeFilter.isRelevant(relativePath: "test.dart"), "a file named like an ignored folder")
    }

    func testRelativeIgnoresNonAppFoldersAtPackageRoot() {
        for dir in ["test", "integration_test", "test_driver", "example", "android", "ios", "macos", "linux", "windows", "web"] {
            XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "\(dir)/x.dart"), dir)
        }
    }

    func testRelativeIgnoresGeneratedAndHiddenEverywhere() {
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "build/gen.dart"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "ui/build/gen.dart"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "ui/node_modules/x.dart"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: ".dart_tool/flutter_build/dart_plugin_registrant.dart"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: ".fvm/flutter_sdk/packages/flutter/lib/x.dart"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "ui/.idea/x.dart"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "lib/.main.dart"))
    }

    func testRelativeNonDartAndTempFiles() {
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "lib/notes.txt"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "lib/main.dart.swp"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: "lib/main.dart~"))
        XCTAssertFalse(DartChangeFilter.isRelevant(relativePath: ""))
    }
}
