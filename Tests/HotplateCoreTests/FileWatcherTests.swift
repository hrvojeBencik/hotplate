import XCTest
@testable import HotplateCore

final class FileWatcherTests: XCTestCase {
    func testDetectsDartWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exp = expectation(description: "change")
        let box = PathBox()
        let w = FileWatcher(path: dir.path) { paths in box.set(paths); exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.5)
        try "void main() {}".write(to: dir.appendingPathComponent("main.dart"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 5)
        w.stop()
        XCTAssertTrue(box.paths.contains { $0.hasSuffix("main.dart") })
    }

    func testIgnoresNonDart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exp = expectation(description: "no change"); exp.isInverted = true
        let w = FileWatcher(path: dir.path) { _ in exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.5)
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 1)
        w.stop()
    }

    // MARK: Watching a whole project and its local packages

    /// app/ (with lib/, ui/, test/, build/, .dart_tool/) and a local package outside it, ../shared/.
    private func makeProjectWithPackage() throws -> (scope: WatchScope, app: URL, shared: URL) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = base.appendingPathComponent("app"), shared = base.appendingPathComponent("shared")
        for dir in ["lib", "ui/widgets", "test", "build", ".dart_tool"] {
            try FileManager.default.createDirectory(at: app.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: shared.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n  shared:\n    path: ../shared\n"
            .write(to: app.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try "name: shared\n".write(to: shared.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let scope = WatchScope.forProject(at: app.path)
        XCTAssertEqual(scope.watchedPaths.count, 2)
        return (scope, app, shared)
    }

    func testDetectsDartWriteOutsideLib() throws {
        let (scope, app, _) = try makeProjectWithPackage()
        let exp = expectation(description: "change")
        let box = PathBox()
        let w = FileWatcher(scope: scope) { paths in box.set(paths); exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.5)
        try "class Button {}".write(to: app.appendingPathComponent("ui/widgets/button.dart"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 5)
        w.stop()
        XCTAssertTrue(box.paths.contains { $0.hasSuffix("/app/ui/widgets/button.dart") }, "\(box.paths)")
    }

    func testDetectsDartWriteInLocalPackageOutsideProject() throws {
        let (scope, _, shared) = try makeProjectWithPackage()
        let exp = expectation(description: "change")
        let box = PathBox()
        let w = FileWatcher(scope: scope) { paths in box.set(paths); exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.5)
        try "class Card {}".write(to: shared.appendingPathComponent("lib/card.dart"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 5)
        w.stop()
        XCTAssertTrue(box.paths.contains { $0.hasSuffix("/shared/lib/card.dart") }, "\(box.paths)")
    }

    func testIgnoresTestsBuildOutputAndToolFilesInProject() throws {
        let (scope, app, _) = try makeProjectWithPackage()
        let exp = expectation(description: "no change"); exp.isInverted = true
        let box = PathBox()
        let w = FileWatcher(scope: scope) { paths in box.set(paths); exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.5)
        try "void main() {}".write(to: app.appendingPathComponent("test/widget_test.dart"), atomically: true, encoding: .utf8)
        try "x".write(to: app.appendingPathComponent("build/gen.dart"), atomically: true, encoding: .utf8)
        try "x".write(to: app.appendingPathComponent(".dart_tool/registrant.dart"), atomically: true, encoding: .utf8)
        try "x".write(to: app.appendingPathComponent("ui/readme.md"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 1.5)
        w.stop()
        XCTAssertEqual(box.paths, [])
    }

    func testStopEndsEvents() throws {
        let (scope, app, _) = try makeProjectWithPackage()
        let exp = expectation(description: "no change after stop"); exp.isInverted = true
        let w = FileWatcher(scope: scope) { _ in exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.3)
        w.stop()
        try "x".write(to: app.appendingPathComponent("lib/main.dart"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 1)
    }
}

private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var p: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return p }
    func set(_ v: [String]) { lock.lock(); p = v; lock.unlock() }
}
