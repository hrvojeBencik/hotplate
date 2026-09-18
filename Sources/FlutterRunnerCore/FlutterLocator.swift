import Foundation

/// Finds the `flutter` executable and builds an environment suitable for child processes.
///
/// GUI apps launched from Finder get a minimal PATH and no locale. Developer tools
/// (flutter, pod, git, ruby) usually live on the PATH set up in `~/.zshrc`, which only an
/// *interactive* shell reads, so we ask an interactive login shell for its PATH once.
public enum FlutterLocator {
    private static let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"
    private static let startMarker = "__FR_PATH__", endMarker = "__FR_END__"

    public static func locate(manualPath: String?) -> String? {
        let fm = FileManager.default
        if let m = manualPath?.trimmingCharacters(in: .whitespaces), !m.isEmpty {
            let expanded = (m as NSString).expandingTildeInPath
            let candidates = [
                expanded,
                (expanded as NSString).appendingPathComponent("flutter"),
                (expanded as NSString).appendingPathComponent("bin/flutter"),
            ]
            if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) && !isDirectory($0) }) { return hit }
        }
        if let hit = find(tool: "flutter", inPath: loginShellPath()) { return hit }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Documents/flutter/bin/flutter", "\(home)/flutter/bin/flutter", "\(home)/development/flutter/bin/flutter",
            "\(home)/dev/flutter/bin/flutter", "\(home)/fvm/default/bin/flutter", "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter", "/opt/flutter/bin/flutter",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// Looks a tool up on a PATH string (used for diagnostics such as `pod`).
    public static func find(tool: String, inPath path: String) -> String? {
        for dir in path.split(separator: ":") {
            let p = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: p), !isDirectory(p) { return p }
        }
        return nil
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Pulls the PATH out of noisy shell output using the markers we asked the shell to print.
    static func extractMarkedPath(from output: String) -> String? {
        guard let s = output.range(of: startMarker), let e = output.range(of: endMarker, range: s.upperBound..<output.endIndex) else { return nil }
        let value = String(output[s.upperBound..<e.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func shellPath(interactive: Bool) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = [interactive ? "-lic" : "-lc", "printf '\(startMarker)%s\(endMarker)' \"$PATH\""]
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { if p.isRunning { p.terminate() } }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return extractMarkedPath(from: String(decoding: data, as: UTF8.self))
    }

    private static let cachedLoginPath: String = {
        shellPath(interactive: true) ?? shellPath(interactive: false) ?? defaultPath
    }()

    public static func loginShellPath() -> String { cachedLoginPath }

    /// Directories that commonly hold developer tools, appended as a safety net.
    private static var fallbackDirs: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin", "\(home)/.pub-cache/bin",
                "\(home)/.rbenv/shims", "\(home)/.rvm/bin", "\(home)/.local/bin"]
    }

    public static func environment(flutterPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let flutterBin = (flutterPath as NSString).deletingLastPathComponent
        var parts = [flutterBin]
        parts += loginShellPath().split(separator: ":").map(String.init)
        parts += fallbackDirs
        parts += defaultPath.split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        // CocoaPods refuses to run without a UTF-8 locale; Finder-launched apps have none.
        if env["LANG"] == nil, env["LC_ALL"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env
    }
}
