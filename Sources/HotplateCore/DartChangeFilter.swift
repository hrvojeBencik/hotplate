/// Decides whether a changed path should trigger a hot reload.
public enum DartChangeFilter {
    /// Without knowing the package root: any `.dart` file outside tool, build and VCS folders.
    public static func isRelevant(_ path: String) -> Bool {
        guard path.hasSuffix(".dart") else { return false }
        let components = path.split(separator: "/")
        guard let file = components.last, !file.hasPrefix(".") else { return false }
        let ignoredDirs: Set<Substring> = [".dart_tool", "build", ".git", ".idea", "node_modules"]
        return !components.dropLast().contains { ignoredDirs.contains($0) }
    }

    /// Top-level folders of a package that the running app never loads: tests, example apps, platform projects.
    public static let ignoredAtPackageRoot: Set<Substring> = [
        "test", "integration_test", "test_driver", "example", "android", "ios", "macos", "linux", "windows", "web",
    ]
    /// Folders skipped at any depth: build output and JavaScript dependencies.
    public static let ignoredAnywhere: Set<Substring> = ["build", "node_modules"]

    /// `relativePath` is relative to the root of the package holding it (the project or a local package). Any `.dart`
    /// file counts except in hidden files and folders (`.dart_tool`, `.git`, `.fvm`, …), `ignoredAnywhere`, and
    /// `ignoredAtPackageRoot` directly under the package root.
    public static func isRelevant(relativePath: String) -> Bool {
        guard relativePath.hasSuffix(".dart") else { return false }
        let components = relativePath.split(separator: "/")
        guard !components.isEmpty, !components.contains(where: { $0.hasPrefix(".") }) else { return false }
        let folders = components.dropLast()
        if let top = folders.first, ignoredAtPackageRoot.contains(top) { return false }
        return !folders.contains { ignoredAnywhere.contains($0) }
    }
}
