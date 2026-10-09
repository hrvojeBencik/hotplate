import Foundation

/// Finds the Flutter project that contains a path, walking up like git looks for `.git`.
public enum ProjectLocator {
    public static func find(from path: String) -> String? {
        var dir = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), !isDir.boolValue {
            dir = (dir as NSString).deletingLastPathComponent
        }
        while true {
            if (try? Project.load(path: dir)) != nil { return dir }
            if dir == "/" || dir.isEmpty { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }
}
