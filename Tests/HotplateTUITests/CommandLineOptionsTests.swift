import XCTest
import HotplateCore
@testable import HotplateTUI

final class CommandLineOptionsTests: XCTestCase {
    func testDefaults() throws {
        let o = try CommandLineOptions.parse([])
        XCTAssertNil(o.path)
        XCTAssertEqual(o.overrides, SessionOverrides())
        XCTAssertFalse(o.noRun)
        XCTAssertNil(o.flutterPath)
    }

    func testAllOptions() throws {
        let o = try CommandLineOptions.parse(["~/code/app", "-d", "iphone", "--config", "Dev", "--no-run",
                                              "--no-auto-reload", "--flutter", "/opt/flutter/bin/flutter"])
        XCTAssertEqual(o.path, "~/code/app")
        XCTAssertEqual(o.overrides, SessionOverrides(deviceQuery: "iphone", configName: "Dev", autoReload: false))
        XCTAssertTrue(o.noRun)
        XCTAssertEqual(o.flutterPath, "/opt/flutter/bin/flutter")
    }

    func testEverythingAfterDoubleDashGoesToFlutter() throws {
        let o = try CommandLineOptions.parse(["-c", "Dev", "--", "--flavor", "dev", "--dart-define=A=1 2", "-d", "x"])
        XCTAssertEqual(o.overrides.configName, "Dev")
        XCTAssertNil(o.overrides.deviceQuery)
        XCTAssertEqual(o.overrides.args, "--flavor dev \"--dart-define=A=1 2\" -d x")
        XCTAssertNil(try CommandLineOptions.parse(["--"]).overrides.args)
    }

    func testHelpAndVersion() throws {
        XCTAssertTrue(try CommandLineOptions.parse(["-h"]).showHelp)
        XCTAssertTrue(try CommandLineOptions.parse(["--version"]).showVersion)
        XCTAssertTrue(CommandLineOptions.usage.contains("--device"))
    }

    func testErrors() {
        XCTAssertThrowsError(try CommandLineOptions.parse(["--wat"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "unknown option --wat")
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(["-d"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "-d needs a value")
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(["-c", "--no-run"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "-c needs a value")
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(["a", "b"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "unexpected argument b")
        }
    }
}
