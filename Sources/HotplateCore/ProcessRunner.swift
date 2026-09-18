import Foundation

public struct ProcessOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let status: Int32
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Runs a process to completion, capturing output, with a hard timeout.
public enum ProcessRunner {
    public static func run(executable: String, arguments: [String], currentDirectory: String? = nil,
                           environment: [String: String]? = nil, timeout: TimeInterval = 30) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory) }
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out; process.standardError = err; process.standardInput = FileHandle.nullDevice

        return try await withCheckedThrowingContinuation { cont in
            let lock = NSLock(); var didTimeout = false
            process.terminationHandler = { p in
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                lock.lock(); let t = didTimeout; lock.unlock()
                if t { cont.resume(throwing: RunnerError.timeout("\(executable) \(arguments.joined(separator: " "))")) }
                else { cont.resume(returning: ProcessOutput(stdout: o, stderr: e, status: p.terminationStatus)) }
            }
            do { try process.run() } catch { cont.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { lock.lock(); didTimeout = true; lock.unlock(); process.terminate() }
            }
        }
    }
}
