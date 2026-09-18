import Foundation
import Observation
import FlutterRunnerCore

/// Persists recent projects and global settings in UserDefaults.
@MainActor @Observable
final class ProjectStore {
    private let defaults: UserDefaults
    private enum Key {
        static let recents = "recents", flutterPath = "manualFlutterPath", debounce = "debounceMs", lastProject = "lastProjectPath"
    }

    var recents: [Project] { didSet { save() } }
    var manualFlutterPath: String { didSet { defaults.set(manualFlutterPath, forKey: Key.flutterPath) } }
    var debounceMs: Int { didSet { defaults.set(debounceMs, forKey: Key.debounce) } }
    var lastProjectPath: String? { didSet { defaults.set(lastProjectPath, forKey: Key.lastProject) } }

    init(defaults: UserDefaults = .standard) {
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
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Key.recents) }
    }

    func touch(_ project: Project) {
        var p = project; p.lastOpened = Date()
        recents.removeAll { $0.path == p.path }
        recents.insert(p, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        lastProjectPath = p.path
    }

    func update(_ project: Project) {
        if let i = recents.firstIndex(where: { $0.path == project.path }) { recents[i] = project } else { touch(project) }
    }

    func remove(path: String) {
        recents.removeAll { $0.path == path }
        if lastProjectPath == path { lastProjectPath = nil }
    }
}
