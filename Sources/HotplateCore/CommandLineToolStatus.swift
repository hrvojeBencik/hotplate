import Foundation

/// Whether `/usr/local/bin/hotplate` points at the command line tool inside this copy of the app.
public enum CommandLineToolStatus: Equatable, Sendable {
    case installed
    case notInstalled
    /// Something else is at the link path: another app copy's tool or an unrelated file.
    case otherCopy(String)
    /// This build has no tool inside the bundle (e.g. `swift run`).
    case unavailable

    public static func check(linkPath: String, helperPath: String, fileManager fm: FileManager = .default) -> CommandLineToolStatus {
        guard fm.fileExists(atPath: helperPath) else { return .unavailable }
        if let destination = try? fm.destinationOfSymbolicLink(atPath: linkPath) {
            let resolved = URL(fileURLWithPath: destination).standardizedFileURL.path
            let helper = URL(fileURLWithPath: helperPath).standardizedFileURL.path
            return resolved == helper ? .installed : .otherCopy(destination)
        }
        return fm.fileExists(atPath: linkPath) ? .otherCopy(linkPath) : .notInstalled
    }

    public static func installScript(helperPath: String, linkPath: String) -> String {
        let dir = (linkPath as NSString).deletingLastPathComponent
        return adminScript("mkdir -p \(shellQuote(dir)) && ln -sf \(shellQuote(helperPath)) \(shellQuote(linkPath))")
    }

    public static func removeScript(linkPath: String) -> String {
        adminScript("rm -f \(shellQuote(linkPath))")
    }

    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func adminScript(_ shell: String) -> String {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
