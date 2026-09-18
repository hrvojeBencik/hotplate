import Foundation

public struct FlutterDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let targetPlatform: String
    public let emulator: Bool
    public let isSupported: Bool

    enum CodingKeys: String, CodingKey { case id, name, targetPlatform, emulator, isSupported }

    public init(id: String, name: String, targetPlatform: String, emulator: Bool, isSupported: Bool) {
        self.id = id; self.name = name; self.targetPlatform = targetPlatform; self.emulator = emulator; self.isSupported = isSupported
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        targetPlatform = try c.decodeIfPresent(String.self, forKey: .targetPlatform) ?? ""
        emulator = try c.decodeIfPresent(Bool.self, forKey: .emulator) ?? false
        isSupported = try c.decodeIfPresent(Bool.self, forKey: .isSupported) ?? true
    }

    /// Decodes `flutter devices --machine` output, tolerating non-JSON noise around the array.
    public static func decodeList(from data: Data) throws -> [FlutterDevice] {
        var text = String(decoding: data, as: UTF8.self)
        if let start = text.firstIndex(of: "[") { text = String(text[start...]) }
        if let end = text.lastIndex(of: "]") { text = String(text[...end]) }
        let all = try JSONDecoder().decode([FlutterDevice].self, from: Data(text.utf8))
        return all.filter(\.isSupported)
    }

    public var displayName: String { emulator ? "\(name) (emulator)" : name }
}

public struct Project: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }
    public let path: String
    public var name: String
    public var lastDeviceId: String?
    public var extraArgs: String
    public var autoReload: Bool
    public var lastOpened: Date
    /// Name of the selected `.vscode/launch.json` configuration; nil means custom args.
    public var launchConfigName: String?

    public init(path: String, name: String, lastDeviceId: String? = nil, extraArgs: String = "", autoReload: Bool = true,
                lastOpened: Date = Date(), launchConfigName: String? = nil) {
        self.path = path; self.name = name; self.lastDeviceId = lastDeviceId; self.extraArgs = extraArgs
        self.autoReload = autoReload; self.lastOpened = lastOpened; self.launchConfigName = launchConfigName
    }

    public static func load(path: String) throws -> Project {
        let pubspec = (path as NSString).appendingPathComponent("pubspec.yaml")
        guard let yaml = try? String(contentsOfFile: pubspec, encoding: .utf8) else {
            throw RunnerError.notAFlutterProject("No pubspec.yaml in \(path)")
        }
        let hasMain = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("lib/main.dart"))
        guard PubspecReader.isFlutterProject(yaml: yaml) || hasMain else {
            throw RunnerError.notAFlutterProject("pubspec.yaml does not depend on flutter")
        }
        let name = PubspecReader.name(fromYaml: yaml) ?? (path as NSString).lastPathComponent
        return Project(path: path, name: name)
    }

    public var libPath: String { (path as NSString).appendingPathComponent("lib") }
}

public enum RunnerError: LocalizedError, Sendable {
    case flutterNotFound
    case notAFlutterProject(String)
    case timeout(String)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .flutterNotFound: return "Could not find the `flutter` executable. Set its path in Settings."
        case .notAFlutterProject(let s): return s
        case .timeout(let s): return "Timed out: \(s)"
        case .processFailed(let s): return s
        }
    }
}
