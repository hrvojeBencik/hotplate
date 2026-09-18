/// Decides whether a changed path should trigger a hot reload.
public enum DartChangeFilter {
    public static func isRelevant(_ path: String) -> Bool {
        guard path.hasSuffix(".dart") else { return false }
        let components = path.split(separator: "/")
        guard let file = components.last, !file.hasPrefix(".") else { return false }
        let ignoredDirs: Set<Substring> = [".dart_tool", "build", ".git", ".idea", "node_modules"]
        return !components.dropLast().contains { ignoredDirs.contains($0) }
    }
}
