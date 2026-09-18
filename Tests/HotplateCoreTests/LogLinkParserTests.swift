import XCTest
@testable import HotplateCore

final class LogLinkParserTests: XCTestCase {
    func testFindsPackageUriWithLineAndColumn() {
        let links = LogLinkParser.links(in: "#0      main (package:lootique/features/auth/page.dart:42:7)")
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links[0].raw, "package:lootique/features/auth/page.dart:42:7")
        XCTAssertEqual(links[0].location, "package:lootique/features/auth/page.dart")
        XCTAssertEqual(links[0].line, 42); XCTAssertEqual(links[0].column, 7)
    }

    func testFindsRelativeLibPathWithoutLine() {
        let links = LogLinkParser.links(in: "Launching lib/flavors/main_development.dart on iPhone")
        XCTAssertEqual(links.map(\.location), ["lib/flavors/main_development.dart"])
        XCTAssertNil(links[0].line)
    }

    func testFindsAbsoluteAndFileUri() {
        let text = "Error in /Users/me/p/lib/a.dart:3 and file:///Users/me/p/lib/b.dart:4:5"
        let links = LogLinkParser.links(in: text)
        XCTAssertEqual(links.map(\.location), ["/Users/me/p/lib/a.dart", "file:///Users/me/p/lib/b.dart"])
        XCTAssertEqual(links.map(\.line), [3, 4])
    }

    func testIgnoresNonDartPaths() {
        XCTAssertTrue(LogLinkParser.links(in: "Running pod install... see ios/Podfile.lock").isEmpty)
    }

    func testResolvesAgainstProjectAndPackageConfig() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent(".dart_tool"), withIntermediateDirectories: true)
        let config = """
        {"configVersion":2,"packages":[
          {"name":"lootique","rootUri":"../","packageUri":"lib/"},
          {"name":"collection","rootUri":"file:///Users/me/.pub-cache/hosted/pub.dev/collection-1.19.0","packageUri":"lib/"}
        ]}
        """
        try config.write(to: dir.appendingPathComponent(".dart_tool/package_config.json"), atomically: true, encoding: .utf8)
        let resolver = PackageConfigResolver(projectPath: dir.path)
        XCTAssertEqual(resolver.resolve("package:lootique/features/x.dart"), dir.appendingPathComponent("lib/features/x.dart").path)
        XCTAssertEqual(resolver.resolve("package:collection/src/list.dart"), "/Users/me/.pub-cache/hosted/pub.dev/collection-1.19.0/lib/src/list.dart")
        XCTAssertEqual(resolver.resolve("lib/main.dart"), dir.appendingPathComponent("lib/main.dart").path)
        XCTAssertEqual(resolver.resolve("/abs/x.dart"), "/abs/x.dart")
        XCTAssertEqual(resolver.resolve("file:///abs/y.dart"), "/abs/y.dart")
        XCTAssertNil(resolver.resolve("package:unknown/z.dart"))
    }
}

final class EditorOpenCommandTests: XCTestCase {
    func testVSCodeUsesBundledCliWithGoto() {
        let cmd = EditorLauncher.openFileCommand(appPath: "/Applications/Visual Studio Code.app", bundleIdentifier: "com.microsoft.VSCode",
                                                 file: "/p/lib/a.dart", line: 12, column: 3)
        XCTAssertEqual(cmd, ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code", "-g", "/p/lib/a.dart:12:3"])
    }

    func testZedUsesBundledCli() {
        let cmd = EditorLauncher.openFileCommand(appPath: "/Applications/Zed.app", bundleIdentifier: "dev.zed.Zed", file: "/p/a.dart", line: 5, column: nil)
        XCTAssertEqual(cmd, ["/Applications/Zed.app/Contents/MacOS/cli", "/p/a.dart:5"])
    }

    func testXcodeUsesXed() {
        XCTAssertEqual(EditorLauncher.openFileCommand(appPath: "/Applications/Xcode.app", bundleIdentifier: "com.apple.dt.Xcode", file: "/p/a.dart", line: 9, column: nil),
                       ["/usr/bin/xed", "-l", "9", "/p/a.dart"])
    }

    func testUnknownEditorReturnsNil() {
        XCTAssertNil(EditorLauncher.openFileCommand(appPath: "/Applications/Foo.app", bundleIdentifier: "com.foo", file: "/p/a.dart", line: 1, column: nil))
    }

    func testCustomTemplateWithFileAndLine() {
        XCTAssertEqual(EditorLauncher.expand(template: "nvim +{line} {file}", projectPath: "/p", file: "/p/a b.dart", line: 7),
                       "nvim +7 '/p/a b.dart'")
    }
}
