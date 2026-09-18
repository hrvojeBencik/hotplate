import Foundation

/// One VSCode (Dart-Code) launch configuration, reduced to what `flutter run` needs.
public struct LaunchConfig: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let program: String?
    public let args: [String]
    public let toolArgs: [String]
    public let flutterMode: String?
    public let deviceId: String?

    public init(name: String, program: String? = nil, args: [String] = [], toolArgs: [String] = [], flutterMode: String? = nil, deviceId: String? = nil) {
        self.name = name; self.program = program; self.args = args; self.toolArgs = toolArgs; self.flutterMode = flutterMode; self.deviceId = deviceId
    }

    /// Arguments to append to `flutter run --machine -d <device>`.
    public var flutterRunArguments: [String] {
        var out = toolArgs
        if let program, program != "lib/main.dart", !Self.hasTarget(args), !Self.hasTarget(toolArgs) {
            out += ["-t", program]
        }
        out += args
        switch flutterMode?.lowercased() {
        case "profile": out.append("--profile")
        case "release": out.append("--release")
        default: break
        }
        return out
    }

    private static func hasTarget(_ args: [String]) -> Bool {
        args.contains { $0 == "-t" || $0 == "--target" || $0.hasPrefix("--target=") || $0.hasPrefix("-t=") }
    }
}

public enum LaunchConfigReader {
    /// Reads `<project>/.vscode/launch.json`; returns an empty list if missing or unparsable.
    public static func load(projectPath: String) -> [LaunchConfig] {
        let file = (projectPath as NSString).appendingPathComponent(".vscode/launch.json")
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        return (try? parse(jsonc: text)) ?? []
    }

    /// Parses launch.json content. Tolerates `//` and `/* */` comments and trailing commas.
    public static func parse(jsonc: String) throws -> [LaunchConfig] {
        let data = Data(stripJSONC(jsonc).utf8)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configs = root["configurations"] as? [[String: Any]] else { return [] }
        return configs.compactMap { c in
            guard let name = c["name"] as? String,
                  (c["type"] as? String)?.lowercased() == "dart",
                  (c["request"] as? String ?? "launch").lowercased() == "launch" else { return nil }
            return LaunchConfig(
                name: name,
                program: c["program"] as? String,
                args: c["args"] as? [String] ?? [],
                toolArgs: c["toolArgs"] as? [String] ?? [],
                flutterMode: c["flutterMode"] as? String,
                deviceId: c["deviceId"] as? String
            )
        }
    }

    /// Removes comments and trailing commas outside of string literals.
    static func stripJSONC(_ input: String) -> String {
        var out = ""
        let chars = Array(input)
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1; continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2; continue
            }
            if c == "," {
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" { i += 1; continue }
            }
            out.append(c); i += 1
        }
        return out
    }
}
