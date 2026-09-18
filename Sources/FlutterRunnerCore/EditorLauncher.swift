import AppKit
import Foundation

/// A GUI code editor we know how to detect and open a folder with.
public struct KnownEditor: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
}

/// An editor found on this machine.
public struct InstalledEditor: Identifiable, Hashable, Sendable {
    public var id: String { appPath }
    public let name: String
    public let appPath: String
    public init(name: String, appPath: String) { self.name = name; self.appPath = appPath }
}

public enum EditorLauncher {
    /// Ordered by preference for the automatic default.
    public static let knownEditors: [KnownEditor] = [
        KnownEditor(name: "Zed", bundleIdentifier: "dev.zed.Zed"),
        KnownEditor(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode"),
        KnownEditor(name: "Cursor", bundleIdentifier: "com.todesktop.230313mzl4w4u92"),
        KnownEditor(name: "Windsurf", bundleIdentifier: "com.exafunction.windsurf"),
        KnownEditor(name: "Sublime Text", bundleIdentifier: "com.sublimetext.4"),
        KnownEditor(name: "Android Studio", bundleIdentifier: "com.google.android.studio"),
        KnownEditor(name: "IntelliJ IDEA", bundleIdentifier: "com.jetbrains.intellij"),
        KnownEditor(name: "IntelliJ IDEA CE", bundleIdentifier: "com.jetbrains.intellij.ce"),
        KnownEditor(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode"),
        KnownEditor(name: "Nova", bundleIdentifier: "com.panic.Nova"),
        KnownEditor(name: "BBEdit", bundleIdentifier: "com.barebones.bbedit"),
    ]

    /// Known editors that are actually installed, in preference order.
    public static func detectInstalled() -> [InstalledEditor] {
        knownEditors.compactMap { editor in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) else { return nil }
            return InstalledEditor(name: editor.name, appPath: url.path)
        }
    }

    public static func name(ofApp appPath: String) -> String {
        let bundle = Bundle(path: appPath)
        return bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Opens the project folder with a GUI application bundle.
    public static func open(projectPath: String, withApp appPath: String) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try await NSWorkspace.shared.open([URL(fileURLWithPath: projectPath)],
                                               withApplicationAt: URL(fileURLWithPath: appPath), configuration: config)
    }

    /// Expands a user command template, substituting a shell-quoted project path for `{path}`
    /// (or appending it when the placeholder is absent).
    public static func expand(template: String, projectPath: String) -> String {
        let quoted = "'" + projectPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let t = template.trimmingCharacters(in: .whitespaces)
        return t.contains("{path}") ? t.replacingOccurrences(of: "{path}", with: quoted) : "\(t) \(quoted)"
    }

    /// Runs a custom command through an interactive login shell so user PATH and aliases apply.
    public static func runCustom(template: String, projectPath: String, environment: [String: String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lic", expand(template: template, projectPath: projectPath)]
        p.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }
}

public extension EditorLauncher {
    /// Command line that opens `file` at `line` in a known editor, using the CLI shipped inside the app bundle
    /// so it works regardless of the user's PATH. Nil when the editor has no known CLI.
    static func openFileCommand(appPath: String, bundleIdentifier: String, file: String, line: Int?, column: Int?) -> [String]? {
        let loc = [file, line.map(String.init), column.map(String.init)].compactMap { $0 }.joined(separator: ":")
        switch bundleIdentifier {
        case "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf":
            let cli = (appPath as NSString).appendingPathComponent("Contents/Resources/app/bin/code")
            let alt = (appPath as NSString).appendingPathComponent("Contents/Resources/app/bin/\(bundleIdentifier == "com.exafunction.windsurf" ? "windsurf" : "cursor")")
            return [FileManager.default.isExecutableFile(atPath: cli) ? cli : alt, "-g", loc]
        case "dev.zed.Zed":
            return [(appPath as NSString).appendingPathComponent("Contents/MacOS/cli"), loc]
        case "com.sublimetext.4":
            return [(appPath as NSString).appendingPathComponent("Contents/SharedSupport/bin/subl"), loc]
        case "com.apple.dt.Xcode":
            return line.map { ["/usr/bin/xed", "-l", String($0), file] } ?? ["/usr/bin/xed", file]
        case "com.google.android.studio":
            let bin = (appPath as NSString).appendingPathComponent("Contents/MacOS/studio")
            return line.map { [bin, "--line", String($0), file] } ?? [bin, file]
        case "com.jetbrains.intellij", "com.jetbrains.intellij.ce":
            let bin = (appPath as NSString).appendingPathComponent("Contents/MacOS/idea")
            return line.map { [bin, "--line", String($0), file] } ?? [bin, file]
        case "com.barebones.bbedit":
            return line.map { ["/usr/local/bin/bbedit", "+\($0)", file] } ?? ["/usr/local/bin/bbedit", file]
        default:
            return nil
        }
    }

    /// Expands a template with `{path}`, `{file}` and `{line}` placeholders (all shell-quoted where needed).
    static func expand(template: String, projectPath: String, file: String, line: Int?) -> String {
        let quotedFile = "'" + file.replacingOccurrences(of: "'", with: "'\\''") + "'"
        var t = template.trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: "{file}", with: quotedFile)
        t = t.replacingOccurrences(of: "{line}", with: line.map(String.init) ?? "1")
        let quotedProject = "'" + projectPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return t.replacingOccurrences(of: "{path}", with: quotedProject)
    }

    /// Runs a command line (argv) detached; `bundleIdentifier` is used only for a friendlier error.
    static func run(argv: [String], environment: [String: String]) throws {
        guard let exe = argv.first else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = Array(argv.dropFirst())
        p.environment = environment
        p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run()
    }
}
