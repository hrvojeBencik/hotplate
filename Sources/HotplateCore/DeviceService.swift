import Foundation

/// Wraps `flutter devices --machine`.
public struct DeviceService: Sendable {
    public let flutterPath: String
    public let environment: [String: String]

    public init(flutterPath: String, environment: [String: String]) { self.flutterPath = flutterPath; self.environment = environment }

    public func listDevices(projectPath: String?) async throws -> [FlutterDevice] {
        let out = try await ProcessRunner.run(executable: flutterPath, arguments: ["devices", "--machine"],
                                              currentDirectory: projectPath, environment: environment, timeout: 60)
        do { return try FlutterDevice.decodeList(from: out.stdout) }
        catch { throw RunnerError.processFailed("flutter devices failed: \(out.stderrText.isEmpty ? out.stdoutText : out.stderrText)") }
    }
}
