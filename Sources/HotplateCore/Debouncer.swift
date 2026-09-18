import Foundation

/// Coalesces a burst of `trigger()` calls into a single `action` invocation
/// that fires `interval` seconds after the last trigger.
public final class Debouncer: @unchecked Sendable {
    private let interval: TimeInterval
    private let queue: DispatchQueue
    private let action: () -> Void
    private var work: DispatchWorkItem?
    private let lock = NSLock()

    public init(interval: TimeInterval, queue: DispatchQueue = .main, action: @escaping () -> Void) {
        self.interval = interval; self.queue = queue; self.action = action
    }

    public func trigger() {
        lock.lock(); defer { lock.unlock() }
        work?.cancel()
        let item = DispatchWorkItem { [action] in action() }
        work = item
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        work?.cancel(); work = nil
    }
}
