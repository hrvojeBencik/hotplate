import Foundation

public enum SessionState: Equatable, Sendable {
    case idle, starting, running, reloading, restarting, stopping
    case failed(String)
}

public enum LogKind: Sendable { case normal, error, warning, info, success }

public struct LogLine: Identifiable, Sendable {
    public let id: Int
    public let text: String
    public let kind: LogKind
    public let time: Date

    public init(id: Int, text: String, kind: LogKind, time: Date) {
        self.id = id; self.text = text; self.kind = kind; self.time = time
    }
}

/// Front-end specific advice appended to error messages.
public struct SessionHints: Sendable {
    public var editor: String
    public var flutter: String

    public init(editor: String, flutter: String) { self.editor = editor; self.flutter = flutter }

    public static let gui = SessionHints(editor: "Pick one in Settings (⌘,) → Editor.", flutter: "Set the path in Settings (⌘,).")
    public static let terminal = SessionHints(editor: "Press E to choose one.",
                                              flutter: "Pass --flutter <path> or set it in Hotplate Settings.")
}

/// Choices given on the command line. They apply to this session only and are never saved.
public struct SessionOverrides: Equatable, Sendable {
    public var deviceQuery: String?
    public var configName: String?
    public var args: String?
    public var autoReload: Bool?

    public init(deviceQuery: String? = nil, configName: String? = nil, args: String? = nil, autoReload: Bool? = nil) {
        self.deviceQuery = deviceQuery; self.configName = configName; self.args = args; self.autoReload = autoReload
    }
}

public enum StartupOutcome: Equatable, Sendable {
    case started
    case idle
    /// No device could be chosen safely; the front end should show the device list with this filter.
    case needsDevice(filter: String)
}
