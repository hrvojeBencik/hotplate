import XCTest
import HotplateCore
import HotplateTestSupport
@testable import HotplateTUI

@MainActor
final class TUIAppTests: XCTestCase {
    private final class Captured {
        var output = ""
        var copied: [String] = []
        var exitCodes: [Int32] = []
        var now = Date(timeIntervalSince1970: 1000)
    }

    private func makeApp(_ h: SessionHarness, savedDevice: String? = nil, overrides: SessionOverrides = SessionOverrides(),
                         size: TerminalSize = TerminalSize(width: 100, height: 30)) throws -> (TUIApp, Session, Captured) {
        let path = try TestProject.make()
        let store = h.makeStore()
        if let savedDevice { store.update(Project(path: path, name: "demo", lastDeviceId: savedDevice)) }
        let s = h.makeSession(store: store)
        s.overrides = overrides
        s.selectProject(path: path)
        let c = Captured()
        let app = TUIApp(session: s, size: size, output: { c.output += $0 }, copy: { c.copied.append($0) },
                         exit: { c.exitCodes.append($0) }, now: { c.now })
        return (app, s, c)
    }

    private func screen(_ app: TUIApp) -> String {
        let b = app.compose()
        return (0..<b.height).map { b.text(row: $0) }.joined(separator: "\n")
    }

    private func key(_ k: Key) -> InputEvent { .key(k) }

    func testStartRunsOnTheRememberedDevice() async throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h, savedDevice: "chrome")
        await app.start(autoRun: true)
        XCTAssertEqual(app.mode, .normal)
        XCTAssertEqual(h.lastDaemon?.config.deviceId, "chrome")
        XCTAssertEqual(s.state, .starting)
    }

    func testStartWithoutRememberedDeviceAsksThenRuns() async throws {
        let h = SessionHarness()
        let (app, _, _) = try makeApp(h)
        await app.start(autoRun: true)
        XCTAssertEqual(app.mode, .picker)
        XCTAssertEqual(app.picker?.kind, .device)
        XCTAssertTrue(h.daemons.isEmpty)
        app.handle(key(.down))
        app.handle(key(.enter))
        XCTAssertEqual(app.mode, .normal)
        let ran = await waitUntil { h.lastDaemon?.config.deviceId == "chrome" }
        XCTAssertTrue(ran)
    }

    func testAmbiguousDeviceQueryOpensAFilteredPicker() async throws {
        let h = SessionHarness(devices: [.fake("a", "iPhone 16"), .fake("b", "iPhone 15"), .fake("chrome", "Chrome")])
        let (app, _, _) = try makeApp(h, overrides: SessionOverrides(deviceQuery: "iphone"))
        await app.start(autoRun: true)
        XCTAssertEqual(app.picker?.filter, "iphone")
        XCTAssertEqual(app.picker?.filtered.count, 2)
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testNoRunLeavesTheAppIdle() async throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: false)
        XCTAssertEqual(s.state, .idle)
        XCTAssertTrue(screen(app).contains("⏎ run"))
        app.handle(key(.enter))
        let ran = await waitUntil { h.daemons.count == 1 }
        XCTAssertTrue(ran)
    }

    func testEnterOnASelectedLineOpensItsLink() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("Error at lib/missing.dart:3", .error)
        _ = app.compose()
        app.handle(key(.char("o")))
        XCTAssertNotNil(app.viewport.selectedLineId)
        app.handle(key(.enter))
        XCTAssertTrue(s.logs.contains { $0.text.contains("Can't find a file for lib/missing.dart") })
    }

    func testClickOnALinkOpensIt() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("Error at lib/missing.dart:3", .error)
        _ = app.compose()
        let target = try XCTUnwrap(s.logs.last?.id)
        let row = try XCTUnwrap(app.viewport.visibleRows.enumerated().first { $0.element.lineId == target }?.offset)
        app.handle(.mouse(MouseEvent(button: .left, x: LogViewport.gutter + 10, y: 2 + row, pressed: true)))
        XCTAssertEqual(app.viewport.selectedLineId, target)
        XCTAssertTrue(s.logs.contains { $0.text.contains("Can't find a file for lib/missing.dart") })
    }

    func testQuitStopsFlutterThenExitsWithZero() async throws {
        let h = SessionHarness()
        let (app, _, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.char("q")))
        let exited = await waitUntil { !c.exitCodes.isEmpty }
        XCTAssertTrue(exited)
        XCTAssertEqual(c.exitCodes.first, 0)
        XCTAssertEqual(h.lastDaemon?.stopCalls, 1)
    }

    func testSecondCtrlCWithinTwoSecondsKills() async throws {
        let h = SessionHarness()
        let (app, _, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.ctrl("c")))
        c.now = c.now.addingTimeInterval(1)
        app.handle(key(.ctrl("c")))
        XCTAssertEqual(c.exitCodes.first, 130)
        XCTAssertEqual(h.lastDaemon?.terminated, true)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(c.exitCodes, [130])
    }

    func testPasteInNormalModeTriggersNothing() async throws {
        let h = SessionHarness()
        let (app, s, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        h.lastDaemon?.send(.appStarted)
        _ = await waitUntil { s.state == .running }
        app.handle(.paste("rrq"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.lastDaemon?.restartCalls, [])
        XCTAssertTrue(c.exitCodes.isEmpty)
    }

    func testPasteIntoArgsReplacesNewlines() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        app.handle(key(.char("a")))
        XCTAssertEqual(app.mode, .input(.args))
        app.handle(key(.ctrl("u")))
        app.handle(.paste("--flavor\ndev"))
        app.handle(key(.enter))
        XCTAssertEqual(app.mode, .normal)
        XCTAssertEqual(s.extraArgs, "--flavor dev")
        XCTAssertNil(s.selectedLaunchConfigName)
    }

    func testSearchSelectsTheNewestMatch() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("needle one"); s.log("hay"); s.log("needle two")
        _ = app.compose()
        app.handle(key(.char("/")))
        for ch in "needle" { app.handle(key(.char(ch))) }
        app.handle(key(.enter))
        XCTAssertEqual(app.viewport.selectedLineId, s.logs.last?.id)
        app.handle(key(.char("N")))
        XCTAssertEqual(app.viewport.selectedLineId, s.logs[s.logs.count - 3].id)
    }

    func testCopyLineAndAll() throws {
        let h = SessionHarness()
        let (app, s, c) = try makeApp(h)
        s.log("Error at lib/a.dart:1", .error)
        _ = app.compose()
        app.handle(key(.char("o")))
        app.handle(key(.char("y")))
        XCTAssertEqual(c.copied.first, "Error at lib/a.dart:1")
        app.handle(key(.char("Y")))
        XCTAssertTrue(c.copied.last?.contains("Error at lib/a.dart:1") ?? false)
    }

    func testResizeBelowMinimumAndBackKeepsPicker() throws {
        let h = SessionHarness()
        let (app, _, _) = try makeApp(h)
        app.handle(key(.char("d")))
        app.resize(to: TerminalSize(width: 40, height: 10))
        XCTAssertTrue(screen(app).contains("Terminal too small (min 60×12)"))
        app.handle(key(.down))
        app.resize(to: TerminalSize(width: 100, height: 30))
        XCTAssertEqual(app.mode, .picker)
        XCTAssertTrue(screen(app).contains("Devices"))
    }

    func testFooterShowsStopWhileRunningAndHelpCloses() async throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        h.lastDaemon?.send(.appStarted)
        _ = await waitUntil { s.state == .running }
        XCTAssertTrue(screen(app).contains("s stop"))
        app.handle(key(.char("?")))
        XCTAssertEqual(app.mode, .help)
        XCTAssertTrue(screen(app).contains("Keyboard shortcuts"))
        app.handle(key(.char("x")))
        XCTAssertEqual(app.mode, .normal)
    }

    func testEscapeClosesPickerWithoutChoosing() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        app.handle(key(.char("c")))
        XCTAssertEqual(app.picker?.kind, .config)
        app.handle(key(.escape))
        XCTAssertEqual(app.mode, .normal)
        XCTAssertNil(app.picker)
        XCTAssertNil(s.selectedLaunchConfigName)
    }

    func testHelpScrollsAndClosesOnOtherKeys() throws {
        let h = SessionHarness()
        let (app, _, _) = try makeApp(h, size: TerminalSize(width: 60, height: 12))
        app.handle(key(.char("?")))
        XCTAssertEqual(app.mode, .help)
        let before = screen(app)
        app.handle(key(.down))
        XCTAssertEqual(app.mode, .help)
        XCTAssertNotEqual(screen(app), before)
        app.handle(key(.char("x")))
        XCTAssertEqual(app.mode, .normal)
    }

    func testStartupProjectPickerIsDrawnImmediately() async throws {
        let h = SessionHarness()
        let store = h.makeStore()
        store.touch(Project(path: try TestProject.make(), name: "demo"))
        let s = h.makeSession(store: store)
        let c = Captured()
        let app = TUIApp(session: s, size: TerminalSize(width: 100, height: 30), output: { c.output += $0 },
                         copy: { _ in }, exit: { _ in }, now: { c.now })
        await app.start(autoRun: true)
        XCTAssertEqual(app.mode, .picker)
        XCTAssertTrue(c.output.contains("Recent projects"))
    }

    func testPasteWithCarriageReturnBecomesSpace() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        app.handle(key(.char("a")))
        app.handle(key(.ctrl("u")))
        app.handle(.paste("--flavor\rdev"))
        app.handle(key(.enter))
        XCTAssertEqual(s.extraArgs, "--flavor dev")
    }

    func testClosingDevicePickerWithoutChoosingDoesNotLeakRunIntent() async throws {
        let h = SessionHarness()
        let (app, _, _) = try makeApp(h)
        await app.start(autoRun: true)
        XCTAssertEqual(app.picker?.kind, .device)
        for ch in "zzz" { app.handle(key(.char(ch))) }
        app.handle(key(.enter))
        XCTAssertEqual(app.mode, .normal)
        app.handle(key(.char("d")))
        app.handle(key(.enter))
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testPressingQTwiceDoesNotForceKill() async throws {
        let h = SessionHarness()
        let (app, _, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.char("q")))
        c.now = c.now.addingTimeInterval(1)
        app.handle(key(.char("q")))
        let exited = await waitUntil { !c.exitCodes.isEmpty }
        XCTAssertTrue(exited)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(c.exitCodes, [0])
        XCTAssertNotEqual(h.lastDaemon?.terminated, true)
    }

    func testMouseIgnoredBelowMinimumSize() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("Error at lib/missing.dart:3", .error)
        _ = app.compose()
        app.resize(to: TerminalSize(width: 40, height: 10))
        app.handle(.mouse(MouseEvent(button: .left, x: LogViewport.gutter + 10, y: 2, pressed: true)))
        XCTAssertNil(app.viewport.selectedLineId)
    }

    func testMissingFlutterShowsTheHintInsteadOfTheDevicePicker() async throws {
        let h = SessionHarness()
        h.flutterPath = nil
        let (app, _, _) = try makeApp(h)
        await app.start(autoRun: true)
        XCTAssertEqual(app.mode, .normal)
        XCTAssertTrue(screen(app).contains("flutter not found"))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testQuittingShowsStoppingAndIgnoresKeys() async throws {
        let h = SessionHarness()
        let (app, s, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.char("q")))
        let exited = await waitUntil { !c.exitCodes.isEmpty }
        XCTAssertTrue(exited)
        XCTAssertTrue(s.logs.contains { $0.text == "Stopping…" })
        app.handle(key(.enter))
        app.handle(key(.char("d")))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(h.daemons.count, 1)
        XCTAssertEqual(app.mode, .normal)
    }

    func testCtrlCStillForcesWhileQuitting() async throws {
        let h = SessionHarness()
        let (app, _, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.char("q")))
        app.handle(key(.ctrl("c")))
        c.now = c.now.addingTimeInterval(1)
        app.handle(key(.ctrl("c")))
        XCTAssertTrue(c.exitCodes.contains(130))
    }

    func testHangupAndEndOfInputQuitGracefully() {
        XCTAssertFalse(TerminalLoop.countsAsInterrupt(signal: SIGHUP))
        XCTAssertTrue(TerminalLoop.countsAsInterrupt(signal: SIGINT))
        XCTAssertTrue(TerminalLoop.countsAsInterrupt(signal: SIGTERM))
    }
}
