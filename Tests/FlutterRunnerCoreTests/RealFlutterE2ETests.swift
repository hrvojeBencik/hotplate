import XCTest
@testable import FlutterRunnerCore

/// Runs a real `flutter run --machine` against a real project. Opt-in:
///   FLUTTER_RUNNER_E2E_PROJECT=/path/to/project FLUTTER_RUNNER_E2E_DEVICE=chrome swift test --filter RealFlutterE2ETests
final class RealFlutterE2ETests: XCTestCase {
    func testRealRunReloadStop() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let project = env["FLUTTER_RUNNER_E2E_PROJECT"], let device = env["FLUTTER_RUNNER_E2E_DEVICE"] else {
            throw XCTSkip("set FLUTTER_RUNNER_E2E_PROJECT and FLUTTER_RUNNER_E2E_DEVICE to run")
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
