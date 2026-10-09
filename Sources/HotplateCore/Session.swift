import Foundation
import Observation

/// The one run session: selected project, device list, the running daemon and its logs.
/// Shared by the macOS app and the terminal UI; holds no UI code.
@MainActor @Observable
public final class Session {
    public let store: ProjectStore
    public let hints: SessionHints
    public var state: SessionState = .idle
    public var project: Project?
    public var devices: [FlutterDevice] = []
    public var selectedDeviceId: String? { didSet { persistProjectSettings() } }
    public var extraArgs: String = "" {
        didSet {
            // A manual edit of the args field means "custom", unless we are applying a config ourselves.
            if !applyingLaunchConfig, !suppressPersist, oldValue != extraArgs, selectedLaunchConfigName != nil {
                selectedLaunchConfigName = nil
            }
            persistProjectSettings()
        }
    }
    public var launchConfigs: [LaunchConfig] = []
    public var selectedLaunchConfigName: String? { didSet { persistProjectSettings() } }
    public var autoReload: Bool = true { didSet { persistProjectSettings() } }
    public var logs: [LogLine] = []
    public var isLoadingDevices = false
    public var flutterPath: String?
    public var followLogs = true
    public var deviceError: String?
    public var installedEditors: [InstalledEditor] = EditorLauncher.detectInstalled()
    /// Called when the user should notice a failure (the app beeps).
    @ObservationIgnored public var onError: ((String) -> Void)?
    /// Command-line choices for this session only; `persistProjectSettings` never writes them.
    public var overrides = SessionOverrides()
    /// The saved device when the project was opened. The device refresh may pick and save a fallback,
    /// so `startup` must not read `project.lastDeviceId` to decide whether the device was remembered.
    @ObservationIgnored private var deviceAtOpen: String?
    /// Where the selected device came from; only a `remembered` device is written to `lastDeviceId`.
    private enum DeviceOrigin {
        case remembered        // the saved device, a TUI/GUI choice, or a config device with no override
        case fallback          // the first device, suggested when nothing usable was saved; saved once the user runs on it
        case overriddenConfig  // a device pinned by a launch config that is overridden for this session only
    }
    @ObservationIgnored private var deviceOrigin = DeviceOrigin.remembered

    @ObservationIgnored private let deps: SessionDependencies
    @ObservationIgnored private let flutterPathOverride: String?
    private var daemon: SessionDaemon?
    private var eventTask: Task<Void, Never>?
    private var watcher: SessionWatcher?
    private var debouncer: Debouncer?
    private var deviceRefreshTask: Task<Void, Never>?
    private var pendingReload = false
    private var nextLogId = 0
    private var suppressPersist = false
    private var applyingLaunchConfig = false
    private let maxLogLines = 5000

    public init(store: ProjectStore, dependencies: SessionDependencies = .live, hints: SessionHints = .gui,
                flutterPathOverride: String? = nil, restoreLastProject: Bool = true) {
        self.store = store
        self.deps = dependencies
        self.hints = hints
        self.flutterPathOverride = flutterPathOverride
        relocateFlutter()
        if restoreLastProject, let last = store.lastProjectPath, FileManager.default.fileExists(atPath: last) {
            selectProject(path: last)
        }
    }

    // MARK: Derived

    public var isRunning: Bool {
        switch state {
        case .idle, .failed: return false
        default: return true
        }
    }
    public var canRun: Bool { !isRunning && project != nil && selectedDeviceId != nil && flutterPath != nil }
    public var canStop: Bool { isRunning && state != .stopping }
    public var canReload: Bool { state == .running }
    public var selectedDevice: FlutterDevice? { devices.first { $0.id == selectedDeviceId } }
    public var statusText: String {
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

    public func relocateFlutter() {
        flutterPath = deps.locateFlutter(flutterPathOverride ?? store.manualFlutterPath)
        if let flutterPath {
            log("Using flutter at \(flutterPath)", .info)
            let path = deps.environment(flutterPath)["PATH"] ?? ""
            if let pod = FlutterLocator.find(tool: "pod", inPath: path) { log("CocoaPods: \(pod)", .info) }
            else { log("CocoaPods (pod) not found on PATH; iOS/macOS builds with plugins will fail.", .warning) }
        } else {
            log("flutter executable not found. \(hints.flutter)", .error)
        }
    }

    // MARK: Projects

    public func selectProject(path: String) {
        if isRunning { Task { await stop(); self.selectProject(path: path) }; return }
        do {
            var p = try Project.load(path: path)
            if let saved = store.recents.first(where: { $0.path == path }) {
                p.lastDeviceId = saved.lastDeviceId; p.extraArgs = saved.extraArgs; p.autoReload = saved.autoReload
                p.launchConfigName = saved.launchConfigName
            }
            launchConfigs = LaunchConfigReader.load(projectPath: path)
            suppressPersist = true
            project = p
            extraArgs = p.extraArgs
            autoReload = p.autoReload
            selectedDeviceId = p.lastDeviceId
            selectedLaunchConfigName = p.launchConfigName
            suppressPersist = false
            store.touch(p)
            log("Project: \(p.name) (\(p.path))", .info)
            if !launchConfigs.isEmpty {
                log("launch.json: \(launchConfigs.map(\.name).joined(separator: ", "))", .info)
            }
            if let name = p.launchConfigName, launchConfigs.contains(where: { $0.name == name }) {
                selectLaunchConfig(name: name)
            } else if p.launchConfigName == nil, p.extraArgs.isEmpty, let first = launchConfigs.first {
                selectLaunchConfig(name: first.name)
            } else {
                selectedLaunchConfigName = nil
            }
            deviceAtOpen = p.lastDeviceId
            deviceOrigin = .remembered
            applyOverrides()
            Task { await refreshDevices() }
        } catch {
            log(error.localizedDescription, .error)
            onError?(error.localizedDescription)
        }
    }

    public func removeRecent(path: String) {
        store.remove(path: path)
        if project?.path == path { project = nil }
    }

    private func persistProjectSettings() {
        guard !suppressPersist, var p = project else { return }
        // An overridden field keeps its saved value; `project` always holds the saved values.
        if overrides.deviceQuery == nil, deviceOrigin == .remembered { p.lastDeviceId = selectedDeviceId }
        if overrides.configName == nil, overrides.args == nil {
            p.extraArgs = extraArgs
            p.launchConfigName = selectedLaunchConfigName
        }
        if overrides.autoReload == nil { p.autoReload = autoReload }
        project = p
        store.update(p)
    }

    private func applyOverrides() {
        if let name = overrides.configName {
            if launchConfigs.contains(where: { $0.name == name }) {
                selectLaunchConfig(name: name)
            } else {
                log("Launch config \"\(name)\" not found in launch.json; using the saved settings.", .warning)
                overrides.configName = nil
            }
        }
        if let args = overrides.args {
            extraArgs = args
            selectedLaunchConfigName = nil
        }
        if let on = overrides.autoReload { autoReload = on }
    }

    // MARK: Choices made in the terminal UI (clear the matching override, then save as usual)

    public func chooseDevice(id: String) {
        overrides.deviceQuery = nil
        deviceOrigin = .remembered
        selectedDeviceId = id
    }

    /// `nil` means "Custom": keep the current args.
    public func chooseLaunchConfig(name: String?) {
        overrides.configName = nil; overrides.args = nil
        selectLaunchConfig(name: name)
    }

    public func setArgs(_ args: String) {
        overrides.configName = nil; overrides.args = nil
        extraArgs = args
        selectedLaunchConfigName = nil
    }

    public func setAutoReload(_ on: Bool) {
        overrides.autoReload = nil
        autoReload = on
    }

    /// Opens another project from the recents list; command-line overrides belonged to the first one.
    public func switchProject(path: String) {
        if isRunning { Task { await stop(); self.switchProject(path: path) }; return }
        overrides = SessionOverrides()
        selectProject(path: path)
    }

    // MARK: Editor

    /// The editor that "Open in Editor" will use: the configured app, or the first installed known editor.
    public var effectiveEditor: InstalledEditor? {
        if !store.editorAppPath.isEmpty, FileManager.default.fileExists(atPath: store.editorAppPath) {
            return InstalledEditor(name: EditorLauncher.name(ofApp: store.editorAppPath), appPath: store.editorAppPath)
        }
        return installedEditors.first
    }

    public var canOpenInEditor: Bool { project != nil && (store.editorUseCustomCommand || effectiveEditor != nil) }

    /// Picker value shared by the toolbar menu, Settings and the terminal: an app path, or "custom".
    public var editorSelection: String {
        get {
            if store.editorUseCustomCommand { return "custom" }
            return effectiveEditor?.appPath ?? ""
        }
        set {
            if newValue == "custom" { store.editorUseCustomCommand = true }
            else { store.editorUseCustomCommand = false; store.editorAppPath = newValue }
        }
    }

    public var editorButtonTitle: String {
        if store.editorUseCustomCommand { return "Command" }
        return effectiveEditor?.name ?? "Editor"
    }

    /// The configured app when it is not one of the detected known editors (chosen via "Other application…").
    public var otherEditor: InstalledEditor? {
        guard !store.editorAppPath.isEmpty, !installedEditors.contains(where: { $0.appPath == store.editorAppPath }),
              FileManager.default.fileExists(atPath: store.editorAppPath) else { return nil }
        return InstalledEditor(name: EditorLauncher.name(ofApp: store.editorAppPath), appPath: store.editorAppPath)
    }

    public func refreshInstalledEditors() { installedEditors = EditorLauncher.detectInstalled() }

    public func openInEditor() {
        guard let project else { return }
        if store.editorUseCustomCommand {
            let env = flutterPath.map { deps.environment($0) } ?? ProcessInfo.processInfo.environment
            do {
                try EditorLauncher.runCustom(template: store.editorCustomCommand, projectPath: project.path, environment: env)
                log("Opened in editor: \(EditorLauncher.expand(template: store.editorCustomCommand, projectPath: project.path))", .info)
            } catch {
                log("Editor command failed: \(error.localizedDescription)", .error)
            }
            return
        }
        guard let editor = effectiveEditor else {
            log("No editor found. \(hints.editor)", .error)
            onError?("No editor found.")
            return
        }
        Task {
            do {
                try await EditorLauncher.open(projectPath: project.path, withApp: editor.appPath)
                log("Opened \(project.name) in \(editor.name).", .info)
            } catch {
                log("Could not open \(editor.name): \(error.localizedDescription)", .error)
            }
        }
    }

    /// Opens the file behind a log link at its line, in the chosen editor.
    public func openLogLink(location: String, line: Int?, column: Int?) {
        guard let project else { return }
        let resolver = PackageConfigResolver(projectPath: project.path)
        guard let file = resolver.resolve(location), FileManager.default.fileExists(atPath: file) else {
            log("Can't find a file for \(location). Run `flutter pub get` if it is in another package.", .warning)
            return
        }
        let env = flutterPath.map { deps.environment($0) } ?? ProcessInfo.processInfo.environment
        let where_ = line.map { ":\($0)" } ?? ""
        do {
            if store.editorUseCustomCommand {
                let cmd = EditorLauncher.expand(template: store.editorOpenFileCommand, projectPath: project.path, file: file, line: line)
                try EditorLauncher.run(argv: ["/bin/zsh", "-lic", cmd], environment: env)
                log("Opened \((file as NSString).lastPathComponent)\(where_) via \(cmd)", .info)
                return
            }
            guard let editor = effectiveEditor else { log("No editor found. \(hints.editor)", .error); return }
            let bundleId = Bundle(path: editor.appPath)?.bundleIdentifier ?? ""
            if let argv = EditorLauncher.openFileCommand(appPath: editor.appPath, bundleIdentifier: bundleId, file: file, line: line, column: column),
               FileManager.default.isExecutableFile(atPath: argv[0]) {
                try EditorLauncher.run(argv: argv, environment: env)
                log("Opened \((file as NSString).lastPathComponent)\(where_) in \(editor.name).", .info)
            } else {
                Task { try? await EditorLauncher.open(projectPath: file, withApp: editor.appPath) }
                log("Opened \((file as NSString).lastPathComponent) in \(editor.name) (this editor has no line-jump CLI).", .info)
            }
        } catch {
            log("Could not open \(file): \(error.localizedDescription)", .error)
        }
    }

    // MARK: Launch configurations (.vscode/launch.json)

    /// Applies a launch configuration to the args field (and device, if the config names one).
    public func selectLaunchConfig(name: String?) {
        guard let name, let cfg = launchConfigs.first(where: { $0.name == name }) else {
            selectedLaunchConfigName = nil
            return
        }
        applyingLaunchConfig = true
        extraArgs = ArgumentSplitter.join(cfg.flutterRunArguments)
        applyingLaunchConfig = false
        selectedLaunchConfigName = name
        if let dev = cfg.deviceId { adoptConfigDevice(dev) }
        log("Launch config \"\(name)\" → \(extraArgs.isEmpty ? "(no extra args)" : extraArgs)", .info)
        if let mode = cfg.flutterMode?.lowercased(), mode != "debug" {
            log("Note: \(mode) mode does not support hot reload.", .warning)
        }
    }

    /// A config's device never replaces a `--device` choice; under an overridden config it is not saved.
    private func adoptConfigDevice(_ id: String) {
        guard overrides.deviceQuery == nil, devices.contains(where: { $0.id == id }) else { return }
        deviceOrigin = (overrides.configName != nil || overrides.args != nil) ? .overriddenConfig : .remembered
        selectedDeviceId = id
    }

    /// Re-reads launch.json so edits made in the editor are picked up before a run.
    public func reloadLaunchConfigs() {
        guard let project else { return }
        launchConfigs = LaunchConfigReader.load(projectPath: project.path)
        guard let name = selectedLaunchConfigName else { return }
        if launchConfigs.contains(where: { $0.name == name }) {
            selectLaunchConfig(name: name)
        } else {
            log("Launch config \"\(name)\" no longer exists in launch.json; keeping current args.", .warning)
            selectedLaunchConfigName = nil
        }
    }

    // MARK: Devices

    /// Reloads the device list; concurrent callers wait for the same `flutter devices` run.
    public func refreshDevices() async {
        if let running = deviceRefreshTask { await running.value; return }
        let task = Task { await self.loadDevices() }
        deviceRefreshTask = task
        await task.value
        deviceRefreshTask = nil
    }

    /// Terminal start: waits for the device list, resolves `--device`, and runs when the device is known.
    public func startup(autoRun: Bool) async -> StartupOutcome {
        guard project != nil else { return .idle }
        await refreshDevices()
        if let query = overrides.deviceQuery {
            guard case .one(let device) = DeviceMatcher.match(query: query, in: devices) else { return .needsDevice(filter: query) }
            selectedDeviceId = device.id
        } else {
            let configDevice = selectedLaunchConfigName.flatMap { name in launchConfigs.first { $0.name == name }?.deviceId }
            let remembered = [deviceAtOpen, configDevice].compactMap { $0 }
            guard let id = selectedDeviceId, remembered.contains(id), devices.contains(where: { $0.id == id }) else {
                return .needsDevice(filter: "")
            }
        }
        guard autoRun, canRun else { return .idle }
        await run()
        return .started
    }

    private func loadDevices() async {
        guard let flutterPath else { return }
        isLoadingDevices = true; deviceError = nil
        defer { isLoadingDevices = false }
        do {
            let list = try await deps.listDevices(flutterPath, deps.environment(flutterPath), project?.path)
            devices = list
            if let name = selectedLaunchConfigName, let dev = launchConfigs.first(where: { $0.name == name })?.deviceId {
                adoptConfigDevice(dev)
            }
            if selectedDeviceId == nil || !list.contains(where: { $0.id == selectedDeviceId }) {
                // A fallback is only a suggestion for this session; it must not become the remembered device.
                let wasSuppressed = suppressPersist
                suppressPersist = true
                selectedDeviceId = list.first?.id
                if list.first != nil { deviceOrigin = .fallback }
                suppressPersist = wasSuppressed
            }
            if list.isEmpty { deviceError = "No devices found. Start a simulator or connect a device, then refresh." }
            log("Devices: \(list.isEmpty ? "none" : list.map(\.displayName).joined(separator: ", "))", .info)
        } catch {
            deviceError = error.localizedDescription
            log("Device list failed: \(error.localizedDescription)", .error)
        }
    }

    // MARK: Run / stop

    public func run() async {
        guard canRun, project != nil, selectedDeviceId != nil, flutterPath != nil else { return }
        clearLogs()
        reloadLaunchConfigs()
        guard let project, let deviceId = selectedDeviceId, let flutterPath else { return }
        if deviceOrigin == .fallback { deviceOrigin = .remembered; persistProjectSettings() }  // running on it means choosing it
        state = .starting
        pendingReload = false
        let args = ArgumentSplitter.split(extraArgs)
        log("$ flutter run --machine -d \(deviceId) \(args.joined(separator: " "))", .info)
        let d = deps.makeDaemon(DaemonConfig(flutterPath: flutterPath, projectPath: project.path, deviceId: deviceId,
                                             extraArgs: args, environment: deps.environment(flutterPath)))
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

    public func stop() async {
        guard let d = daemon, isRunning else { return }
        state = .stopping
        log("Stopping…", .info)
        await d.stop()
    }

    /// Kills flutter immediately (second Ctrl+C in the terminal).
    public func forceQuit() {
        stopWatcher()
        daemon?.terminate()
    }

    public func hotReload() async { await restart(full: false) }
    public func hotRestart() async { await restart(full: true) }

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
        watcher = deps.startWatcher(project.libPath) { debouncer.trigger() }
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

    @ObservationIgnored private let mirrorLogsToStderr = ProcessInfo.processInfo.environment["HOTPLATE_LOG_STDERR"] == "1"

    public func log(_ text: String, _ kind: LogKind = .normal) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            logs.append(LogLine(id: nextLogId, text: String(line), kind: kind, time: Date())); nextLogId += 1
            if mirrorLogsToStderr { FileHandle.standardError.write(Data("[\(kind)] \(line)\n".utf8)) }
        }
        if logs.count > maxLogLines { logs.removeFirst(logs.count - maxLogLines) }
    }

    public func clearLogs() { logs.removeAll() }

    /// Called on quit: stops the daemon if needed.
    public func shutdown() async {
        stopWatcher()
        await daemon?.stop()
    }
}
