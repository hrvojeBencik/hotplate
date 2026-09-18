import Foundation

/// Events emitted by a running `flutter run --machine` process.
public enum DaemonEvent: Sendable {
    case connected
    case daemonLog(level: String, message: String)
    case appStarting(appId: String, deviceId: String, supportsRestart: Bool)
    case appStarted
    case progress(message: String?, finished: Bool)
    case appLog(String, isError: Bool)
    case rawOutput(String, isStderr: Bool)
    case webLaunchUrl(String)
    case appStopped
    case processExited(code: Int32)
}

public struct RestartResult: Sendable {
    public let code: Int
    public let message: String
}

/// Owns one `flutter run --machine` process and speaks its JSON protocol.
public final class FlutterDaemon: @unchecked Sendable {
    public let events: AsyncStream<DaemonEvent>
    private let continuation: AsyncStream<DaemonEvent>.Continuation
    private let process = Process()
    private let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    private let lock = NSLock()
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<Any?, Error>] = [:]
    private var stdoutBuffer = Data(), stderrBuffer = Data()
    private var _appId: String?
    private var stopRequested = false
    private var exited = false

    public var appId: String? { lock.lock(); defer { lock.unlock() }; return _appId }
    public var isRunning: Bool { process.isRunning }
    public var wasStopRequested: Bool { lock.lock(); defer { lock.unlock() }; return stopRequested }

    public init(flutterPath: String, projectPath: String, deviceId: String, extraArgs: [String], environment: [String: String]) {
        var cont: AsyncStream<DaemonEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        continuation = cont
        process.executableURL = URL(fileURLWithPath: flutterPath)
        process.arguments = ["run", "--machine", "-d", deviceId] + extraArgs
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
    }

    public func start() throws {
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.consume(h.availableData, stderr: false) }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] h in self?.consume(h.availableData, stderr: true) }
        process.terminationHandler = { [weak self] p in self?.handleExit(p.terminationStatus) }
        try process.run()
    }

    // MARK: Reading

    private func consume(_ data: Data, stderr: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        if stderr { stderrBuffer.append(data) } else { stdoutBuffer.append(data) }
        var lines: [String] = []
        var rest = stderr ? stderrBuffer : stdoutBuffer
        while let nl = rest.firstIndex(of: 0x0A) {
            lines.append(String(decoding: rest[rest.startIndex..<nl], as: UTF8.self))
            rest = rest[rest.index(after: nl)...]
        }
        if stderr { stderrBuffer = Data(rest) } else { stdoutBuffer = Data(rest) }
        lock.unlock()
        for line in lines { handleLine(line, stderr: stderr) }
    }

    private func handleLine(_ line: String, stderr: Bool) {
        guard !stderr, let message = DaemonProtocol.parseLine(line) else {
            let t = line.trimmingCharacters(in: .newlines)
            if !t.isEmpty { continuation.yield(.rawOutput(t, isStderr: stderr)) }
            return
        }
        switch message {
        case let .response(id, result, error):
            lock.lock(); let cont = pending.removeValue(forKey: id); lock.unlock()
            if let error { cont?.resume(throwing: RunnerError.processFailed(error)) } else { cont?.resume(returning: result) }
        case let .event(name, params):
            switch name {
            case "daemon.connected": continuation.yield(.connected)
            case "daemon.logMessage":
                continuation.yield(.daemonLog(level: params["level"] as? String ?? "info", message: params["message"] as? String ?? ""))
            case "app.start":
                let id = params["appId"] as? String ?? ""
                lock.lock(); _appId = id; lock.unlock()
                continuation.yield(.appStarting(appId: id, deviceId: params["deviceId"] as? String ?? "",
                                                supportsRestart: params["supportsRestart"] as? Bool ?? true))
            case "app.started": continuation.yield(.appStarted)
            case "app.progress":
                continuation.yield(.progress(message: params["message"] as? String, finished: params["finished"] as? Bool ?? false))
            case "app.log": continuation.yield(.appLog(params["log"] as? String ?? "", isError: params["error"] as? Bool ?? false))
            case "app.webLaunchUrl": if let u = params["url"] as? String { continuation.yield(.webLaunchUrl(u)) }
            case "app.stop": continuation.yield(.appStopped)
            default: break
            }
        }
    }

    // MARK: Commands

    private func send(method: String, params: [String: Any]) async throws -> Any? {
        guard process.isRunning else { throw RunnerError.processFailed("flutter is not running") }
        let id: Int
        lock.lock(); id = nextId; nextId += 1; lock.unlock()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Any?, Error>) in
            lock.lock(); pending[id] = cont; lock.unlock()
            let line = DaemonProtocol.encodeCommand(id: id, method: method, params: params)
            do { try stdinPipe.fileHandleForWriting.write(contentsOf: Data(line.utf8)) }
            catch {
                lock.lock(); let c = pending.removeValue(forKey: id); lock.unlock()
                c?.resume(throwing: error)
            }
        }
    }

    public func restart(full: Bool) async throws -> RestartResult {
        guard let appId else { throw RunnerError.processFailed("App has not started yet") }
        let result = try await send(method: "app.restart", params: ["appId": appId, "fullRestart": full, "reason": "manual", "pause": false])
        let dict = result as? [String: Any] ?? [:]
        return RestartResult(code: dict["code"] as? Int ?? 0, message: dict["message"] as? String ?? "")
    }

    public func stop() async {
        lock.lock(); stopRequested = true; lock.unlock()
        guard process.isRunning else { return }
        if let appId {
            _ = try? await withTimeout(seconds: 5) { try await self.send(method: "app.stop", params: ["appId": appId]) }
        }
        for _ in 0..<50 where process.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
        if process.isRunning { process.terminate() }
        for _ in 0..<20 where process.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        // Wait for the termination handler so callers observe a consistent state.
        for _ in 0..<50 where !hasExited { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    private var hasExited: Bool { lock.lock(); defer { lock.unlock() }; return exited }

    private func handleExit(_ code: Int32) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        consume(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), stderr: false)
        consume(stderrPipe.fileHandleForReading.readDataToEndOfFile(), stderr: true)
        lock.lock(); let leftovers = pending; pending = [:]; lock.unlock()
        for (_, c) in leftovers { c.resume(throwing: RunnerError.processFailed("flutter exited with code \(code)")) }
        continuation.yield(.processExited(code: code))
        continuation.finish()
        lock.lock(); exited = true; lock.unlock()
    }

    private func withTimeout<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask { try await Task.sleep(nanoseconds: UInt64(seconds * 1e9)); throw RunnerError.timeout("daemon command") }
            let r = try await group.next()!
            group.cancelAll()
            return r
        }
    }
}
