import Foundation
import CoreServices

/// Watches directory trees with FSEvents and reports changed files that pass `isRelevant`.
public final class FileWatcher: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    private let isRelevant: (String) -> Bool
    private let onChange: ([String]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "Hotplate.FileWatcher")

    public init(paths: [String], latency: TimeInterval = 0.1, isRelevant: @escaping (String) -> Bool = { DartChangeFilter.isRelevant($0) },
                onChange: @escaping ([String]) -> Void) {
        self.paths = paths; self.latency = latency; self.isRelevant = isRelevant; self.onChange = onChange
    }

    /// Watches one folder for `.dart` changes.
    public convenience init(path: String, latency: TimeInterval = 0.1, onChange: @escaping ([String]) -> Void) {
        self.init(paths: [path], latency: latency, onChange: onChange)
    }

    /// Watches a project and its local packages for the `.dart` changes that can affect the app.
    public convenience init(scope: WatchScope, latency: TimeInterval = 0.1, onChange: @escaping ([String]) -> Void) {
        self.init(paths: scope.watchedPaths, latency: latency, isRelevant: scope.isRelevant, onChange: onChange)
    }

    public func start() {
        guard stream == nil, !paths.isEmpty else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, fileWatcherCallback, &context, paths as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        stream = nil
    }

    fileprivate func handle(_ paths: [String]) {
        let relevant = paths.filter(isRelevant)
        if !relevant.isEmpty { onChange(relevant) }
    }

    deinit { stop() }
}

private let fileWatcherCallback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
    guard let info else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    watcher.handle(paths)
}
