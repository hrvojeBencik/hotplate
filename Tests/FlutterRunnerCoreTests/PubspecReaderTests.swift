import XCTest
@testable import FlutterRunnerCore

final class PubspecReaderTests: XCTestCase {
    let yaml = """
    name: usput
    description: A demo.
    dependencies:
      flutter:
        sdk: flutter
    """
    func testName() { XCTAssertEqual(PubspecReader.name(fromYaml: yaml), "usput") }
    func testQuotedName() { XCTAssertEqual(PubspecReader.name(fromYaml: "name: \"my_app\"\n"), "my_app") }
    func testMissingName() { XCTAssertNil(PubspecReader.name(fromYaml: "description: x\n")) }
    func testIsFlutter() { XCTAssertTrue(PubspecReader.isFlutterProject(yaml: yaml)) }
    func testIsNotFlutter() { XCTAssertFalse(PubspecReader.isFlutterProject(yaml: "name: cli\ndependencies:\n  args: ^2.0.0\n")) }
}
