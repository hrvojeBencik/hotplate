import Foundation

public struct DaemonConfig: Equatable, Sendable {
    public let flutterPath: String
    public let projectPath: String
    public let deviceId: String
    public let extraArgs: [String]
    public let environment: [String: String]

    public init(flutterPath: String, projectPath: String, deviceId: String, extraArgs: [String], environment: [String: String]) {
        self.flutterPath = flutterPath; self.projectPath = projectPath; self.deviceId = deviceId
        self.extraArgs = extraArgs; self.environment = environment
    }
}

/// What `Session` needs from a running `flutter run --machine`; `FlutterDaemon` in production, a fake in tests.
public protocol SessionDaemon: AnyObject {
    var events: AsyncStream<DaemonEvent> { get }
    var wasStopRequested: Bool { get }
    func start() throws
    func stop() async
    func terminate()
    func restart(full: Bool) async throws -> RestartResult
}

extension FlutterDaemon: SessionDaemon {}

public protocol SessionWatcher: AnyObject {
    func stop()
}

extension FileWatcher: SessionWatcher {}

/// Everything `Session` does to the outside world, injectable for tests.
public struct SessionDependencies {
    public var locateFlutter: (_ manualPath: String?) -> String?
    public var environment: (_ flutterPath: String) -> [String: String]
    public var listDevices: (_ flutterPath: String, _ environment: [String: String], _ projectPath: String?) async throws -> [FlutterDevice]
    public var makeDaemon: (DaemonConfig) -> SessionDaemon
    /// Starts watching `path` for `.dart` changes and returns the running watcher.
    public var startWatcher: (_ path: String, _ onChange: @escaping () -> Void) -> SessionWatcher

    public init(locateFlutter: @escaping (String?) -> String?,
                environment: @escaping (String) -> [String: String],
                listDevices: @escaping (String, [String: String], String?) async throws -> [FlutterDevice],
                makeDaemon: @escaping (DaemonConfig) -> SessionDaemon,
                startWatcher: @escaping (String, @escaping () -> Void) -> SessionWatcher) {
        self.locateFlutter = locateFlutter; self.environment = environment; self.listDevices = listDevices
        self.makeDaemon = makeDaemon; self.startWatcher = startWatcher
    }

    public static var live: SessionDependencies {
        SessionDependencies(
            locateFlutter: { FlutterLocator.locate(manualPath: $0) },
            environment: { FlutterLocator.environment(flutterPath: $0) },
            listDevices: { flutter, env, project in
                try await DeviceService(flutterPath: flutter, environment: env).listDevices(projectPath: project)
            },
            makeDaemon: { c in
                FlutterDaemon(flutterPath: c.flutterPath, projectPath: c.projectPath, deviceId: c.deviceId,
                              extraArgs: c.extraArgs, environment: c.environment)
            },
            startWatcher: { path, onChange in
                let w = FileWatcher(path: path) { _ in onChange() }
                w.start()
                return w
            })
    }
}
