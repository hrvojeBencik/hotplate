import XCTest
@testable import HotplateCore

final class FlutterDaemonTests: XCTestCase {
    /// A shell script pretending to be `flutter run --machine`.
    private func makeFakeFlutter() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("flutter")
        let body = #"""
        #!/bin/bash
        echo '[{"event":"daemon.connected","params":{"version":"0.6.1","pid":1}}]'
        echo 'Launching lib/main.dart on Fake in debug mode...'
        echo '[{"event":"app.start","params":{"appId":"app1","deviceId":"fake","supportsRestart":true}}]'
        echo '[{"event":"app.started","params":{"appId":"app1"}}]'
        while IFS= read -r line; do
          id=$(echo "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
          case "$line" in
            *app.restart*) echo "[{\"id\":$id,\"result\":{\"code\":0,\"message\":\"Reloaded\"}}]" ;;
            *app.stop*) echo "[{\"id\":$id,\"result\":true}]"; echo '[{"event":"app.stop","params":{"appId":"app1"}}]'; exit 0 ;;
          esac
        done
        """#
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script.path
    }

    func testLifecycle() async throws {
        let fake = try makeFakeFlutter()
        let daemon = FlutterDaemon(flutterPath: fake, projectPath: FileManager.default.temporaryDirectory.path,
                                   deviceId: "fake", extraArgs: [], environment: ProcessInfo.processInfo.environment)
        let seen = SeenEvents()
        let collector = Task {
            for await e in daemon.events {
                switch e {
                case .connected: seen.add("connected")
                case .appStarting(let id, _, _): seen.add("starting:\(id)")
                case .appStarted: seen.add("started")
                case .rawOutput(let s, _): seen.add("raw:\(s)")
                case .appStopped: seen.add("stopped")
                case .processExited(let c): seen.add("exit:\(c)")
                default: break
                }
            }
        }
        try daemon.start()
        for _ in 0..<50 where daemon.appId == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(daemon.appId, "app1")
        let r = try await daemon.restart(full: false)
        XCTAssertEqual(r.code, 0); XCTAssertEqual(r.message, "Reloaded")
        await daemon.stop()
        await collector.value
        let list = seen.list
        XCTAssertEqual(list.first, "connected")
        XCTAssertTrue(list.contains("raw:Launching lib/main.dart on Fake in debug mode..."))
        XCTAssertTrue(list.contains("starting:app1")); XCTAssertTrue(list.contains("started"))
        XCTAssertTrue(list.contains("stopped")); XCTAssertEqual(list.last, "exit:0")
        XCTAssertFalse(daemon.isRunning)
        XCTAssertTrue(daemon.wasStopRequested)
    }
}

private final class SeenEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var list: [String] { lock.lock(); defer { lock.unlock() }; return items }
    func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
}
