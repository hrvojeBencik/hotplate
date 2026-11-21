import XCTest
@testable import HotplateCore
import HotplateTestSupport

/// Runs a real `flutter run --machine` against a real project. Opt-in:
///   HOTPLATE_E2E_PROJECT=/path/to/project HOTPLATE_E2E_DEVICE=chrome swift test --filter RealFlutterE2ETests
final class RealFlutterE2ETests: XCTestCase {
    func testRealRunReloadStop() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let project = env["HOTPLATE_E2E_PROJECT"], let device = env["HOTPLATE_E2E_DEVICE"] else {
            throw XCTSkip("set HOTPLATE_E2E_PROJECT and HOTPLATE_E2E_DEVICE to run")
        }
        guard let flutter = FlutterLocator.locate(manualPath: nil) else { throw XCTSkip("flutter not found") }
        let environment = FlutterLocator.environment(flutterPath: flutter)

        let devices = try await DeviceService(flutterPath: flutter, environment: environment).listDevices(projectPath: project)
        XCTAssertTrue(devices.contains { $0.id == device }, "device \(device) not in \(devices.map(\.id))")

        let daemon = FlutterDaemon(flutterPath: flutter, projectPath: project, deviceId: device, extraArgs: [], environment: environment)
        let log = SeenLog()
        let collector = Task { for await e in daemon.events { log.add(e) } }
        try daemon.start()
        for _ in 0..<1200 where !log.started { try await Task.sleep(nanoseconds: 250_000_000) }  // up to 5 min
        XCTAssertTrue(log.started, "app never started. Log:\n\(log.dump())")

        let r1 = try await daemon.restart(full: false)
        XCTAssertEqual(r1.code, 0, "reload: \(r1.message)")
        let r2 = try await daemon.restart(full: true)
        XCTAssertEqual(r2.code, 0, "restart: \(r2.message)")

        await daemon.stop()
        await collector.value
        XCTAssertFalse(daemon.isRunning)
        XCTAssertTrue(log.exited, "no processExited. Log:\n\(log.dump())")
        print("E2E OK. reload='\(r1.message)' restart='\(r2.message)'\n\(log.dump())")
    }

    /// Hot reload on save through the live `Session` and `FileWatcher`, for files outside `lib/`: a `ui/` package
    /// inside the project and a `shared/` package outside it, both `path:` dependencies (a relative import can't leave
    /// `lib/`). Creates its own project. Opt-in:
    ///   HOTPLATE_E2E_DEVICE=chrome swift test --filter RealFlutterE2ETests/testSavesOutsideLibHotReload
    @MainActor
    func testSavesOutsideLibHotReload() async throws {
        guard let device = ProcessInfo.processInfo.environment["HOTPLATE_E2E_DEVICE"] else {
            throw XCTSkip("set HOTPLATE_E2E_DEVICE to run")
        }
        guard let flutter = FlutterLocator.locate(manualPath: nil) else { throw XCTSkip("flutter not found") }
        let environment = FlutterLocator.environment(flutterPath: flutter)
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hotplate-e2e-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let app = base.appendingPathComponent("app").path, shared = base.appendingPathComponent("shared").path

        try runTool(flutter, ["create", "--offline", "--empty", "--platforms=web,macos", "--project-name", "probe_app", app], env: environment)
        try write("\(shared)/pubspec.yaml", "name: shared\nenvironment:\n  sdk: ^3.0.0\n")
        try write("\(shared)/lib/shared.dart", "String sharedWord() => 'alpha';\n")
        try write("\(app)/ui/pubspec.yaml", "name: ui\nenvironment:\n  sdk: ^3.0.0\n")
        try write("\(app)/ui/lib/greeting.dart", "String greeting() => 'hello';\n")
        let pubspec = try String(contentsOfFile: "\(app)/pubspec.yaml", encoding: .utf8)
        try write("\(app)/pubspec.yaml", pubspec.replacingOccurrences(of: "dependencies:\n  flutter:\n    sdk: flutter\n",
            with: "dependencies:\n  flutter:\n    sdk: flutter\n  ui:\n    path: ui\n  shared:\n    path: ../shared\n"))
        try write("\(app)/lib/main.dart", """
            import 'package:flutter/material.dart';
            import 'package:shared/shared.dart';
            import 'package:ui/greeting.dart';

            void main() => runApp(const ProbeApp());

            class ProbeApp extends StatelessWidget {
              const ProbeApp({super.key});
              @override
              Widget build(BuildContext context) {
                debugPrint('PROBE ${greeting()} ${sharedWord()}');
                return MaterialApp(home: Text('${greeting()} ${sharedWord()}'));
              }
            }

            """)
        try runTool(flutter, ["pub", "get", "--offline"], env: environment, cwd: app)

        let suite = "hotplate.e2e.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let store = ProjectStore(defaults: UserDefaults(suiteName: suite)!)
        store.debounceMs = 100
        let session = Session(store: store, hints: .terminal, restoreLastProject: false)
        session.selectProject(path: app)
        await session.refreshDevices()
        session.selectedDeviceId = device
        await session.run()
        func logged(_ text: String) -> Bool { session.logs.contains { $0.text.contains(text) } }
        func dump() -> String { session.logs.map(\.text).joined(separator: "\n") }

        func failed() -> Bool { if case .failed = session.state { return true }; return session.state == .idle }
        let started = await waitUntil(timeout: 300) { logged("PROBE hello alpha") || failed() }
        guard logged("PROBE hello alpha") else { return XCTFail("app never printed its first frame. Log:\n\(dump())") }
        XCTAssertTrue(started)
        XCTAssertTrue(logged("Reload on save also watches local packages: ui, shared"), dump())

        try write("\(app)/ui/lib/greeting.dart", "String greeting() => 'bonjour';\n")
        let uiReloaded = await waitUntil(timeout: 60) { logged("PROBE bonjour alpha") || failed() }
        XCTAssertTrue(uiReloaded && !failed(), "saving ui/lib/greeting.dart did not reload. Log:\n\(dump())")
        XCTAssertTrue(logged("Change detected in ui/lib/greeting.dart → hot reload"), dump())

        try write("\(shared)/lib/shared.dart", "String sharedWord() => 'beta';\n")
        let packageReloaded = await waitUntil(timeout: 60) { logged("PROBE bonjour beta") || failed() }
        XCTAssertTrue(packageReloaded && !failed(), "saving the local package did not reload. Log:\n\(dump())")
        XCTAssertTrue(logged("Change detected in shared/lib/shared.dart → hot reload"), dump())

        let reloadsBefore = session.logs.filter { $0.text.contains("→ hot reload") }.count
        try write("\(app)/test/probe_test.dart", "void main() {}\n")
        try write("\(app)/ui/test/greeting_test.dart", "void main() {}\n")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(session.logs.filter { $0.text.contains("→ hot reload") }.count, reloadsBefore, "a test file reloaded")

        await session.stop()
        let stopped = await waitUntil(timeout: 60) { session.state == .idle }
        XCTAssertTrue(stopped, dump())
        print("E2E outside-lib log:\n\(dump())")
    }

    private func write(_ path: String, _ content: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func runTool(_ tool: String, _ args: [String], env: [String: String], cwd: String? = nil) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = env
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            XCTFail("\(tool) \(args.joined(separator: " ")) exited \(p.terminationStatus):\n\(String(decoding: data, as: UTF8.self))")
            throw XCTSkip("setup failed")
        }
    }
}

private final class SeenLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private(set) var started = false
    private(set) var exited = false
    func add(_ e: DaemonEvent) {
        lock.lock(); defer { lock.unlock() }
        switch e {
        case .appStarted: started = true; lines.append("appStarted")
        case .processExited(let c): exited = true; lines.append("exit \(c)")
        case .appLog(let s, _): lines.append("log: \(s)")
        case .rawOutput(let s, let err): lines.append("\(err ? "stderr" : "raw"): \(s)")
        case .progress(let m, let f): lines.append("progress(\(f)): \(m ?? "")")
        case .daemonLog(let l, let m): lines.append("daemon[\(l)]: \(m)")
        default: lines.append("\(e)")
        }
    }
    func dump() -> String { lock.lock(); defer { lock.unlock() }; return lines.joined(separator: "\n") }
}
