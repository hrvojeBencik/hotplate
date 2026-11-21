import XCTest
@testable import HotplateCore

final class WatchScopeTests: XCTestCase {
    /// A temp folder (symlinks resolved the way FSEvents reports them) holding `files` at relative paths.
    private func makeTree(_ files: [String: String]) throws -> String {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("watchscope-\(UUID().uuidString)")
        for (rel, content) in files {
            let url = base.appendingPathComponent(rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return WatchScope.canonical(base.path)
    }

    private let flutterPubspec = "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n"

    // MARK: Discovery

    func testPlainProjectWatchesOnlyItsRoot() throws {
        let base = try makeTree(["app/pubspec.yaml": flutterPubspec, "app/lib/main.dart": ""])
        let scope = WatchScope.forProject(at: "\(base)/app")
        XCTAssertEqual(scope.projectPath, "\(base)/app")
        XCTAssertEqual(scope.packageRoots, ["\(base)/app"])
        XCTAssertEqual(scope.watchedPaths, ["\(base)/app"])
        XCTAssertEqual(scope.localPackages, [])
    }

    func testPubspecPathDependenciesInsideAndOutsideTheProject() throws {
        let base = try makeTree([
            "app/pubspec.yaml": flutterPubspec + "  ui:\n    path: ui\n  shared: {path: ../shared}\n  gone:\n    path: ../missing\n",
            "app/ui/pubspec.yaml": "name: ui\n",
            "shared/pubspec.yaml": "name: shared\n",
        ])
        let scope = WatchScope.forProject(at: "\(base)/app")
        XCTAssertEqual(scope.packageRoots, ["\(base)/app", "\(base)/app/ui", "\(base)/shared"],
                       "a path that does not exist is skipped")
        XCTAssertEqual(scope.watchedPaths, ["\(base)/app", "\(base)/shared"], "ui/ is already inside the project")
        XCTAssertEqual(scope.localPackages, ["ui", "shared"])
    }

    func testAbsolutePathDependency() throws {
        let base = try makeTree(["elsewhere/kit/pubspec.yaml": "name: kit\n", "app/lib/main.dart": ""])
        try (flutterPubspec + "  kit:\n    path: \(base)/elsewhere/kit\n")
            .write(toFile: "\(base)/app/pubspec.yaml", atomically: true, encoding: .utf8)
        let scope = WatchScope.forProject(at: "\(base)/app")
        XCTAssertEqual(scope.packageRoots, ["\(base)/app", "\(base)/elsewhere/kit"])
    }

    func testPackageConfigAddsTransitiveLocalPackagesButNotPubCacheOrSdk() throws {
        let config = """
        {
          "configVersion": 2,
          "packages": [
            { "name": "app", "rootUri": "../", "packageUri": "lib/" },
            { "name": "ui", "rootUri": "../../ui", "packageUri": "lib/" },
            { "name": "core", "rootUri": "../../core%20lib", "packageUri": "lib/" },
            { "name": "http", "rootUri": "file:///Users/x/.pub-cache/hosted/pub.dev/http-1.2.0", "packageUri": "lib/" },
            { "name": "flutter", "rootUri": "file:///opt/flutter/packages/flutter", "packageUri": "lib/" }
          ]
        }
        """
        let base = try makeTree([
            "app/pubspec.yaml": flutterPubspec + "  ui:\n    path: ../ui\n",
            "app/.dart_tool/package_config.json": config,
            "ui/pubspec.yaml": "name: ui\n",
            "core lib/pubspec.yaml": "name: core\n",
        ])
        let scope = WatchScope.forProject(at: "\(base)/app")
        XCTAssertEqual(scope.packageRoots, ["\(base)/app", "\(base)/ui", "\(base)/core lib"], "no duplicates, project first")
    }

    func testMalformedPackageConfigIsIgnored() throws {
        let base = try makeTree(["app/pubspec.yaml": flutterPubspec, "app/.dart_tool/package_config.json": "{ not json"])
        XCTAssertEqual(WatchScope.forProject(at: "\(base)/app").packageRoots, ["\(base)/app"])
    }

    func testWorkspaceMemberUsesTheWorkspacePackageConfig() throws {
        let config = """
        {"configVersion": 2, "packages": [
          {"name": "app", "rootUri": "../apps/app", "packageUri": "lib/"},
          {"name": "design", "rootUri": "../packages/design", "packageUri": "lib/"}
        ]}
        """
        let base = try makeTree([
            "ws/pubspec.yaml": "name: ws\nworkspace:\n  - apps/app\n  - packages/design\n",
            "ws/.dart_tool/package_config.json": config,
            "ws/apps/app/pubspec.yaml": "name: app\nresolution: workspace\ndependencies:\n  flutter:\n    sdk: flutter\n  design: any\n",
            "ws/packages/design/pubspec.yaml": "name: design\nresolution: workspace\n",
        ])
        let scope = WatchScope.forProject(at: "\(base)/ws/apps/app")
        XCTAssertEqual(scope.packageRoots, ["\(base)/ws/apps/app", "\(base)/ws/packages/design"])
    }

    func testNonWorkspaceProjectIgnoresAParentPackageConfig() throws {
        let base = try makeTree([
            "outer/.dart_tool/package_config.json": #"{"packages": [{"name": "x", "rootUri": "../x"}]}"#,
            "outer/x/pubspec.yaml": "name: x\n",
            "outer/app/pubspec.yaml": flutterPubspec,
        ])
        XCTAssertEqual(WatchScope.forProject(at: "\(base)/outer/app").packageRoots, ["\(base)/outer/app"])
    }

    func testExampleAppOfAPackageWatchesTheParentPackage() throws {
        let base = try makeTree([
            "pkg/pubspec.yaml": "name: pkg\n",
            "pkg/example/pubspec.yaml": flutterPubspec + "  pkg:\n    path: ../\n",
        ])
        let scope = WatchScope.forProject(at: "\(base)/pkg/example")
        XCTAssertEqual(scope.packageRoots, ["\(base)/pkg/example", "\(base)/pkg"])
        XCTAssertEqual(scope.watchedPaths, ["\(base)/pkg"], "the project is inside its dependency")
        XCTAssertTrue(scope.isRelevant("\(base)/pkg/lib/src/widget.dart"))
        XCTAssertTrue(scope.isRelevant("\(base)/pkg/example/lib/main.dart"), "example/ is skipped only for other packages")
        XCTAssertFalse(scope.isRelevant("\(base)/pkg/test/widget_test.dart"))
        XCTAssertFalse(scope.isRelevant("\(base)/pkg/example/test/widget_test.dart"))
    }

    func testMissingPubspecStillWatchesTheProject() throws {
        let base = try makeTree(["app/lib/main.dart": ""])
        XCTAssertEqual(WatchScope.forProject(at: "\(base)/app").packageRoots, ["\(base)/app"])
    }

    // MARK: Relevance

    func testFoldersOutsideLibAreRelevant() {
        let scope = WatchScope(projectPath: "/p/app")
        XCTAssertTrue(scope.isRelevant("/p/app/lib/main.dart"))
        XCTAssertTrue(scope.isRelevant("/p/app/ui/widgets/button.dart"))
        XCTAssertTrue(scope.isRelevant("/p/app/packages/design/lib/theme.dart"))
    }

    func testIgnoredFoldersOfTheProject() {
        let scope = WatchScope(projectPath: "/p/app")
        XCTAssertFalse(scope.isRelevant("/p/app/test/widget_test.dart"))
        XCTAssertFalse(scope.isRelevant("/p/app/integration_test/app_test.dart"))
        XCTAssertFalse(scope.isRelevant("/p/app/build/x.dart"))
        XCTAssertFalse(scope.isRelevant("/p/app/.dart_tool/flutter_build/dart_plugin_registrant.dart"))
        XCTAssertFalse(scope.isRelevant("/p/app/ios/.symlinks/plugins/x/lib/x.dart"))
        XCTAssertFalse(scope.isRelevant("/p/app/lib/notes.md"))
    }

    func testPathsOutsideEveryRootAreIgnored() {
        let scope = WatchScope(projectPath: "/p/app", packageRoots: ["/p/shared"])
        XCTAssertFalse(scope.isRelevant("/p/other/lib/x.dart"))
        XCTAssertFalse(scope.isRelevant("/p/app2/lib/x.dart"), "a sibling with the same prefix is not inside")
        XCTAssertFalse(scope.isRelevant("/p/app.dart"))
        XCTAssertTrue(scope.isRelevant("/p/shared/lib/x.dart"))
    }

    func testRulesApplyRelativeToTheDeepestPackage() {
        let scope = WatchScope(projectPath: "/p/app", packageRoots: ["/p/app/ui", "/p/shared"])
        XCTAssertFalse(scope.isRelevant("/p/app/ui/test/button_test.dart"), "ui's own tests")
        XCTAssertFalse(scope.isRelevant("/p/shared/example/lib/main.dart"), "a dependency's example app")
        XCTAssertFalse(scope.isRelevant("/p/shared/test/x_test.dart"))
        XCTAssertTrue(scope.isRelevant("/p/shared/lib/x.dart"))
        XCTAssertTrue(scope.isRelevant("/p/shared/src/x.dart"))
    }

    func testProjectUnderAHiddenFolderStillWorks() {
        let scope = WatchScope(projectPath: "/Users/me/.work/app")
        XCTAssertTrue(scope.isRelevant("/Users/me/.work/app/lib/main.dart"))
        XCTAssertTrue(scope.isRelevant("/Users/me/.work/app/ui/button.dart"))
    }

    func testSymlinkedSpellingOfAPathMatches() throws {
        // FSEvents reports /private/var/…; callers may hold /var/… (or the reverse).
        let base = try makeTree(["app/ui/button.dart": ""])
        let scope = WatchScope(projectPath: "\(base)/app")
        XCTAssertTrue(base.hasPrefix("/private/"), "temp dir resolves through /private")
        let unresolved = String(base.dropFirst("/private".count))
        XCTAssertTrue(scope.isRelevant("\(unresolved)/app/ui/button.dart"))
        XCTAssertTrue(scope.isRelevant("\(unresolved)/app/ui/deleted_meanwhile.dart"))
        XCTAssertEqual(WatchScope(projectPath: "\(unresolved)/app").projectPath, "\(base)/app")
    }

    // MARK: Display

    func testDisplayPath() {
        let scope = WatchScope(projectPath: "/p/app", packageRoots: ["/p/shared_ui"])
        XCTAssertEqual(scope.displayPath("/p/app/ui/button.dart"), "ui/button.dart")
        XCTAssertEqual(scope.displayPath("/p/shared_ui/lib/card.dart"), "shared_ui/lib/card.dart")
        XCTAssertEqual(scope.displayPath("/elsewhere/x.dart"), "/elsewhere/x.dart")
    }

    func testDuplicateAndTrailingSlashRootsCollapse() {
        let scope = WatchScope(projectPath: "/p/app/", packageRoots: ["/p/app", "/p/shared/", "/p/shared", "/p/x/../shared"])
        XCTAssertEqual(scope.packageRoots, ["/p/app", "/p/shared"])
    }
}
