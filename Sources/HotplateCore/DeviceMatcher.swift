import Foundation

public enum DeviceMatch: Equatable, Sendable {
    case one(FlutterDevice)
    case many([FlutterDevice])
    case none
}

/// Resolves `--device <query>`: exact id, then exact name, then part of the name or id (case-insensitive).
public enum DeviceMatcher {
    public static func match(query: String, in devices: [FlutterDevice]) -> DeviceMatch {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return .none }
        if let exact = devices.first(where: { $0.id == q }) { return .one(exact) }
        let byName = devices.filter { $0.name.caseInsensitiveCompare(q) == .orderedSame }
        if byName.count == 1 { return .one(byName[0]) }
        if byName.count > 1 { return .many(byName) }
        let partial = devices.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
        switch partial.count {
        case 0: return .none
        case 1: return .one(partial[0])
        default: return .many(partial)
        }
    }
}
