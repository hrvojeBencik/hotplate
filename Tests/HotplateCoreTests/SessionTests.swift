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
        XCTAssertEqual(h.watchers.last?.path, "\(path)/lib")
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
}
