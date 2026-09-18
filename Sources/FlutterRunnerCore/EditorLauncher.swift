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
