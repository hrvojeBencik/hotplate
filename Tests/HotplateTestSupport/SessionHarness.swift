import Foundation
import HotplateCore

public final class FakeDaemon: SessionDaemon, @unchecked Sendable {
    public let config: DaemonConfig
    public let events: AsyncStream<DaemonEvent>
    private let continuation: AsyncStream<DaemonEvent>.Continuation
    public private(set) var started = false
    public private(set) var stopCalls = 0
    public private(set) var terminated = false
    public private(set) var restartCalls: [Bool] = []
    /// How long each restart takes, in nanoseconds.
    public var restartDelay: UInt64 = 0
    public var wasStopRequested = false

    public init(config: DaemonConfig) {
        self.config = config
        var c: AsyncStream<DaemonEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        continuation = c
    }

    public func start() throws { started = true }

    public func stop() async {
        stopCalls += 1
        wasStopRequested = true
        continuation.yield(.processExited(code: 0))
        continuation.finish()
    }

    public func terminate() {
        terminated = true
        wasStopRequested = true
        continuation.yield(.processExited(code: 143))
        continuation.finish()
    }

    public func restart(full: Bool) async throws -> RestartResult {
        restartCalls.append(full)
        if restartDelay > 0 { try await Task.sleep(nanoseconds: restartDelay) }
        return RestartResult(code: 0, message: "")
    }

    public func send(_ event: DaemonEvent) { continuation.yield(event) }
}

public final class FakeWatcher: SessionWatcher, @unchecked Sendable {
    public let path: String
    private let onChange: () -> Void
    public private(set) var stopped = false

    public init(path: String, onChange: @escaping () -> Void) { self.path = path; self.onChange = onChange }
    public func stop() { stopped = true }
    /// Simulates a saved `.dart` file.
    public func fire() { onChange() }
}

/// Builds a `Session` wired to fakes, with its own throwaway UserDefaults suite.
public final class SessionHarness: @unchecked Sendable {
    public var devices: [FlutterDevice]
    public var flutterPath: String? = "/fake/flutter"
    public private(set) var daemons: [FakeDaemon] = []
    public private(set) var watchers: [FakeWatcher] = []
    public let suiteName = "hotplate.tests.\(UUID().uuidString)"
    public var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    public private(set) var listDevicesCalls = 0
    /// How long each device listing takes, in nanoseconds.
    public var listDevicesDelay: UInt64 = 0
    public var lastDaemon: FakeDaemon? { daemons.last }

    public init(devices: [FlutterDevice] = [.fake("ios1", "iPhone 16 Pro"), .fake("chrome", "Chrome", platform: "web-javascript")]) {
        self.devices = devices
    }

    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    public var dependencies: SessionDependencies {
        SessionDependencies(
            locateFlutter: { [weak self] _ in self?.flutterPath },
            environment: { _ in ["PATH": "/usr/bin:/bin"] },
            listDevices: { [weak self] _, _, _ in
                guard let self else { return [] }
                self.listDevicesCalls += 1
                let delay = self.listDevicesDelay
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                return self.devices
            },
            makeDaemon: { [weak self] config in
                let d = FakeDaemon(config: config); self?.daemons.append(d); return d
            },
            startWatcher: { [weak self] path, onChange in
                let w = FakeWatcher(path: path, onChange: onChange); self?.watchers.append(w); return w
            })
    }

    @MainActor public func makeStore() -> ProjectStore {
        let store = ProjectStore(defaults: defaults)
        store.debounceMs = 20
        return store
    }

    @MainActor public func makeSession(store: ProjectStore? = nil, hints: SessionHints = .terminal) -> Session {
        Session(store: store ?? makeStore(), dependencies: dependencies, hints: hints, restoreLastProject: false)
    }
}

public enum TestProject {
    /// Creates a minimal Flutter project in a temp folder and returns its (symlink-resolved) path.
    public static func make(name: String = "demo", launchJSON: String? = nil) throws -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hotplate-\(UUID().uuidString)")
            .appendingPathComponent(name)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "name: \(name)\ndependencies:\n  flutter:\n    sdk: flutter\n"
            .write(to: root.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try "void main() {}\n".write(to: root.appendingPathComponent("lib/main.dart"), atomically: true, encoding: .utf8)
        if let launchJSON {
            try fm.createDirectory(at: root.appendingPathComponent(".vscode"), withIntermediateDirectories: true)
            try launchJSON.write(to: root.appendingPathComponent(".vscode/launch.json"), atomically: true, encoding: .utf8)
        }
        return root.resolvingSymlinksInPath().path
    }

    /// Dev is pinned to the device `chrome`; Prod has no device.
    public static let deviceLaunchJSON = """
    {
      "configurations": [
        { "name": "Dev", "request": "launch", "type": "dart", "deviceId": "chrome", "args": ["--flavor", "dev"] },
        { "name": "Prod", "request": "launch", "type": "dart", "args": ["--flavor", "prod"] }
      ]
    }
    """

    public static let devAndProdLaunchJSON = """
    {
      "configurations": [
        { "name": "Dev", "request": "launch", "type": "dart", "args": ["--flavor", "dev"] },
        { "name": "Prod", "request": "launch", "type": "dart", "args": ["--flavor", "prod"] }
      ]
    }
    """
}

public extension FlutterDevice {
    static func fake(_ id: String, _ name: String, platform: String = "ios") -> FlutterDevice {
        FlutterDevice(id: id, name: name, targetPlatform: platform, emulator: true, isSupported: true)
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
public func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
}
