import Foundation
import Observation

/// Persists recent projects and global settings in UserDefaults. Shared by the app and the terminal tool.
@MainActor @Observable
public final class ProjectStore {
    nonisolated public static let suiteName = "com.hrvojebencik.hotplate"

    /// The app reads its own domain through `.standard`; the terminal tool (another process, no bundle id)
    /// opens the same domain as a suite. Using the own bundle id as a suite name does not work, hence the check.
    nonisolated public static func makeDefaults() -> UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    private let defaults: UserDefaults
    private enum Key {
        static let recents = "recents", flutterPath = "manualFlutterPath", debounce = "debounceMs", lastProject = "lastProjectPath"
        static let editorApp = "editorAppPath", editorCommand = "editorCustomCommand", editorUseCommand = "editorUseCustomCommand"
        static let editorFileCommand = "editorOpenFileCommand", hotkeys = "globalHotkeysEnabled"
    }

    public var recents: [Project] { didSet { save() } }
    public var manualFlutterPath: String { didSet { defaults.set(manualFlutterPath, forKey: Key.flutterPath) } }
    public var debounceMs: Int { didSet { defaults.set(debounceMs, forKey: Key.debounce) } }
    public var lastProjectPath: String? { didSet { defaults.set(lastProjectPath, forKey: Key.lastProject) } }
    /// Path to the editor .app bundle; empty means "auto-detect".
    public var editorAppPath: String { didSet { defaults.set(editorAppPath, forKey: Key.editorApp) } }
    /// Shell command template with `{path}`; used when `editorUseCustomCommand` is on.
    public var editorCustomCommand: String { didSet { defaults.set(editorCustomCommand, forKey: Key.editorCommand) } }
    public var editorUseCustomCommand: Bool { didSet { defaults.set(editorUseCustomCommand, forKey: Key.editorUseCommand) } }
    /// Shell command template with `{file}` and `{line}`; used for log links when the custom command is on.
    public var editorOpenFileCommand: String { didSet { defaults.set(editorOpenFileCommand, forKey: Key.editorFileCommand) } }
    public var globalHotkeysEnabled: Bool { didSet { defaults.set(globalHotkeysEnabled, forKey: Key.hotkeys) } }

    public init(defaults: UserDefaults = ProjectStore.makeDefaults()) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.recents), let list = try? JSONDecoder().decode([Project].self, from: data) {
            recents = list
        } else {
            recents = []
        }
        manualFlutterPath = defaults.string(forKey: Key.flutterPath) ?? ""
        let d = defaults.integer(forKey: Key.debounce)
        debounceMs = d == 0 ? 300 : d
        lastProjectPath = defaults.string(forKey: Key.lastProject)
        editorAppPath = defaults.string(forKey: Key.editorApp) ?? ""
        editorCustomCommand = defaults.string(forKey: Key.editorCommand) ?? "zed {path}"
        editorUseCustomCommand = defaults.bool(forKey: Key.editorUseCommand)
        editorOpenFileCommand = defaults.string(forKey: Key.editorFileCommand) ?? "zed {file}:{line}"
        globalHotkeysEnabled = defaults.object(forKey: Key.hotkeys) as? Bool ?? true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Key.recents) }
    }

    public func touch(_ project: Project) {
        var p = project; p.lastOpened = Date()
        recents.removeAll { $0.path == p.path }
        recents.insert(p, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        lastProjectPath = p.path
    }

    public func update(_ project: Project) {
        if let i = recents.firstIndex(where: { $0.path == project.path }) { recents[i] = project } else { touch(project) }
    }

    public func remove(path: String) {
        recents.removeAll { $0.path == path }
        if lastProjectPath == path { lastProjectPath = nil }
    }
}
