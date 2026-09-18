import Foundation

/// One line of the `flutter run --machine` protocol, decoded.
public enum DaemonMessage {
    case event(name: String, params: [String: Any])
    case response(id: Int, result: Any?, error: String?)
}

public enum DaemonProtocol {
    /// Parses a single stdout line. Returns nil for anything that is not a
    /// `[{...}]` JSON envelope (Flutter prints plain text too).
    public static func parseLine(_ line: String) -> DaemonMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), let data = trimmed.data(using: .utf8) else { return nil }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let obj = array.first else { return nil }
        if let event = obj["event"] as? String {
            return .event(name: event, params: obj["params"] as? [String: Any] ?? [:])
        }
        if let id = obj["id"] as? Int {
            let error: String?
            if let s = obj["error"] as? String { error = s }
            else if let e = obj["error"] { error = String(describing: e) }
            else { error = nil }
            return .response(id: id, result: obj["result"], error: error)
        }
        return nil
    }

    /// Encodes a command as a single line (with trailing newline) for stdin.
    public static func encodeCommand(id: Int, method: String, params: [String: Any]? = nil) -> String {
        var obj: [String: Any] = ["id": id, "method": method]
        if let params { obj["params"] = params }
        let data = (try? JSONSerialization.data(withJSONObject: [obj], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
