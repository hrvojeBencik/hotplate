import XCTest
@testable import HotplateCore

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

    func testLoginShellDisablesJobControl() {
        // Without +m an interactive zsh started from a terminal grabs the tty and is stopped (SIGTTOU/SIGTTIN).
        XCTAssertEqual(FlutterLocator.loginShellArguments("echo hi"), ["+m", "-lic", "echo hi"])
        XCTAssertEqual(FlutterLocator.loginShellArguments("echo hi", interactive: false), ["+m", "-lc", "echo hi"])
    }

    func testComposedPathKeepsInheritedPathBeforeLoginShellPath() {
        let path = FlutterLocator.composePath(flutterBin: "/f/bin", inherited: "/term/bin:/usr/bin:/f/bin", login: "/login/bin:/usr/bin")
        let parts = path.split(separator: ":").map(String.init)
        XCTAssertEqual(Array(parts.prefix(4)), ["/f/bin", "/term/bin", "/login/bin", "/usr/bin"])
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertEqual(parts.count, Set(parts).count, "PATH has duplicates: \(parts)")
    }

    func testComposedPathForAGUIAppKeepsLoginOrder() {
        // A Finder-launched app inherits launchd's minimal PATH; it must not move /usr/bin ahead of Homebrew.
        let path = FlutterLocator.composePath(flutterBin: "/f/bin", inherited: "/usr/bin:/bin:/usr/sbin:/sbin",
                                              login: "/opt/homebrew/bin:/usr/bin:/bin")
        XCTAssertEqual(Array(path.split(separator: ":").map(String.init).prefix(4)), ["/f/bin", "/opt/homebrew/bin", "/usr/bin", "/bin"])
    }
}
