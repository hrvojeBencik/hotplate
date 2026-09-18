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
}

private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var p: [String] = []
    var paths: [String] { lock.lock(); defer { lock.unlock() }; return p }
    func set(_ v: [String]) { lock.lock(); p = v; lock.unlock() }
}
