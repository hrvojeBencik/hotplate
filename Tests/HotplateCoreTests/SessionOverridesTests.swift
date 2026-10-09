import XCTest
@testable import HotplateCore
import HotplateTestSupport

@MainActor
final class SessionOverridesTests: XCTestCase {
    private let threeDevices: [FlutterDevice] = [.fake("ios1", "iPhone 16 Pro"), .fake("chrome", "Chrome", platform: "web-javascript"),
                                                 .fake("macos", "macOS", platform: "darwin")]

    /// A project whose saved settings are: device macos, config Prod, auto reload on.
    private func savedProject(_ h: SessionHarness) throws -> (String, ProjectStore) {
        let path = try TestProject.make(launchJSON: TestProject.devAndProdLaunchJSON)
        let store = h.makeStore()
        store.update(Project(path: path, name: "demo", lastDeviceId: "macos", extraArgs: "--flavor prod", autoReload: true,
                             launchConfigName: "Prod"))
        return (path, store)
    }

    private func saved(_ h: SessionHarness, _ path: String) -> Project? { h.makeStore().recents.first { $0.path == path } }

    func testCommandLineOverridesApplyButAreNotSaved() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "chrome", configName: "Dev", autoReload: false)
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: false)
        XCTAssertEqual(outcome, .idle)
        XCTAssertEqual(s.selectedDeviceId, "chrome")
        XCTAssertEqual(s.selectedLaunchConfigName, "Dev")
        XCTAssertEqual(s.extraArgs, "--flavor dev")
        XCTAssertFalse(s.autoReload)
        let p = try XCTUnwrap(saved(h, path))
        XCTAssertEqual(p.lastDeviceId, "macos")
        XCTAssertEqual(p.launchConfigName, "Prod")
        XCTAssertEqual(p.extraArgs, "--flavor prod")
        XCTAssertTrue(p.autoReload)
    }

    func testChoosingInTheTUIClearsThatOverrideAndSaves() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "chrome", configName: "Dev", autoReload: false)
        s.selectProject(path: path)
        _ = await s.startup(autoRun: false)

        s.chooseDevice(id: "ios1")
        XCTAssertNil(s.overrides.deviceQuery)
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "ios1")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod", "config is still overridden")

        s.setArgs("--verbose")
        XCTAssertNil(s.overrides.configName)
        XCTAssertEqual(saved(h, path)?.extraArgs, "--verbose")
        XCTAssertNil(saved(h, path)?.launchConfigName)

        s.setAutoReload(false)
        XCTAssertEqual(saved(h, path)?.autoReload, false)
    }

    func testChooseLaunchConfigSavesIt() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(args: "--flavor qa")
        s.selectProject(path: path)
        XCTAssertNil(s.selectedLaunchConfigName)
        XCTAssertEqual(s.extraArgs, "--flavor qa")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod")
        s.chooseLaunchConfig(name: "Dev")
        XCTAssertEqual(s.extraArgs, "--flavor dev")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Dev")
        XCTAssertNil(s.overrides.args)
    }

    func testArgsOverrideMeansCustomWithoutSaving() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(args: "--flavor dev --dart-define=X=1")
        s.selectProject(path: path)
        XCTAssertNil(s.selectedLaunchConfigName)
        XCTAssertEqual(s.extraArgs, "--flavor dev --dart-define=X=1")
        XCTAssertEqual(saved(h, path)?.extraArgs, "--flavor prod")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod")
    }

    func testUnknownConfigOverrideWarnsAndKeepsSaved() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(configName: "Staging")
        s.selectProject(path: path)
        XCTAssertEqual(s.selectedLaunchConfigName, "Prod")
        XCTAssertNil(s.overrides.configName)
        XCTAssertTrue(s.logs.contains { $0.kind == .warning && $0.text.contains("\"Staging\" not found") })
    }

    func testSwitchProjectClearsOverrides() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let other = try TestProject.make(name: "other")
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "chrome", args: "--x", autoReload: false)
        s.selectProject(path: path)
        s.switchProject(path: other)
        XCTAssertEqual(s.overrides, SessionOverrides())
        XCTAssertEqual(s.project?.path, other)
        XCTAssertTrue(s.autoReload)
    }

    func testStartupRunsOnRememberedDevice() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .started)
        XCTAssertEqual(h.lastDaemon?.config.deviceId, "macos")
        XCTAssertEqual(h.lastDaemon?.config.extraArgs, ["--flavor", "prod"])
    }

    func testStartupAsksForDeviceWhenNoneRemembered() async throws {
        let h = SessionHarness(devices: threeDevices)
        let s = h.makeSession()
        s.selectProject(path: try TestProject.make())
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .needsDevice(filter: ""))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testStartupAsksWhenRememberedDeviceIsGone() async throws {
        let h = SessionHarness(devices: [.fake("ios1", "iPhone 16 Pro")])
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .needsDevice(filter: ""))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testAmbiguousDeviceQueryAsksWithFilter() async throws {
        let h = SessionHarness(devices: [.fake("a", "iPhone 16"), .fake("b", "iPhone 15")])
        let s = h.makeSession()
        s.overrides = SessionOverrides(deviceQuery: "iphone")
        s.selectProject(path: try TestProject.make())
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .needsDevice(filter: "iphone"))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testStartupWithoutProjectIsIdle() async {
        let h = SessionHarness()
        let s = h.makeSession()
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .idle)
    }

    // MARK: Memory rule: command-line options are never saved

    private func deviceProject(_ h: SessionHarness, savedDevice: String?, config: String? = "Prod") throws -> (String, ProjectStore) {
        let path = try TestProject.make(launchJSON: TestProject.deviceLaunchJSON)
        let store = h.makeStore()
        store.update(Project(path: path, name: "demo", lastDeviceId: savedDevice, extraArgs: "--flavor prod", autoReload: true,
                             launchConfigName: config))
        return (path, store)
    }

    func testConfigOverrideDeviceIsNotSavedEvenAfterRun() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try deviceProject(h, savedDevice: "macos")
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(configName: "Dev")
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .started)
        XCTAssertEqual(h.lastDaemon?.config.deviceId, "chrome")
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "macos")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod")
        s.chooseDevice(id: "ios1")
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "ios1")
    }

    func testDeviceOverrideBeatsConfigDevice() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try deviceProject(h, savedDevice: "macos", config: "Dev")
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "ios1")
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .started)
        XCTAssertEqual(h.lastDaemon?.config.deviceId, "ios1")
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "macos")
    }

    func testFallbackDeviceIsNotRemembered() async throws {
        let h = SessionHarness(devices: threeDevices)
        let path = try TestProject.make()
        let store = h.makeStore()
        let s = h.makeSession(store: store)
        s.selectProject(path: path)
        let first = await s.startup(autoRun: true)
        XCTAssertEqual(first, .needsDevice(filter: ""))
        XCTAssertNil(saved(h, path)?.lastDeviceId)

        let s2 = h.makeSession(store: h.makeStore())
        s2.selectProject(path: path)
        let second = await s2.startup(autoRun: true)
        XCTAssertEqual(second, .needsDevice(filter: ""))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testGoneDeviceStaysSavedAfterStartup() async throws {
        let h = SessionHarness(devices: [.fake("ios1", "iPhone 16 Pro")])
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.selectProject(path: path)
        _ = await s.startup(autoRun: true)
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "macos")
    }

    func testFallbackDeviceIsNotSavedByOtherSettingChanges() async throws {
        let h = SessionHarness(devices: threeDevices)
        let path = try TestProject.make()
        let s = h.makeSession(store: h.makeStore())
        s.selectProject(path: path)
        let first = await s.startup(autoRun: true)
        XCTAssertEqual(first, .needsDevice(filter: ""))
        s.setAutoReload(false)
        s.setArgs("--x")
        XCTAssertNil(saved(h, path)?.lastDeviceId)

        let s2 = h.makeSession(store: h.makeStore())
        s2.selectProject(path: path)
        let second = await s2.startup(autoRun: true)
        XCTAssertEqual(second, .needsDevice(filter: ""))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testRunningOnTheFallbackRemembersIt() async throws {
        let h = SessionHarness(devices: threeDevices)
        let path = try TestProject.make()
        let s = h.makeSession(store: h.makeStore())
        s.selectProject(path: path)
        _ = await s.startup(autoRun: true)
        let fallback = try XCTUnwrap(s.selectedDeviceId)
        await s.run()
        XCTAssertEqual(saved(h, path)?.lastDeviceId, fallback)
    }

    func testChoosingTheOverriddenConfigInTheTUISavesItsDevice() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try deviceProject(h, savedDevice: "macos")
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(configName: "Dev")
        s.selectProject(path: path)
        _ = await s.startup(autoRun: false)
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "macos")
        s.chooseLaunchConfig(name: "Dev")
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "chrome")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Dev")
    }
}
