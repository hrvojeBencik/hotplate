import XCTest
@testable import FlutterRunnerCore

final class EditorLauncherTests: XCTestCase {
    func testTemplateSubstitutesQuotedPath() {
        let cmd = EditorLauncher.expand(template: "zed {path}", projectPath: "/Users/me/My Project")
        XCTAssertEqual(cmd, "zed '/Users/me/My Project'")
    }

    func testTemplateWithoutPlaceholderAppendsPath() {
        XCTAssertEqual(EditorLauncher.expand(template: "code", projectPath: "/p"), "code '/p'")
    }

    func testTemplateEscapesSingleQuotesInPath() {
        XCTAssertEqual(EditorLauncher.expand(template: "nvim {path}", projectPath: "/a'b"), "nvim '/a'\\''b'")
    }

    func testKnownEditorsHavePriorityOrder() {
        let ids = EditorLauncher.knownEditors.map(\.bundleIdentifier)
        XCTAssertEqual(ids.first, "dev.zed.Zed")
        XCTAssertTrue(ids.contains("com.microsoft.VSCode"))
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
