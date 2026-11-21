import XCTest
@testable import HotplateCore
import HotplateTestSupport

@MainActor
final class SessionTests: XCTestCase {
    private func runningSession() async throws -> (Session, SessionHarness, FakeDaemon) {
        let h = SessionHarness()
        let path = try TestProject.make()
        let s = h.makeSession()
        s.selectProject(path: path)
        await s.refreshDevices()
        await s.run()
        let d = try XCTUnwrap(h.lastDaemon)
        d.send(.appStarted)
        let running = await waitUntil { s.state == .running }
        XCTAssertTrue(running)
        return (s, h, d)
    }

    func testRunStartsDaemonWithDeviceAndArgs() async throws {
        let h = SessionHarness()
        let path = try TestProject.make()
        let s = h.makeSession()
        s.selectProject(path: path)
        await s.refreshDevices()
        s.extraArgs = "--flavor dev"
        await s.run()
        XCTAssertEqual(s.state, .starting)
        let d = try XCTUnwrap(h.lastDaemon)
        XCTAssertTrue(d.started)
        XCTAssertEqual(d.config.deviceId, "ios1")
        XCTAssertEqual(d.config.extraArgs, ["--flavor", "dev"])
        XCTAssertEqual(d.config.projectPath, path)
        XCTAssertEqual(h.watchers.last?.scope, WatchScope(projectPath: path), "the whole project, not only lib/")
    }

    func testReloadAndStopTransitions() async throws {
        let (s, h, d) = try await runningSession()
        await s.hotReload()
        XCTAssertEqual(d.restartCalls, [false])
        XCTAssertEqual(s.state, .running)
        await s.hotRestart()
        XCTAssertEqual(d.restartCalls, [false, true])
        await s.stop()
        let idle = await waitUntil { s.state == .idle }
        XCTAssertTrue(idle)
        XCTAssertEqual(d.stopCalls, 1)
        XCTAssertTrue(h.watchers.last?.stopped ?? false)
    }

    func testNonZeroExitFails() async throws {
        let (s, _, d) = try await runningSession()
        d.send(.processExited(code: 1))
        let failed = await waitUntil { s.state == .failed("flutter exited with code 1") }
        XCTAssertTrue(failed)
    }

    func testSavingDuringReloadQueuesExactlyOneMoreReload() async throws {
        let (s, h, d) = try await runningSession()
        d.restartDelay = 200_000_000
        let watcher = try XCTUnwrap(h.watchers.last)
        watcher.fire()
        let first = await waitUntil { d.restartCalls.count == 1 }
        XCTAssertTrue(first)
        watcher.fire(); watcher.fire()
        let second = await waitUntil(timeout: 3) { d.restartCalls.count == 2 && s.state == .running }
        XCTAssertTrue(second)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(d.restartCalls.count, 2)
    }

    func testAutoReloadOffIgnoresSaves() async throws {
        let (s, h, d) = try await runningSession()
        s.autoReload = false
        h.watchers.last?.fire()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(d.restartCalls, [])
    }

    func testForceQuitTerminatesDaemon() async throws {
        let (s, _, d) = try await runningSession()
        s.forceQuit()
        XCTAssertTrue(d.terminated)
        let idle = await waitUntil { s.state == .idle }
        XCTAssertTrue(idle)
    }

    func testMissingFlutterUsesFrontEndHint() {
        let h = SessionHarness()
        h.flutterPath = nil
        let s = h.makeSession(hints: .terminal)
        XCTAssertNil(s.flutterPath)
        XCTAssertTrue(s.logs.contains { $0.text.contains("Pass --flutter <path>") && $0.kind == .error })
        XCTAssertFalse(s.canRun)
    }

    func testBadProjectCallsOnError() throws {
        let h = SessionHarness()
        let s = h.makeSession()
        var errors: [String] = []
        s.onError = { errors.append($0) }
        s.selectProject(path: NSTemporaryDirectory())
        XCTAssertEqual(errors.count, 1)
        XCTAssertNil(s.project)
    }

    func testConcurrentDeviceRefreshesShareOneLoad() async throws {
        let h = SessionHarness()
        h.listDevicesDelay = 50_000_000
        let s = h.makeSession()
        s.selectProject(path: try TestProject.make())
        // selectProject starts its own refresh; wait until it is in flight, then add two more callers.
        let started = await waitUntil { h.listDevicesCalls == 1 }
        XCTAssertTrue(started)
        async let a: Void = s.refreshDevices()
        async let b: Void = s.refreshDevices()
        _ = await (a, b)
        XCTAssertEqual(h.listDevicesCalls, 1)
        XCTAssertEqual(s.devices.map(\.id), ["ios1", "chrome"])
        XCTAssertFalse(s.isLoadingDevices)
    }

    func testOnErrorPassedToInitSeesAFailedRestore() throws {
        let h = SessionHarness()
        let store = h.makeStore()
        store.lastProjectPath = NSTemporaryDirectory()  // exists, but is not a Flutter project
        var errors: [String] = []
        let s = Session(store: store, dependencies: h.dependencies, hints: .gui, onError: { errors.append($0) })
        XCTAssertNil(s.project)
        XCTAssertEqual(errors.count, 1)
    }

    func testShutdownAfterARequestedStopStillWaitsForFlutter() async throws {
        let (s, _, d) = try await runningSession()
        d.exitsOnStop = false
        await s.stop()
        XCTAssertEqual(s.state, .stopping)
        await s.shutdown()
        XCTAssertEqual(d.stopCalls, 2, "shutdown must wait for (and escalate) the stop, not skip it")
    }

    // MARK: Watching outside lib/

    func testSaveInFolderOutsideLibHotReloadsAndNamesTheFile() async throws {
        let (s, h, d) = try await runningSession()
        let watcher = try XCTUnwrap(h.watchers.last)
        let project = watcher.scope.projectPath
        watcher.fire("\(project)/ui/widgets/button.dart")
        let reloaded = await waitUntil { d.restartCalls == [false] }
        XCTAssertTrue(reloaded)
        XCTAssertTrue(s.logs.contains { $0.text == "Change detected in ui/widgets/button.dart → hot reload" },
                      "\(s.logs.map(\.text))")
    }

    func testSavesOfTestsAreIgnored() async throws {
        let (_, h, d) = try await runningSession()
        let watcher = try XCTUnwrap(h.watchers.last)
        watcher.fire("\(watcher.scope.projectPath)/test/widget_test.dart")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(d.restartCalls, [])
    }

    func testBurstOfSavesIsOneReloadThatCountsTheFiles() async throws {
        let (s, h, d) = try await runningSession()
        let watcher = try XCTUnwrap(h.watchers.last)
        let p = watcher.scope.projectPath
        watcher.fire("\(p)/lib/a.dart", "\(p)/ui/b.dart")
        watcher.fire("\(p)/lib/a.dart")
        watcher.fire("\(p)/ui/c.dart")
        let reloaded = await waitUntil { d.restartCalls.count == 1 }
        XCTAssertTrue(reloaded)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(d.restartCalls, [false])
        XCTAssertTrue(s.logs.contains { $0.text == "Changes detected in lib/a.dart and 2 more files → hot reload" },
                      "\(s.logs.map(\.text))")
    }

    func testTwoSavesSaySingularMoreFile() async throws {
        let (s, h, d) = try await runningSession()
        let watcher = try XCTUnwrap(h.watchers.last)
        let p = watcher.scope.projectPath
        watcher.fire("\(p)/ui/a.dart", "\(p)/ui/b.dart")
        _ = await waitUntil { d.restartCalls.count == 1 }
        XCTAssertTrue(s.logs.contains { $0.text == "Changes detected in ui/a.dart and 1 more file → hot reload" },
                      "\(s.logs.map(\.text))")
    }

    func testUnnamedChangeStillReloads() async throws {
        let (s, h, d) = try await runningSession()
        h.watchers.last?.fire()
        _ = await waitUntil { d.restartCalls.count == 1 }
        XCTAssertTrue(s.logs.contains { $0.text == "Change detected → hot reload" }, "\(s.logs.map(\.text))")
    }

    func testNextReloadOnlyNamesNewChanges() async throws {
        let (s, h, d) = try await runningSession()
        let watcher = try XCTUnwrap(h.watchers.last)
        let p = watcher.scope.projectPath
        watcher.fire("\(p)/lib/a.dart")
        _ = await waitUntil { d.restartCalls.count == 1 && s.state == .running }
        watcher.fire("\(p)/ui/b.dart")
        let second = await waitUntil { d.restartCalls.count == 2 }
        XCTAssertTrue(second)
        XCTAssertTrue(s.logs.contains { $0.text == "Change detected in ui/b.dart → hot reload" }, "\(s.logs.map(\.text))")
    }

    func testLocalPackagesAreWatchedAndAnnounced() async throws {
        let h = SessionHarness()
        let path = try TestProject.make(name: "app")
        let parent = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: "\(parent)/shared_ui/lib", withIntermediateDirectories: true)
        try "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n  shared_ui:\n    path: ../shared_ui\n"
            .write(toFile: "\(path)/pubspec.yaml", atomically: true, encoding: .utf8)
        let s = h.makeSession()
        s.selectProject(path: path)
        await s.refreshDevices()
        await s.run()
        let d = try XCTUnwrap(h.lastDaemon)
        d.send(.appStarted)
        _ = await waitUntil { s.state == .running }
        let watcher = try XCTUnwrap(h.watchers.last)
        XCTAssertEqual(watcher.scope.localPackages, ["shared_ui"])
        XCTAssertTrue(s.logs.contains { $0.text == "Reload on save also watches local packages: shared_ui" }, "\(s.logs.map(\.text))")
        watcher.fire("\(parent)/shared_ui/lib/card.dart")
        let reloaded = await waitUntil { d.restartCalls == [false] }
        XCTAssertTrue(reloaded)
        XCTAssertTrue(s.logs.contains { $0.text == "Change detected in shared_ui/lib/card.dart → hot reload" }, "\(s.logs.map(\.text))")
    }

    func testPlainProjectDoesNotAnnounceLocalPackages() async throws {
        let (s, _, _) = try await runningSession()
        XCTAssertFalse(s.logs.contains { $0.text.contains("local packages") })
    }

    func testEachRunRereadsTheLocalPackages() async throws {
        let (s, h, d) = try await runningSession()
        let path = try XCTUnwrap(h.watchers.last).scope.projectPath
        XCTAssertEqual(h.watchers.last?.scope.localPackages, [])
        try FileManager.default.createDirectory(atPath: "\(path)/ui", withIntermediateDirectories: true)
        try "name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n  ui:\n    path: ui\n"
            .write(toFile: "\(path)/pubspec.yaml", atomically: true, encoding: .utf8)
        await s.stop()
        _ = await waitUntil { s.state == .idle }
        XCTAssertEqual(d.stopCalls, 1)
        await s.run()
        XCTAssertEqual(h.watchers.count, 2)
        XCTAssertEqual(h.watchers.last?.scope.localPackages, ["ui"])
    }
}
