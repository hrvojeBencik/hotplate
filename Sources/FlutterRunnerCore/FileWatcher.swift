import Foundation
import CoreServices

/// Watches a directory tree with FSEvents and reports changed `.dart` files.
public final class FileWatcher: @unchecked Sendable {
    private let path: String
    private let latency: TimeInterval
    private let onChange: ([String]) -> Void
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "FlutterRunner.FileWatcher")

    public init(path: String, latency: TimeInterval = 0.1, onChange: @escaping ([String]) -> Void) {
        self.path = path; self.latency = latency; self.onChange = onChange
    }

    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, fileWatcherCallback, &context, [path] as CFArray,
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
        let relevant = paths.filter(DartChangeFilter.isRelevant)
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
