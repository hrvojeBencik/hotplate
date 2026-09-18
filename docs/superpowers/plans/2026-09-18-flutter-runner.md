# FlutterRunner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS app that runs a Flutter project via `flutter run --machine`, offers Run/Stop/Hot Reload/Hot Restart, auto hot-reloads on `.dart` file saves, shows logs, and lives in the menu bar.

**Architecture:** Swift Package with two targets: `FlutterRunnerCore` (pure logic + process/FSEvents wrappers, unit-tested) and `FlutterRunner` (SwiftUI app: view model, windows, menu bar). A shell script assembles the `.app` bundle and zip for distribution.

**Tech Stack:** Swift 5.9 tools-version, SwiftUI, Observation framework, Foundation `Process`, FSEvents, XCTest. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-09-18-flutter-runner-design.md`

## Global Constraints

- Minimum macOS 14 (Sonoma). `platforms: [.macOS(.v14)]`.
- No App Sandbox. No third-party packages.
- Flutter daemon protocol: every stdin/stdout line is a JSON array containing one object.
- Debounce for file changes: 300 ms default, configurable.
- Log buffer capped at 5000 lines.
- Recent projects capped at 10.
- Tests run with `swift test` from the repo root.

---

## File Structure

```
Package.swift
Sources/FlutterRunnerCore/
  DaemonProtocol.swift      # parse/encode daemon JSON lines
  ArgumentSplitter.swift    # split extra args string honoring quotes
  Debouncer.swift           # coalesce bursts of events
  DartChangeFilter.swift    # which changed paths trigger reload
  PubspecReader.swift       # project name from pubspec.yaml
  Models.swift              # FlutterDevice, Project, errors
  ProcessRunner.swift       # run a process to completion with timeout
  FlutterLocator.swift      # find flutter binary + login-shell PATH
  DeviceService.swift       # flutter devices --machine
  FlutterDaemon.swift       # flutter run --machine lifecycle
  FileWatcher.swift         # FSEvents wrapper
Sources/FlutterRunner/
  FlutterRunnerApp.swift    # @main, scenes, commands
  AppDelegate.swift         # quit handling
  ProjectStore.swift        # UserDefaults persistence
  SessionViewModel.swift    # state machine tying everything together
  MainWindow.swift          # toolbar + log view
  LogView.swift
  MenuBarMenu.swift
  SettingsView.swift
Tests/FlutterRunnerCoreTests/
  DaemonProtocolTests.swift
  ArgumentSplitterTests.swift
  DebouncerTests.swift
  DartChangeFilterTests.swift
  PubspecReaderTests.swift
  ModelsTests.swift
Resources/Info.plist
Resources/README-dist.txt
scripts/build_app.sh
scripts/make_icon.swift
```

---

### Task 1: Package skeleton + DaemonProtocol

**Files:**
- Create: `Package.swift`
- Create: `Sources/FlutterRunnerCore/DaemonProtocol.swift`
- Create: `Sources/FlutterRunner/main.swift` (temporary placeholder so the package builds; replaced in Task 8)
- Test: `Tests/FlutterRunnerCoreTests/DaemonProtocolTests.swift`

**Interfaces:**
- Produces: `enum DaemonMessage { case event(name: String, params: [String: Any]); case response(id: Int, result: Any?, error: String?) }`
- Produces: `DaemonProtocol.parseLine(_:) -> DaemonMessage?`, `DaemonProtocol.encodeCommand(id:method:params:) -> String`

- [ ] **Step 1: Create Package.swift and placeholder main**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlutterRunner",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FlutterRunnerCore"),
        .executableTarget(name: "FlutterRunner", dependencies: ["FlutterRunnerCore"]),
        .testTarget(name: "FlutterRunnerCoreTests", dependencies: ["FlutterRunnerCore"]),
    ]
)
```

`Sources/FlutterRunner/main.swift`:
```swift
print("placeholder")
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import FlutterRunnerCore

final class DaemonProtocolTests: XCTestCase {
    func testParsesEvent() throws {
        let line = #"[{"event":"app.start","params":{"appId":"abc","deviceId":"chrome","supportsRestart":true}}]"#
        guard case let .event(name, params)? = DaemonProtocol.parseLine(line) else { return XCTFail("expected event") }
        XCTAssertEqual(name, "app.start")
        XCTAssertEqual(params["appId"] as? String, "abc")
        XCTAssertEqual(params["supportsRestart"] as? Bool, true)
    }

    func testParsesResponseWithResult() throws {
        let line = #"[{"id":3,"result":{"code":0,"message":"ok"}}]"#
        guard case let .response(id, result, error)? = DaemonProtocol.parseLine(line) else { return XCTFail() }
        XCTAssertEqual(id, 3)
        XCTAssertNil(error)
        XCTAssertEqual((result as? [String: Any])?["code"] as? Int, 0)
    }

    func testParsesResponseWithError() throws {
        let line = #"[{"id":4,"error":"boom"}]"#
        guard case let .response(id, _, error)? = DaemonProtocol.parseLine(line) else { return XCTFail() }
        XCTAssertEqual(id, 4)
        XCTAssertEqual(error, "boom")
    }

    func testParsesResponseWithoutResult() throws {
        guard case let .response(id, result, error)? = DaemonProtocol.parseLine(#"[{"id":2}]"#) else { return XCTFail() }
        XCTAssertEqual(id, 2); XCTAssertNil(result); XCTAssertNil(error)
    }

    func testNonJsonReturnsNil() {
        XCTAssertNil(DaemonProtocol.parseLine("Launching lib/main.dart on Chrome in debug mode..."))
        XCTAssertNil(DaemonProtocol.parseLine(""))
        XCTAssertNil(DaemonProtocol.parseLine("[not json]"))
    }

    func testEncodeCommand() {
        let s = DaemonProtocol.encodeCommand(id: 1, method: "app.restart", params: ["appId": "x", "fullRestart": false])
        XCTAssertEqual(s, #"[{"id":1,"method":"app.restart","params":{"appId":"x","fullRestart":false}}]"# + "\n")
    }

    func testEncodeCommandWithoutParams() {
        XCTAssertEqual(DaemonProtocol.encodeCommand(id: 7, method: "daemon.shutdown"), #"[{"id":7,"method":"daemon.shutdown"}]"# + "\n")
    }
}
```

- [ ] **Step 3: Run tests, expect compile failure** — `swift test 2>&1 | tail -5`

- [ ] **Step 4: Implement**

```swift
import Foundation

public enum DaemonMessage {
    case event(name: String, params: [String: Any])
    case response(id: Int, result: Any?, error: String?)
}

public enum DaemonProtocol {
    public static func parseLine(_ line: String) -> DaemonMessage? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), let data = trimmed.data(using: .utf8) else { return nil }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let obj = array.first else { return nil }
        if let event = obj["event"] as? String {
            return .event(name: event, params: obj["params"] as? [String: Any] ?? [:])
        }
        if let id = obj["id"] as? Int {
            let error: String?
            if let s = obj["error"] as? String { error = s }
            else if let e = obj["error"] { error = String(describing: e) }
            else { error = nil }
            return .response(id: id, result: obj["result"], error: error)
        }
        return nil
    }

    public static func encodeCommand(id: Int, method: String, params: [String: Any]? = nil) -> String {
        var obj: [String: Any] = ["id": id, "method": method]
        if let params { obj["params"] = params }
        let data = (try? JSONSerialization.data(withJSONObject: [obj], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
```

- [ ] **Step 5: Run tests, expect PASS** — `swift test 2>&1 | tail -5`
- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: package skeleton and daemon protocol parser"`

---

### Task 2: ArgumentSplitter, DartChangeFilter, PubspecReader

**Files:**
- Create: `Sources/FlutterRunnerCore/ArgumentSplitter.swift`, `DartChangeFilter.swift`, `PubspecReader.swift`
- Test: `Tests/FlutterRunnerCoreTests/ArgumentSplitterTests.swift`, `DartChangeFilterTests.swift`, `PubspecReaderTests.swift`

**Interfaces:**
- Produces: `ArgumentSplitter.split(_ input: String) -> [String]`
- Produces: `DartChangeFilter.isRelevant(_ path: String) -> Bool`
- Produces: `PubspecReader.name(fromYaml: String) -> String?`, `PubspecReader.isFlutterProject(yaml:) -> Bool`

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import FlutterRunnerCore

final class ArgumentSplitterTests: XCTestCase {
    func testEmpty() { XCTAssertEqual(ArgumentSplitter.split(""), []); XCTAssertEqual(ArgumentSplitter.split("   "), []) }
    func testSimple() {
        XCTAssertEqual(ArgumentSplitter.split("--flavor dev -t lib/main_dev.dart"), ["--flavor", "dev", "-t", "lib/main_dev.dart"])
    }
    func testDoubleQuotes() {
        XCTAssertEqual(ArgumentSplitter.split(#"--dart-define="API=a b" x"#), ["--dart-define=API=a b", "x"])
    }
    func testSingleQuotes() { XCTAssertEqual(ArgumentSplitter.split("'a b' c"), ["a b", "c"]) }
    func testEscapedSpace() { XCTAssertEqual(ArgumentSplitter.split(#"a\ b c"#), ["a b", "c"]) }
}

final class DartChangeFilterTests: XCTestCase {
    func testDartInLib() { XCTAssertTrue(DartChangeFilter.isRelevant("/p/lib/main.dart")) }
    func testNonDart() { XCTAssertFalse(DartChangeFilter.isRelevant("/p/lib/notes.txt")) }
    func testDartTool() { XCTAssertFalse(DartChangeFilter.isRelevant("/p/.dart_tool/x/y.dart")) }
    func testBuildDir() { XCTAssertFalse(DartChangeFilter.isRelevant("/p/build/gen.dart")) }
    func testTempFiles() {
        XCTAssertFalse(DartChangeFilter.isRelevant("/p/lib/main.dart.swp"))
        XCTAssertFalse(DartChangeFilter.isRelevant("/p/lib/.main.dart.tmp"))
    }
}

final class PubspecReaderTests: XCTestCase {
    let yaml = """
    name: usput
    description: A demo.
    dependencies:
      flutter:
        sdk: flutter
    """
    func testName() { XCTAssertEqual(PubspecReader.name(fromYaml: yaml), "usput") }
    func testQuotedName() { XCTAssertEqual(PubspecReader.name(fromYaml: "name: \"my_app\"\n"), "my_app") }
    func testMissingName() { XCTAssertNil(PubspecReader.name(fromYaml: "description: x\n")) }
    func testIsFlutter() { XCTAssertTrue(PubspecReader.isFlutterProject(yaml: yaml)) }
    func testIsNotFlutter() { XCTAssertFalse(PubspecReader.isFlutterProject(yaml: "name: cli\ndependencies:\n  args: ^2.0.0\n")) }
}
```

- [ ] **Step 2: Run, expect compile failure**
- [ ] **Step 3: Implement**

`ArgumentSplitter.swift`:
```swift
public enum ArgumentSplitter {
    public static func split(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuote: Character? = nil
        var hasToken = false
        var escape = false
        for ch in input {
            if escape { current.append(ch); escape = false; hasToken = true; continue }
            if ch == "\\" && inQuote != "'" { escape = true; continue }
            if let q = inQuote {
                if ch == q { inQuote = nil } else { current.append(ch) }
                continue
            }
            if ch == "\"" || ch == "'" { inQuote = ch; hasToken = true; continue }
            if ch.isWhitespace {
                if hasToken { result.append(current); current = ""; hasToken = false }
                continue
            }
            current.append(ch); hasToken = true
        }
        if hasToken { result.append(current) }
        return result
    }
}
```

`DartChangeFilter.swift`:
```swift
public enum DartChangeFilter {
    public static func isRelevant(_ path: String) -> Bool {
        guard path.hasSuffix(".dart") else { return false }
        let components = path.split(separator: "/")
        guard let file = components.last, !file.hasPrefix(".") else { return false }
        let ignoredDirs: Set<Substring> = [".dart_tool", "build", ".git", ".idea", "node_modules"]
        return !components.dropLast().contains { ignoredDirs.contains($0) }
    }
}
```

`PubspecReader.swift`:
```swift
public enum PubspecReader {
    public static func name(fromYaml yaml: String) -> String? {
        for rawLine in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("name:"), !rawLine.hasPrefix(" ") else { continue }
            var value = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]).trimmingCharacters(in: .whitespaces) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    public static func isFlutterProject(yaml: String) -> Bool {
        yaml.contains("sdk: flutter") || yaml.range(of: #"^\s*flutter:\s*$"#, options: .regularExpression) != nil
    }
}
```

- [ ] **Step 4: Run tests, expect PASS**
- [ ] **Step 5: Commit** — `git commit -am "feat: argument splitter, dart change filter, pubspec reader"`

---

### Task 3: Debouncer

**Files:**
- Create: `Sources/FlutterRunnerCore/Debouncer.swift`
- Test: `Tests/FlutterRunnerCoreTests/DebouncerTests.swift`

**Interfaces:**
- Produces: `final class Debouncer { init(interval: TimeInterval, queue: DispatchQueue = .main, action: @escaping () -> Void); func trigger(); func cancel() }`

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import FlutterRunnerCore

final class DebouncerTests: XCTestCase {
    func testBurstFiresOnce() {
        let exp = expectation(description: "fired")
        var count = 0
        let d = Debouncer(interval: 0.1, queue: DispatchQueue(label: "t")) { count += 1; exp.fulfill() }
        for _ in 0..<5 { d.trigger() }
        wait(for: [exp], timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func testSeparateBurstsFireTwice() {
        let exp = expectation(description: "fired"); exp.expectedFulfillmentCount = 2
        let d = Debouncer(interval: 0.05, queue: DispatchQueue(label: "t")) { exp.fulfill() }
        d.trigger()
        Thread.sleep(forTimeInterval: 0.2)
        d.trigger()
        wait(for: [exp], timeout: 1)
    }

    func testCancelPreventsFire() {
        let exp = expectation(description: "not fired"); exp.isInverted = true
        let d = Debouncer(interval: 0.05, queue: DispatchQueue(label: "t")) { exp.fulfill() }
        d.trigger(); d.cancel()
        wait(for: [exp], timeout: 0.3)
    }
}
```

- [ ] **Step 2: Run, expect failure**
- [ ] **Step 3: Implement**

```swift
import Foundation

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
```

- [ ] **Step 4: Run tests, expect PASS**
- [ ] **Step 5: Commit** — `git commit -am "feat: debouncer"`

---

### Task 4: Models, ProcessRunner, FlutterLocator, DeviceService

**Files:**
- Create: `Sources/FlutterRunnerCore/Models.swift`, `ProcessRunner.swift`, `FlutterLocator.swift`, `DeviceService.swift`
- Test: `Tests/FlutterRunnerCoreTests/ModelsTests.swift`

**Interfaces:**
- Produces: `struct FlutterDevice: Identifiable, Hashable, Codable { id, name, targetPlatform, emulator, isSupported }`, `FlutterDevice.decodeList(from: Data) throws -> [FlutterDevice]`
- Produces: `struct Project: Identifiable, Hashable, Codable { path, name, lastDeviceId, extraArgs, autoReload, lastOpened }`, `Project.load(path:) throws -> Project`
- Produces: `enum RunnerError: LocalizedError { case flutterNotFound, notAFlutterProject(String), timeout(String), processFailed(String) }`
- Produces: `ProcessRunner.run(executable:arguments:currentDirectory:environment:timeout:) async throws -> ProcessOutput`
- Produces: `FlutterLocator.locate(manualPath:) -> String?`, `FlutterLocator.loginShellPath() -> String`, `FlutterLocator.environment(flutterPath:) -> [String: String]`
- Produces: `DeviceService(flutterPath:environment:).listDevices(projectPath:) async throws -> [FlutterDevice]`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import FlutterRunnerCore

final class ModelsTests: XCTestCase {
    func testDecodeDevices() throws {
        let json = """
        [
          {"name":"Chrome","id":"chrome","isSupported":true,"targetPlatform":"web-javascript","emulator":false,"sdk":"x","capabilities":{"hotReload":true}},
          {"name":"Old","id":"old","isSupported":false,"targetPlatform":"android-arm","emulator":true}
        ]
        """
        let devices = try FlutterDevice.decodeList(from: Data(json.utf8))
        XCTAssertEqual(devices.map(\.id), ["chrome"])
        XCTAssertEqual(devices[0].name, "Chrome")
        XCTAssertFalse(devices[0].emulator)
    }

    func testDecodeDevicesSkipsLeadingNoise() throws {
        let json = "Some warning line\n[{\"name\":\"A\",\"id\":\"a\",\"isSupported\":true,\"targetPlatform\":\"darwin\",\"emulator\":false}]\n"
        XCTAssertEqual(try FlutterDevice.decodeList(from: Data(json.utf8)).count, 1)
    }

    func testProjectLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "name: demo_app\ndependencies:\n  flutter:\n    sdk: flutter\n".write(to: dir.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        let p = try Project.load(path: dir.path)
        XCTAssertEqual(p.name, "demo_app"); XCTAssertEqual(p.path, dir.path); XCTAssertTrue(p.autoReload)
    }

    func testProjectLoadRejectsNonFlutter() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try Project.load(path: dir.path))
    }
}
```

- [ ] **Step 2: Run, expect failure**
- [ ] **Step 3: Implement**

`Models.swift`:
```swift
import Foundation

public struct FlutterDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let targetPlatform: String
    public let emulator: Bool
    public let isSupported: Bool

    enum CodingKeys: String, CodingKey { case id, name, targetPlatform, emulator, isSupported }

    public init(id: String, name: String, targetPlatform: String, emulator: Bool, isSupported: Bool) {
        self.id = id; self.name = name; self.targetPlatform = targetPlatform; self.emulator = emulator; self.isSupported = isSupported
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        targetPlatform = try c.decodeIfPresent(String.self, forKey: .targetPlatform) ?? ""
        emulator = try c.decodeIfPresent(Bool.self, forKey: .emulator) ?? false
        isSupported = try c.decodeIfPresent(Bool.self, forKey: .isSupported) ?? true
    }

    /// Decodes `flutter devices --machine` output, tolerating non-JSON noise before the array.
    public static func decodeList(from data: Data) throws -> [FlutterDevice] {
        var text = String(decoding: data, as: UTF8.self)
        if let start = text.firstIndex(of: "[") { text = String(text[start...]) }
        if let end = text.lastIndex(of: "]") { text = String(text[...end]) }
        let all = try JSONDecoder().decode([FlutterDevice].self, from: Data(text.utf8))
        return all.filter(\.isSupported)
    }

    public var displayName: String { emulator ? "\(name) (emulator)" : name }
}

public struct Project: Identifiable, Hashable, Codable, Sendable {
    public var id: String { path }
    public let path: String
    public var name: String
    public var lastDeviceId: String?
    public var extraArgs: String
    public var autoReload: Bool
    public var lastOpened: Date

    public init(path: String, name: String, lastDeviceId: String? = nil, extraArgs: String = "", autoReload: Bool = true, lastOpened: Date = Date()) {
        self.path = path; self.name = name; self.lastDeviceId = lastDeviceId; self.extraArgs = extraArgs; self.autoReload = autoReload; self.lastOpened = lastOpened
    }

    public static func load(path: String) throws -> Project {
        let pubspec = (path as NSString).appendingPathComponent("pubspec.yaml")
        guard let yaml = try? String(contentsOfFile: pubspec, encoding: .utf8) else {
            throw RunnerError.notAFlutterProject("No pubspec.yaml in \(path)")
        }
        let hasMain = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("lib/main.dart"))
        guard PubspecReader.isFlutterProject(yaml: yaml) || hasMain else {
            throw RunnerError.notAFlutterProject("pubspec.yaml does not depend on flutter")
        }
        let name = PubspecReader.name(fromYaml: yaml) ?? (path as NSString).lastPathComponent
        return Project(path: path, name: name)
    }

    public var libPath: String { (path as NSString).appendingPathComponent("lib") }
}

public enum RunnerError: LocalizedError, Sendable {
    case flutterNotFound
    case notAFlutterProject(String)
    case timeout(String)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .flutterNotFound: return "Could not find the `flutter` executable. Set its path in Settings."
        case .notAFlutterProject(let s): return s
        case .timeout(let s): return "Timed out: \(s)"
        case .processFailed(let s): return s
        }
    }
}
```

`ProcessRunner.swift`:
```swift
import Foundation

public struct ProcessOutput: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let status: Int32
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

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
            let timedOut = NSLock(); var didTimeout = false
            process.terminationHandler = { p in
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                timedOut.lock(); let t = didTimeout; timedOut.unlock()
                if t { cont.resume(throwing: RunnerError.timeout("\(executable) \(arguments.joined(separator: " "))")) }
                else { cont.resume(returning: ProcessOutput(stdout: o, stderr: e, status: p.terminationStatus)) }
            }
            do { try process.run() } catch { cont.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { timedOut.lock(); didTimeout = true; timedOut.unlock(); process.terminate() }
            }
        }
    }
}
```

`FlutterLocator.swift`:
```swift
import Foundation

public enum FlutterLocator {
    private static let defaultPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    public static func locate(manualPath: String?) -> String? {
        let fm = FileManager.default
        if let m = manualPath?.trimmingCharacters(in: .whitespaces), !m.isEmpty {
            let candidate = m.hasSuffix("/flutter") ? m : (m as NSString).appendingPathComponent("flutter")
            if fm.isExecutableFile(atPath: candidate) { return candidate }
            if fm.isExecutableFile(atPath: (m as NSString).appendingPathComponent("bin/flutter")) { return (m as NSString).appendingPathComponent("bin/flutter") }
        }
        for dir in loginShellPath().split(separator: ":") {
            let p = "\(dir)/flutter"
            if fm.isExecutableFile(atPath: p) { return p }
        }
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Documents/flutter/bin/flutter", "\(home)/flutter/bin/flutter", "\(home)/development/flutter/bin/flutter",
            "\(home)/dev/flutter/bin/flutter", "\(home)/fvm/default/bin/flutter", "/opt/homebrew/bin/flutter",
            "/usr/local/bin/flutter", "/opt/flutter/bin/flutter",
        ]
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    private static let cachedLoginPath: String = {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "echo $PATH"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return defaultPath }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? defaultPath : s
    }()

    public static func loginShellPath() -> String { cachedLoginPath }

    public static func environment(flutterPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let flutterBin = (flutterPath as NSString).deletingLastPathComponent
        var parts = [flutterBin]
        parts += loginShellPath().split(separator: ":").map(String.init)
        parts += defaultPath.split(separator: ":").map(String.init)
        var seen = Set<String>()
        env["PATH"] = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        env["FLUTTER_SUPPRESS_ANALYTICS"] = "true"
        return env
    }
}
```

`DeviceService.swift`:
```swift
import Foundation

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
```

- [ ] **Step 4: Run tests, expect PASS**
- [ ] **Step 5: Commit** — `git commit -am "feat: models, process runner, flutter locator, device service"`

---

### Task 5: FlutterDaemon

**Files:**
- Create: `Sources/FlutterRunnerCore/FlutterDaemon.swift`
- Test: `Tests/FlutterRunnerCoreTests/FlutterDaemonTests.swift` (uses a fake `flutter` shell script)

**Interfaces:**
- Produces:
```swift
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
public struct RestartResult: Sendable { public let code: Int; public let message: String }
public final class FlutterDaemon {
    public let events: AsyncStream<DaemonEvent>
    public init(flutterPath: String, projectPath: String, deviceId: String, extraArgs: [String], environment: [String: String])
    public func start() throws
    public func restart(full: Bool) async throws -> RestartResult
    public func stop() async
    public var isRunning: Bool
}
```

- [ ] **Step 1: Failing test with a fake flutter script**

```swift
import XCTest
@testable import FlutterRunnerCore

final class FlutterDaemonTests: XCTestCase {
    /// A shell script pretending to be `flutter run --machine`.
    private func makeFakeFlutter() throws -> String {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("flutter")
        let body = #"""
        #!/bin/bash
        echo '[{"event":"daemon.connected","params":{"version":"0.6.1","pid":1}}]'
        echo 'Launching lib/main.dart on Fake in debug mode...'
        echo '[{"event":"app.start","params":{"appId":"app1","deviceId":"fake","supportsRestart":true}}]'
        echo '[{"event":"app.started","params":{"appId":"app1"}}]'
        while IFS= read -r line; do
          id=$(echo "$line" | sed -E 's/.*"id":([0-9]+).*/\1/')
          case "$line" in
            *app.restart*) echo "[{\"id\":$id,\"result\":{\"code\":0,\"message\":\"Reloaded\"}}]" ;;
            *app.stop*) echo "[{\"id\":$id,\"result\":true}]"; echo '[{"event":"app.stop","params":{"appId":"app1"}}]'; exit 0 ;;
          esac
        done
        """#
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAt: script)
        return script.path
    }

    func testLifecycle() async throws {
        let fake = try makeFakeFlutter()
        let daemon = FlutterDaemon(flutterPath: fake, projectPath: FileManager.default.temporaryDirectory.path,
                                   deviceId: "fake", extraArgs: [], environment: ProcessInfo.processInfo.environment)
        var seen: [String] = []
        let collector = Task {
            for await e in daemon.events {
                switch e {
                case .connected: seen.append("connected")
                case .appStarting(let id, _, _): seen.append("starting:\(id)")
                case .appStarted: seen.append("started")
                case .rawOutput(let s, _): seen.append("raw:\(s)")
                case .appStopped: seen.append("stopped")
                case .processExited(let c): seen.append("exit:\(c)")
                default: break
                }
            }
        }
        try daemon.start()
        // wait for app.started
        for _ in 0..<50 where daemon.appId == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertEqual(daemon.appId, "app1")
        let r = try await daemon.restart(full: false)
        XCTAssertEqual(r.code, 0); XCTAssertEqual(r.message, "Reloaded")
        await daemon.stop()
        await collector.value
        XCTAssertEqual(seen.first, "connected")
        XCTAssertTrue(seen.contains("raw:Launching lib/main.dart on Fake in debug mode..."))
        XCTAssertTrue(seen.contains("starting:app1")); XCTAssertTrue(seen.contains("started"))
        XCTAssertTrue(seen.contains("stopped")); XCTAssertEqual(seen.last, "exit:0")
        XCTAssertFalse(daemon.isRunning)
    }
}
```

- [ ] **Step 2: Run, expect failure**
- [ ] **Step 3: Implement**

```swift
import Foundation

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

public final class FlutterDaemon: @unchecked Sendable {
    public let events: AsyncStream<DaemonEvent>
    private let continuation: AsyncStream<DaemonEvent>.Continuation
    private let process = Process()
    private let stdinPipe = Pipe(), stdoutPipe = Pipe(), stderrPipe = Pipe()
    private let lock = NSLock()
    private var nextId = 1
    private var pending: [Int: CheckedContinuation<(Any?, String?), Error>] = [:]
    private var stdoutBuffer = Data(), stderrBuffer = Data()
    private var _appId: String?
    private var stopRequested = false

    public var appId: String? { lock.lock(); defer { lock.unlock() }; return _appId }
    public var isRunning: Bool { process.isRunning }

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

    private func consume(_ data: Data, stderr: Bool) {
        guard !data.isEmpty else { return }
        lock.lock()
        if stderr { stderrBuffer.append(data) } else { stdoutBuffer.append(data) }
        var lines: [String] = []
        let buffer = stderr ? stderrBuffer : stdoutBuffer
        var rest = buffer
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
            if let error { cont?.resume(throwing: RunnerError.processFailed(error)) } else { cont?.resume(returning: (result, nil)) }
        case let .event(name, params):
            switch name {
            case "daemon.connected": continuation.yield(.connected)
            case "daemon.logMessage":
                continuation.yield(.daemonLog(level: params["level"] as? String ?? "info", message: params["message"] as? String ?? ""))
            case "app.start":
                let id = params["appId"] as? String ?? ""
                lock.lock(); _appId = id; lock.unlock()
                continuation.yield(.appStarting(appId: id, deviceId: params["deviceId"] as? String ?? "", supportsRestart: params["supportsRestart"] as? Bool ?? true))
            case "app.started": continuation.yield(.appStarted)
            case "app.progress": continuation.yield(.progress(message: params["message"] as? String, finished: params["finished"] as? Bool ?? false))
            case "app.log": continuation.yield(.appLog(params["log"] as? String ?? "", isError: params["error"] as? Bool ?? false))
            case "app.webLaunchUrl": if let u = params["url"] as? String { continuation.yield(.webLaunchUrl(u)) }
            case "app.stop": continuation.yield(.appStopped)
            default: break
            }
        }
    }

    private func send(method: String, params: [String: Any]) async throws -> Any? {
        guard process.isRunning else { throw RunnerError.processFailed("flutter is not running") }
        let id: Int
        lock.lock(); id = nextId; nextId += 1; lock.unlock()
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Any?, String?), Error>) in
            lock.lock(); pending[id] = cont; lock.unlock()
            let line = DaemonProtocol.encodeCommand(id: id, method: method, params: params)
            stdinPipe.fileHandleForWriting.write(Data(line.utf8))
        }.0
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
    }

    public var wasStopRequested: Bool { lock.lock(); defer { lock.unlock() }; return stopRequested }

    private func handleExit(_ code: Int32) {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        consume(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), stderr: false)
        consume(stderrPipe.fileHandleForReading.readDataToEndOfFile(), stderr: true)
        lock.lock(); let leftovers = pending; pending = [:]; lock.unlock()
        for (_, c) in leftovers { c.resume(throwing: RunnerError.processFailed("flutter exited with code \(code)")) }
        continuation.yield(.processExited(code: code))
        continuation.finish()
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
```

- [ ] **Step 4: Run tests, expect PASS**
- [ ] **Step 5: Commit** — `git commit -am "feat: flutter daemon process wrapper"`

---

### Task 6: FileWatcher

**Files:**
- Create: `Sources/FlutterRunnerCore/FileWatcher.swift`
- Test: `Tests/FlutterRunnerCoreTests/FileWatcherTests.swift`

**Interfaces:**
- Produces: `final class FileWatcher { init(path: String, latency: TimeInterval = 0.1, onChange: @escaping ([String]) -> Void); func start(); func stop() }` — `onChange` receives only paths passing `DartChangeFilter`.

- [ ] **Step 1: Failing test**

```swift
import XCTest
@testable import FlutterRunnerCore

final class FileWatcherTests: XCTestCase {
    func testDetectsDartWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("lib")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exp = expectation(description: "change")
        var got: [String] = []
        let w = FileWatcher(path: dir.path) { paths in got = paths; exp.fulfill() }
        w.start()
        Thread.sleep(forTimeInterval: 0.5)
        try "void main() {}".write(to: dir.appendingPathComponent("main.dart"), atomically: true, encoding: .utf8)
        wait(for: [exp], timeout: 5)
        w.stop()
        XCTAssertTrue(got.contains { $0.hasSuffix("main.dart") })
    }
}
```

- [ ] **Step 2: Run, expect failure**
- [ ] **Step 3: Implement**

```swift
import Foundation
import CoreServices

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
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
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

private let fileWatcherCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
    guard let info else { return }
    let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
    watcher.handle(paths)
}
```

- [ ] **Step 4: Run tests, expect PASS**
- [ ] **Step 5: Commit** — `git commit -am "feat: FSEvents file watcher"`

---

### Task 7: ProjectStore + SessionViewModel (app target)

**Files:**
- Create: `Sources/FlutterRunner/ProjectStore.swift`, `Sources/FlutterRunner/SessionViewModel.swift`
- Delete: `Sources/FlutterRunner/main.swift` (replaced by `@main` in Task 8; keep placeholder until then — build check uses `swift build`)

**Interfaces:**
- Produces: `@MainActor @Observable final class ProjectStore { var recents: [Project]; var manualFlutterPath: String; var debounceMs: Int; var lastProjectPath: String?; func touch(_:); func update(_:); func remove(path:) }`
- Produces: `enum SessionState: Equatable { idle, starting, running, reloading, restarting, stopping, failed(String) }`
- Produces: `struct LogLine: Identifiable { id: Int, text: String, kind: LogKind }`, `enum LogKind { normal, error, warning, info, success }`
- Produces: `@MainActor @Observable final class SessionViewModel` with `static let shared`, properties `state, project, devices, selectedDeviceId, extraArgs, autoReload, logs, isLoadingDevices, flutterPath, followLogs`, methods `selectProject(path:)`, `openProjectPanel()`, `refreshDevices()`, `run()`, `stop()`, `hotReload()`, `hotRestart()`, `clearLogs()`, `relocateFlutter()`, computed `canRun, canStop, canReload, isRunning, statusText`.

- [ ] **Step 1: Implement ProjectStore**

```swift
import Foundation
import Observation
import FlutterRunnerCore

@MainActor @Observable
final class ProjectStore {
    private let defaults: UserDefaults
    private enum Key { static let recents = "recents", flutterPath = "manualFlutterPath", debounce = "debounceMs", lastProject = "lastProjectPath" }

    var recents: [Project] { didSet { save() } }
    var manualFlutterPath: String { didSet { defaults.set(manualFlutterPath, forKey: Key.flutterPath) } }
    var debounceMs: Int { didSet { defaults.set(debounceMs, forKey: Key.debounce) } }
    var lastProjectPath: String? { didSet { defaults.set(lastProjectPath, forKey: Key.lastProject) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.recents), let list = try? JSONDecoder().decode([Project].self, from: data) { recents = list } else { recents = [] }
        manualFlutterPath = defaults.string(forKey: Key.flutterPath) ?? ""
        let d = defaults.integer(forKey: Key.debounce); debounceMs = d == 0 ? 300 : d
        lastProjectPath = defaults.string(forKey: Key.lastProject)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Key.recents) }
    }

    func touch(_ project: Project) {
        var p = project; p.lastOpened = Date()
        recents.removeAll { $0.path == p.path }
        recents.insert(p, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        lastProjectPath = p.path
    }

    func update(_ project: Project) {
        if let i = recents.firstIndex(where: { $0.path == project.path }) { recents[i] = project } else { touch(project) }
    }

    func remove(path: String) {
        recents.removeAll { $0.path == path }
        if lastProjectPath == path { lastProjectPath = nil }
    }
}
```

- [ ] **Step 2: Implement SessionViewModel**

```swift
import AppKit
import Foundation
import Observation
import FlutterRunnerCore

enum SessionState: Equatable {
    case idle, starting, running, reloading, restarting, stopping
    case failed(String)
}

enum LogKind { case normal, error, warning, info, success }

struct LogLine: Identifiable {
    let id: Int
    let text: String
    let kind: LogKind
}

@MainActor @Observable
final class SessionViewModel {
    static let shared = SessionViewModel(store: ProjectStore())

    let store: ProjectStore
    var state: SessionState = .idle
    var project: Project?
    var devices: [FlutterDevice] = []
    var selectedDeviceId: String? { didSet { persistProjectSettings() } }
    var extraArgs: String = "" { didSet { persistProjectSettings() } }
    var autoReload: Bool = true { didSet { persistProjectSettings() } }
    var logs: [LogLine] = []
    var isLoadingDevices = false
    var flutterPath: String?
    var followLogs = true
    var deviceError: String?

    private var daemon: FlutterDaemon?
    private var eventTask: Task<Void, Never>?
    private var watcher: FileWatcher?
    private var debouncer: Debouncer?
    private var pendingReload = false
    private var nextLogId = 0
    private var suppressPersist = false
    private let maxLogLines = 5000

    init(store: ProjectStore) {
        self.store = store
        relocateFlutter()
        if let last = store.lastProjectPath, FileManager.default.fileExists(atPath: last) { selectProject(path: last) }
    }

    // MARK: Derived
    var isRunning: Bool { if case .idle = state { return false }; if case .failed = state { return false }; return true }
    var canRun: Bool { !isRunning && project != nil && selectedDeviceId != nil && flutterPath != nil }
    var canStop: Bool { isRunning && state != .stopping }
    var canReload: Bool { state == .running }
    var selectedDevice: FlutterDevice? { devices.first { $0.id == selectedDeviceId } }
    var statusText: String {
        switch state {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .running: return "Running"
        case .reloading: return "Hot reloading…"
        case .restarting: return "Hot restarting…"
        case .stopping: return "Stopping…"
        case .failed(let m): return "Failed: \(m)"
        }
    }

    // MARK: Flutter location
    func relocateFlutter() {
        flutterPath = FlutterLocator.locate(manualPath: store.manualFlutterPath)
        if flutterPath == nil { log("flutter executable not found. Set the path in Settings (⌘,).", .error) }
    }

    // MARK: Projects
    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a Flutter project folder (contains pubspec.yaml)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectProject(path: url.path)
    }

    func selectProject(path: String) {
        if isRunning { Task { await stop(); self.selectProject(path: path) }; return }
        do {
            var p = try Project.load(path: path)
            if let saved = store.recents.first(where: { $0.path == path }) {
                p.lastDeviceId = saved.lastDeviceId; p.extraArgs = saved.extraArgs; p.autoReload = saved.autoReload
            }
            suppressPersist = true
            project = p
            extraArgs = p.extraArgs
            autoReload = p.autoReload
            selectedDeviceId = p.lastDeviceId
            suppressPersist = false
            store.touch(p)
            log("Project: \(p.name) (\(p.path))", .info)
            Task { await refreshDevices() }
        } catch {
            log(error.localizedDescription, .error)
            NSSound.beep()
        }
    }

    func removeRecent(path: String) { store.remove(path: path); if project?.path == path { project = nil } }

    private func persistProjectSettings() {
        guard !suppressPersist, var p = project else { return }
        p.lastDeviceId = selectedDeviceId; p.extraArgs = extraArgs; p.autoReload = autoReload
        project = p
        store.update(p)
    }

    // MARK: Devices
    func refreshDevices() async {
        guard let flutterPath, !isLoadingDevices else { return }
        isLoadingDevices = true; deviceError = nil
        defer { isLoadingDevices = false }
        do {
            let list = try await DeviceService(flutterPath: flutterPath, environment: FlutterLocator.environment(flutterPath: flutterPath))
                .listDevices(projectPath: project?.path)
            devices = list
            if selectedDeviceId == nil || !list.contains(where: { $0.id == selectedDeviceId }) {
                selectedDeviceId = list.first?.id
            }
            if list.isEmpty { deviceError = "No devices found. Start a simulator or connect a device, then refresh." }
        } catch {
            deviceError = error.localizedDescription
            log("Device list failed: \(error.localizedDescription)", .error)
        }
    }

    // MARK: Run / stop
    func run() async {
        guard canRun, let project, let deviceId = selectedDeviceId, let flutterPath else { return }
        clearLogs()
        state = .starting
        pendingReload = false
        let args = ArgumentSplitter.split(extraArgs)
        log("$ flutter run --machine -d \(deviceId) \(args.joined(separator: " "))", .info)
        let d = FlutterDaemon(flutterPath: flutterPath, projectPath: project.path, deviceId: deviceId, extraArgs: args,
                              environment: FlutterLocator.environment(flutterPath: flutterPath))
        daemon = d
        eventTask = Task { [weak self] in
            for await event in d.events { await self?.handle(event) }
        }
        do { try d.start() } catch {
            state = .failed(error.localizedDescription); log(error.localizedDescription, .error); daemon = nil
        }
        startWatcher(project: project)
    }

    func stop() async {
        guard let d = daemon, isRunning else { return }
        state = .stopping
        log("Stopping…", .info)
        await d.stop()
    }

    func hotReload() async { await restart(full: false) }
    func hotRestart() async { await restart(full: true) }

    private func restart(full: Bool) async {
        guard let d = daemon else { return }
        guard state == .running else {
            if state == .reloading || state == .restarting { pendingReload = true }
            return
        }
        state = full ? .restarting : .reloading
        let started = Date()
        do {
            let r = try await d.restart(full: full)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if r.code == 0 { log("\(full ? "Hot restart" : "Hot reload") done in \(ms) ms. \(r.message)", .success) }
            else { log("\(full ? "Hot restart" : "Hot reload") failed: \(r.message)", .error) }
        } catch {
            log("\(full ? "Hot restart" : "Hot reload") error: \(error.localizedDescription)", .error)
        }
        if isRunning, state == (full ? .restarting : .reloading) { state = .running }
        if pendingReload, state == .running { pendingReload = false; await restart(full: false) }
    }

    // MARK: Watcher
    private func startWatcher(project: Project) {
        stopWatcher()
        let debouncer = Debouncer(interval: Double(store.debounceMs) / 1000.0) { [weak self] in
            Task { @MainActor in await self?.autoReloadFired() }
        }
        self.debouncer = debouncer
        let w = FileWatcher(path: project.libPath) { _ in debouncer.trigger() }
        w.start()
        watcher = w
    }

    private func stopWatcher() { watcher?.stop(); watcher = nil; debouncer?.cancel(); debouncer = nil }

    private func autoReloadFired() async {
        guard autoReload, state == .running || state == .reloading || state == .restarting else { return }
        log("Change detected in lib/ → hot reload", .info)
        await hotReload()
    }

    // MARK: Events
    private func handle(_ event: DaemonEvent) {
        switch event {
        case .connected: break
        case .daemonLog(let level, let message):
            log(message, level == "error" ? .error : (level == "warning" ? .warning : .normal))
        case .appStarting(_, let deviceId, _): log("Launching on \(deviceId)…", .info)
        case .appStarted:
            state = .running
            log("App started. Auto reload is \(autoReload ? "on" : "off").", .success)
        case .progress(let message, let finished):
            if let message, !finished { log(message, .normal) }
        case .appLog(let text, let isError): log(text, isError ? .error : .normal)
        case .rawOutput(let text, let isStderr): log(text, isStderr ? .warning : .normal)
        case .webLaunchUrl(let url): log("Web app at \(url)", .info)
        case .appStopped: log("App stopped.", .info)
        case .processExited(let code):
            let requested = daemon?.wasStopRequested ?? false
            stopWatcher()
            daemon = nil; eventTask = nil
            if code == 0 || requested { state = .idle; log("flutter exited.", .info) }
            else { state = .failed("flutter exited with code \(code)"); log("flutter exited with code \(code)", .error) }
        }
    }

    // MARK: Logs
    func log(_ text: String, _ kind: LogKind = .normal) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            logs.append(LogLine(id: nextLogId, text: String(line), kind: kind)); nextLogId += 1
        }
        if logs.count > maxLogLines { logs.removeFirst(logs.count - maxLogLines) }
    }

    func clearLogs() { logs.removeAll() }

    /// Called on app quit: stops the daemon if needed.
    func shutdown() async { stopWatcher(); await daemon?.stop() }
}
```

- [ ] **Step 3: Build** — `swift build 2>&1 | tail -5`, expect success
- [ ] **Step 4: Commit** — `git add -A && git commit -m "feat: project store and session view model"`

---

### Task 8: SwiftUI app: main window, log view, menu bar, settings, commands

**Files:**
- Delete: `Sources/FlutterRunner/main.swift`
- Create: `Sources/FlutterRunner/FlutterRunnerApp.swift`, `AppDelegate.swift`, `MainWindow.swift`, `LogView.swift`, `MenuBarMenu.swift`, `SettingsView.swift`

- [ ] **Step 1: FlutterRunnerApp.swift**

```swift
import SwiftUI
import FlutterRunnerCore

@main
struct FlutterRunnerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = SessionViewModel.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("FlutterRunner", id: "main") {
            MainWindow().environment(model).frame(minWidth: 720, minHeight: 420)
        }
        .defaultSize(width: 960, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Project…") { model.openProjectPanel() }.keyboardShortcut("o")
            }
            CommandMenu("Flutter") {
                Button("Run") { Task { await model.run() } }.keyboardShortcut(.return, modifiers: .command).disabled(!model.canRun)
                Button("Stop") { Task { await model.stop() } }.keyboardShortcut(".", modifiers: .command).disabled(!model.canStop)
                Divider()
                Button("Hot Reload") { Task { await model.hotReload() } }.keyboardShortcut("r").disabled(!model.canReload)
                Button("Hot Restart") { Task { await model.hotRestart() } }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(!model.canReload)
                Divider()
                Toggle("Auto Reload on Save", isOn: Binding(get: { model.autoReload }, set: { model.autoReload = $0 }))
                Button("Refresh Devices") { Task { await model.refreshDevices() } }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Clear Logs") { model.clearLogs() }.keyboardShortcut("k")
            }
        }

        MenuBarExtra {
            MenuBarMenu().environment(model)
        } label: {
            Image(systemName: menuBarSymbol)
        }

        Settings { SettingsView().environment(model) }
    }

    private var menuBarSymbol: String {
        switch model.state {
        case .idle: return "play.circle"
        case .starting, .stopping: return "circle.dotted"
        case .running: return "play.circle.fill"
        case .reloading, .restarting: return "arrow.triangle.2.circlepath.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
}
```

- [ ] **Step 2: AppDelegate.swift**

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = SessionViewModel.shared
        guard model.isRunning else { return .terminateNow }
        Task { @MainActor in
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

- [ ] **Step 3: MainWindow.swift**

```swift
import SwiftUI
import FlutterRunnerCore

struct MainWindow: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    projectPicker
                    devicePicker
                    TextField("Extra args, e.g. --flavor dev -t lib/main_dev.dart", text: $model.extraArgs)
                        .textFieldStyle(.roundedBorder)
                        .disabled(model.isRunning)
                        .frame(minWidth: 220)
                }
                HStack(spacing: 10) {
                    if model.canStop {
                        Button { Task { await model.stop() } } label: { Label("Stop", systemImage: "stop.fill") }
                            .keyboardShortcut(".", modifiers: .command)
                    } else {
                        Button { Task { await model.run() } } label: { Label("Run", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).disabled(!model.canRun)
                    }
                    Button { Task { await model.hotReload() } } label: { Label("Hot Reload", systemImage: "bolt.fill") }
                        .disabled(!model.canReload)
                    Button { Task { await model.hotRestart() } } label: { Label("Hot Restart", systemImage: "arrow.counterclockwise") }
                        .disabled(!model.canReload)
                    Toggle("Auto reload", isOn: $model.autoReload).toggleStyle(.switch).controlSize(.small)
                    Spacer()
                    statusIndicator
                }
            }
            .padding(12)
            Divider()
            LogView()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Toggle(isOn: $model.followLogs) { Label("Follow", systemImage: "arrow.down.to.line") }.help("Auto-scroll to newest log line")
            }
            ToolbarItem(placement: .automatic) {
                Button { model.clearLogs() } label: { Label("Clear", systemImage: "trash") }.help("Clear logs (⌘K)")
            }
        }
    }

    private var projectPicker: some View {
        Menu {
            ForEach(model.store.recents) { p in
                Button(p.name + "  —  " + abbreviate(p.path)) { model.selectProject(path: p.path) }
            }
            if !model.store.recents.isEmpty { Divider() }
            Button("Open Folder…") { model.openProjectPanel() }
            if let p = model.project {
                Divider()
                Button("Remove \(p.name) from Recents") { model.removeRecent(path: p.path) }
            }
        } label: {
            Label(model.project?.name ?? "Choose project", systemImage: "folder")
        }
        .disabled(model.isRunning)
        .frame(maxWidth: 260)
    }

    private var devicePicker: some View {
        HStack(spacing: 4) {
            Picker("Device", selection: Binding(get: { model.selectedDeviceId ?? "" }, set: { model.selectedDeviceId = $0.isEmpty ? nil : $0 })) {
                if model.devices.isEmpty { Text(model.isLoadingDevices ? "Loading…" : "No devices").tag("") }
                ForEach(model.devices) { d in Text(d.displayName).tag(d.id) }
            }
            .labelsHidden()
            .disabled(model.isRunning || model.devices.isEmpty)
            .frame(maxWidth: 240)
            Button { Task { await model.refreshDevices() } } label: {
                if model.isLoadingDevices { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
            }
            .disabled(model.isLoadingDevices || model.isRunning)
            .help(model.deviceError ?? "Refresh devices (⌘⇧D)")
        }
    }

    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(model.statusText).font(.callout).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch model.state {
        case .idle: return .gray
        case .starting, .stopping: return .blue
        case .running: return .green
        case .reloading, .restarting: return .yellow
        case .failed: return .red
        }
    }

    private func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
```

- [ ] **Step 4: LogView.swift**

```swift
import SwiftUI

struct LogView: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.logs) { line in
                        Text(line.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: model.logs.count) { _, _ in
                if model.followLogs, let last = model.logs.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: LogKind) -> Color {
        switch kind {
        case .normal: return .primary
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        case .success: return .green
        }
    }
}
```

- [ ] **Step 5: MenuBarMenu.swift**

```swift
import SwiftUI

struct MenuBarMenu: View {
    @Environment(SessionViewModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Text(model.project?.name ?? "No project")
        Text(model.selectedDevice?.displayName ?? "No device")
        Text(model.statusText)
        Divider()
        if model.canStop {
            Button("Stop") { Task { await model.stop() } }
        } else {
            Button("Run") { Task { await model.run() } }.disabled(!model.canRun)
        }
        Button("Hot Reload") { Task { await model.hotReload() } }.disabled(!model.canReload)
        Button("Hot Restart") { Task { await model.hotRestart() } }.disabled(!model.canReload)
        Toggle("Auto Reload on Save", isOn: $model.autoReload)
        Divider()
        Button("Show Logs") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Quit FlutterRunner") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
```

- [ ] **Step 6: SettingsView.swift**

```swift
import SwiftUI

struct SettingsView: View {
    @Environment(SessionViewModel.self) private var model

    var body: some View {
        @Bindable var store = model.store
        Form {
            Section("Flutter") {
                TextField("Flutter path (leave empty to auto-detect)", text: $store.manualFlutterPath)
                    .onSubmit { model.relocateFlutter() }
                HStack {
                    Text("Detected: \(model.flutterPath ?? "not found")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Re-detect") { model.relocateFlutter() }
                }
            }
            Section("Auto reload") {
                Stepper("Debounce: \(store.debounceMs) ms", value: $store.debounceMs, in: 100...3000, step: 100)
                Text("Changes to .dart files under lib/ within this window are merged into one hot reload.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
```

- [ ] **Step 7: Delete `main.swift`, build** — `rm Sources/FlutterRunner/main.swift && swift build 2>&1 | tail -5`
- [ ] **Step 8: Run tests** — `swift test 2>&1 | tail -3`, all pass
- [ ] **Step 9: Commit** — `git add -A && git commit -m "feat: SwiftUI app with main window, menu bar and settings"`

---

### Task 9: App bundle, icon, distribution script

**Files:**
- Create: `Resources/Info.plist`, `Resources/README-dist.txt`, `scripts/make_icon.swift`, `scripts/build_app.sh`, `README.md`

- [ ] **Step 1: Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>FlutterRunner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.hrvojebencik.FlutterRunner</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>FlutterRunner</string>
    <key>CFBundleDisplayName</key><string>FlutterRunner</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Hrvoje Bencik</string>
</dict>
</plist>
```

- [ ] **Step 2: make_icon.swift** (draws a rounded square with a play triangle and a bolt, writes iconset PNGs)

```swift
import AppKit

let sizes: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
let outDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let rect = NSRect(x: s*0.05, y: s*0.05, width: s*0.9, height: s*0.9)
    let path = NSBezierPath(roundedRect: rect, xRadius: s*0.2, yRadius: s*0.2)
    let grad = NSGradient(starting: NSColor(calibratedRed: 0.02, green: 0.35, blue: 0.85, alpha: 1), ending: NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.95, alpha: 1))!
    grad.draw(in: path, angle: -60)
    let tri = NSBezierPath()
    tri.move(to: NSPoint(x: s*0.36, y: s*0.28)); tri.line(to: NSPoint(x: s*0.36, y: s*0.72)); tri.line(to: NSPoint(x: s*0.74, y: s*0.5)); tri.close()
    NSColor.white.setFill(); tri.fill()
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: s*0.30, y: s*0.86)); bolt.line(to: NSPoint(x: s*0.20, y: s*0.64)); bolt.line(to: NSPoint(x: s*0.27, y: s*0.64))
    bolt.line(to: NSPoint(x: s*0.22, y: s*0.48)); bolt.line(to: NSPoint(x: s*0.34, y: s*0.70)); bolt.line(to: NSPoint(x: s*0.27, y: s*0.70)); bolt.close()
    NSColor(calibratedRed: 1, green: 0.85, blue: 0.2, alpha: 1).setFill(); bolt.fill()
    img.unlockFocus()
    return img
}

for (pt, scale) in sizes {
    let px = pt * scale
    let img = render(px)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try! png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
```

- [ ] **Step 3: build_app.sh**

```bash
#!/bin/bash
# Builds FlutterRunner.app (universal), ad-hoc signs it and zips it into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Building release binary…"
if swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -3; then
  BIN=".build/apple/Products/Release/FlutterRunner"
else
  echo "Universal build failed, falling back to native arch"
  swift build -c release 2>&1 | tail -3
  BIN=".build/release/FlutterRunner"
fi

APP="dist/FlutterRunner.app"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FlutterRunner"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "▸ Generating icon…"
ICONSET="dist/AppIcon.iconset"
swift scripts/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "▸ Zipping…"
cp Resources/README-dist.txt dist/README.txt
ditto -c -k --keepParent "$APP" dist/FlutterRunner.zip
echo "Done: $APP and dist/FlutterRunner.zip"
```

- [ ] **Step 4: README-dist.txt** (instructions for recipients, in Serbian and English, Gatekeeper steps)
- [ ] **Step 5: Run `chmod +x scripts/build_app.sh && scripts/build_app.sh`**, expect `dist/FlutterRunner.app` and `dist/FlutterRunner.zip`
- [ ] **Step 6: Launch `open dist/FlutterRunner.app`, verify window and menu bar icon appear**
- [ ] **Step 7: Write README.md (build, run, test, distribute), commit** — `git add -A && git commit -m "feat: app bundle, icon and distribution script"`

---

### Task 10: Manual end-to-end verification on a real project

- [ ] Open `~/Documents/Projects/Usput/usput`, refresh devices, select Chrome (or a simulator), Run.
- [ ] Wait for "App started", touch a `.dart` file in `lib/`, confirm "Change detected → hot reload" and "Hot reload done".
- [ ] Hot Restart button works; Stop returns to Idle; Quit from menu bar stops the daemon.
- [ ] Fix anything found, commit.
