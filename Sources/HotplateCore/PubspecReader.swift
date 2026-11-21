import Foundation

/// Minimal pubspec.yaml reading: just enough to name and validate a project.
public enum PubspecReader {
    public static func name(fromYaml yaml: String) -> String? {
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("name:"), !rawLine.hasPrefix(" ") else { continue }
            var value = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]).trimmingCharacters(in: .whitespaces) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    public static func isFlutterProject(yaml: String) -> Bool {
        yaml.contains("sdk: flutter") || yaml.range(of: #"^\s*flutter:\s*$"#, options: .regularExpression) != nil
    }

    /// `path:` values of the packages in `dependencies`, `dev_dependencies` and `dependency_overrides`, in file order,
    /// as written (relative to the pubspec's folder, or absolute). Both `ui:\n    path: ui` and `ui: {path: ui}`
    /// count; the `path:` inside a `git:` dependency (a folder within the repository) does not.
    public static func pathDependencies(fromYaml yaml: String) -> [String] {
        let sections: Set<String> = ["dependencies", "dev_dependencies", "dependency_overrides"]
        var inSection = false
        var packageIndent: Int?   // indent of the package names in this section
        var keyIndent: Int?       // indent of the current package's own keys
        var result: [String] = []
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = stripComment(String(rawLine))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let indent = line.prefix { $0 == " " }.count
            if indent == 0 {
                inSection = sections.contains(key(of: trimmed) ?? "")
                packageIndent = nil; keyIndent = nil
                continue
            }
            guard inSection else { continue }
            if packageIndent == nil || indent <= packageIndent! {
                packageIndent = indent; keyIndent = nil
                if let value = flowPath(trimmed) { result.append(value) }
                continue
            }
            if keyIndent == nil { keyIndent = indent }
            if indent == keyIndent, key(of: trimmed) == "path", let value = value(of: trimmed), !value.isEmpty {
                result.append(value)
            }
        }
        return result
    }

    /// Whether the package is a pub workspace member (`resolution: workspace`); its packages resolve in the workspace root.
    public static func usesWorkspaceResolution(yaml: String) -> Bool {
        yaml.split(separator: "\n").contains { rawLine in
            guard !rawLine.hasPrefix(" ") else { return false }
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            return key(of: line) == "resolution" && value(of: line) == "workspace"
        }
    }

    /// The key of a `key: value` or `key:` line.
    private static func key(of trimmedLine: String) -> String? {
        guard let colon = trimmedLine.firstIndex(of: ":") else { return nil }
        return unquote(String(trimmedLine[..<colon]))
    }

    /// The value of a `key: value` line, unquoted.
    private static func value(of trimmedLine: String) -> String? {
        guard let colon = trimmedLine.firstIndex(of: ":") else { return nil }
        return unquote(String(trimmedLine[trimmedLine.index(after: colon)...]))
    }

    /// `ui: {path: ../ui}` → `../ui`; only a top-level `path` of the flow mapping (not one nested in `git: {…}`).
    private static func flowPath(_ trimmedLine: String) -> String? {
        guard let open = trimmedLine.firstIndex(of: "{"), let close = trimmedLine.lastIndex(of: "}"), open < close else { return nil }
        let body = trimmedLine[trimmedLine.index(after: open)..<close]
        guard !body.contains("{") else { return nil }
        for entry in body.split(separator: ",") {
            let pair = entry.trimmingCharacters(in: .whitespaces)
            if key(of: pair) == "path", let value = value(of: pair), !value.isEmpty { return value }
        }
        return nil
    }

    /// Drops a YAML comment: `#` at the start or after whitespace, outside quotes.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for (offset, c) in line.enumerated() {
            if let q = quote { if c == q { quote = nil } }
            else if c == "\"" || c == "'" { quote = c }
            else if c == "#", previous == " " || previous == "\t" { return String(line.prefix(offset)) }
            previous = c
        }
        return line
    }

    private static func unquote(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
}
