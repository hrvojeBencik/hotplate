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
}
