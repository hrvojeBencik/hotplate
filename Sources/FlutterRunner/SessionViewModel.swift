import AppKit
import Foundation
import Observation
import FlutterRunnerCore

enum SessionState: Equatable {
    case idle, starting, running, reloading, restarting, stopping
    case failed(String)
}

enum LogKind { case normal, error, warning, info, success }

struct LogLine: Identifiable {
    let id: Int
    let text: String
    let kind: LogKind
}

/// The one session: selected project, device list, the running daemon and its logs.
@MainActor @Observable
final class SessionViewModel {
    static let shared = SessionViewModel(store: ProjectStore())

    let store: ProjectStore
    var state: SessionState = .idle
    var project: Project?
    var devices: [FlutterDevice] = []
    var selectedDeviceId: String? { didSet { persistProjectSettings() } }
    var extraArgs: String = "" { didSet { persistProjectSettings() } }
    var autoReload: Bool = true { didSet { persistProjectSettings() } }
    var logs: [LogLine] = []
    var isLoadingDevices = false
    var flutterPath: String?
    var followLogs = true
    var deviceError: String?

    private var daemon: FlutterDaemon?
    private var eventTask: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var debouncer: Debouncer?
    private var pendingReload = false
    private var nextLogId = 0
    private var suppressPersist = false
    private let maxLogLines = 5000

    init(store: ProjectStore) {
        self.store = store
        relocateFlutter()
        if let last = store.lastProjectPath, FileManager.default.fileExists(atPath: last) { selectProject(path: last) }
    }

    // MARK: Derived

    var isRunning: Bool {
        switch state {
        case .idle, .failed: return false
        default: return true
        }
    }
    var canRun: Bool { !isRunning && project != nil && selectedDeviceId != nil && flutterPath != nil }
    var canStop: Bool { isRunning && state != .stopping }
    var canReload: Bool { state == .running }
    var selectedDevice: FlutterDevice? { devices.first { $0.id == selectedDeviceId } }
    var statusText: String {
        switch state {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .reloading: return "Hot reloading…"
        case .restarting: return "Hot restarting…"
        case .stopping: return "Stopping…"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    // MARK: Flutter location

    func relocateFlutter() {
        flutterPath = FlutterLocator.locate(manualPath: store.manualFlutterPath)
        if let flutterPath { log("Using flutter at \(flutterPath)", .info) }
        else { log("flutter executable not found. Set the path in Settings (⌘,).", .error) }
    }

    // MARK: Projects

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a Flutter project folder (the one containing pubspec.yaml)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectProject(path: url.path)
    }

    func selectProject(path: String) {
        if isRunning { Task { await stop(); self.selectProject(path: path) }; return }
        do {
            var p = try Project.load(path: path)
            if let saved = store.recents.first(where: { $0.path == path }) {
                p.lastDeviceId = saved.lastDeviceId; p.extraArgs = saved.extraArgs; p.autoReload = saved.autoReload
            }
            suppressPersist = true
            project = p
            extraArgs = p.extraArgs
            autoReload = p.autoReload
            selectedDeviceId = p.lastDeviceId
            suppressPersist = false
            store.touch(p)
            log("Project: \(p.name) (\(p.path))", .info)
            Task { await refreshDevices() }
        } catch {
            log(error.localizedDescription, .error)
            NSSound.beep()
        }
    }

    func removeRecent(path: String) {
        store.remove(path: path)
        if project?.path == path { project = nil }
    }

    private func persistProjectSettings() {
        guard !suppressPersist, var p = project else { return }
        p.lastDeviceId = selectedDeviceId; p.extraArgs = extraArgs; p.autoReload = autoReload
        project = p
        store.update(p)
    }

    // MARK: Devices

    func refreshDevices() async {
        guard let flutterPath, !isLoadingDevices else { return }
        isLoadingDevices = true; deviceError = nil
        defer { isLoadingDevices = false }
        do {
            let service = DeviceService(flutterPath: flutterPath, environment: FlutterLocator.environment(flutterPath: flutterPath))
            let list = try await service.listDevices(projectPath: project?.path)
            devices = list
            if selectedDeviceId == nil || !list.contains(where: { $0.id == selectedDeviceId }) {
                selectedDeviceId = list.first?.id
            }
            if list.isEmpty { deviceError = "No devices found. Start a simulator or connect a device, then refresh." }
            log("Devices: \(list.isEmpty ? "none" : list.map(\.displayName).joined(separator: ", "))", .info)
        } catch {
            deviceError = error.localizedDescription
            log("Device list failed: \(error.localizedDescription)", .error)
        }
    }

    // MARK: Run / stop

    func run() async {
        guard canRun, let project, let deviceId = selectedDeviceId, let flutterPath else { return }
        clearLogs()
        state = .starting
        pendingReload = false
        let args = ArgumentSplitter.split(extraArgs)
        log("$ flutter run --machine -d \(deviceId) \(args.joined(separator: " "))", .info)
        let d = FlutterDaemon(flutterPath: flutterPath, projectPath: project.path, deviceId: deviceId, extraArgs: args,
                              environment: FlutterLocator.environment(flutterPath: flutterPath))
        daemon = d
        eventTask = Task { [weak self] in
            for await event in d.events { self?.handle(event) }
        }
        do { try d.start() } catch {
            state = .failed(error.localizedDescription)
            log(error.localizedDescription, .error)
            daemon = nil
            return
        }
        startWatcher(project: project)
    }

    func stop() async {
        guard let d = daemon, isRunning else { return }
        state = .stopping
        log("Stopping…", .info)
        await d.stop()
    }

    func hotReload() async { await restart(full: false) }
    func hotRestart() async { await restart(full: true) }

    private func restart(full: Bool) async {
        guard let d = daemon else { return }
        guard state == .running else {
            if state == .reloading || state == .restarting { pendingReload = true }
            return
        }
        state = full ? .restarting : .reloading
        let label = full ? "Hot restart" : "Hot reload"
        let started = Date()
        do {
            let r = try await d.restart(full: full)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if r.code == 0 { log("\(label) done in \(ms) ms. \(r.message)", .success) }
            else { log("\(label) failed: \(r.message)", .error) }
        } catch {
            log("\(label) error: \(error.localizedDescription)", .error)
        }
        if isRunning, state == (full ? .restarting : .reloading) { state = .running }
        if pendingReload, state == .running { pendingReload = false; await restart(full: false) }
    }

    // MARK: Watcher

    private func startWatcher(project: Project) {
        stopWatcher()
        let debouncer = Debouncer(interval: Double(store.debounceMs) / 1000.0) { [weak self] in
            Task { @MainActor in await self?.autoReloadFired() }
        }
        self.debouncer = debouncer
        let w = FileWatcher(path: project.libPath) { _ in debouncer.trigger() }
        w.start()
        watcher = w
    }

    private func stopWatcher() {
        watcher?.stop(); watcher = nil
        debouncer?.cancel(); debouncer = nil
    }

    private func autoReloadFired() async {
        guard autoReload else { return }
        switch state {
        case .running, .reloading, .restarting: break
        default: return
        }
        log("Change detected in lib/ → hot reload", .info)
        await hotReload()
    }

    // MARK: Events

    private func handle(_ event: DaemonEvent) {
        switch event {
        case .connected: break
        case .daemonLog(let level, let message):
            log(message, level == "error" ? .error : (level == "warning" ? .warning : .normal))
        case .appStarting(_, let deviceId, _):
            log("Launching on \(deviceId)…", .info)
        case .appStarted:
            state = .running
            log("App started. Auto reload is \(autoReload ? "on" : "off").", .success)
        case .progress(let message, let finished):
            if let message, !finished { log(message, .normal) }
        case .appLog(let text, let isError):
            log(text, isError ? .error : .normal)
        case .rawOutput(let text, let isStderr):
            log(text, isStderr ? .warning : .normal)
        case .webLaunchUrl(let url):
            log("Web app at \(url)", .info)
        case .appStopped:
            log("App stopped.", .info)
        case .processExited(let code):
            let requested = daemon?.wasStopRequested ?? false
            stopWatcher()
            daemon = nil; eventTask = nil
            if code == 0 || requested {
                state = .idle; log("flutter exited.", .info)
            } else {
                state = .failed("flutter exited with code \(code)"); log("flutter exited with code \(code)", .error)
            }
        }
    }

    // MARK: Logs

    func log(_ text: String, _ kind: LogKind = .normal) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            logs.append(LogLine(id: nextLogId, text: String(line), kind: kind)); nextLogId += 1
        }
        if logs.count > maxLogLines { logs.removeFirst(logs.count - maxLogLines) }
    }

    func clearLogs() { logs.removeAll() }

    /// Called on app quit: stops the daemon if needed.
    func shutdown() async {
        stopWatcher()
        await daemon?.stop()
    }
}
