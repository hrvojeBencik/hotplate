import Foundation

/// Finds the `flutter` executable and builds a PATH suitable for child processes.
/// GUI apps get a minimal PATH, so we borrow the user's login-shell PATH.
public enum FlutterLocator {
    private static let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"

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
        for dir in loginShellPath().split(separator: ":") {
            let p = "\(dir)/flutter"
            if fm.isExecutableFile(atPath: p) { return p }
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Documents/flutter/bin/flutter", "\(home)/flutter/bin/flutter", "\(home)/development/flutter/bin/flutter",
            "\(home)/dev/flutter/bin/flutter", "\(home)/fvm/default/bin/flutter", "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter", "/opt/flutter/bin/flutter",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    private static let cachedLoginPath: String = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "echo $PATH"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return defaultPath }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? defaultPath : s
    }()

    public static func loginShellPath() -> String { cachedLoginPath }

    public static func environment(flutterPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let flutterBin = (flutterPath as NSString).deletingLastPathComponent
        var parts = [flutterBin]
        parts += loginShellPath().split(separator: ":").map(String.init)
        parts += defaultPath.split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        return env
    }
}
