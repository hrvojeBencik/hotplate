import Foundation

/// Whether `/usr/local/bin/hotplate` points at the command line tool inside this copy of the app.
public enum CommandLineToolStatus: Equatable, Sendable {
    case installed
    case notInstalled
    /// A symlink points to another app copy's tool.
    case otherCopy(String)
    /// A non-symlink file exists at the link path.
    case foreignFile
    /// This build has no tool inside the bundle (e.g. `swift run`).
    case unavailable

    public static func check(linkPath: String, helperPath: String, fileManager fm: FileManager = .default) -> CommandLineToolStatus {
        guard fm.fileExists(atPath: helperPath) else { return .unavailable }
        if let destination = try? fm.destinationOfSymbolicLink(atPath: linkPath) {
            let helper = URL(fileURLWithPath: helperPath).standardizedFileURL.path
            let resolved: String
            if destination.hasPrefix("/") {
                resolved = URL(fileURLWithPath: destination).standardizedFileURL.path
            } else {
                let linkDir = (linkPath as NSString).deletingLastPathComponent
                let absoluteDestination = (linkDir as NSString).appendingPathComponent(destination)
                resolved = URL(fileURLWithPath: absoluteDestination).standardizedFileURL.path
            }
            return resolved == helper ? .installed : .otherCopy(resolved)
        }
        guard fm.fileExists(atPath: linkPath) else { return .notInstalled }
        if let attrs = try? fm.attributesOfItem(atPath: linkPath), let fileType = attrs[.type] as? FileAttributeType, fileType == .typeSymbolicLink {
            return .otherCopy(linkPath)
        }
        return .foreignFile
    }

    /// True when macOS runs the app from a randomized read-only copy (Gatekeeper App Translocation, e.g. straight
    /// from Downloads); a link to that copy would break once the app quits.
    public static func isTranslocated(path: String) -> Bool { path.contains("/AppTranslocation/") }

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
