import XCTest
@testable import FlutterRunnerCore

final class FlutterLocatorTests: XCTestCase {
    func testExtractsPathBetweenMarkersIgnoringShellNoise() {
        let noisy = "Welcome banner\n\u{1B}[0mprompt junk\n__FR_PATH__/opt/homebrew/bin:/usr/bin__FR_END__\nmore junk\n"
        XCTAssertEqual(FlutterLocator.extractMarkedPath(from: noisy), "/opt/homebrew/bin:/usr/bin")
    }

    func testMissingMarkersReturnsNil() {
        XCTAssertNil(FlutterLocator.extractMarkedPath(from: "/usr/bin:/bin\n"))
    }

    func testEnvironmentPathContainsFlutterBinFirstAndFallbackDirsWithoutDuplicates() {
        let env = FlutterLocator.environment(flutterPath: "/x/flutter/bin/flutter")
        let parts = env["PATH"]!.split(separator: ":").map(String.init)
        XCTAssertEqual(parts.first, "/x/flutter/bin")
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/local/bin"))
        XCTAssertEqual(parts.count, Set(parts).count, "PATH has duplicates: \(parts)")
        XCTAssertNotNil(env["LANG"])
    }
}
