import Foundation

/// A Dart source reference found in a log line.
public struct LogLink: Equatable, Sendable {
    /// The matched text, e.g. `package:app/main.dart:12:3`.
    public let raw: String
    public let range: Range<String.Index>
    /// `package:` URI, `file://` URI, absolute path or project-relative path, without line/column.
    public let location: String
    public let line: Int?
    public let column: Int?
}

public enum LogLinkParser {
    private static let regex = try! NSRegularExpression(
        pattern: #"((?:package:[A-Za-z0-9_\-.]+/|file:///|/|(?:lib|test|bin|integration_test)/)[A-Za-z0-9_\-./]+?\.dart)(?::(\d+))?(?::(\d+))?(?![A-Za-z0-9_])"#)

    public static func links(in text: String) -> [LogLink] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let whole = Range(m.range, in: text), let loc = Range(m.range(at: 1), in: text) else { return nil }
            let line = m.range(at: 2).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 2)))
            let column = m.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 3)))
            return LogLink(raw: String(text[whole]), range: whole, location: String(text[loc]), line: line, column: column)
        }
    }
}

/// Resolves `package:` URIs and relative paths to absolute files using `.dart_tool/package_config.json`.
public struct PackageConfigResolver: Sendable {
    public let projectPath: String
    private let packageRoots: [String: String]   // package name -> absolute directory of its packageUri

    public init(projectPath: String) {
        self.projectPath = projectPath
        var roots: [String: String] = [:]
        let configURL = URL(fileURLWithPath: projectPath).appendingPathComponent(".dart_tool/package_config.json")
        if let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let packages = json["packages"] as? [[String: Any]] {
            let base = configURL.deletingLastPathComponent()
            for p in packages {
                guard let name = p["name"] as? String, let rootUri = p["rootUri"] as? String else { continue }
                let packageUri = p["packageUri"] as? String ?? "lib/"
                let root = URL(string: rootUri, relativeTo: base)?.absoluteURL ?? base
                roots[name] = root.appendingPathComponent(packageUri).standardizedFileURL.path
            }
        }
        packageRoots = roots
    }

    public func resolve(_ location: String) -> String? {
        if location.hasPrefix("package:") {
            let rest = location.dropFirst("package:".count)
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            let name = String(rest[..<slash]); let path = String(rest[rest.index(after: slash)...])
            if let root = packageRoots[name] { return (root as NSString).appendingPathComponent(path) }
            // Without a package_config, assume the project's own package lives in lib/.
            if name == (projectPath as NSString).lastPathComponent { return (projectPath as NSString).appendingPathComponent("lib/\(path)") }
            return nil
        }
        if location.hasPrefix("file://") { return URL(string: location)?.path }
        if location.hasPrefix("/") { return location }
        return (projectPath as NSString).appendingPathComponent(location)
    }
}
