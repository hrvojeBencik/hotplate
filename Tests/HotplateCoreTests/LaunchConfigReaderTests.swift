import XCTest
@testable import HotplateCore

final class LaunchConfigReaderTests: XCTestCase {
    let lootique = """
    {
      // VSCode launch configs
      "version": "0.2.0",
      "configurations": [
        {
          "name": "[DEV] Lootique",
          "request": "launch",
          "type": "dart",
          "program": "lib/flavors/main_development.dart",
          "args": ["--flavor", "development", "--target", "lib/flavors/main_development.dart", "--dart-define-from-file", "env-dev.json"]
        },
        {
          "name": "Lootique (release mode)",
          "request": "launch",
          "type": "dart",
          "program": "lib/flavors/main_production.dart",
          "args": ["--flavor", "production", "--dart-define-from-file", "env-prod.json"],
          "flutterMode": "release",
        },
        { "name": "Attach", "request": "attach", "type": "dart" },
        { "name": "Node thing", "request": "launch", "type": "node", "program": "x.js" },
      ]
    }
    """

    func testParsesJsonWithCommentsAndTrailingCommas() throws {
        let configs = try LaunchConfigReader.parse(jsonc: lootique)
        XCTAssertEqual(configs.map(\.name), ["[DEV] Lootique", "Lootique (release mode)"])
    }

    func testArgsWithExplicitTargetAreNotDuplicated() throws {
        let c = try LaunchConfigReader.parse(jsonc: lootique)[0]
        XCTAssertEqual(c.flutterRunArguments, ["--flavor", "development", "--target", "lib/flavors/main_development.dart", "--dart-define-from-file", "env-dev.json"])
    }

    func testProgramBecomesTargetAndModeBecomesFlag() throws {
        let c = try LaunchConfigReader.parse(jsonc: lootique)[1]
        XCTAssertEqual(c.flutterRunArguments, ["-t", "lib/flavors/main_production.dart", "--flavor", "production", "--dart-define-from-file", "env-prod.json", "--release"])
    }

    func testDefaultMainIsOmittedAndToolArgsIncluded() throws {
        let json = """
        {"configurations":[{"name":"Dev","type":"dart","program":"lib/main.dart","toolArgs":["--dart-define-from-file=env/dev.json"],"deviceId":"chrome"}]}
        """
        let c = try LaunchConfigReader.parse(jsonc: json)[0]
        XCTAssertEqual(c.flutterRunArguments, ["--dart-define-from-file=env/dev.json"])
        XCTAssertEqual(c.deviceId, "chrome")
    }

    func testProfileMode() throws {
        let c = try LaunchConfigReader.parse(jsonc: #"{"configurations":[{"name":"P","type":"dart","flutterMode":"profile"}]}"#)[0]
        XCTAssertEqual(c.flutterRunArguments, ["--profile"])
    }

    func testCommentMarkersInsideStringsSurvive() throws {
        let c = try LaunchConfigReader.parse(jsonc: #"{"configurations":[{"name":"U","type":"dart","args":["--dart-define=URL=http://x/y"]}]}"#)[0]
        XCTAssertEqual(c.flutterRunArguments, ["--dart-define=URL=http://x/y"])
    }

    func testLoadFromProjectWithoutFileIsEmpty() {
        XCTAssertEqual(LaunchConfigReader.load(projectPath: "/nonexistent/project").count, 0)
    }

    func testLoadFromProject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".vscode"), withIntermediateDirectories: true)
        try lootique.write(to: dir.appendingPathComponent(".vscode/launch.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(LaunchConfigReader.load(projectPath: dir.path).count, 2)
    }
}

final class ArgumentJoinerTests: XCTestCase {
    func testJoinQuotesTokensWithSpaces() {
        XCTAssertEqual(ArgumentSplitter.join(["--dart-define=A=b c", "-t", "lib/main.dart"]), #""--dart-define=A=b c" -t lib/main.dart"#)
    }
    func testRoundTrip() {
        let args = ["--flavor", "dev", "--dart-define=X=hello world", "--dart-define=Q=say \"hi\""]
        XCTAssertEqual(ArgumentSplitter.split(ArgumentSplitter.join(args)), args)
    }
}
