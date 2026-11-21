import Foundation

/// Where saved `.dart` files can change the running app: the whole project folder (not only `lib/`, so folders like
/// `ui/` imported with relative paths count) plus the local packages it uses through `path:` dependencies, which may
/// live outside the project. Which files count is decided relative to the package that holds them; see
/// `DartChangeFilter.isRelevant(relativePath:)`.
public struct WatchScope: Equatable, Sendable {
    /// The project folder, symlinks resolved.
    public let projectPath: String
    /// Package folders, the project first, symlinks resolved, without duplicates.
    public let packageRoots: [String]

    public init(projectPath: String, packageRoots: [String] = []) {
        let project = Self.canonical(projectPath)
        var seen: Set<String> = []
        self.projectPath = project
        self.packageRoots = ([project] + packageRoots.map(Self.canonical)).filter { seen.insert($0).inserted }
    }

    /// The folders to watch: package roots that are not inside another one.
    public var watchedPaths: [String] {
        packageRoots.filter { root in !packageRoots.contains { $0 != root && Self.isInside(root, $0) } }
    }

    /// Folder names of the local packages (everything but the project).
    public var localPackages: [String] { packageRoots.dropFirst().map { ($0 as NSString).lastPathComponent } }

    /// Whether a change to `path` (absolute) should trigger a hot reload.
    public func isRelevant(_ path: String) -> Bool {
        guard path.hasSuffix(".dart"), let (_, relative) = locate(path) else { return false }
        return DartChangeFilter.isRelevant(relativePath: relative)
    }

    /// `path` as shown in the log: relative to the project, or `<package folder>/…` for a package outside it.
    public func displayPath(_ path: String) -> String {
        guard let (root, relative) = locate(path) else { return path }
        if root == projectPath || Self.isInside(root, projectPath) {
            return String((root + "/" + relative).dropFirst(projectPath.count + 1))
        }
        return (root as NSString).lastPathComponent + "/" + relative
    }

    /// The deepest package root holding `path`, and `path` relative to it.
    private func locate(_ path: String) -> (root: String, relative: String)? {
        func find(_ p: String) -> (String, String)? {
            guard let root = packageRoots.filter({ Self.isInside(p, $0) }).max(by: { $0.count < $1.count }) else { return nil }
            return (root, String(p.dropFirst(root.count + 1)))
        }
        // FSEvents reports resolved paths; other callers may not (/var vs /private/var), so retry resolved.
        return find(path) ?? find(Self.canonical(path))
    }

    /// Whether `path` is strictly inside the folder `root`.
    static func isInside(_ path: String, _ root: String) -> Bool {
        path.count > root.count + 1 && path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    /// `path` standardized with symlinks resolved, as FSEvents reports it (`/private/var/…`). Parts that do not exist
    /// (a file deleted since) are kept as written below the deepest folder that does.
    static func canonical(_ path: String) -> String {
        var head = (path as NSString).standardizingPath
        var tail: [String] = []
        while !head.isEmpty {
            if let resolved = realpath(head, nil) {
                defer { free(resolved) }
                return ([String(cString: resolved)] + tail.reversed()).joined(separator: "/")
                    .replacingOccurrences(of: "//", with: "/")
            }
            guard head != "/" else { break }
            tail.append((head as NSString).lastPathComponent)
            head = (head as NSString).deletingLastPathComponent
        }
        return (path as NSString).standardizingPath
    }

    // MARK: Discovery

    /// The project at `path` and its local packages, read from `pubspec.yaml` (`path:` dependencies) and
    /// `.dart_tool/package_config.json` (packages with a relative root, which includes local packages of local
    /// packages and pub workspace members). Folders that do not exist are left out.
    public static func forProject(at path: String) -> WatchScope {
        let fm = FileManager.default
        let project = (path as NSString).standardizingPath
        var roots: [String] = []
        let yaml = try? String(contentsOfFile: (project as NSString).appendingPathComponent("pubspec.yaml"), encoding: .utf8)
        if let yaml {
            roots += PubspecReader.pathDependencies(fromYaml: yaml).map {
                $0.hasPrefix("/") ? $0 : (project as NSString).appendingPathComponent($0)
            }
        }
        if let config = packageConfig(for: project, workspaceMember: yaml.map(PubspecReader.usesWorkspaceResolution) ?? false) {
            roots += localPackageRoots(fromPackageConfig: config)
        }
        let existing = roots.filter { var isDir: ObjCBool = false; return fm.fileExists(atPath: $0, isDirectory: &isDir) && isDir.boolValue }
        return WatchScope(projectPath: project, packageRoots: existing)
    }

    /// The project's `package_config.json`; a pub workspace member's lives in the workspace root above it.
    private static func packageConfig(for project: String, workspaceMember: Bool) -> URL? {
        var dir = URL(fileURLWithPath: project, isDirectory: true)
        for _ in 0..<(workspaceMember ? 16 : 1) {
            let candidate = dir.appendingPathComponent(".dart_tool/package_config.json")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    /// Roots of packages with a relative `rootUri`: those are local. Hosted, git and SDK packages have absolute ones.
    static func localPackageRoots(fromPackageConfig url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let packages = json["packages"] as? [[String: Any]] else { return [] }
        let base = url.deletingLastPathComponent()
        return packages.compactMap { package in
            guard let rootUri = package["rootUri"] as? String, let uri = URL(string: rootUri), uri.scheme == nil,
                  let root = URL(string: rootUri, relativeTo: base) else { return nil }
            return root.standardizedFileURL.path
        }
    }
}
