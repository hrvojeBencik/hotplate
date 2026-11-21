import XCTest
@testable import HotplateCore

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

    // MARK: path dependencies

    func testPathDependenciesBlockAndFlowForms() {
        let yaml = """
        name: app
        dependencies:
          flutter:
            sdk: flutter
          ui:
            path: ui
          core: {path: ../core}
          quoted:
            path: "../shared widgets" # reused across apps
          http: ^1.2.0
        dev_dependencies:
          lints:
            path: tools/lints
        dependency_overrides:
          fork: { path: '/abs/fork' }
        flutter:
          uses-material-design: true
        """
        XCTAssertEqual(PubspecReader.pathDependencies(fromYaml: yaml),
                       ["ui", "../core", "../shared widgets", "tools/lints", "/abs/fork"])
    }

    func testGitSubPathIsNotALocalPath() {
        let yaml = """
        dependencies:
          remote:
            git:
              url: https://example.com/repo.git
              path: packages/remote
          remote_flow: {git: {url: https://example.com/r.git, path: pkg}}
        """
        XCTAssertEqual(PubspecReader.pathDependencies(fromYaml: yaml), [])
    }

    func testPathKeysOutsideDependencySectionsAreIgnored() {
        let yaml = """
        flutter:
          assets:
            path: assets
        environment:
          sdk: ^3.5.0
        dependencies:
          ui:
            path: ui
        """
        XCTAssertEqual(PubspecReader.pathDependencies(fromYaml: yaml), ["ui"])
    }

    func testPathDependenciesWithFourSpaceIndentAndComments() {
        let yaml = """
        dependencies:   # all of them
            # a commented out entry
            # old:
            #     path: old
            ui:

                path: ../ui
        """
        XCTAssertEqual(PubspecReader.pathDependencies(fromYaml: yaml), ["../ui"])
    }

    func testNoPathDependencies() {
        XCTAssertEqual(PubspecReader.pathDependencies(fromYaml: yaml), [])
        XCTAssertEqual(PubspecReader.pathDependencies(fromYaml: ""), [])
    }

    func testWorkspaceResolution() {
        XCTAssertTrue(PubspecReader.usesWorkspaceResolution(yaml: "name: app\nresolution: workspace\n"))
        XCTAssertFalse(PubspecReader.usesWorkspaceResolution(yaml: "name: app\n"))
        XCTAssertFalse(PubspecReader.usesWorkspaceResolution(yaml: "dependencies:\n  resolution: workspace\n"))
    }
}
