# Hotplate 1.1 — terminal (TUI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Komanda `hotplate` koja u full-screen terminalskom interfejsu radi sve što radi Hotplate prozor (run, hot reload na save, uređaji, launch.json, argumenti, log sa linkovima ka editoru), uz prečice i miš.

**Architecture:** Logika sesije se seli iz GUI `SessionViewModel` u `HotplateCore.Session` (UI-agnostičan, `@Observable`), koju koriste i GUI i novi TUI. Novi library target `HotplateTUI` sadrži dekoder ulaza, ćelijski ekran sa diff rendererom, log viewport, widgete i `TUIApp` mašinu stanja. Executable `hotplate-cli` je tanak `main.swift`, a `build_app.sh` ga pakuje kao `Hotplate.app/Contents/Helpers/hotplate`.

**Tech Stack:** Swift 5.9 tools, SwiftPM, macOS 14+, Foundation/Observation/Darwin (termios, ioctl, DispatchSource), XCTest. Bez spoljnih zavisnosti.

**Spec:** `docs/superpowers/specs/2026-10-09-terminal-tui-design.md`

## Global Constraints

- macOS 14 (Sonoma)+, `swift-tools-version: 5.9`, Swift 5 jezički mod; **nijedna spoljna zavisnost**.
- UserDefaults domen: `com.hrvojebencik.hotplate` (GUI preko `.standard`, CLI kao suite).
- Instalirana komanda: `hotplate`, u paketu na `Hotplate.app/Contents/Helpers/hotplate`. SwiftPM proizvod/target: `hotplate-cli` (nikad `hotplate`, sudar sa `Hotplate` na case-insensitive disku).
- Verzija: `1.1.0` (`Info.plist` `CFBundleShortVersionString`, `CFBundleVersion` `2`, `HotplateVersion.current`).
- Minimalna veličina terminala: 60×12; ispod toga samo „Terminal too small (min 60×12)“.
- Opcije komandne linije važe samo za sesiju i nikad se ne upisuju; izbori iz TUI-ja se pamte po projektu.
- Izlazni kodovi: 0 normalan izlaz, 1 nema projekta i nema nedavnih, 2 greška u opcijama ili nije interaktivni terminal, 130 prinudni izlaz (drugi Ctrl+C u 2 s).
- Testovi: XCTest (`import XCTest`, `@testable import …`), kao postojeći; `swift test` mora proći posle svakog taska.
- Komentari i stringovi u kodu na engleskom, kao u postojećem kodu.

## Review Focus

1. **ANSI boje, tabovi i `\r` u logovima** (npr. `logger` paket boji izlaz) — moraju se prikazati čisto, bez pokvarenog ekrana, a linkovi posle njih ostaju klikabilni na tačnoj koloni. → test u Task 7 (`testSanitizesAnsiAndTabsKeepingLinkColumns`).
2. **Ogromne linije** (JSON/stack trace od 20 000 znakova) — prelamanje bez gubitka znakova i bez zamrzavanja. → test u Task 7 (`testVeryLongLineWrapsWithoutLosingCharacters`).
3. **Resize ispod minimuma i nazad dok je popup otvoren** — bez pada (index out of range), popup ostaje. → test u Task 10 (`testResizeBelowMinimumAndBackKeepsPicker`).
4. **Široki znakovi (emoji, CJK) u logovima i imenima uređaja** — ne smeju preći ivicu ni pomeriti kolone. → testovi u Task 6 (`testWideCharacterIsNotSplitAtRightEdge`, `testRendersWideCharacterOnce`).
5. **Paste u normalnom modu** (npr. nalepljen tekst „rrq“) ne sme da okine reload/quit; paste u polje za argumente pretvara nove redove u razmake. → testovi u Task 10 (`testPasteInNormalModeTriggersNothing`, `testPasteIntoArgsReplacesNewlines`).

## Mapa fajlova

```
Package.swift                                         MODIFY (targeti HotplateTUI, hotplate-cli, HotplateTestSupport, HotplateTUITests)
Sources/HotplateCore/HotplateVersion.swift            CREATE
Sources/HotplateCore/DeviceMatcher.swift              CREATE
Sources/HotplateCore/ProjectLocator.swift             CREATE
Sources/HotplateCore/ProjectStore.swift               MOVE iz Sources/Hotplate, public + makeDefaults()
Sources/HotplateCore/SessionTypes.swift               CREATE (SessionState, LogKind, LogLine, SessionHints, SessionOverrides, StartupOutcome)
Sources/HotplateCore/SessionDependencies.swift        CREATE (DaemonConfig, SessionDaemon, SessionWatcher, SessionDependencies)
Sources/HotplateCore/Session.swift                    CREATE (logika iz SessionViewModel)
Sources/HotplateCore/FlutterDaemon.swift              MODIFY (terminate(), public RestartResult.init)
Sources/HotplateCore/CommandLineToolStatus.swift      CREATE
Sources/Hotplate/SessionViewModel.swift               REPLACE (typealias + GUI ekstenzija)
Sources/Hotplate/Theme.swift, MenuBarPanel.swift, AppDelegate.swift   MODIFY (import HotplateCore)
Sources/Hotplate/CommandLineInstaller.swift           CREATE
Sources/Hotplate/HotplateApp.swift, SettingsView.swift  MODIFY (meni + sekcija Command line)
Sources/HotplateTUI/InputEvent.swift, InputDecoder.swift
Sources/HotplateTUI/Style.swift, CharWidth.swift, ScreenBuffer.swift, Renderer.swift
Sources/HotplateTUI/LogText.swift, LogViewport.swift
Sources/HotplateTUI/Picker.swift, TextInput.swift
Sources/HotplateTUI/KeyBindings.swift, Widgets.swift (StatusBar, FooterBar, HelpOverlay, LogPane)
Sources/HotplateTUI/TUIApp.swift
Sources/HotplateTUI/CommandLineOptions.swift, Terminal.swift, TerminalLoop.swift, Clipboard.swift
Sources/hotplate-cli/main.swift
Tests/HotplateTestSupport/SessionHarness.swift
Tests/HotplateCoreTests/{DeviceMatcher,ProjectLocator,ProjectStore,Session,SessionOverrides,CommandLineToolStatus}Tests.swift
Tests/HotplateTUITests/{InputDecoder,ScreenBuffer,Renderer,LogViewport,Picker,TextInput,KeyBindings,TUIApp,CommandLineOptions}Tests.swift
scripts/build_app.sh, Resources/Info.plist, Resources/README-dist.txt, README.md, CHANGELOG.md   MODIFY
```

---

### Task 1: DeviceMatcher, ProjectLocator, HotplateVersion

**Files:**
- Create: `Sources/HotplateCore/DeviceMatcher.swift`, `Sources/HotplateCore/ProjectLocator.swift`, `Sources/HotplateCore/HotplateVersion.swift`
- Test: `Tests/HotplateCoreTests/DeviceMatcherTests.swift`, `Tests/HotplateCoreTests/ProjectLocatorTests.swift`

**Interfaces:**
- Consumes: `FlutterDevice`, `Project.load(path:)` (postojeće)
- Produces: `enum DeviceMatch: Equatable { case one(FlutterDevice), many([FlutterDevice]), none }`, `DeviceMatcher.match(query: String, in: [FlutterDevice]) -> DeviceMatch`, `ProjectLocator.find(from: String) -> String?`, `HotplateVersion.current: String`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateCoreTests/DeviceMatcherTests.swift`:
```swift
import XCTest
@testable import HotplateCore

final class DeviceMatcherTests: XCTestCase {
    private let devices = [
        FlutterDevice(id: "A1B2", name: "iPhone 16 Pro", targetPlatform: "ios", emulator: true, isSupported: true),
        FlutterDevice(id: "C3D4", name: "iPhone 15", targetPlatform: "ios", emulator: true, isSupported: true),
        FlutterDevice(id: "chrome", name: "Chrome", targetPlatform: "web-javascript", emulator: false, isSupported: true),
    ]

    func testExactIdWins() {
        XCTAssertEqual(DeviceMatcher.match(query: "C3D4", in: devices), .one(devices[1]))
    }

    func testExactNameIgnoringCase() {
        XCTAssertEqual(DeviceMatcher.match(query: "iphone 15", in: devices), .one(devices[1]))
    }

    func testUniqueSubstringOfNameOrId() {
        XCTAssertEqual(DeviceMatcher.match(query: "chr", in: devices), .one(devices[2]))
        XCTAssertEqual(DeviceMatcher.match(query: "16", in: devices), .one(devices[0]))
    }

    func testAmbiguousSubstring() {
        XCTAssertEqual(DeviceMatcher.match(query: "iphone", in: devices), .many([devices[0], devices[1]]))
    }

    func testNoMatchAndEmptyQuery() {
        XCTAssertEqual(DeviceMatcher.match(query: "pixel", in: devices), .none)
        XCTAssertEqual(DeviceMatcher.match(query: "  ", in: devices), .none)
    }
}
```

`Tests/HotplateCoreTests/ProjectLocatorTests.swift`:
```swift
import XCTest
@testable import HotplateCore

final class ProjectLocatorTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath().path
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(root!)/app/lib/src/widgets", withIntermediateDirectories: true)
        try "name: app\ndependencies:\n  flutter:\n    sdk: flutter\n".write(toFile: "\(root!)/app/pubspec.yaml", atomically: true, encoding: .utf8)
        try "void main() {}\n".write(toFile: "\(root!)/app/lib/main.dart", atomically: true, encoding: .utf8)
        try fm.createDirectory(atPath: "\(root!)/plain", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: root) }

    func testFindsProjectRootItself() {
        XCTAssertEqual(ProjectLocator.find(from: "\(root!)/app"), "\(root!)/app")
    }

    func testWalksUpFromSubdirectory() {
        XCTAssertEqual(ProjectLocator.find(from: "\(root!)/app/lib/src/widgets"), "\(root!)/app")
    }

    func testAcceptsAFileAsStart() {
        XCTAssertEqual(ProjectLocator.find(from: "\(root!)/app/lib/main.dart"), "\(root!)/app")
    }

    func testReturnsNilOutsideAProject() {
        XCTAssertNil(ProjectLocator.find(from: "\(root!)/plain"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'DeviceMatcherTests|ProjectLocatorTests'`
Expected: build FAIL — `cannot find 'DeviceMatcher' in scope`, `cannot find 'ProjectLocator' in scope`.

- [ ] **Step 3: Implement**

`Sources/HotplateCore/DeviceMatcher.swift`:
```swift
import Foundation

public enum DeviceMatch: Equatable, Sendable {
    case one(FlutterDevice)
    case many([FlutterDevice])
    case none
}

/// Resolves `--device <query>`: exact id, then exact name, then part of the name or id (case-insensitive).
public enum DeviceMatcher {
    public static func match(query: String, in devices: [FlutterDevice]) -> DeviceMatch {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return .none }
        if let exact = devices.first(where: { $0.id == q }) { return .one(exact) }
        let byName = devices.filter { $0.name.caseInsensitiveCompare(q) == .orderedSame }
        if byName.count == 1 { return .one(byName[0]) }
        if byName.count > 1 { return .many(byName) }
        let partial = devices.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
        switch partial.count {
        case 0: return .none
        case 1: return .one(partial[0])
        default: return .many(partial)
        }
    }
}
```

`Sources/HotplateCore/ProjectLocator.swift`:
```swift
import Foundation

/// Finds the Flutter project that contains a path, walking up like git looks for `.git`.
public enum ProjectLocator {
    public static func find(from path: String) -> String? {
        var dir = URL(fileURLWithPath: path).standardizedFileURL.path
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), !isDir.boolValue {
            dir = (dir as NSString).deletingLastPathComponent
        }
        while true {
            if (try? Project.load(path: dir)) != nil { return dir }
            if dir == "/" || dir.isEmpty { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }
}
```

`Sources/HotplateCore/HotplateVersion.swift`:
```swift
/// The app and command line version. `scripts/build_app.sh` checks it matches Info.plist.
public enum HotplateVersion {
    public static let current = "1.1.0"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'DeviceMatcherTests|ProjectLocatorTests'`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/HotplateCore/DeviceMatcher.swift Sources/HotplateCore/ProjectLocator.swift Sources/HotplateCore/HotplateVersion.swift Tests/HotplateCoreTests/DeviceMatcherTests.swift Tests/HotplateCoreTests/ProjectLocatorTests.swift
git commit -m "feat(core): device matcher, project locator, version constant"
```

---

### Task 2: ProjectStore u HotplateCore

**Files:**
- Move: `Sources/Hotplate/ProjectStore.swift` → `Sources/HotplateCore/ProjectStore.swift`
- Test: `Tests/HotplateCoreTests/ProjectStoreTests.swift`

**Interfaces:**
- Produces: `public final class ProjectStore` (svi postojeći članovi `public`), `ProjectStore.suiteName == "com.hrvojebencik.hotplate"`, `ProjectStore.makeDefaults() -> UserDefaults`, `init(defaults: UserDefaults = ProjectStore.makeDefaults())`

- [ ] **Step 1: Write the failing test**

`Tests/HotplateCoreTests/ProjectStoreTests.swift`:
```swift
import XCTest
@testable import HotplateCore

@MainActor
final class ProjectStoreTests: XCTestCase {
    private let suite = "hotplate.tests.store.\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suite)! }

    override func tearDown() { UserDefaults.standard.removePersistentDomain(forName: suite) }

    func testPersistsAcrossInstances() {
        let a = ProjectStore(defaults: defaults)
        a.touch(Project(path: "/p/one", name: "one", lastDeviceId: "chrome", extraArgs: "--flavor dev"))
        a.editorUseCustomCommand = true
        a.debounceMs = 500
        let b = ProjectStore(defaults: defaults)
        XCTAssertEqual(b.recents.first?.lastDeviceId, "chrome")
        XCTAssertEqual(b.recents.first?.extraArgs, "--flavor dev")
        XCTAssertEqual(b.lastProjectPath, "/p/one")
        XCTAssertTrue(b.editorUseCustomCommand)
        XCTAssertEqual(b.debounceMs, 500)
    }

    func testRecentsAreCappedAtTen() {
        let s = ProjectStore(defaults: defaults)
        for i in 0..<12 { s.touch(Project(path: "/p/\(i)", name: "\(i)")) }
        XCTAssertEqual(s.recents.count, 10)
        XCTAssertEqual(s.recents.first?.path, "/p/11")
    }

    func testSuiteNameIsTheAppBundleId() {
        XCTAssertEqual(ProjectStore.suiteName, "com.hrvojebencik.hotplate")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter ProjectStoreTests`
Expected: build FAIL — `cannot find 'ProjectStore' in scope` (živi u GUI targetu).

- [ ] **Step 3: Move and make public**

```bash
git mv Sources/Hotplate/ProjectStore.swift Sources/HotplateCore/ProjectStore.swift
```
Zameni ceo sadržaj `Sources/HotplateCore/ProjectStore.swift`:
```swift
import Foundation
import Observation

/// Persists recent projects and global settings in UserDefaults. Shared by the app and the terminal tool.
@MainActor @Observable
public final class ProjectStore {
    public static let suiteName = "com.hrvojebencik.hotplate"

    /// The app reads its own domain through `.standard`; the terminal tool (another process, no bundle id)
    /// opens the same domain as a suite. Using the own bundle id as a suite name does not work, hence the check.
    public static func makeDefaults() -> UserDefaults {
        if Bundle.main.bundleIdentifier == suiteName { return .standard }
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    private let defaults: UserDefaults
    private enum Key {
        static let recents = "recents", flutterPath = "manualFlutterPath", debounce = "debounceMs", lastProject = "lastProjectPath"
        static let editorApp = "editorAppPath", editorCommand = "editorCustomCommand", editorUseCommand = "editorUseCustomCommand"
        static let editorFileCommand = "editorOpenFileCommand", hotkeys = "globalHotkeysEnabled"
    }

    public var recents: [Project] { didSet { save() } }
    public var manualFlutterPath: String { didSet { defaults.set(manualFlutterPath, forKey: Key.flutterPath) } }
    public var debounceMs: Int { didSet { defaults.set(debounceMs, forKey: Key.debounce) } }
    public var lastProjectPath: String? { didSet { defaults.set(lastProjectPath, forKey: Key.lastProject) } }
    /// Path to the editor .app bundle; empty means "auto-detect".
    public var editorAppPath: String { didSet { defaults.set(editorAppPath, forKey: Key.editorApp) } }
    /// Shell command template with `{path}`; used when `editorUseCustomCommand` is on.
    public var editorCustomCommand: String { didSet { defaults.set(editorCustomCommand, forKey: Key.editorCommand) } }
    public var editorUseCustomCommand: Bool { didSet { defaults.set(editorUseCustomCommand, forKey: Key.editorUseCommand) } }
    /// Shell command template with `{file}` and `{line}`; used for log links when the custom command is on.
    public var editorOpenFileCommand: String { didSet { defaults.set(editorOpenFileCommand, forKey: Key.editorFileCommand) } }
    public var globalHotkeysEnabled: Bool { didSet { defaults.set(globalHotkeysEnabled, forKey: Key.hotkeys) } }

    public init(defaults: UserDefaults = ProjectStore.makeDefaults()) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.recents), let list = try? JSONDecoder().decode([Project].self, from: data) {
            recents = list
        } else {
            recents = []
        }
        manualFlutterPath = defaults.string(forKey: Key.flutterPath) ?? ""
        let d = defaults.integer(forKey: Key.debounce)
        debounceMs = d == 0 ? 300 : d
        lastProjectPath = defaults.string(forKey: Key.lastProject)
        editorAppPath = defaults.string(forKey: Key.editorApp) ?? ""
        editorCustomCommand = defaults.string(forKey: Key.editorCommand) ?? "zed {path}"
        editorUseCustomCommand = defaults.bool(forKey: Key.editorUseCommand)
        editorOpenFileCommand = defaults.string(forKey: Key.editorFileCommand) ?? "zed {file}:{line}"
        globalHotkeysEnabled = defaults.object(forKey: Key.hotkeys) as? Bool ?? true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: Key.recents) }
    }

    public func touch(_ project: Project) {
        var p = project; p.lastOpened = Date()
        recents.removeAll { $0.path == p.path }
        recents.insert(p, at: 0)
        if recents.count > 10 { recents.removeLast(recents.count - 10) }
        lastProjectPath = p.path
    }

    public func update(_ project: Project) {
        if let i = recents.firstIndex(where: { $0.path == project.path }) { recents[i] = project } else { touch(project) }
    }

    public func remove(path: String) {
        recents.removeAll { $0.path == path }
        if lastProjectPath == path { lastProjectPath = nil }
    }
}
```
Napomena: `Theme.swift`, `MenuBarPanel.swift` i `AppDelegate.swift` u GUI targetu nemaju `import HotplateCore`. GUI još koristi `ProjectStore` samo iz fajlova koji ga već uvoze (`SessionViewModel.swift`, `Snapshot.swift`, `SettingsView.swift`), pa ovde ništa ne menjaš.

- [ ] **Step 4: Run all tests and build the app**

Run: `swift build && swift test`
Expected: build OK, svi testovi PASS (60 postojećih + 9 iz Task 1 + 3 nova).

- [ ] **Step 5: Commit**

```bash
git add -A Sources/Hotplate/ProjectStore.swift Sources/HotplateCore/ProjectStore.swift Tests/HotplateCoreTests/ProjectStoreTests.swift
git commit -m "refactor(core): move ProjectStore to HotplateCore with a shared defaults domain"
```

---
### Task 3: Session u HotplateCore (selidba bez promene ponašanja)

**Files:**
- Create: `Sources/HotplateCore/SessionTypes.swift`, `Sources/HotplateCore/SessionDependencies.swift`, `Sources/HotplateCore/Session.swift`
- Modify: `Sources/HotplateCore/FlutterDaemon.swift` (`terminate()`, `RestartResult.init`)
- Replace: `Sources/Hotplate/SessionViewModel.swift`
- Modify: `Sources/Hotplate/Theme.swift`, `Sources/Hotplate/MenuBarPanel.swift`, `Sources/Hotplate/AppDelegate.swift` (dodaj `import HotplateCore`)
- Modify: `Package.swift` (target `HotplateTestSupport`)
- Create: `Tests/HotplateTestSupport/SessionHarness.swift`
- Test: `Tests/HotplateCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: `ProjectStore` (Task 2), `FlutterDaemon`, `FileWatcher`, `Debouncer`, `DeviceService`, `FlutterLocator`, `LaunchConfigReader`, `EditorLauncher`, `PackageConfigResolver`
- Produces:
  - `public enum SessionState: Equatable { idle, starting, running, reloading, restarting, stopping, failed(String) }`
  - `public enum LogKind { normal, error, warning, info, success }`, `public struct LogLine { id: Int, text: String, kind: LogKind, time: Date }`
  - `public struct SessionHints { editor: String, flutter: String; static let gui, terminal }`
  - `public struct DaemonConfig`, `public protocol SessionDaemon`, `public protocol SessionWatcher`, `public struct SessionDependencies { static var live }`
  - `@MainActor @Observable public final class Session` sa `init(store:dependencies:hints:flutterPathOverride:restoreLastProject:)`, `var onError: ((String) -> Void)?`, `func forceQuit()` i svim članovima koje je imao `SessionViewModel` osim `openProjectPanel()`/`chooseEditorApp()`
  - `HotplateTestSupport`: `FakeDaemon`, `FakeWatcher`, `SessionHarness`, `TestProject.make(name:launchJSON:)`, `waitUntil(timeout:_:)`, `FlutterDevice.fake(_:_:platform:)`

- [ ] **Step 1: Dodaj `HotplateTestSupport` target u `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hotplate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HotplateCore"),
        .executableTarget(name: "Hotplate", dependencies: ["HotplateCore"]),
        .target(name: "HotplateTestSupport", dependencies: ["HotplateCore"], path: "Tests/HotplateTestSupport"),
        .testTarget(name: "HotplateCoreTests", dependencies: ["HotplateCore", "HotplateTestSupport"]),
    ]
)
```

- [ ] **Step 2: Napiši tipove i zavisnosti**

`Sources/HotplateCore/SessionTypes.swift`:
```swift
import Foundation

public enum SessionState: Equatable, Sendable {
    case idle, starting, running, reloading, restarting, stopping
    case failed(String)
}

public enum LogKind: Sendable { case normal, error, warning, info, success }

public struct LogLine: Identifiable, Sendable {
    public let id: Int
    public let text: String
    public let kind: LogKind
    public let time: Date

    public init(id: Int, text: String, kind: LogKind, time: Date) {
        self.id = id; self.text = text; self.kind = kind; self.time = time
    }
}

/// Front-end specific advice appended to error messages.
public struct SessionHints: Sendable {
    public var editor: String
    public var flutter: String

    public init(editor: String, flutter: String) { self.editor = editor; self.flutter = flutter }

    public static let gui = SessionHints(editor: "Pick one in Settings (⌘,) → Editor.", flutter: "Set the path in Settings (⌘,).")
    public static let terminal = SessionHints(editor: "Press E to choose one.",
                                              flutter: "Pass --flutter <path> or set it in Hotplate Settings.")
}
```

`Sources/HotplateCore/SessionDependencies.swift`:
```swift
import Foundation

public struct DaemonConfig: Equatable, Sendable {
    public let flutterPath: String
    public let projectPath: String
    public let deviceId: String
    public let extraArgs: [String]
    public let environment: [String: String]

    public init(flutterPath: String, projectPath: String, deviceId: String, extraArgs: [String], environment: [String: String]) {
        self.flutterPath = flutterPath; self.projectPath = projectPath; self.deviceId = deviceId
        self.extraArgs = extraArgs; self.environment = environment
    }
}

/// What `Session` needs from a running `flutter run --machine`; `FlutterDaemon` in production, a fake in tests.
public protocol SessionDaemon: AnyObject {
    var events: AsyncStream<DaemonEvent> { get }
    var wasStopRequested: Bool { get }
    func start() throws
    func stop() async
    func terminate()
    func restart(full: Bool) async throws -> RestartResult
}

extension FlutterDaemon: SessionDaemon {}

public protocol SessionWatcher: AnyObject {
    func stop()
}

extension FileWatcher: SessionWatcher {}

/// Everything `Session` does to the outside world, injectable for tests.
public struct SessionDependencies {
    public var locateFlutter: (_ manualPath: String?) -> String?
    public var environment: (_ flutterPath: String) -> [String: String]
    public var listDevices: (_ flutterPath: String, _ environment: [String: String], _ projectPath: String?) async throws -> [FlutterDevice]
    public var makeDaemon: (DaemonConfig) -> SessionDaemon
    /// Starts watching `path` for `.dart` changes and returns the running watcher.
    public var startWatcher: (_ path: String, _ onChange: @escaping () -> Void) -> SessionWatcher

    public init(locateFlutter: @escaping (String?) -> String?,
                environment: @escaping (String) -> [String: String],
                listDevices: @escaping (String, [String: String], String?) async throws -> [FlutterDevice],
                makeDaemon: @escaping (DaemonConfig) -> SessionDaemon,
                startWatcher: @escaping (String, @escaping () -> Void) -> SessionWatcher) {
        self.locateFlutter = locateFlutter; self.environment = environment; self.listDevices = listDevices
        self.makeDaemon = makeDaemon; self.startWatcher = startWatcher
    }

    public static var live: SessionDependencies {
        SessionDependencies(
            locateFlutter: { FlutterLocator.locate(manualPath: $0) },
            environment: { FlutterLocator.environment(flutterPath: $0) },
            listDevices: { flutter, env, project in
                try await DeviceService(flutterPath: flutter, environment: env).listDevices(projectPath: project)
            },
            makeDaemon: { c in
                FlutterDaemon(flutterPath: c.flutterPath, projectPath: c.projectPath, deviceId: c.deviceId,
                              extraArgs: c.extraArgs, environment: c.environment)
            },
            startWatcher: { path, onChange in
                let w = FileWatcher(path: path) { _ in onChange() }
                w.start()
                return w
            })
    }
}
```

U `Sources/HotplateCore/FlutterDaemon.swift` zameni:
```swift
public struct RestartResult: Sendable {
    public let code: Int
    public let message: String
}
```
sa:
```swift
public struct RestartResult: Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) { self.code = code; self.message = message }
}
```
i odmah posle `public func stop() async { … }` (pre `private var hasExited`) dodaj:
```swift
    /// Kills the process right away without asking the app to stop (second Ctrl+C in the terminal).
    public func terminate() {
        lock.lock(); stopRequested = true; lock.unlock()
        if process.isRunning { process.terminate() }
    }
```

- [ ] **Step 3: Napiši test podršku**

`Tests/HotplateTestSupport/SessionHarness.swift`:
```swift
import Foundation
import HotplateCore

public final class FakeDaemon: SessionDaemon, @unchecked Sendable {
    public let config: DaemonConfig
    public let events: AsyncStream<DaemonEvent>
    private let continuation: AsyncStream<DaemonEvent>.Continuation
    public private(set) var started = false
    public private(set) var stopCalls = 0
    public private(set) var terminated = false
    public private(set) var restartCalls: [Bool] = []
    /// How long each restart takes, in nanoseconds.
    public var restartDelay: UInt64 = 0
    public var wasStopRequested = false

    public init(config: DaemonConfig) {
        self.config = config
        var c: AsyncStream<DaemonEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
        continuation = c
    }

    public func start() throws { started = true }

    public func stop() async {
        stopCalls += 1
        wasStopRequested = true
        continuation.yield(.processExited(code: 0))
        continuation.finish()
    }

    public func terminate() {
        terminated = true
        wasStopRequested = true
        continuation.yield(.processExited(code: 143))
        continuation.finish()
    }

    public func restart(full: Bool) async throws -> RestartResult {
        restartCalls.append(full)
        if restartDelay > 0 { try await Task.sleep(nanoseconds: restartDelay) }
        return RestartResult(code: 0, message: "")
    }

    public func send(_ event: DaemonEvent) { continuation.yield(event) }
}

public final class FakeWatcher: SessionWatcher, @unchecked Sendable {
    public let path: String
    private let onChange: () -> Void
    public private(set) var stopped = false

    public init(path: String, onChange: @escaping () -> Void) { self.path = path; self.onChange = onChange }
    public func stop() { stopped = true }
    /// Simulates a saved `.dart` file.
    public func fire() { onChange() }
}

/// Builds a `Session` wired to fakes, with its own throwaway UserDefaults suite.
public final class SessionHarness: @unchecked Sendable {
    public var devices: [FlutterDevice]
    public var flutterPath: String? = "/fake/flutter"
    public private(set) var daemons: [FakeDaemon] = []
    public private(set) var watchers: [FakeWatcher] = []
    public let suiteName = "hotplate.tests.\(UUID().uuidString)"
    public var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    public var lastDaemon: FakeDaemon? { daemons.last }

    public init(devices: [FlutterDevice] = [.fake("ios1", "iPhone 16 Pro"), .fake("chrome", "Chrome", platform: "web-javascript")]) {
        self.devices = devices
    }

    deinit { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

    public var dependencies: SessionDependencies {
        SessionDependencies(
            locateFlutter: { [unowned self] _ in self.flutterPath },
            environment: { _ in ["PATH": "/usr/bin:/bin"] },
            listDevices: { [unowned self] _, _, _ in self.devices },
            makeDaemon: { [unowned self] config in
                let d = FakeDaemon(config: config); self.daemons.append(d); return d
            },
            startWatcher: { [unowned self] path, onChange in
                let w = FakeWatcher(path: path, onChange: onChange); self.watchers.append(w); return w
            })
    }

    @MainActor public func makeStore() -> ProjectStore {
        let store = ProjectStore(defaults: defaults)
        store.debounceMs = 20
        return store
    }

    @MainActor public func makeSession(store: ProjectStore? = nil, hints: SessionHints = .terminal) -> Session {
        Session(store: store ?? makeStore(), dependencies: dependencies, hints: hints, restoreLastProject: false)
    }
}

public enum TestProject {
    /// Creates a minimal Flutter project in a temp folder and returns its (symlink-resolved) path.
    public static func make(name: String = "demo", launchJSON: String? = nil) throws -> String {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hotplate-\(UUID().uuidString)")
            .appendingPathComponent(name)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("lib"), withIntermediateDirectories: true)
        try "name: \(name)\ndependencies:\n  flutter:\n    sdk: flutter\n"
            .write(to: root.appendingPathComponent("pubspec.yaml"), atomically: true, encoding: .utf8)
        try "void main() {}\n".write(to: root.appendingPathComponent("lib/main.dart"), atomically: true, encoding: .utf8)
        if let launchJSON {
            try fm.createDirectory(at: root.appendingPathComponent(".vscode"), withIntermediateDirectories: true)
            try launchJSON.write(to: root.appendingPathComponent(".vscode/launch.json"), atomically: true, encoding: .utf8)
        }
        return root.resolvingSymlinksInPath().path
    }

    public static let devAndProdLaunchJSON = """
    {
      "configurations": [
        { "name": "Dev", "request": "launch", "type": "dart", "args": ["--flavor", "dev"] },
        { "name": "Prod", "request": "launch", "type": "dart", "args": ["--flavor", "prod"] }
      ]
    }
    """
}

public extension FlutterDevice {
    static func fake(_ id: String, _ name: String, platform: String = "ios") -> FlutterDevice {
        FlutterDevice(id: id, name: name, targetPlatform: platform, emulator: true, isSupported: true)
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
public func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
}
```

- [ ] **Step 4: Write the failing tests**

`Tests/HotplateCoreTests/SessionTests.swift`:
```swift
import XCTest
@testable import HotplateCore
import HotplateTestSupport

@MainActor
final class SessionTests: XCTestCase {
    private func runningSession() async throws -> (Session, SessionHarness, FakeDaemon) {
        let h = SessionHarness()
        let path = try TestProject.make()
        let s = h.makeSession()
        s.selectProject(path: path)
        await s.refreshDevices()
        await s.run()
        let d = try XCTUnwrap(h.lastDaemon)
        d.send(.appStarted)
        let running = await waitUntil { s.state == .running }
        XCTAssertTrue(running)
        return (s, h, d)
    }

    func testRunStartsDaemonWithDeviceAndArgs() async throws {
        let h = SessionHarness()
        let path = try TestProject.make()
        let s = h.makeSession()
        s.selectProject(path: path)
        await s.refreshDevices()
        s.extraArgs = "--flavor dev"
        await s.run()
        XCTAssertEqual(s.state, .starting)
        let d = try XCTUnwrap(h.lastDaemon)
        XCTAssertTrue(d.started)
        XCTAssertEqual(d.config.deviceId, "ios1")
        XCTAssertEqual(d.config.extraArgs, ["--flavor", "dev"])
        XCTAssertEqual(d.config.projectPath, path)
        XCTAssertEqual(h.watchers.last?.path, "\(path)/lib")
    }

    func testReloadAndStopTransitions() async throws {
        let (s, h, d) = try await runningSession()
        await s.hotReload()
        XCTAssertEqual(d.restartCalls, [false])
        XCTAssertEqual(s.state, .running)
        await s.hotRestart()
        XCTAssertEqual(d.restartCalls, [false, true])
        await s.stop()
        let idle = await waitUntil { s.state == .idle }
        XCTAssertTrue(idle)
        XCTAssertEqual(d.stopCalls, 1)
        XCTAssertTrue(h.watchers.last?.stopped ?? false)
    }

    func testNonZeroExitFails() async throws {
        let (s, _, d) = try await runningSession()
        d.send(.processExited(code: 1))
        let failed = await waitUntil { s.state == .failed("flutter exited with code 1") }
        XCTAssertTrue(failed)
    }

    func testSavingDuringReloadQueuesExactlyOneMoreReload() async throws {
        let (s, h, d) = try await runningSession()
        d.restartDelay = 200_000_000
        let watcher = try XCTUnwrap(h.watchers.last)
        watcher.fire()
        let first = await waitUntil { d.restartCalls.count == 1 }
        XCTAssertTrue(first)
        watcher.fire(); watcher.fire()
        let second = await waitUntil(timeout: 3) { d.restartCalls.count == 2 && s.state == .running }
        XCTAssertTrue(second)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(d.restartCalls.count, 2)
    }

    func testAutoReloadOffIgnoresSaves() async throws {
        let (s, h, d) = try await runningSession()
        s.autoReload = false
        h.watchers.last?.fire()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(d.restartCalls, [])
    }

    func testForceQuitTerminatesDaemon() async throws {
        let (s, _, d) = try await runningSession()
        s.forceQuit()
        XCTAssertTrue(d.terminated)
        let idle = await waitUntil { s.state == .idle }
        XCTAssertTrue(idle)
    }

    func testMissingFlutterUsesFrontEndHint() {
        let h = SessionHarness()
        h.flutterPath = nil
        let s = h.makeSession(hints: .terminal)
        XCTAssertNil(s.flutterPath)
        XCTAssertTrue(s.logs.contains { $0.text.contains("Pass --flutter <path>") && $0.kind == .error })
        XCTAssertFalse(s.canRun)
    }

    func testBadProjectCallsOnError() throws {
        let h = SessionHarness()
        let s = h.makeSession()
        var errors: [String] = []
        s.onError = { errors.append($0) }
        s.selectProject(path: NSTemporaryDirectory())
        XCTAssertEqual(errors.count, 1)
        XCTAssertNil(s.project)
    }

    func testConcurrentDeviceRefreshesShareOneLoad() async throws {
        let h = SessionHarness()
        let s = h.makeSession()
        s.selectProject(path: try TestProject.make())
        async let a: Void = s.refreshDevices()
        async let b: Void = s.refreshDevices()
        _ = await (a, b)
        XCTAssertEqual(s.devices.map(\.id), ["ios1", "chrome"])
        XCTAssertFalse(s.isLoadingDevices)
    }
}
```

- [ ] **Step 5: Run to verify they fail**

Run: `swift test --filter SessionTests`
Expected: build FAIL — `cannot find 'Session' in scope`.

- [ ] **Step 6: Napiši `Session`**

`Sources/HotplateCore/Session.swift` (logika je preneta iz `SessionViewModel` bez promene ponašanja; razlike: zavisnosti preko `deps`, poruke koriste `hints`, `onError` umesto `NSSound.beep()`, deduplikacija `refreshDevices`, novo `forceQuit()`):
```swift
import Foundation
import Observation

/// The one run session: selected project, device list, the running daemon and its logs.
/// Shared by the macOS app and the terminal UI; holds no UI code.
@MainActor @Observable
public final class Session {
    public let store: ProjectStore
    public let hints: SessionHints
    public var state: SessionState = .idle
    public var project: Project?
    public var devices: [FlutterDevice] = []
    public var selectedDeviceId: String? { didSet { persistProjectSettings() } }
    public var extraArgs: String = "" {
        didSet {
            // A manual edit of the args field means "custom", unless we are applying a config ourselves.
            if !applyingLaunchConfig, !suppressPersist, oldValue != extraArgs, selectedLaunchConfigName != nil {
                selectedLaunchConfigName = nil
            }
            persistProjectSettings()
        }
    }
    public var launchConfigs: [LaunchConfig] = []
    public var selectedLaunchConfigName: String? { didSet { persistProjectSettings() } }
    public var autoReload: Bool = true { didSet { persistProjectSettings() } }
    public var logs: [LogLine] = []
    public var isLoadingDevices = false
    public var flutterPath: String?
    public var followLogs = true
    public var deviceError: String?
    public var installedEditors: [InstalledEditor] = EditorLauncher.detectInstalled()
    /// Called when the user should notice a failure (the app beeps).
    @ObservationIgnored public var onError: ((String) -> Void)?

    @ObservationIgnored private let deps: SessionDependencies
    @ObservationIgnored private let flutterPathOverride: String?
    private var daemon: SessionDaemon?
    private var eventTask: Task<Void, Never>?
    private var watcher: SessionWatcher?
    private var debouncer: Debouncer?
    private var deviceRefreshTask: Task<Void, Never>?
    private var pendingReload = false
    private var nextLogId = 0
    private var suppressPersist = false
    private var applyingLaunchConfig = false
    private let maxLogLines = 5000

    public init(store: ProjectStore, dependencies: SessionDependencies = .live, hints: SessionHints = .gui,
                flutterPathOverride: String? = nil, restoreLastProject: Bool = true) {
        self.store = store
        self.deps = dependencies
        self.hints = hints
        self.flutterPathOverride = flutterPathOverride
        relocateFlutter()
        if restoreLastProject, let last = store.lastProjectPath, FileManager.default.fileExists(atPath: last) {
            selectProject(path: last)
        }
    }

    // MARK: Derived

    public var isRunning: Bool {
        switch state {
        case .idle, .failed: return false
        default: return true
        }
    }
    public var canRun: Bool { !isRunning && project != nil && selectedDeviceId != nil && flutterPath != nil }
    public var canStop: Bool { isRunning && state != .stopping }
    public var canReload: Bool { state == .running }
    public var selectedDevice: FlutterDevice? { devices.first { $0.id == selectedDeviceId } }
    public var statusText: String {
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

    public func relocateFlutter() {
        flutterPath = deps.locateFlutter(flutterPathOverride ?? store.manualFlutterPath)
        if let flutterPath {
            log("Using flutter at \(flutterPath)", .info)
            let path = deps.environment(flutterPath)["PATH"] ?? ""
            if let pod = FlutterLocator.find(tool: "pod", inPath: path) { log("CocoaPods: \(pod)", .info) }
            else { log("CocoaPods (pod) not found on PATH; iOS/macOS builds with plugins will fail.", .warning) }
        } else {
            log("flutter executable not found. \(hints.flutter)", .error)
        }
    }

    // MARK: Projects

    public func selectProject(path: String) {
        if isRunning { Task { await stop(); self.selectProject(path: path) }; return }
        do {
            var p = try Project.load(path: path)
            if let saved = store.recents.first(where: { $0.path == path }) {
                p.lastDeviceId = saved.lastDeviceId; p.extraArgs = saved.extraArgs; p.autoReload = saved.autoReload
                p.launchConfigName = saved.launchConfigName
            }
            launchConfigs = LaunchConfigReader.load(projectPath: path)
            suppressPersist = true
            project = p
            extraArgs = p.extraArgs
            autoReload = p.autoReload
            selectedDeviceId = p.lastDeviceId
            selectedLaunchConfigName = p.launchConfigName
            suppressPersist = false
            store.touch(p)
            log("Project: \(p.name) (\(p.path))", .info)
            if !launchConfigs.isEmpty {
                log("launch.json: \(launchConfigs.map(\.name).joined(separator: ", "))", .info)
            }
            if let name = p.launchConfigName, launchConfigs.contains(where: { $0.name == name }) {
                selectLaunchConfig(name: name)
            } else if p.launchConfigName == nil, p.extraArgs.isEmpty, let first = launchConfigs.first {
                selectLaunchConfig(name: first.name)
            } else {
                selectedLaunchConfigName = nil
            }
            Task { await refreshDevices() }
        } catch {
            log(error.localizedDescription, .error)
            onError?(error.localizedDescription)
        }
    }

    public func removeRecent(path: String) {
        store.remove(path: path)
        if project?.path == path { project = nil }
    }

    private func persistProjectSettings() {
        guard !suppressPersist, var p = project else { return }
        p.lastDeviceId = selectedDeviceId; p.extraArgs = extraArgs; p.autoReload = autoReload
        p.launchConfigName = selectedLaunchConfigName
        project = p
        store.update(p)
    }

    // MARK: Editor

    /// The editor that "Open in Editor" will use: the configured app, or the first installed known editor.
    public var effectiveEditor: InstalledEditor? {
        if !store.editorAppPath.isEmpty, FileManager.default.fileExists(atPath: store.editorAppPath) {
            return InstalledEditor(name: EditorLauncher.name(ofApp: store.editorAppPath), appPath: store.editorAppPath)
        }
        return installedEditors.first
    }

    public var canOpenInEditor: Bool { project != nil && (store.editorUseCustomCommand || effectiveEditor != nil) }

    /// Picker value shared by the toolbar menu, Settings and the terminal: an app path, or "custom".
    public var editorSelection: String {
        get {
            if store.editorUseCustomCommand { return "custom" }
            return effectiveEditor?.appPath ?? ""
        }
        set {
            if newValue == "custom" { store.editorUseCustomCommand = true }
            else { store.editorUseCustomCommand = false; store.editorAppPath = newValue }
        }
    }

    public var editorButtonTitle: String {
        if store.editorUseCustomCommand { return "Command" }
        return effectiveEditor?.name ?? "Editor"
    }

    /// The configured app when it is not one of the detected known editors (chosen via "Other application…").
    public var otherEditor: InstalledEditor? {
        guard !store.editorAppPath.isEmpty, !installedEditors.contains(where: { $0.appPath == store.editorAppPath }),
              FileManager.default.fileExists(atPath: store.editorAppPath) else { return nil }
        return InstalledEditor(name: EditorLauncher.name(ofApp: store.editorAppPath), appPath: store.editorAppPath)
    }

    public func refreshInstalledEditors() { installedEditors = EditorLauncher.detectInstalled() }

    public func openInEditor() {
        guard let project else { return }
        if store.editorUseCustomCommand {
            let env = flutterPath.map { deps.environment($0) } ?? ProcessInfo.processInfo.environment
            do {
                try EditorLauncher.runCustom(template: store.editorCustomCommand, projectPath: project.path, environment: env)
                log("Opened in editor: \(EditorLauncher.expand(template: store.editorCustomCommand, projectPath: project.path))", .info)
            } catch {
                log("Editor command failed: \(error.localizedDescription)", .error)
            }
            return
        }
        guard let editor = effectiveEditor else {
            log("No editor found. \(hints.editor)", .error)
            onError?("No editor found.")
            return
        }
        Task {
            do {
                try await EditorLauncher.open(projectPath: project.path, withApp: editor.appPath)
                log("Opened \(project.name) in \(editor.name).", .info)
            } catch {
                log("Could not open \(editor.name): \(error.localizedDescription)", .error)
            }
        }
    }

    /// Opens the file behind a log link at its line, in the chosen editor.
    public func openLogLink(location: String, line: Int?, column: Int?) {
        guard let project else { return }
        let resolver = PackageConfigResolver(projectPath: project.path)
        guard let file = resolver.resolve(location), FileManager.default.fileExists(atPath: file) else {
            log("Can't find a file for \(location). Run `flutter pub get` if it is in another package.", .warning)
            return
        }
        let env = flutterPath.map { deps.environment($0) } ?? ProcessInfo.processInfo.environment
        let where_ = line.map { ":\($0)" } ?? ""
        do {
            if store.editorUseCustomCommand {
                let cmd = EditorLauncher.expand(template: store.editorOpenFileCommand, projectPath: project.path, file: file, line: line)
                try EditorLauncher.run(argv: ["/bin/zsh", "-lic", cmd], environment: env)
                log("Opened \((file as NSString).lastPathComponent)\(where_) via \(cmd)", .info)
                return
            }
            guard let editor = effectiveEditor else { log("No editor found. \(hints.editor)", .error); return }
            let bundleId = Bundle(path: editor.appPath)?.bundleIdentifier ?? ""
            if let argv = EditorLauncher.openFileCommand(appPath: editor.appPath, bundleIdentifier: bundleId, file: file, line: line, column: column),
               FileManager.default.isExecutableFile(atPath: argv[0]) {
                try EditorLauncher.run(argv: argv, environment: env)
                log("Opened \((file as NSString).lastPathComponent)\(where_) in \(editor.name).", .info)
            } else {
                Task { try? await EditorLauncher.open(projectPath: file, withApp: editor.appPath) }
                log("Opened \((file as NSString).lastPathComponent) in \(editor.name) (this editor has no line-jump CLI).", .info)
            }
        } catch {
            log("Could not open \(file): \(error.localizedDescription)", .error)
        }
    }

    // MARK: Launch configurations (.vscode/launch.json)

    /// Applies a launch configuration to the args field (and device, if the config names one).
    public func selectLaunchConfig(name: String?) {
        guard let name, let cfg = launchConfigs.first(where: { $0.name == name }) else {
            selectedLaunchConfigName = nil
            return
        }
        applyingLaunchConfig = true
        extraArgs = ArgumentSplitter.join(cfg.flutterRunArguments)
        applyingLaunchConfig = false
        selectedLaunchConfigName = name
        if let dev = cfg.deviceId, devices.contains(where: { $0.id == dev }) { selectedDeviceId = dev }
        log("Launch config \"\(name)\" → \(extraArgs.isEmpty ? "(no extra args)" : extraArgs)", .info)
        if let mode = cfg.flutterMode?.lowercased(), mode != "debug" {
            log("Note: \(mode) mode does not support hot reload.", .warning)
        }
    }

    /// Re-reads launch.json so edits made in the editor are picked up before a run.
    public func reloadLaunchConfigs() {
        guard let project else { return }
        launchConfigs = LaunchConfigReader.load(projectPath: project.path)
        guard let name = selectedLaunchConfigName else { return }
        if launchConfigs.contains(where: { $0.name == name }) {
            selectLaunchConfig(name: name)
        } else {
            log("Launch config \"\(name)\" no longer exists in launch.json; keeping current args.", .warning)
            selectedLaunchConfigName = nil
        }
    }

    // MARK: Devices

    /// Reloads the device list; concurrent callers wait for the same `flutter devices` run.
    public func refreshDevices() async {
        if let running = deviceRefreshTask { await running.value; return }
        let task = Task { await self.loadDevices() }
        deviceRefreshTask = task
        await task.value
        deviceRefreshTask = nil
    }

    private func loadDevices() async {
        guard let flutterPath else { return }
        isLoadingDevices = true; deviceError = nil
        defer { isLoadingDevices = false }
        do {
            let list = try await deps.listDevices(flutterPath, deps.environment(flutterPath), project?.path)
            devices = list
            if let name = selectedLaunchConfigName, let dev = launchConfigs.first(where: { $0.name == name })?.deviceId,
               list.contains(where: { $0.id == dev }) {
                selectedDeviceId = dev
            }
            if selectedDeviceId == nil || !list.contains(where: { $0.id == selectedDeviceId }) {
                selectedDeviceId = list.first?.id
            }
            if list.isEmpty { deviceError = "No devices found. Start a simulator or connect a device, then refresh." }
            log("Devices: \(list.isEmpty ? "none" : list.map(\.displayName).joined(separator: ", "))", .info)
        } catch {
            deviceError = error.localizedDescription
            log("Device list failed: \(error.localizedDescription)", .error)
        }
    }

    // MARK: Run / stop

    public func run() async {
        guard canRun, project != nil, selectedDeviceId != nil, flutterPath != nil else { return }
        clearLogs()
        reloadLaunchConfigs()
        guard let project, let deviceId = selectedDeviceId, let flutterPath else { return }
        state = .starting
        pendingReload = false
        let args = ArgumentSplitter.split(extraArgs)
        log("$ flutter run --machine -d \(deviceId) \(args.joined(separator: " "))", .info)
        let d = deps.makeDaemon(DaemonConfig(flutterPath: flutterPath, projectPath: project.path, deviceId: deviceId,
                                             extraArgs: args, environment: deps.environment(flutterPath)))
        daemon = d
        eventTask = Task { [weak self] in
            for await event in d.events { self?.handle(event) }
        }
        do { try d.start() } catch {
            state = .failed(error.localizedDescription)
            log(error.localizedDescription, .error)
            daemon = nil
            return
        }
        startWatcher(project: project)
    }

    public func stop() async {
        guard let d = daemon, isRunning else { return }
        state = .stopping
        log("Stopping…", .info)
        await d.stop()
    }

    /// Kills flutter immediately (second Ctrl+C in the terminal).
    public func forceQuit() {
        stopWatcher()
        daemon?.terminate()
    }

    public func hotReload() async { await restart(full: false) }
    public func hotRestart() async { await restart(full: true) }

    private func restart(full: Bool) async {
        guard let d = daemon else { return }
        guard state == .running else {
            if state == .reloading || state == .restarting { pendingReload = true }
            return
        }
        state = full ? .restarting : .reloading
        let label = full ? "Hot restart" : "Hot reload"
        let started = Date()
        do {
            let r = try await d.restart(full: full)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            if r.code == 0 { log("\(label) done in \(ms) ms. \(r.message)", .success) }
            else { log("\(label) failed: \(r.message)", .error) }
        } catch {
            log("\(label) error: \(error.localizedDescription)", .error)
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
        watcher = deps.startWatcher(project.libPath) { debouncer.trigger() }
    }

    private func stopWatcher() {
        watcher?.stop(); watcher = nil
        debouncer?.cancel(); debouncer = nil
    }

    private func autoReloadFired() async {
        guard autoReload else { return }
        switch state {
        case .running, .reloading, .restarting: break
        default: return
        }
        log("Change detected in lib/ → hot reload", .info)
        await hotReload()
    }

    // MARK: Events

    private func handle(_ event: DaemonEvent) {
        switch event {
        case .connected: break
        case .daemonLog(let level, let message):
            log(message, level == "error" ? .error : (level == "warning" ? .warning : .normal))
        case .appStarting(_, let deviceId, _):
            log("Launching on \(deviceId)…", .info)
        case .appStarted:
            state = .running
            log("App started. Auto reload is \(autoReload ? "on" : "off").", .success)
        case .progress(let message, let finished):
            if let message, !finished { log(message, .normal) }
        case .appLog(let text, let isError):
            log(text, isError ? .error : .normal)
        case .rawOutput(let text, let isStderr):
            log(text, isStderr ? .warning : .normal)
        case .webLaunchUrl(let url):
            log("Web app at \(url)", .info)
        case .appStopped:
            log("App stopped.", .info)
        case .processExited(let code):
            let requested = daemon?.wasStopRequested ?? false
            stopWatcher()
            daemon = nil; eventTask = nil
            if code == 0 || requested {
                state = .idle; log("flutter exited.", .info)
            } else {
                state = .failed("flutter exited with code \(code)"); log("flutter exited with code \(code)", .error)
            }
        }
    }

    // MARK: Logs

    @ObservationIgnored private let mirrorLogsToStderr = ProcessInfo.processInfo.environment["HOTPLATE_LOG_STDERR"] == "1"

    public func log(_ text: String, _ kind: LogKind = .normal) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            logs.append(LogLine(id: nextLogId, text: String(line), kind: kind, time: Date())); nextLogId += 1
            if mirrorLogsToStderr { FileHandle.standardError.write(Data("[\(kind)] \(line)\n".utf8)) }
        }
        if logs.count > maxLogLines { logs.removeFirst(logs.count - maxLogLines) }
    }

    public func clearLogs() { logs.removeAll() }

    /// Called on quit: stops the daemon if needed.
    public func shutdown() async {
        stopWatcher()
        await daemon?.stop()
    }
}
```

- [ ] **Step 7: Prebaci GUI na `Session`**

Zameni ceo sadržaj `Sources/Hotplate/SessionViewModel.swift`:
```swift
import AppKit
import UniformTypeIdentifiers
import HotplateCore

/// The SwiftUI views keep their name for the model; the logic lives in `HotplateCore.Session`.
typealias SessionViewModel = Session

extension Session {
    static let shared: Session = Snapshot.requestedDirectory != nil ? preview() : makeAppSession()

    private static func makeAppSession() -> Session {
        let session = Session(store: ProjectStore(), hints: .gui)
        session.onError = { _ in NSSound.beep() }
        return session
    }

    func openProjectPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a Flutter project folder (the one containing pubspec.yaml)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectProject(path: url.path)
    }

    func chooseEditorApp() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose the editor application"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.editorAppPath = url.path
        store.editorUseCustomCommand = false
    }
}
```
Dodaj `import HotplateCore` ispod postojećih importa u `Sources/Hotplate/Theme.swift`, `Sources/Hotplate/MenuBarPanel.swift` i `Sources/Hotplate/AppDelegate.swift`. `Snapshot.swift` ne menjaš: `SessionViewModel(store:)` je sada `Session(store:)` sa podrazumevanim ostalim parametrima.

- [ ] **Step 8: Run all tests, build, and snapshot the GUI**

Run: `swift build && swift test`
Expected: build OK (moguća su samo upozorenja o Sendable), svi testovi PASS, uključujući 9 iz `SessionTests`.

Run: `swift run Hotplate --snapshot "$TMPDIR/hotplate-snap"` pa otvori `main-dark.png` i `menubar-dark.png` (Read tool).
Expected: proces izlazi sa 0, slike izgledaju isto kao `docs/images/main-dark.png` i `docs/images/menubar-dark.png`.

- [ ] **Step 9: Commit**

```bash
git add -A Package.swift Sources/HotplateCore Sources/Hotplate Tests/HotplateTestSupport Tests/HotplateCoreTests/SessionTests.swift
git commit -m "refactor: move session logic from the app into HotplateCore.Session"
```

---
### Task 4: Overrides, startup i izbori iz TUI-ja

**Files:**
- Modify: `Sources/HotplateCore/SessionTypes.swift`, `Sources/HotplateCore/Session.swift`
- Test: `Tests/HotplateCoreTests/SessionOverridesTests.swift`

**Interfaces:**
- Consumes: `Session` (Task 3), `DeviceMatcher` (Task 1), `SessionHarness`/`TestProject` (Task 3)
- Produces:
  - `public struct SessionOverrides: Equatable { deviceQuery: String?, configName: String?, args: String?, autoReload: Bool? }`
  - `public enum StartupOutcome: Equatable { case started, idle, needsDevice(filter: String) }`
  - `Session.overrides`, `Session.startup(autoRun: Bool) async -> StartupOutcome`, `Session.chooseDevice(id:)`, `Session.chooseLaunchConfig(name: String?)`, `Session.setArgs(_:)`, `Session.setAutoReload(_:)`, `Session.switchProject(path:)`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateCoreTests/SessionOverridesTests.swift`:
```swift
import XCTest
@testable import HotplateCore
import HotplateTestSupport

@MainActor
final class SessionOverridesTests: XCTestCase {
    private let threeDevices: [FlutterDevice] = [.fake("ios1", "iPhone 16 Pro"), .fake("chrome", "Chrome", platform: "web-javascript"),
                                                 .fake("macos", "macOS", platform: "darwin")]

    /// A project whose saved settings are: device macos, config Prod, auto reload on.
    private func savedProject(_ h: SessionHarness) throws -> (String, ProjectStore) {
        let path = try TestProject.make(launchJSON: TestProject.devAndProdLaunchJSON)
        let store = h.makeStore()
        store.update(Project(path: path, name: "demo", lastDeviceId: "macos", extraArgs: "--flavor prod", autoReload: true,
                             launchConfigName: "Prod"))
        return (path, store)
    }

    private func saved(_ h: SessionHarness, _ path: String) -> Project? { h.makeStore().recents.first { $0.path == path } }

    func testCommandLineOverridesApplyButAreNotSaved() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "chrome", configName: "Dev", autoReload: false)
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: false)
        XCTAssertEqual(outcome, .idle)
        XCTAssertEqual(s.selectedDeviceId, "chrome")
        XCTAssertEqual(s.selectedLaunchConfigName, "Dev")
        XCTAssertEqual(s.extraArgs, "--flavor dev")
        XCTAssertFalse(s.autoReload)
        let p = try XCTUnwrap(saved(h, path))
        XCTAssertEqual(p.lastDeviceId, "macos")
        XCTAssertEqual(p.launchConfigName, "Prod")
        XCTAssertEqual(p.extraArgs, "--flavor prod")
        XCTAssertTrue(p.autoReload)
    }

    func testChoosingInTheTUIClearsThatOverrideAndSaves() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "chrome", configName: "Dev", autoReload: false)
        s.selectProject(path: path)
        _ = await s.startup(autoRun: false)

        s.chooseDevice(id: "ios1")
        XCTAssertNil(s.overrides.deviceQuery)
        XCTAssertEqual(saved(h, path)?.lastDeviceId, "ios1")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod", "config is still overridden")

        s.setArgs("--verbose")
        XCTAssertNil(s.overrides.configName)
        XCTAssertEqual(saved(h, path)?.extraArgs, "--verbose")
        XCTAssertNil(saved(h, path)?.launchConfigName)

        s.setAutoReload(false)
        XCTAssertEqual(saved(h, path)?.autoReload, false)
    }

    func testChooseLaunchConfigSavesIt() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(args: "--flavor qa")
        s.selectProject(path: path)
        XCTAssertNil(s.selectedLaunchConfigName)
        XCTAssertEqual(s.extraArgs, "--flavor qa")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod")
        s.chooseLaunchConfig(name: "Dev")
        XCTAssertEqual(s.extraArgs, "--flavor dev")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Dev")
        XCTAssertNil(s.overrides.args)
    }

    func testArgsOverrideMeansCustomWithoutSaving() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(args: "--flavor dev --dart-define=X=1")
        s.selectProject(path: path)
        XCTAssertNil(s.selectedLaunchConfigName)
        XCTAssertEqual(s.extraArgs, "--flavor dev --dart-define=X=1")
        XCTAssertEqual(saved(h, path)?.extraArgs, "--flavor prod")
        XCTAssertEqual(saved(h, path)?.launchConfigName, "Prod")
    }

    func testUnknownConfigOverrideWarnsAndKeepsSaved() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(configName: "Staging")
        s.selectProject(path: path)
        XCTAssertEqual(s.selectedLaunchConfigName, "Prod")
        XCTAssertNil(s.overrides.configName)
        XCTAssertTrue(s.logs.contains { $0.kind == .warning && $0.text.contains("\"Staging\" not found") })
    }

    func testSwitchProjectClearsOverrides() throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let other = try TestProject.make(name: "other")
        let s = h.makeSession(store: store)
        s.overrides = SessionOverrides(deviceQuery: "chrome", args: "--x", autoReload: false)
        s.selectProject(path: path)
        s.switchProject(path: other)
        XCTAssertEqual(s.overrides, SessionOverrides())
        XCTAssertEqual(s.project?.path, other)
        XCTAssertTrue(s.autoReload)
    }

    func testStartupRunsOnRememberedDevice() async throws {
        let h = SessionHarness(devices: threeDevices)
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .started)
        XCTAssertEqual(h.lastDaemon?.config.deviceId, "macos")
        XCTAssertEqual(h.lastDaemon?.config.extraArgs, ["--flavor", "prod"])
    }

    func testStartupAsksForDeviceWhenNoneRemembered() async throws {
        let h = SessionHarness(devices: threeDevices)
        let s = h.makeSession()
        s.selectProject(path: try TestProject.make())
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .needsDevice(filter: ""))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testStartupAsksWhenRememberedDeviceIsGone() async throws {
        let h = SessionHarness(devices: [.fake("ios1", "iPhone 16 Pro")])
        let (path, store) = try savedProject(h)
        let s = h.makeSession(store: store)
        s.selectProject(path: path)
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .needsDevice(filter: ""))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testAmbiguousDeviceQueryAsksWithFilter() async throws {
        let h = SessionHarness(devices: [.fake("a", "iPhone 16"), .fake("b", "iPhone 15")])
        let s = h.makeSession()
        s.overrides = SessionOverrides(deviceQuery: "iphone")
        s.selectProject(path: try TestProject.make())
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .needsDevice(filter: "iphone"))
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testStartupWithoutProjectIsIdle() async {
        let h = SessionHarness()
        let s = h.makeSession()
        let outcome = await s.startup(autoRun: true)
        XCTAssertEqual(outcome, .idle)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter SessionOverridesTests`
Expected: build FAIL — `cannot find 'SessionOverrides' in scope`.

- [ ] **Step 3: Dodaj tipove u `SessionTypes.swift`** (na kraj fajla)

```swift
/// Choices given on the command line. They apply to this session only and are never saved.
public struct SessionOverrides: Equatable, Sendable {
    public var deviceQuery: String?
    public var configName: String?
    public var args: String?
    public var autoReload: Bool?

    public init(deviceQuery: String? = nil, configName: String? = nil, args: String? = nil, autoReload: Bool? = nil) {
        self.deviceQuery = deviceQuery; self.configName = configName; self.args = args; self.autoReload = autoReload
    }
}

public enum StartupOutcome: Equatable, Sendable {
    case started
    case idle
    /// No device could be chosen safely; the front end should show the device list with this filter.
    case needsDevice(filter: String)
}
```

- [ ] **Step 4: Izmeni `Session.swift`**

4a. Ispod `@ObservationIgnored public var onError …` dodaj:
```swift
    /// Command-line choices for this session only; `persistProjectSettings` never writes them.
    public var overrides = SessionOverrides()
    /// The saved device when the project was opened. The device refresh may pick and save a fallback,
    /// so `startup` must not read `project.lastDeviceId` to decide whether the device was remembered.
    @ObservationIgnored private var deviceAtOpen: String?
```

4b. U `selectProject(path:)` zameni red `            Task { await refreshDevices() }` sa:
```swift
            deviceAtOpen = p.lastDeviceId
            applyOverrides()
            Task { await refreshDevices() }
```

4c. Zameni celu `persistProjectSettings()` sa:
```swift
    private func persistProjectSettings() {
        guard !suppressPersist, var p = project else { return }
        // An overridden field keeps its saved value; `project` always holds the saved values.
        if overrides.deviceQuery == nil { p.lastDeviceId = selectedDeviceId }
        if overrides.configName == nil, overrides.args == nil {
            p.extraArgs = extraArgs
            p.launchConfigName = selectedLaunchConfigName
        }
        if overrides.autoReload == nil { p.autoReload = autoReload }
        project = p
        store.update(p)
    }

    private func applyOverrides() {
        if let name = overrides.configName {
            if launchConfigs.contains(where: { $0.name == name }) {
                selectLaunchConfig(name: name)
            } else {
                log("Launch config \"\(name)\" not found in launch.json; using the saved settings.", .warning)
                overrides.configName = nil
            }
        }
        if let args = overrides.args {
            extraArgs = args
            selectedLaunchConfigName = nil
        }
        if let on = overrides.autoReload { autoReload = on }
    }

    // MARK: Choices made in the terminal UI (clear the matching override, then save as usual)

    public func chooseDevice(id: String) {
        overrides.deviceQuery = nil
        selectedDeviceId = id
    }

    /// `nil` means "Custom": keep the current args.
    public func chooseLaunchConfig(name: String?) {
        overrides.configName = nil; overrides.args = nil
        selectLaunchConfig(name: name)
    }

    public func setArgs(_ args: String) {
        overrides.configName = nil; overrides.args = nil
        extraArgs = args
        selectedLaunchConfigName = nil
    }

    public func setAutoReload(_ on: Bool) {
        overrides.autoReload = nil
        autoReload = on
    }

    /// Opens another project from the recents list; command-line overrides belonged to the first one.
    public func switchProject(path: String) {
        overrides = SessionOverrides()
        selectProject(path: path)
    }
```

4d. Iza `refreshDevices()` dodaj:
```swift
    /// Terminal start: waits for the device list, resolves `--device`, and runs when the device is known.
    public func startup(autoRun: Bool) async -> StartupOutcome {
        guard project != nil else { return .idle }
        await refreshDevices()
        if let query = overrides.deviceQuery {
            guard case .one(let device) = DeviceMatcher.match(query: query, in: devices) else { return .needsDevice(filter: query) }
            selectedDeviceId = device.id
        } else {
            let configDevice = selectedLaunchConfigName.flatMap { name in launchConfigs.first { $0.name == name }?.deviceId }
            let remembered = [deviceAtOpen, configDevice].compactMap { $0 }
            guard let id = selectedDeviceId, remembered.contains(id), devices.contains(where: { $0.id == id }) else {
                return .needsDevice(filter: "")
            }
        }
        guard autoRun, canRun else { return .idle }
        await run()
        return .started
    }
```

- [ ] **Step 5: Run all tests**

Run: `swift test`
Expected: svi PASS (11 novih u `SessionOverridesTests`).

- [ ] **Step 6: Commit**

```bash
git add Sources/HotplateCore/SessionTypes.swift Sources/HotplateCore/Session.swift Tests/HotplateCoreTests/SessionOverridesTests.swift
git commit -m "feat(core): session-only overrides, terminal startup and explicit choices"
```

---
### Task 5: HotplateTUI target i dekoder ulaza

**Files:**
- Modify: `Package.swift`
- Create: `Sources/HotplateTUI/InputEvent.swift`, `Sources/HotplateTUI/InputDecoder.swift`
- Test: `Tests/HotplateTUITests/InputDecoderTests.swift`

**Interfaces:**
- Produces: `enum Key: Hashable { char(Character), ctrl(Character), enter, escape, backspace, tab, up, down, left, right, home, end, pageUp, pageDown, delete }`, `enum MouseButton { left, wheelUp, wheelDown, other }`, `struct MouseEvent { button, x, y (0-based), pressed }`, `enum InputEvent: Equatable { key(Key), mouse(MouseEvent), paste(String) }`, `struct InputDecoder { mutating feed([UInt8]) -> [InputEvent]; var hasPendingEscape: Bool; mutating flushEscape() -> [InputEvent] }`

- [ ] **Step 1: Dodaj targete u `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hotplate",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HotplateCore"),
        .target(name: "HotplateTUI", dependencies: ["HotplateCore"]),
        .executableTarget(name: "Hotplate", dependencies: ["HotplateCore"]),
        .target(name: "HotplateTestSupport", dependencies: ["HotplateCore"], path: "Tests/HotplateTestSupport"),
        .testTarget(name: "HotplateCoreTests", dependencies: ["HotplateCore", "HotplateTestSupport"]),
        .testTarget(name: "HotplateTUITests", dependencies: ["HotplateTUI", "HotplateCore", "HotplateTestSupport"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

`Tests/HotplateTUITests/InputDecoderTests.swift`:
```swift
import XCTest
@testable import HotplateTUI

final class InputDecoderTests: XCTestCase {
    private func decode(_ s: String) -> [InputEvent] {
        var d = InputDecoder()
        return d.feed(Array(s.utf8))
    }

    func testPrintableAndControlKeys() {
        XCTAssertEqual(decode("rR"), [.key(.char("r")), .key(.char("R"))])
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0x03, 0x0D, 0x7F, 0x09, 0x0C]),
                       [.key(.ctrl("c")), .key(.enter), .key(.backspace), .key(.tab), .key(.ctrl("l"))])
    }

    func testCursorAndEditingKeys() {
        XCTAssertEqual(decode("\u{1B}[A\u{1B}[B\u{1B}[C\u{1B}[D"), [.key(.up), .key(.down), .key(.right), .key(.left)])
        XCTAssertEqual(decode("\u{1B}OA\u{1B}OB"), [.key(.up), .key(.down)])
        XCTAssertEqual(decode("\u{1B}[5~\u{1B}[6~\u{1B}[3~"), [.key(.pageUp), .key(.pageDown), .key(.delete)])
        XCTAssertEqual(decode("\u{1B}[H\u{1B}[F\u{1B}[1~\u{1B}[4~"), [.key(.home), .key(.end), .key(.home), .key(.end)])
    }

    func testSequenceSplitAcrossReads() {
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0x1B, 0x5B]), [])
        XCTAssertFalse(d.hasPendingEscape)
        XCTAssertEqual(d.feed([0x41]), [.key(.up)])
    }

    func testLoneEscapeWaitsForFlush() {
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0x1B]), [])
        XCTAssertTrue(d.hasPendingEscape)
        XCTAssertEqual(d.flushEscape(), [.key(.escape)])
        XCTAssertFalse(d.hasPendingEscape)
        XCTAssertEqual(d.flushEscape(), [])
    }

    func testUTF8SplitAcrossReads() {
        var d = InputDecoder()
        XCTAssertEqual(d.feed([0xC5]), [])
        XCTAssertEqual(d.feed([0xBE]), [.key(.char("ž"))])
    }

    func testSGRMouse() {
        XCTAssertEqual(decode("\u{1B}[<0;10;5M"), [.mouse(MouseEvent(button: .left, x: 9, y: 4, pressed: true))])
        XCTAssertEqual(decode("\u{1B}[<0;10;5m"), [.mouse(MouseEvent(button: .left, x: 9, y: 4, pressed: false))])
        XCTAssertEqual(decode("\u{1B}[<64;3;3M"), [.mouse(MouseEvent(button: .wheelUp, x: 2, y: 2, pressed: true))])
        XCTAssertEqual(decode("\u{1B}[<65;3;3M"), [.mouse(MouseEvent(button: .wheelDown, x: 2, y: 2, pressed: true))])
        XCTAssertEqual(decode("\u{1B}[<32;1;1M"), [], "motion is ignored")
    }

    func testBracketedPaste() {
        XCTAssertEqual(decode("\u{1B}[200~hello\nr\u{1B}[201~q"), [.paste("hello\nr"), .key(.char("q"))])
        var d = InputDecoder()
        XCTAssertEqual(d.feed(Array("\u{1B}[200~abc\u{1B}[20".utf8)), [])
        XCTAssertEqual(d.feed(Array("1~".utf8)), [.paste("abc")])
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `swift test --filter InputDecoderTests`
Expected: build FAIL — `cannot find 'InputDecoder' in scope` (ili prazan target).

- [ ] **Step 4: Implement**

`Sources/HotplateTUI/InputEvent.swift`:
```swift
public enum Key: Hashable, Sendable {
    case char(Character)
    /// Ctrl plus a lowercase letter, e.g. `.ctrl("c")`.
    case ctrl(Character)
    case enter, escape, backspace, tab, up, down, left, right, home, end, pageUp, pageDown, delete
}

public enum MouseButton: Equatable, Sendable { case left, wheelUp, wheelDown, other }

public struct MouseEvent: Equatable, Sendable {
    public let button: MouseButton
    /// 0-based column and row.
    public let x: Int
    public let y: Int
    public let pressed: Bool

    public init(button: MouseButton, x: Int, y: Int, pressed: Bool) {
        self.button = button; self.x = x; self.y = y; self.pressed = pressed
    }
}

public enum InputEvent: Equatable, Sendable {
    case key(Key)
    case mouse(MouseEvent)
    case paste(String)
}
```

`Sources/HotplateTUI/InputDecoder.swift`:
```swift
/// Turns raw terminal bytes into key, mouse and paste events. Incomplete sequences wait for the next `feed`.
public struct InputDecoder {
    private static let pasteEnd: [UInt8] = Array("\u{1B}[201~".utf8)
    private var buffer: [UInt8] = []
    private var pasting = false
    private var pasteBytes: [UInt8] = []

    public init() {}

    /// A lone ESC is either the Escape key or the start of a sequence; the caller flushes it after a short pause.
    public var hasPendingEscape: Bool { !pasting && buffer == [0x1B] }

    public mutating func feed(_ bytes: [UInt8]) -> [InputEvent] {
        buffer += bytes
        var events: [InputEvent] = []
        while !buffer.isEmpty {
            if pasting {
                guard let end = indexOf(Self.pasteEnd) else {
                    // Keep a possible partial terminator for the next read.
                    let keep = min(buffer.count, Self.pasteEnd.count - 1)
                    pasteBytes += buffer.dropLast(keep)
                    buffer = Array(buffer.suffix(keep))
                    break
                }
                pasteBytes += buffer[..<end]
                buffer.removeFirst(end + Self.pasteEnd.count)
                pasting = false
                events.append(.paste(String(decoding: pasteBytes, as: UTF8.self)))
                pasteBytes = []
                continue
            }
            guard let (event, used) = decodeOne() else { break }
            buffer.removeFirst(used)
            if let event { events.append(event) }
        }
        return events
    }

    public mutating func flushEscape() -> [InputEvent] {
        guard hasPendingEscape else { return [] }
        buffer.removeAll()
        return [.key(.escape)]
    }

    /// One event (or nil for ignored bytes) and how many bytes it used; nil when more bytes are needed.
    private mutating func decodeOne() -> (InputEvent?, Int)? {
        let b = buffer[0]
        switch b {
        case 0x1B: return decodeEscape()
        case 0x0D, 0x0A: return (.key(.enter), 1)
        case 0x09: return (.key(.tab), 1)
        case 0x7F, 0x08: return (.key(.backspace), 1)
        case 0x01...0x1A: return (.key(.ctrl(Character(UnicodeScalar(b + 0x60)))), 1)
        case 0x00, 0x1C...0x1F: return (nil, 1)
        default: return decodeUTF8()
        }
    }

    private mutating func decodeEscape() -> (InputEvent?, Int)? {
        guard buffer.count >= 2 else { return nil }
        switch buffer[1] {
        case UInt8(ascii: "["): return decodeCSI()
        case UInt8(ascii: "O"):
            guard buffer.count >= 3 else { return nil }
            let key: Key? = switch buffer[2] {
            case UInt8(ascii: "A"): .up
            case UInt8(ascii: "B"): .down
            case UInt8(ascii: "C"): .right
            case UInt8(ascii: "D"): .left
            case UInt8(ascii: "H"): .home
            case UInt8(ascii: "F"): .end
            default: nil
            }
            return (key.map { .key($0) }, 3)
        default:
            // ESC ESC, or Alt+key: report Escape and decode the rest separately.
            return (.key(.escape), 1)
        }
    }

    private mutating func decodeCSI() -> (InputEvent?, Int)? {
        var i = 2
        while i < buffer.count, (0x20...0x3F).contains(buffer[i]) { i += 1 }
        guard i < buffer.count else { return nil }
        let final = buffer[i]
        guard (0x40...0x7E).contains(final) else { return (nil, i) }
        let params = String(decoding: buffer[2..<i], as: UTF8.self)
        let used = i + 1
        if params.hasPrefix("<"), final == UInt8(ascii: "M") || final == UInt8(ascii: "m") {
            return (Self.mouse(params: String(params.dropFirst()), pressed: final == UInt8(ascii: "M")), used)
        }
        let first = params.split(separator: ";").first.flatMap { Int($0) }
        switch final {
        case UInt8(ascii: "A"): return (.key(.up), used)
        case UInt8(ascii: "B"): return (.key(.down), used)
        case UInt8(ascii: "C"): return (.key(.right), used)
        case UInt8(ascii: "D"): return (.key(.left), used)
        case UInt8(ascii: "H"): return (.key(.home), used)
        case UInt8(ascii: "F"): return (.key(.end), used)
        case UInt8(ascii: "~"):
            switch first {
            case 1, 7: return (.key(.home), used)
            case 4, 8: return (.key(.end), used)
            case 3: return (.key(.delete), used)
            case 5: return (.key(.pageUp), used)
            case 6: return (.key(.pageDown), used)
            case 200: pasting = true; return (nil, used)
            default: return (nil, used)
            }
        default: return (nil, used)
        }
    }

    private static func mouse(params: String, pressed: Bool) -> InputEvent? {
        let parts = params.split(separator: ";").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let code = parts[0]
        if code & 32 != 0 { return nil }
        let button: MouseButton = switch code & ~(4 | 8 | 16) {
        case 0: .left
        case 64: .wheelUp
        case 65: .wheelDown
        default: .other
        }
        return .mouse(MouseEvent(button: button, x: parts[1] - 1, y: parts[2] - 1, pressed: pressed))
    }

    private func decodeUTF8() -> (InputEvent?, Int)? {
        let b = buffer[0]
        let length = b < 0x80 ? 1 : b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1
        guard buffer.count >= length else { return nil }
        guard let c = String(bytes: buffer[0..<length], encoding: .utf8)?.first else { return (nil, length) }
        return (.key(.char(c)), length)
    }

    private func indexOf(_ needle: [UInt8]) -> Int? {
        guard buffer.count >= needle.count else { return nil }
        for i in 0...(buffer.count - needle.count) where Array(buffer[i..<(i + needle.count)]) == needle { return i }
        return nil
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter InputDecoderTests`
Expected: PASS (7 testova).

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/HotplateTUI Tests/HotplateTUITests
git commit -m "feat(tui): input decoder for keys, SGR mouse and bracketed paste"
```

---

### Task 6: Stil, širina znakova, ekranski bafer i diff renderer

**Files:**
- Create: `Sources/HotplateTUI/Style.swift`, `Sources/HotplateTUI/CharWidth.swift`, `Sources/HotplateTUI/ScreenBuffer.swift`, `Sources/HotplateTUI/Renderer.swift`
- Test: `Tests/HotplateTUITests/ScreenBufferTests.swift`, `Tests/HotplateTUITests/RendererTests.swift`

**Interfaces:**
- Produces: `struct TermColor { index: UInt8; static black, red, green, yellow, blue, magenta, cyan, white, gray }`, `struct Style: Hashable { fg, bg, bold, dim, underline, inverse; static plain; var sgr: String }`, `CharWidth.of(Character) -> Int`, `CharWidth.of(String) -> Int`, `CharWidth.truncate(String, to: Int) -> String`, `struct Cell { char, width, style }`, `struct ScreenBuffer { width, height; subscript(x, y); @discardableResult put(_:x:y:style:maxWidth:) -> Int; fill(x:y:width:style:); text(row:) -> String }`, `struct Renderer { mutating render(ScreenBuffer) -> String; mutating invalidate() }`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateTUITests/ScreenBufferTests.swift`:
```swift
import XCTest
@testable import HotplateTUI

final class ScreenBufferTests: XCTestCase {
    func testPutClipsAtRightEdgeAndMaxWidth() {
        var b = ScreenBuffer(width: 5, height: 1)
        XCTAssertEqual(b.put("abcdefg", x: 1, y: 0), 4)
        XCTAssertEqual(b.text(row: 0), " abcd")
        XCTAssertEqual(b.put("xyz", x: 0, y: 0, maxWidth: 2), 2)
        XCTAssertEqual(b.text(row: 0), "xybcd")
    }

    func testWideCharacterIsNotSplitAtRightEdge() {
        var b = ScreenBuffer(width: 3, height: 1)
        XCTAssertEqual(b.put("ab界", x: 0, y: 0), 2)
        XCTAssertEqual(b.text(row: 0), "ab ")
        var c = ScreenBuffer(width: 4, height: 1)
        XCTAssertEqual(c.put("🔥x", x: 0, y: 0), 3)
        XCTAssertEqual(c.text(row: 0), "🔥x ")
        XCTAssertEqual(c[1, 0].width, 0)
    }

    func testOutOfBoundsWritesAreIgnored() {
        var b = ScreenBuffer(width: 3, height: 1)
        XCTAssertEqual(b.put("a", x: 0, y: 5), 0)
        XCTAssertEqual(b.put("a", x: -1, y: 0), 0)
        b.fill(x: 2, y: 0, width: 10, style: Style(inverse: true))
        XCTAssertTrue(b[2, 0].style.inverse)
    }

    func testCharWidths() {
        XCTAssertEqual(CharWidth.of("a"), 1)
        XCTAssertEqual(CharWidth.of("界"), 2)
        XCTAssertEqual(CharWidth.of("🔥"), 2)
        XCTAssertEqual(CharWidth.of("●"), 1)
        XCTAssertEqual(CharWidth.of("▶"), 1)
        XCTAssertEqual(CharWidth.of("\u{0301}"), 0)
        XCTAssertEqual(CharWidth.truncate("abcdef", to: 4), "abc…")
        XCTAssertEqual(CharWidth.truncate("abc", to: 4), "abc")
    }
}
```

`Tests/HotplateTUITests/RendererTests.swift`:
```swift
import XCTest
@testable import HotplateTUI

final class RendererTests: XCTestCase {
    private let esc = "\u{1B}"

    func testFirstFrameClearsAndDrawsEverything() {
        var b = ScreenBuffer(width: 2, height: 1)
        b.put("ab", x: 0, y: 0)
        var r = Renderer()
        XCTAssertEqual(r.render(b), "\(esc)[0m\(esc)[2J\(esc)[1;1H\(esc)[0mab\(esc)[0m")
    }

    func testUnchangedFrameEmitsNothing() {
        var b = ScreenBuffer(width: 2, height: 1)
        b.put("ab", x: 0, y: 0)
        var r = Renderer()
        _ = r.render(b)
        XCTAssertEqual(r.render(b), "")
    }

    func testOneChangedCellMovesOnceAndWritesOnce() {
        var b = ScreenBuffer(width: 3, height: 2)
        b.put("abc", x: 0, y: 0)
        var r = Renderer()
        _ = r.render(b)
        b.put("X", x: 1, y: 1)
        XCTAssertEqual(r.render(b), "\(esc)[2;2H\(esc)[0mX\(esc)[0m")
    }

    func testStyleChangeIsEmitted() {
        var b = ScreenBuffer(width: 1, height: 1)
        b.put("A", x: 0, y: 0)
        var r = Renderer()
        _ = r.render(b)
        b.put("A", x: 0, y: 0, style: Style(fg: .red, bold: true))
        XCTAssertEqual(r.render(b), "\(esc)[1;1H\(esc)[0;1;31mA\(esc)[0m")
    }

    func testRendersWideCharacterOnce() {
        var b = ScreenBuffer(width: 3, height: 1)
        b.put("界", x: 0, y: 0)
        var r = Renderer()
        XCTAssertEqual(r.render(b), "\(esc)[0m\(esc)[2J\(esc)[1;1H\(esc)[0m界 \(esc)[0m")
    }

    func testResizeOrInvalidateRedrawsFully() {
        var r = Renderer()
        _ = r.render(ScreenBuffer(width: 2, height: 1))
        XCTAssertTrue(r.render(ScreenBuffer(width: 3, height: 1)).hasPrefix("\(esc)[0m\(esc)[2J"))
        r.invalidate()
        XCTAssertTrue(r.render(ScreenBuffer(width: 3, height: 1)).hasPrefix("\(esc)[0m\(esc)[2J"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter 'ScreenBufferTests|RendererTests'`
Expected: build FAIL — `cannot find 'ScreenBuffer' in scope`.

- [ ] **Step 3: Implement**

`Sources/HotplateTUI/Style.swift`:
```swift
/// One of the 16 ANSI colors, so the user's terminal theme decides the actual shade.
public struct TermColor: Hashable, Sendable {
    public let index: UInt8
    public init(index: UInt8) { self.index = index }

    public static let black = TermColor(index: 0)
    public static let red = TermColor(index: 1)
    public static let green = TermColor(index: 2)
    public static let yellow = TermColor(index: 3)
    public static let blue = TermColor(index: 4)
    public static let magenta = TermColor(index: 5)
    public static let cyan = TermColor(index: 6)
    public static let white = TermColor(index: 7)
    public static let gray = TermColor(index: 8)
}

public struct Style: Hashable, Sendable {
    public var fg: TermColor?
    public var bg: TermColor?
    public var bold: Bool
    public var dim: Bool
    public var underline: Bool
    public var inverse: Bool

    public init(fg: TermColor? = nil, bg: TermColor? = nil, bold: Bool = false, dim: Bool = false,
                underline: Bool = false, inverse: Bool = false) {
        self.fg = fg; self.bg = bg; self.bold = bold; self.dim = dim; self.underline = underline; self.inverse = inverse
    }

    public static let plain = Style()

    /// SGR sequence that resets, then applies this style.
    public var sgr: String {
        var codes = ["0"]
        if bold { codes.append("1") }
        if dim { codes.append("2") }
        if underline { codes.append("4") }
        if inverse { codes.append("7") }
        if let fg { codes.append(fg.index < 8 ? "3\(fg.index)" : "9\(fg.index - 8)") }
        if let bg { codes.append(bg.index < 8 ? "4\(bg.index)" : "10\(bg.index - 8)") }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}
```

`Sources/HotplateTUI/CharWidth.swift`:
```swift
/// Terminal column width of characters: 0 for marks and controls, 2 for East Asian wide and emoji.
public enum CharWidth {
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F, 0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF,
        0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
        0x1F300...0x1F64F, 0x1F900...0x1F9FF, 0x20000...0x3FFFD,
    ]

    public static func of(_ c: Character) -> Int {
        guard let scalar = c.unicodeScalars.first else { return 0 }
        let v = scalar.value
        if v < 0x20 || (0x7F..<0xA0).contains(v) { return 0 }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format: return 0
        default: break
        }
        if scalar.properties.isEmojiPresentation || c.unicodeScalars.contains(where: { $0.value == 0xFE0F }) { return 2 }
        if wideRanges.contains(where: { $0.contains(v) }) { return 2 }
        return 1
    }

    public static func of(_ s: String) -> Int { s.reduce(0) { $0 + of($1) } }

    /// Cuts `s` to at most `width` columns, ending with "…" when it was cut.
    public static func truncate(_ s: String, to width: Int) -> String {
        guard of(s) > width else { return s }
        guard width > 1 else { return width == 1 ? "…" : "" }
        var out = ""; var used = 0
        for c in s {
            let w = of(c)
            if used + w > width - 1 { break }
            out.append(c); used += w
        }
        return out + "…"
    }
}
```

`Sources/HotplateTUI/ScreenBuffer.swift`:
```swift
public struct Cell: Equatable, Sendable {
    public var char: Character
    /// 1 or 2 for a visible character; 0 for the right half of a wide character.
    public var width: Int
    public var style: Style

    public static let blank = Cell(char: " ", width: 1, style: .plain)
}

/// A grid of cells that widgets draw into; `Renderer` turns it into terminal output.
public struct ScreenBuffer: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell]

    public init(width: Int, height: Int) {
        self.width = max(0, width); self.height = max(0, height)
        cells = Array(repeating: .blank, count: self.width * self.height)
    }

    public subscript(x: Int, y: Int) -> Cell { cells[y * width + x] }

    /// Writes `text` at (x, y), clipped to `maxWidth` columns and the right edge. Returns the columns used.
    @discardableResult
    public mutating func put(_ text: String, x: Int, y: Int, style: Style = .plain, maxWidth: Int? = nil) -> Int {
        guard y >= 0, y < height, x >= 0, x < width else { return 0 }
        let limit = min(width, x + (maxWidth ?? width))
        var col = x
        for c in text {
            let w = CharWidth.of(c)
            if w == 0 { continue }
            if col + w > limit { break }
            cells[y * width + col] = Cell(char: c, width: w, style: style)
            if w == 2 { cells[y * width + col + 1] = Cell(char: " ", width: 0, style: style) }
            col += w
        }
        return col - x
    }

    public mutating func fill(x: Int = 0, y: Int, width w: Int? = nil, style: Style) {
        guard y >= 0, y < height else { return }
        let start = max(0, x), end = min(width, x + (w ?? width))
        guard start < end else { return }
        for col in start..<end { cells[y * width + col] = Cell(char: " ", width: 1, style: style) }
    }

    /// Plain text of a row, for tests and debugging.
    public func text(row y: Int) -> String {
        (0..<width).compactMap { x -> String? in
            let c = self[x, y]
            return c.width == 0 ? nil : String(c.char)
        }.joined()
    }
}
```

`Sources/HotplateTUI/Renderer.swift`:
```swift
/// Emits only what changed since the previous frame: cursor moves, style changes and characters.
public struct Renderer {
    private var previous: ScreenBuffer?

    public init() {}

    /// The next frame is drawn from scratch (after resize or Ctrl+L).
    public mutating func invalidate() { previous = nil }

    public mutating func render(_ frame: ScreenBuffer) -> String {
        var out = ""
        let old = previous.flatMap { $0.width == frame.width && $0.height == frame.height ? $0 : nil }
        if old == nil { out += "\u{1B}[0m\u{1B}[2J" }
        var style: Style?
        var cursor: (x: Int, y: Int)?
        for y in 0..<frame.height {
            var x = 0
            while x < frame.width {
                let cell = frame[x, y]
                if cell.width == 0 { x += 1; continue }
                if let old, old[x, y] == cell, cell.width == 1 || old[x + 1, y] == frame[x + 1, y] {
                    x += cell.width
                    continue
                }
                if cursor.map({ $0.x != x || $0.y != y }) ?? true { out += "\u{1B}[\(y + 1);\(x + 1)H" }
                if style != cell.style { out += cell.style.sgr; style = cell.style }
                out.append(cell.char)
                x += cell.width
                cursor = (x, y)
            }
        }
        if style != nil { out += "\u{1B}[0m" }
        previous = frame
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'ScreenBufferTests|RendererTests'`
Expected: PASS (10 testova).

- [ ] **Step 5: Commit**

```bash
git add Sources/HotplateTUI Tests/HotplateTUITests
git commit -m "feat(tui): styles, character widths, screen buffer and diff renderer"
```

---
### Task 7: Log viewport (prelamanje, skrol, follow, izbor, linkovi, pretraga)

**Files:**
- Create: `Sources/HotplateTUI/LogText.swift`, `Sources/HotplateTUI/LogViewport.swift`
- Test: `Tests/HotplateTUITests/LogViewportTests.swift`

**Interfaces:**
- Consumes: `LogLine`, `LogKind` (Task 3), `LogLinkParser`, `LogLink` (postojeće), `CharWidth` (Task 6)
- Produces: `LogText.sanitize(String) -> String`, `struct VisualRow { lineId, text, startOffset, isFirst }`, `struct LogEntry { text, kind, time, rows }`, `struct LogViewport` sa: `static gutter = 11`, `rows`, `top`, `height`, `follow`, `selectedLineId`, `searchQuery`, `visibleRows`, `entry(_:)`, `update(lines:width:height:)`, `scroll(by:)`, `scrollToTop()`, `scrollToBottom()`, `setFollow(_:)`, `select(lineId:)`, `moveSelection(by:)`, `setSearch(_:)`, `links(onLine:)`, `lastLinkLine()`, `linkLine(from:forward:)`, `searchMatch(from:forward:)`, `hit(row:column:) -> (lineId: Int, link: LogLink?)?`, `static offsets(of: LogLink, in: String) -> Range<Int>`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateTUITests/LogViewportTests.swift`:
```swift
import XCTest
import HotplateCore
@testable import HotplateTUI

final class LogViewportTests: XCTestCase {
    private let g = LogViewport.gutter

    private func lines(_ texts: [String], kinds: [LogKind]? = nil, firstId: Int = 0) -> [LogLine] {
        texts.enumerated().map { i, t in LogLine(id: firstId + i, text: t, kind: kinds?[i] ?? .normal, time: Date(timeIntervalSince1970: 0)) }
    }

    private func numbered(_ n: Int, firstId: Int = 0) -> [LogLine] { lines((0..<n).map { "line \($0 + firstId)" }, firstId: firstId) }

    func testWrapsLongLinesUnderTheText() {
        var v = LogViewport()
        v.update(lines: lines([String(repeating: "0123456789", count: 2) + "01234"]), width: g + 10, height: 5)
        XCTAssertEqual(v.rows.map(\.text), ["0123456789", "0123456789", "01234"])
        XCTAssertEqual(v.rows.map(\.isFirst), [true, false, false])
        XCTAssertEqual(v.rows.map(\.startOffset), [0, 10, 20])
    }

    func testVeryLongLineWrapsWithoutLosingCharacters() {
        var v = LogViewport()
        v.update(lines: lines([String(repeating: "x", count: 20_000)]), width: g + 100, height: 10)
        XCTAssertEqual(v.rows.count, 200)
        XCTAssertEqual(v.rows.last?.startOffset, 19_900)
        XCTAssertEqual(v.rows.map(\.text.count).reduce(0, +), 20_000)
    }

    func testFollowKeepsTheBottomVisible() {
        var v = LogViewport()
        v.update(lines: numbered(30), width: 80, height: 10)
        XCTAssertEqual(v.top, 20)
        v.update(lines: numbered(35), width: 80, height: 10)
        XCTAssertEqual(v.top, 25)
        XCTAssertEqual(v.visibleRows.last?.lineId, 34)
    }

    func testScrollingUpStopsFollowAndBottomResumesIt() {
        var v = LogViewport()
        v.update(lines: numbered(30), width: 80, height: 10)
        v.scroll(by: -3)
        XCTAssertFalse(v.follow)
        XCTAssertEqual(v.top, 17)
        v.update(lines: numbered(40), width: 80, height: 10)
        XCTAssertEqual(v.top, 17, "view stays where the user put it")
        v.scrollToBottom()
        XCTAssertTrue(v.follow)
        XCTAssertEqual(v.top, 30)
    }

    func testScrollPositionInsideAWrappedLineSurvivesUpdates() {
        var v = LogViewport()
        let long = String(repeating: "y", count: 50)
        v.update(lines: lines([long] + (0..<20).map { "l\($0)" }), width: g + 10, height: 5)
        v.scrollToTop()
        v.scroll(by: 2)
        XCTAssertEqual(v.rows[v.top].startOffset, 20)
        v.update(lines: lines([long] + (0..<21).map { "l\($0)" }), width: g + 10, height: 5)
        XCTAssertEqual(v.rows[v.top].startOffset, 20)
    }

    func testHitFindsLinkOnAWrappedRow() throws {
        var v = LogViewport()
        v.update(lines: lines(["aaaaaaaaaa(package:app/x.dart:3:1)"]), width: g + 10, height: 5)
        let hit = try XCTUnwrap(v.hit(row: 1, column: g + 1))
        XCTAssertEqual(hit.lineId, 0)
        XCTAssertEqual(hit.link?.location, "package:app/x.dart")
        XCTAssertEqual(hit.link?.line, 3)
        XCTAssertNil(v.hit(row: 0, column: g)?.link)
        XCTAssertNil(v.hit(row: 0, column: 2)?.link, "the gutter is not a link")
        XCTAssertNil(v.hit(row: 9, column: g), "below the last row")
    }

    func testSanitizesAnsiAndTabsKeepingLinkColumns() throws {
        XCTAssertEqual(LogText.sanitize("\u{1B}[31mError\u{1B}[0m\tat x\r"), "Error    at x")
        var v = LogViewport()
        v.update(lines: lines(["\u{1B}[31mError\u{1B}[0m\tat lib/main.dart:5"]), width: g + 80, height: 5)
        XCTAssertEqual(v.entry(0)?.text, "Error    at lib/main.dart:5")
        let hit = try XCTUnwrap(v.hit(row: 0, column: g + 12))
        XCTAssertEqual(hit.link?.location, "lib/main.dart")
        XCTAssertEqual(hit.link?.line, 5)
    }

    func testSelectScrollsIntoViewAndStopsFollow() {
        var v = LogViewport()
        v.update(lines: numbered(30), width: 80, height: 10)
        v.select(lineId: 3)
        XCTAssertEqual(v.selectedLineId, 3)
        XCTAssertEqual(v.top, 3)
        XCTAssertFalse(v.follow)
        v.moveSelection(by: -1)
        XCTAssertEqual(v.selectedLineId, 2)
        XCTAssertEqual(v.top, 2)
        v.moveSelection(by: -5)
        XCTAssertEqual(v.selectedLineId, 0)
    }

    func testSelectionIsClearedWhenItsLineIsTrimmed() {
        var v = LogViewport()
        v.update(lines: numbered(10), width: 80, height: 5)
        v.select(lineId: 1)
        v.update(lines: numbered(10, firstId: 5), width: 80, height: 5)
        XCTAssertNil(v.selectedLineId)
    }

    func testLastLinkLinePrefersTheNewestError() {
        var v = LogViewport()
        v.update(lines: lines(["see lib/a.dart:1", "Error at lib/b.dart:2", "see lib/c.dart:3", "plain"],
                              kinds: [.normal, .error, .normal, .normal]), width: 80, height: 10)
        XCTAssertEqual(v.lastLinkLine(), 1)
        XCTAssertEqual(v.linkLine(from: nil, forward: false), 2)
        XCTAssertEqual(v.linkLine(from: 2, forward: false), 1)
        XCTAssertEqual(v.linkLine(from: 0, forward: true), 1)
        XCTAssertNil(v.linkLine(from: 2, forward: true))
    }

    func testSearchFindsMatchesAndWraps() {
        var v = LogViewport()
        v.update(lines: lines(["alpha", "Beta", "gamma", "beta again"]), width: 80, height: 10)
        v.setSearch("beta")
        XCTAssertEqual(v.searchMatch(from: nil, forward: false), 3)
        XCTAssertEqual(v.searchMatch(from: 3, forward: false), 1)
        XCTAssertEqual(v.searchMatch(from: 3, forward: true), 1, "wraps around")
        v.setSearch("")
        XCTAssertNil(v.searchQuery)
        XCTAssertNil(v.searchMatch(from: nil, forward: true))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter LogViewportTests`
Expected: build FAIL — `cannot find 'LogViewport' in scope`.

- [ ] **Step 3: Implement**

`Sources/HotplateTUI/LogText.swift`:
```swift
import Foundation

enum LogText {
    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    /// Removes terminal escape sequences and control characters from app output; tabs become four spaces.
    static func sanitize(_ s: String) -> String {
        let stripped = ansi.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        var out = ""
        for c in stripped {
            if c == "\t" { out += "    " }
            else if c.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) { out.append(c) }
        }
        return out
    }
}
```

`Sources/HotplateTUI/LogViewport.swift`:
```swift
import Foundation
import HotplateCore

public struct VisualRow: Equatable, Sendable {
    public let lineId: Int
    /// This row's part of the sanitized line.
    public let text: String
    /// Character offset of `text` within the sanitized line.
    public let startOffset: Int
    public let isFirst: Bool
}

public struct LogEntry: Sendable {
    public let text: String
    public let kind: LogKind
    public let time: Date
    public let rows: [VisualRow]
}

/// The wrapped, scrollable log: which rows are visible, what is selected, what a search matches.
public struct LogViewport {
    /// Columns before the text: selection marker, `HH:mm:ss`, two spaces.
    public static let gutter = 11

    public private(set) var rows: [VisualRow] = []
    public private(set) var top = 0
    public private(set) var height = 0
    public private(set) var follow = true
    public private(set) var selectedLineId: Int?
    public private(set) var searchQuery: String?
    private var lineIds: [Int] = []
    private var entries: [Int: LogEntry] = [:]
    private var wrapWidth = 0

    public init() {}

    public func entry(_ lineId: Int) -> LogEntry? { entries[lineId] }
    private var maxTop: Int { max(0, rows.count - height) }
    public var visibleRows: ArraySlice<VisualRow> { rows[min(top, rows.count)..<min(rows.count, top + height)] }

    public mutating func update(lines: [LogLine], width: Int, height: Int) {
        let textWidth = max(1, width - Self.gutter)
        if textWidth != wrapWidth { entries = [:]; wrapWidth = textWidth }
        let anchor = follow || !rows.indices.contains(top) ? nil : rows[top]
        var newRows: [VisualRow] = []
        newRows.reserveCapacity(rows.count + 16)
        for line in lines {
            if let e = entries[line.id] { newRows += e.rows; continue }
            let text = LogText.sanitize(line.text)
            let e = LogEntry(text: text, kind: line.kind, time: line.time, rows: Self.wrap(lineId: line.id, text: text, width: textWidth))
            entries[line.id] = e
            newRows += e.rows
        }
        if entries.count > lines.count + 1000 {
            let ids = Set(lines.map(\.id))
            entries = entries.filter { ids.contains($0.key) }
        }
        lineIds = lines.map(\.id)
        rows = newRows
        self.height = max(0, height)
        if let s = selectedLineId, !lineIds.contains(s) { selectedLineId = nil }
        if follow {
            top = maxTop
        } else if let anchor,
                  let i = rows.firstIndex(where: { $0.lineId == anchor.lineId && $0.startOffset == anchor.startOffset })
                    ?? rows.firstIndex(where: { $0.lineId == anchor.lineId }) {
            top = min(i, maxTop)
        } else {
            top = min(top, maxTop)
        }
    }

    // MARK: Scrolling

    public mutating func scroll(by delta: Int) {
        top = min(max(0, top + delta), maxTop)
        follow = top >= maxTop
    }

    public mutating func scrollToTop() { top = 0; follow = maxTop == 0 }
    public mutating func scrollToBottom() { top = maxTop; follow = true }

    public mutating func setFollow(_ on: Bool) {
        if on { selectedLineId = nil; scrollToBottom() } else { follow = false }
    }

    // MARK: Selection

    public mutating func select(lineId: Int?) {
        selectedLineId = lineId
        guard let lineId, let first = rows.firstIndex(where: { $0.lineId == lineId }) else { return }
        follow = false
        let last = rows.lastIndex(where: { $0.lineId == lineId }) ?? first
        if first < top { top = first }
        else if last >= top + height { top = min(maxTop, max(first, last - height + 1)) }
    }

    public mutating func moveSelection(by delta: Int) {
        guard let current = selectedLineId, let i = lineIds.firstIndex(of: current) else { return }
        select(lineId: lineIds[min(max(0, i + delta), lineIds.count - 1)])
    }

    // MARK: Links

    public func links(onLine id: Int) -> [LogLink] { entries[id].map { LogLinkParser.links(in: $0.text) } ?? [] }

    /// The newest line with an error and a link, else the newest line with a link.
    public func lastLinkLine() -> Int? {
        let withLinks = lineIds.filter { !links(onLine: $0).isEmpty }
        return withLinks.last(where: { entries[$0]?.kind == .error }) ?? withLinks.last
    }

    /// The next line with a link after `from` (or from the start/end when nil).
    public func linkLine(from lineId: Int?, forward: Bool) -> Int? {
        let ids = forward ? lineIds : Array(lineIds.reversed())
        let start = lineId.flatMap { id in ids.firstIndex(of: id).map { $0 + 1 } } ?? 0
        guard start < ids.count else { return nil }
        return ids[start...].first { !links(onLine: $0).isEmpty }
    }

    public static func offsets(of link: LogLink, in text: String) -> Range<Int> {
        text.distance(from: text.startIndex, to: link.range.lowerBound)..<text.distance(from: text.startIndex, to: link.range.upperBound)
    }

    /// The line under a log-area position (row 0 = first visible row) and the link under the column, if any.
    public func hit(row: Int, column: Int) -> (lineId: Int, link: LogLink?)? {
        let index = top + row
        guard row >= 0, row < height, rows.indices.contains(index) else { return nil }
        let r = rows[index]
        guard column >= Self.gutter, let text = entries[r.lineId]?.text else { return (r.lineId, nil) }
        var col = Self.gutter, offset = r.startOffset
        var hitOffset: Int?
        for c in r.text {
            let w = CharWidth.of(c)
            if column < col + w { hitOffset = offset; break }
            col += w; offset += 1
        }
        guard let hitOffset else { return (r.lineId, nil) }
        let link = LogLinkParser.links(in: text).first { Self.offsets(of: $0, in: text).contains(hitOffset) }
        return (r.lineId, link)
    }

    // MARK: Search

    public mutating func setSearch(_ query: String?) {
        searchQuery = (query ?? "").isEmpty ? nil : query
    }

    /// The next line containing the search text after `from`, wrapping around.
    public func searchMatch(from lineId: Int?, forward: Bool) -> Int? {
        guard let q = searchQuery else { return nil }
        let ids = forward ? lineIds : Array(lineIds.reversed())
        let matches = { (id: Int) in entries[id]?.text.range(of: q, options: .caseInsensitive) != nil }
        let start = min(ids.count, lineId.flatMap { id in ids.firstIndex(of: id).map { $0 + 1 } } ?? 0)
        return ids[start...].first(where: matches) ?? ids[..<start].first(where: matches)
    }

    // MARK: Wrapping

    static func wrap(lineId: Int, text: String, width: Int) -> [VisualRow] {
        var rows: [VisualRow] = []
        var current = "", used = 0, start = 0, offset = 0
        for c in text {
            let w = CharWidth.of(c)
            if used + w > width, !current.isEmpty {
                rows.append(VisualRow(lineId: lineId, text: current, startOffset: start, isFirst: rows.isEmpty))
                current = ""; used = 0; start = offset
            }
            current.append(c); used += w; offset += 1
        }
        rows.append(VisualRow(lineId: lineId, text: current, startOffset: start, isFirst: rows.isEmpty))
        return rows
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LogViewportTests`
Expected: PASS (12 testova).

- [ ] **Step 5: Commit**

```bash
git add Sources/HotplateTUI Tests/HotplateTUITests
git commit -m "feat(tui): log viewport with wrapping, follow, selection, links and search"
```

---
### Task 8: Popup lista i polje za unos

**Files:**
- Create: `Sources/HotplateTUI/Picker.swift`, `Sources/HotplateTUI/TextInput.swift`
- Test: `Tests/HotplateTUITests/PickerTests.swift`, `Tests/HotplateTUITests/TextInputTests.swift`

**Interfaces:**
- Consumes: `ScreenBuffer`, `Style`, `CharWidth` (Task 6), `Key` (Task 5)
- Produces:
  - `struct TerminalSize: Equatable { width, height }`
  - `enum PickerKind { device, config, editor, project }`, `struct PickerItem { id, title, detail, isCurrent }`
  - `struct Picker { kind, items, filter, selectedIndex, filtered, selected, title, emptyMessage; type(_:), backspace(), move(by:), select(index:), setItems(_:), contains(x:y:in:), itemIndex(atX:y:in:), draw(into:busy:) }`
  - `struct TextInput { text, cursor; enum Outcome { editing, submit, cancel }; handle(_ key: Key) -> Outcome; insert(_:); draw(into:y:prompt:) }`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateTUITests/PickerTests.swift`:
```swift
import XCTest
@testable import HotplateTUI

final class PickerTests: XCTestCase {
    private let items = [
        PickerItem(id: "ios1", title: "iPhone 16 Pro (emulator)", detail: "ios", isCurrent: false),
        PickerItem(id: "chrome", title: "Chrome", detail: "web-javascript", isCurrent: true),
        PickerItem(id: "macos", title: "macOS", detail: "darwin", isCurrent: false),
    ]

    func testStartsOnTheCurrentItem() {
        XCTAssertEqual(Picker(kind: .device, items: items).selected?.id, "chrome")
    }

    func testFilterMatchesTitleIdOrDetailIgnoringCase() {
        var p = Picker(kind: .device, items: items)
        p.type("I"); p.type("O"); p.type("S")
        XCTAssertEqual(p.filtered.map(\.id), ["ios1"])
        XCTAssertEqual(p.selected?.id, "ios1")
        p.backspace(); p.backspace(); p.backspace()
        XCTAssertEqual(p.filtered.count, 3)
        XCTAssertEqual(Picker(kind: .device, items: items, filter: "darwin").filtered.map(\.id), ["macos"])
    }

    func testMoveClampsAndEmptyHasNoSelection() {
        var p = Picker(kind: .device, items: items)
        p.move(by: 10)
        XCTAssertEqual(p.selected?.id, "macos")
        p.move(by: -10)
        XCTAssertEqual(p.selected?.id, "ios1")
        let empty = Picker(kind: .device, items: items, filter: "pixel")
        XCTAssertNil(empty.selected)
        XCTAssertEqual(Picker(kind: .device, items: []).emptyMessage, "No devices. Start one, then press Ctrl+R.")
    }

    func testSetItemsKeepsTheSelectedId() {
        var p = Picker(kind: .device, items: items)
        p.move(by: 1)
        p.setItems([PickerItem(id: "new", title: "New", detail: "", isCurrent: false)] + items)
        XCTAssertEqual(p.selected?.id, "macos")
    }

    func testMouseHitTesting() {
        let p = Picker(kind: .device, items: items)
        let size = TerminalSize(width: 80, height: 24)
        var buf = ScreenBuffer(width: 80, height: 24)
        p.draw(into: &buf, busy: false)
        let row = (0..<24).first { buf.text(row: $0).contains("macOS") }!
        let col = buf.text(row: row).range(of: "macOS")!.lowerBound.utf16Offset(in: buf.text(row: row))
        XCTAssertEqual(p.itemIndex(atX: col, y: row, in: size), 2)
        XCTAssertTrue(p.contains(x: col, y: row, in: size))
        XCTAssertFalse(p.contains(x: 0, y: 0, in: size))
        XCTAssertNil(p.itemIndex(atX: 0, y: 0, in: size))
    }

    func testDrawShowsTitleFilterAndBusy() {
        var p = Picker(kind: .device, items: items)
        p.type("c")
        var buf = ScreenBuffer(width: 80, height: 24)
        p.draw(into: &buf, busy: true)
        let all = (0..<24).map { buf.text(row: $0) }.joined(separator: "\n")
        XCTAssertTrue(all.contains("Devices · Refreshing…"))
        XCTAssertTrue(all.contains("› c"))
        XCTAssertTrue(all.contains("Chrome"))
    }
}
```

`Tests/HotplateTUITests/TextInputTests.swift`:
```swift
import XCTest
@testable import HotplateTUI

final class TextInputTests: XCTestCase {
    func testTypingAndCursorMovement() {
        var t = TextInput(text: "--flavor")
        XCTAssertEqual(t.cursor, 8)
        XCTAssertEqual(t.handle(.char(" ")), .editing)
        t.insert("dev")
        XCTAssertEqual(t.text, "--flavor dev")
        _ = t.handle(.home); _ = t.handle(.right); _ = t.handle(.delete)
        XCTAssertEqual(t.text, "-flavor dev")
        _ = t.handle(.end); _ = t.handle(.backspace)
        XCTAssertEqual(t.text, "-flavor de")
        _ = t.handle(.ctrl("a"))
        XCTAssertEqual(t.cursor, 0)
        _ = t.handle(.ctrl("e"))
        XCTAssertEqual(t.cursor, 10)
    }

    func testDeleteWordAndLine() {
        var t = TextInput(text: "--flavor dev  ")
        _ = t.handle(.ctrl("w"))
        XCTAssertEqual(t.text, "--flavor ")
        _ = t.handle(.ctrl("u"))
        XCTAssertEqual(t.text, "")
        XCTAssertEqual(t.cursor, 0)
    }

    func testSubmitAndCancel() {
        var t = TextInput(text: "x")
        XCTAssertEqual(t.handle(.enter), .submit)
        XCTAssertEqual(t.handle(.escape), .cancel)
        XCTAssertEqual(t.text, "x")
    }

    func testDrawShowsPromptAndText() {
        let t = TextInput(text: "--flavor dev")
        var buf = ScreenBuffer(width: 40, height: 1)
        t.draw(into: &buf, y: 0, prompt: "args: ")
        XCTAssertTrue(buf.text(row: 0).hasPrefix(" args: --flavor dev"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter 'PickerTests|TextInputTests'`
Expected: build FAIL — `cannot find 'Picker' in scope`.

- [ ] **Step 3: Implement**

`Sources/HotplateTUI/Picker.swift`:
```swift
public struct TerminalSize: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
}

public enum PickerKind: Equatable, Sendable { case device, config, editor, project }

public struct PickerItem: Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let isCurrent: Bool

    public init(id: String, title: String, detail: String, isCurrent: Bool) {
        self.id = id; self.title = title; self.detail = detail; self.isCurrent = isCurrent
    }
}

/// A centered list with type-to-filter, used for devices, configurations, editors and projects.
public struct Picker: Equatable {
    public let kind: PickerKind
    public private(set) var items: [PickerItem]
    public private(set) var filter: String
    public private(set) var selectedIndex = 0

    public init(kind: PickerKind, items: [PickerItem], filter: String = "") {
        self.kind = kind; self.items = items; self.filter = filter
        selectedIndex = filtered.firstIndex(where: \.isCurrent) ?? 0
    }

    public var filtered: [PickerItem] {
        guard !filter.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter)
                || $0.detail.localizedCaseInsensitiveContains(filter)
        }
    }

    public var selected: PickerItem? {
        let f = filtered
        return f.indices.contains(selectedIndex) ? f[selectedIndex] : nil
    }

    public var title: String {
        switch kind {
        case .device: return "Devices"
        case .config: return "Launch configuration"
        case .editor: return "Editor"
        case .project: return "Recent projects"
        }
    }

    public var emptyMessage: String {
        switch kind {
        case .device: return "No devices. Start one, then press Ctrl+R."
        case .config: return "No configurations."
        case .editor: return "No editors found."
        case .project: return "No recent projects."
        }
    }

    public mutating func type(_ c: Character) { filter.append(c); selectedIndex = 0 }

    public mutating func backspace() {
        guard !filter.isEmpty else { return }
        filter.removeLast(); selectedIndex = 0
    }

    public mutating func move(by delta: Int) {
        let n = filtered.count
        guard n > 0 else { return }
        selectedIndex = min(max(0, selectedIndex + delta), n - 1)
    }

    public mutating func select(index: Int) {
        if filtered.indices.contains(index) { selectedIndex = index }
    }

    /// Replaces the items (e.g. after a device refresh) and keeps the same item selected when it still exists.
    public mutating func setItems(_ newItems: [PickerItem]) {
        guard newItems != items else { return }
        let keep = selected?.id
        items = newItems
        let f = filtered
        selectedIndex = keep.flatMap { id in f.firstIndex { $0.id == id } } ?? min(selectedIndex, max(0, f.count - 1))
    }

    // MARK: Geometry

    struct Box {
        let x: Int, y: Int, width: Int, height: Int
        let listTop: Int, visibleCount: Int, firstIndex: Int
    }

    func box(in size: TerminalSize) -> Box {
        let f = filtered
        let longest = f.map { CharWidth.of($0.title) + CharWidth.of($0.detail) + 8 }.max() ?? 0
        let width = max(10, min(size.width - 4, max(44, longest, CharWidth.of(emptyMessage) + 4)))
        let visible = max(1, min(max(1, size.height - 8), f.count))
        let height = visible + 3
        let x = max(0, (size.width - width) / 2), y = max(1, (size.height - height) / 2)
        let first = max(0, min(selectedIndex - visible + 1, f.count - visible))
        return Box(x: x, y: y, width: width, height: height, listTop: y + 2, visibleCount: visible, firstIndex: first)
    }

    public func contains(x: Int, y: Int, in size: TerminalSize) -> Bool {
        let b = box(in: size)
        return x >= b.x && x < b.x + b.width && y >= b.y && y < b.y + b.height
    }

    public func itemIndex(atX x: Int, y: Int, in size: TerminalSize) -> Int? {
        let b = box(in: size)
        let row = y - b.listTop
        guard contains(x: x, y: y, in: size), row >= 0, row < b.visibleCount else { return nil }
        let index = b.firstIndex + row
        return filtered.indices.contains(index) ? index : nil
    }

    public func draw(into buf: inout ScreenBuffer, busy: Bool) {
        let b = box(in: TerminalSize(width: buf.width, height: buf.height))
        let border = Style(fg: .cyan)
        for row in 0..<b.height { buf.fill(x: b.x, y: b.y + row, width: b.width, style: .plain) }
        let rule = String(repeating: "─", count: max(0, b.width - 2))
        buf.put("┌" + rule + "┐", x: b.x, y: b.y, style: border)
        buf.put("└" + rule + "┘", x: b.x, y: b.y + b.height - 1, style: border)
        for row in 1..<(b.height - 1) {
            buf.put("│", x: b.x, y: b.y + row, style: border)
            buf.put("│", x: b.x + b.width - 1, y: b.y + row, style: border)
        }
        buf.put(" \(title)\(busy ? " · Refreshing…" : "") ", x: b.x + 2, y: b.y, style: Style(bold: true), maxWidth: b.width - 4)
        buf.put("› " + filter + "▏", x: b.x + 2, y: b.y + 1, style: Style(fg: .yellow), maxWidth: b.width - 4)
        let f = filtered
        guard !f.isEmpty else {
            buf.put(emptyMessage, x: b.x + 2, y: b.listTop, style: Style(dim: true), maxWidth: b.width - 4)
            return
        }
        for i in 0..<b.visibleCount {
            let index = b.firstIndex + i
            guard f.indices.contains(index) else { break }
            let item = f[index], y = b.listTop + i, isSelected = index == selectedIndex
            let style = Style(inverse: isSelected)
            if isSelected { buf.fill(x: b.x + 1, y: y, width: b.width - 2, style: style) }
            buf.put(item.isCurrent ? "●" : " ", x: b.x + 2, y: y, style: Style(fg: .green, inverse: isSelected))
            let used = buf.put(item.title, x: b.x + 4, y: y, style: style, maxWidth: b.width - 6)
            let room = b.width - 6 - used - 2
            if room > 3, !item.detail.isEmpty {
                let d = CharWidth.truncate(item.detail, to: room)
                buf.put(d, x: b.x + b.width - 2 - CharWidth.of(d), y: y, style: Style(dim: true, inverse: isSelected))
            }
        }
    }
}
```

Napomena za `box`: visina je `visible + 3` (gornja ivica sa naslovom, red filtera, lista, donja ivica), pa je `listTop = y + 2`.

`Sources/HotplateTUI/TextInput.swift`:
```swift
/// A one-line editor shown in the footer, for run arguments and search.
public struct TextInput: Equatable {
    public enum Outcome: Equatable { case editing, submit, cancel }

    public private(set) var text: String
    /// Character index of the cursor.
    public private(set) var cursor: Int

    public init(text: String) { self.text = text; cursor = text.count }

    public mutating func insert(_ s: String) {
        var chars = Array(text)
        chars.insert(contentsOf: Array(s), at: cursor)
        text = String(chars)
        cursor += s.count
    }

    public mutating func handle(_ key: Key) -> Outcome {
        var chars = Array(text)
        switch key {
        case .enter: return .submit
        case .escape: return .cancel
        case .char(let c): insert(String(c)); return .editing
        case .backspace: if cursor > 0 { chars.remove(at: cursor - 1); cursor -= 1 }
        case .delete: if cursor < chars.count { chars.remove(at: cursor) }
        case .left: cursor = max(0, cursor - 1)
        case .right: cursor = min(chars.count, cursor + 1)
        case .home, .ctrl("a"): cursor = 0
        case .end, .ctrl("e"): cursor = chars.count
        case .ctrl("u"): chars.removeSubrange(0..<cursor); cursor = 0
        case .ctrl("w"):
            var i = cursor
            while i > 0, chars[i - 1] == " " { i -= 1 }
            while i > 0, chars[i - 1] != " " { i -= 1 }
            chars.removeSubrange(i..<cursor); cursor = i
        default: return .editing
        }
        text = String(chars)
        return .editing
    }

    public func draw(into buf: inout ScreenBuffer, y: Int, prompt: String) {
        buf.fill(y: y, style: .plain)
        let x0 = 1 + buf.put(prompt, x: 1, y: y, style: Style(fg: .yellow, bold: true))
        let room = max(1, buf.width - x0 - 1)
        let chars = Array(text)
        let start = max(0, cursor - room + 1)
        var x = x0
        for i in start..<chars.count {
            if x >= buf.width - 1 { break }
            x += buf.put(String(chars[i]), x: x, y: y, style: i == cursor ? Style(inverse: true) : .plain)
        }
        if cursor == chars.count { buf.put(" ", x: x, y: y, style: Style(inverse: true)) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'PickerTests|TextInputTests'`
Expected: PASS (10 testova).

- [ ] **Step 5: Commit**

```bash
git add Sources/HotplateTUI Tests/HotplateTUITests
git commit -m "feat(tui): filterable picker and one-line text input"
```

---
### Task 9: Prečice, statusna traka, footer, pomoć i log panel

**Files:**
- Create: `Sources/HotplateTUI/KeyBindings.swift`, `Sources/HotplateTUI/Widgets.swift`
- Test: `Tests/HotplateTUITests/KeyBindingsTests.swift`, `Tests/HotplateTUITests/WidgetsTests.swift`

**Interfaces:**
- Consumes: `Key` (Task 5), `ScreenBuffer`, `Style`, `CharWidth` (Task 6), `LogViewport`, `LogEntry` (Task 7), `SessionState`, `LogKind` (Task 3)
- Produces:
  - `enum Action` (vidi kod), `struct KeyBinding { keys, keyLabel, action, footerLabel, help }`, `struct FooterItem: Equatable { key, label }`
  - `KeyBindings.normal: [KeyBinding]`, `KeyBindings.action(for: Key) -> Action?`, `KeyBindings.footerItems(width:isRunning:) -> [FooterItem]`
  - `struct StatusInfo`, `StatusBar.draw(_:into:)`, `FooterBar.draw(_:into:y:)`, `HelpOverlay.lines`, `HelpOverlay.draw(into:)`, `LogPane.draw(_:into:top:)`, `LogPane.timeFormatter`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateTUITests/KeyBindingsTests.swift`:
```swift
import XCTest
@testable import HotplateTUI

final class KeyBindingsTests: XCTestCase {
    func testNoKeyIsBoundTwice() {
        let keys = KeyBindings.normal.flatMap(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count)
    }

    func testEveryBindingIsDocumented() {
        for b in KeyBindings.normal {
            XCTAssertFalse(b.help.isEmpty, "\(b.action)")
            XCTAssertFalse(b.keyLabel.isEmpty, "\(b.action)")
        }
    }

    func testCoreKeys() {
        XCTAssertEqual(KeyBindings.action(for: .ctrl("c")), .quit)
        XCTAssertEqual(KeyBindings.action(for: .char("q")), .quit)
        XCTAssertEqual(KeyBindings.action(for: .char("r")), .reload)
        XCTAssertEqual(KeyBindings.action(for: .char("R")), .restart)
        XCTAssertEqual(KeyBindings.action(for: .char("K")), .clearLog)
        XCTAssertEqual(KeyBindings.action(for: .char("k")), .lineUp)
        XCTAssertEqual(KeyBindings.action(for: .enter), .enter)
        XCTAssertNil(KeyBindings.action(for: .char("z")))
    }

    func testFooterFitsAndEndsWithHelp() {
        for width in [60, 80, 120, 200] {
            for running in [false, true] {
                let items = KeyBindings.footerItems(width: width, isRunning: running)
                let rendered = " " + items.map { "\($0.key) \($0.label)" }.joined(separator: "  ")
                XCTAssertLessThanOrEqual(CharWidth.of(rendered), width)
                XCTAssertEqual(items.last, FooterItem(key: "?", label: "help"))
            }
        }
    }

    func testFooterLeadsWithRunOrStop() {
        XCTAssertEqual(KeyBindings.footerItems(width: 120, isRunning: false).first, FooterItem(key: "⏎", label: "run"))
        XCTAssertEqual(KeyBindings.footerItems(width: 120, isRunning: true).first, FooterItem(key: "s", label: "stop"))
    }
}
```

`Tests/HotplateTUITests/WidgetsTests.swift`:
```swift
import XCTest
import HotplateCore
@testable import HotplateTUI

final class WidgetsTests: XCTestCase {
    func testStatusBarShowsProjectStateDeviceConfigAndAuto() {
        var buf = ScreenBuffer(width: 100, height: 1)
        StatusBar.draw(StatusInfo(project: "my_app", state: .running, statusText: "Running", flutterMissing: false,
                                  device: "iPhone 16 Pro", config: "dev", autoReload: true), into: &buf)
        let row = buf.text(row: 0)
        for part in ["Hotplate", "my_app", "● Running", "iPhone 16 Pro", "cfg: dev", "↻ auto"] {
            XCTAssertTrue(row.contains(part), part)
        }
    }

    func testStatusBarFlagsMissingFlutterAndCustomConfig() {
        var buf = ScreenBuffer(width: 100, height: 1)
        StatusBar.draw(StatusInfo(project: nil, state: .idle, statusText: "Idle", flutterMissing: true,
                                  device: nil, config: nil, autoReload: false), into: &buf)
        let row = buf.text(row: 0)
        XCTAssertTrue(row.contains("● flutter not found"))
        XCTAssertTrue(row.contains("cfg: custom"))
        XCTAssertFalse(row.contains("↻"))
    }

    func testLogPaneDrawsTimeTextAndSelection() {
        var v = LogViewport()
        let time = Date(timeIntervalSince1970: 0)
        v.update(lines: [LogLine(id: 0, text: "hello lib/main.dart:3", kind: .error, time: time)], width: 60, height: 3)
        v.select(lineId: 0)
        var buf = ScreenBuffer(width: 60, height: 5)
        LogPane.draw(v, into: &buf, top: 2)
        let row = buf.text(row: 2)
        XCTAssertTrue(row.hasPrefix("▶" + LogPane.timeFormatter.string(from: time)))
        XCTAssertTrue(row.contains("hello lib/main.dart:3"))
        XCTAssertTrue(buf[LogViewport.gutter + 6, 2].style.underline, "the link is underlined")
        XCTAssertTrue(buf[LogViewport.gutter, 2].style.inverse, "the selected line is highlighted")
    }

    func testHelpListsEveryBinding() {
        XCTAssertTrue(HelpOverlay.lines.contains { $0.contains("Hot reload") })
        XCTAssertTrue(HelpOverlay.lines.contains { $0.contains("Shift") })
        var buf = ScreenBuffer(width: 120, height: 40)
        HelpOverlay.draw(into: &buf)
        let all = (0..<40).map { buf.text(row: $0) }.joined()
        XCTAssertTrue(all.contains("Keyboard shortcuts"))
        XCTAssertTrue(all.contains("Hot restart"))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter 'KeyBindingsTests|WidgetsTests'`
Expected: build FAIL — `cannot find 'KeyBindings' in scope`.

- [ ] **Step 3: Implement**

`Sources/HotplateTUI/KeyBindings.swift`:
```swift
public enum Action: Equatable, Sendable {
    case enter, reload, restart, stop, quit
    case devices, configs, editArgs, toggleAutoReload, openProject, chooseEditor, projects
    case jumpToLink, previousLink, nextLink, copyLine, copyAll
    case search, nextMatch, previousMatch
    case lineUp, lineDown, pageUp, pageDown, halfPageUp, halfPageDown, top, bottom, toggleFollow
    case clearLog, cancel, redraw, help
}

public struct KeyBinding: Sendable {
    public let keys: [Key]
    public let keyLabel: String
    public let action: Action
    /// Short label for the footer; nil keeps the binding out of the footer.
    public let footerLabel: String?
    public let help: String

    init(_ keys: [Key], _ keyLabel: String, _ action: Action, _ footerLabel: String?, _ help: String) {
        self.keys = keys; self.keyLabel = keyLabel; self.action = action; self.footerLabel = footerLabel; self.help = help
    }
}

public struct FooterItem: Equatable, Sendable {
    public let key: String
    public let label: String
}

/// The single source of truth for normal-mode keys; the footer and the help screen are generated from it.
public enum KeyBindings {
    public static let normal: [KeyBinding] = [
        KeyBinding([.enter], "⏎", .enter, "run", "Run, or open the selected line's file"),
        KeyBinding([.char("r")], "r", .reload, "reload", "Hot reload"),
        KeyBinding([.char("R")], "R", .restart, "restart", "Hot restart"),
        KeyBinding([.char("s")], "s", .stop, "stop", "Stop the app"),
        KeyBinding([.char("q"), .ctrl("c")], "q", .quit, nil, "Stop and quit (Ctrl+C twice kills flutter)"),
        KeyBinding([.char("d")], "d", .devices, "device", "Choose device (Ctrl+R in the list refreshes)"),
        KeyBinding([.char("c")], "c", .configs, "config", "Choose launch.json configuration"),
        KeyBinding([.char("a")], "a", .editArgs, "args", "Edit run arguments"),
        KeyBinding([.char("A")], "A", .toggleAutoReload, "auto", "Reload on save on/off"),
        KeyBinding([.char("e")], "e", .openProject, "editor", "Open the project in your editor"),
        KeyBinding([.char("E")], "E", .chooseEditor, nil, "Choose the editor"),
        KeyBinding([.char("p")], "p", .projects, nil, "Recent projects"),
        KeyBinding([.char("o")], "o", .jumpToLink, "link", "Select the newest error or file link"),
        KeyBinding([.char("[")], "[", .previousLink, nil, "Previous file link"),
        KeyBinding([.char("]")], "]", .nextLink, nil, "Next file link"),
        KeyBinding([.char("y")], "y", .copyLine, nil, "Copy the selected line"),
        KeyBinding([.char("Y")], "Y", .copyAll, nil, "Copy the whole log"),
        KeyBinding([.char("/")], "/", .search, "find", "Search the log"),
        KeyBinding([.char("n")], "n", .nextMatch, nil, "Next match"),
        KeyBinding([.char("N")], "N", .previousMatch, nil, "Previous match"),
        KeyBinding([.char("k"), .up], "k ↑", .lineUp, nil, "Scroll up, or move the selection"),
        KeyBinding([.char("j"), .down], "j ↓", .lineDown, nil, "Scroll down, or move the selection"),
        KeyBinding([.pageUp], "PgUp", .pageUp, nil, "Page up"),
        KeyBinding([.pageDown], "PgDn", .pageDown, nil, "Page down"),
        KeyBinding([.ctrl("u")], "^U", .halfPageUp, nil, "Half a page up"),
        KeyBinding([.ctrl("d")], "^D", .halfPageDown, nil, "Half a page down"),
        KeyBinding([.char("g"), .home], "g", .top, nil, "Top of the log"),
        KeyBinding([.char("G"), .end], "G", .bottom, nil, "Bottom, and follow new lines"),
        KeyBinding([.char("f")], "f", .toggleFollow, nil, "Follow new lines on/off"),
        KeyBinding([.char("K")], "K", .clearLog, nil, "Clear the log"),
        KeyBinding([.escape], "Esc", .cancel, nil, "Clear the selection, then the search"),
        KeyBinding([.ctrl("l")], "^L", .redraw, nil, "Redraw the screen"),
        KeyBinding([.char("?")], "?", .help, "help", "Show this help"),
    ]

    public static func action(for key: Key) -> Action? {
        normal.first { $0.keys.contains(key) }?.action
    }

    /// Footer entries that fit in `width` columns (rendered as " k label  k label …"), always ending with "? help".
    public static func footerItems(width: Int, isRunning: Bool) -> [FooterItem] {
        let order: [Action] = isRunning
            ? [.stop, .reload, .restart, .devices, .configs, .editArgs, .openProject, .jumpToLink, .search, .toggleAutoReload]
            : [.enter, .devices, .configs, .editArgs, .openProject, .jumpToLink, .search, .toggleAutoReload]
        let help = FooterItem(key: "?", label: "help")
        var used = 1 + CharWidth.of("\(help.key) \(help.label)")
        var items: [FooterItem] = []
        for action in order {
            guard let b = normal.first(where: { $0.action == action }), let label = b.footerLabel else { continue }
            let w = CharWidth.of("\(b.keyLabel) \(label)") + 2
            if used + w > width { break }
            items.append(FooterItem(key: b.keyLabel, label: label))
            used += w
        }
        return items + [help]
    }
}
```

`Sources/HotplateTUI/Widgets.swift`:
```swift
import Foundation
import HotplateCore

enum Layout {
    /// First screen row of the log area (row 0 is the status bar, row 1 a rule).
    static let logTop = 2
    static let minWidth = 60
    static let minHeight = 12
}

struct StatusInfo {
    var project: String?
    var state: SessionState
    var statusText: String
    var flutterMissing: Bool
    var device: String?
    var config: String?
    var autoReload: Bool
}

enum StatusBar {
    static func draw(_ info: StatusInfo, into buf: inout ScreenBuffer) {
        var x = 1
        x += buf.put("Hotplate", x: x, y: 0, style: Style(bold: true))
        x += buf.put(" · \(info.project ?? "no project")", x: x, y: 0)
        x += 3
        if info.flutterMissing {
            x += buf.put("● flutter not found", x: x, y: 0, style: Style(fg: .red, bold: true))
        } else {
            x += buf.put("● \(info.statusText)", x: x, y: 0, style: Style(fg: color(for: info.state), bold: true))
        }
        x += 3
        x += buf.put(info.device ?? "no device", x: x, y: 0)
        x += 3
        x += buf.put("cfg: \(info.config ?? "custom")", x: x, y: 0, style: Style(dim: true))
        if info.autoReload {
            x += 3
            buf.put("↻ auto", x: x, y: 0, style: Style(fg: .cyan))
        }
    }

    static func color(for state: SessionState) -> TermColor {
        switch state {
        case .idle: return .gray
        case .starting, .stopping: return .cyan
        case .running: return .green
        case .reloading, .restarting: return .yellow
        case .failed: return .red
        }
    }
}

enum FooterBar {
    static func draw(_ items: [FooterItem], into buf: inout ScreenBuffer, y: Int) {
        var x = 1
        for item in items {
            x += buf.put(item.key, x: x, y: y, style: Style(bold: true))
            x += buf.put(" " + item.label, x: x, y: y, style: Style(dim: true))
            x += 2
        }
    }
}

enum HelpOverlay {
    static var lines: [String] {
        KeyBindings.normal.map { $0.keyLabel.padding(toLength: 6, withPad: " ", startingAt: 0) + $0.help }
            + [
                "Click Select a line; click a file link to open it",
                "Wheel Scroll the log",
                "Shift+drag selects text (Option+drag in iTerm2)",
                "",
                "Any key closes this help.",
            ]
    }

    static func draw(into buf: inout ScreenBuffer) {
        let x0 = 2, y0 = 1, w = buf.width - 4, h = buf.height - 2
        guard w > 10, h > 4 else { return }
        for row in 0..<h { buf.fill(x: x0, y: y0 + row, width: w, style: .plain) }
        let border = Style(fg: .cyan)
        let rule = String(repeating: "─", count: w - 2)
        buf.put("┌" + rule + "┐", x: x0, y: y0, style: border)
        buf.put("└" + rule + "┘", x: x0, y: y0 + h - 1, style: border)
        for row in 1..<(h - 1) {
            buf.put("│", x: x0, y: y0 + row, style: border)
            buf.put("│", x: x0 + w - 1, y: y0 + row, style: border)
        }
        buf.put(" Keyboard shortcuts ", x: x0 + 2, y: y0, style: Style(bold: true))
        let columnWidth = 52
        let columns = max(1, (w - 4) / columnWidth)
        let perColumn = h - 3
        for (i, line) in lines.enumerated() {
            let column = i / perColumn
            guard column < columns else { break }
            buf.put(line, x: x0 + 2 + column * columnWidth, y: y0 + 2 + i % perColumn, maxWidth: columnWidth - 2)
        }
    }
}

enum LogPane {
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    static func draw(_ v: LogViewport, into buf: inout ScreenBuffer, top: Int) {
        for (i, row) in v.visibleRows.enumerated() {
            let y = top + i
            guard let entry = v.entry(row.lineId) else { continue }
            let selected = row.lineId == v.selectedLineId
            var base = style(for: entry.kind)
            base.inverse = selected
            if selected { buf.fill(y: y, style: Style(inverse: true)) }
            if row.isFirst {
                if selected { buf.put("▶", x: 0, y: y, style: Style(fg: .cyan, inverse: true)) }
                buf.put(timeFormatter.string(from: entry.time), x: 1, y: y, style: Style(dim: true, inverse: selected))
            }
            let links = LogLinkParser.links(in: entry.text).map { LogViewport.offsets(of: $0, in: entry.text) }
            let matches = matchOffsets(in: entry.text, query: v.searchQuery)
            var x = LogViewport.gutter, offset = row.startOffset
            for c in row.text {
                var st = base
                if links.contains(where: { $0.contains(offset) }) {
                    st.underline = true
                    if !selected { st.fg = .blue }
                }
                if matches.contains(where: { $0.contains(offset) }) { st = Style(fg: .black, bg: .yellow) }
                x += buf.put(String(c), x: x, y: y, style: st)
                offset += 1
            }
        }
    }

    static func style(for kind: LogKind) -> Style {
        switch kind {
        case .normal: return .plain
        case .error: return Style(fg: .red)
        case .warning: return Style(fg: .yellow)
        case .info: return Style(fg: .gray)
        case .success: return Style(fg: .green, bold: true)
        }
    }

    private static func matchOffsets(in text: String, query: String?) -> [Range<Int>] {
        guard let query, !query.isEmpty else { return [] }
        var out: [Range<Int>] = []
        var searchStart = text.startIndex
        while let r = text.range(of: query, options: .caseInsensitive, range: searchStart..<text.endIndex) {
            out.append(text.distance(from: text.startIndex, to: r.lowerBound)..<text.distance(from: text.startIndex, to: r.upperBound))
            searchStart = r.upperBound
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'KeyBindingsTests|WidgetsTests'`
Expected: PASS (9 testova).

- [ ] **Step 5: Commit**

```bash
git add Sources/HotplateTUI Tests/HotplateTUITests
git commit -m "feat(tui): key bindings table, status bar, footer, help and log pane"
```

---
### Task 10: TUIApp — mašina stanja, akcije i crtanje ekrana

**Files:**
- Create: `Sources/HotplateTUI/TUIApp.swift`
- Test: `Tests/HotplateTUITests/TUIAppTests.swift`

**Interfaces:**
- Consumes: `Session` + `chooseDevice/chooseLaunchConfig/setArgs/setAutoReload/switchProject/startup/forceQuit/shutdown` (Tasks 3–4), sve iz Tasks 5–9, `SessionHarness` (Task 3)
- Produces: `@MainActor public final class TUIApp` sa `init(session:size:output:copy:exit:now:)`, `enum Mode { normal, picker, input(InputKind), help }`, `enum InputKind { args, search }`, `mode`, `picker`, `viewport`, `size`, `start(autoRun:) async`, `handle(_ event: InputEvent)`, `resize(to:)`, `render()`, `compose() -> ScreenBuffer`, `quit()`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateTUITests/TUIAppTests.swift`:
```swift
import XCTest
import HotplateCore
import HotplateTestSupport
@testable import HotplateTUI

@MainActor
final class TUIAppTests: XCTestCase {
    private final class Captured {
        var output = ""
        var copied: [String] = []
        var exitCodes: [Int32] = []
        var now = Date(timeIntervalSince1970: 1000)
    }

    private func makeApp(_ h: SessionHarness, savedDevice: String? = nil, overrides: SessionOverrides = SessionOverrides(),
                         size: TerminalSize = TerminalSize(width: 100, height: 30)) throws -> (TUIApp, Session, Captured) {
        let path = try TestProject.make()
        let store = h.makeStore()
        if let savedDevice { store.update(Project(path: path, name: "demo", lastDeviceId: savedDevice)) }
        let s = h.makeSession(store: store)
        s.overrides = overrides
        s.selectProject(path: path)
        let c = Captured()
        let app = TUIApp(session: s, size: size, output: { c.output += $0 }, copy: { c.copied.append($0) },
                         exit: { c.exitCodes.append($0) }, now: { c.now })
        return (app, s, c)
    }

    private func screen(_ app: TUIApp) -> String {
        let b = app.compose()
        return (0..<b.height).map { b.text(row: $0) }.joined(separator: "\n")
    }

    private func key(_ k: Key) -> InputEvent { .key(k) }

    func testStartRunsOnTheRememberedDevice() async throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h, savedDevice: "chrome")
        await app.start(autoRun: true)
        XCTAssertEqual(app.mode, .normal)
        XCTAssertEqual(h.lastDaemon?.config.deviceId, "chrome")
        XCTAssertEqual(s.state, .starting)
    }

    func testStartWithoutRememberedDeviceAsksThenRuns() async throws {
        let h = SessionHarness()
        let (app, _, _) = try makeApp(h)
        await app.start(autoRun: true)
        XCTAssertEqual(app.mode, .picker)
        XCTAssertEqual(app.picker?.kind, .device)
        XCTAssertTrue(h.daemons.isEmpty)
        app.handle(key(.down))
        app.handle(key(.enter))
        XCTAssertEqual(app.mode, .normal)
        let ran = await waitUntil { h.lastDaemon?.config.deviceId == "chrome" }
        XCTAssertTrue(ran)
    }

    func testAmbiguousDeviceQueryOpensAFilteredPicker() async throws {
        let h = SessionHarness(devices: [.fake("a", "iPhone 16"), .fake("b", "iPhone 15"), .fake("chrome", "Chrome")])
        let (app, _, _) = try makeApp(h, overrides: SessionOverrides(deviceQuery: "iphone"))
        await app.start(autoRun: true)
        XCTAssertEqual(app.picker?.filter, "iphone")
        XCTAssertEqual(app.picker?.filtered.count, 2)
        XCTAssertTrue(h.daemons.isEmpty)
    }

    func testNoRunLeavesTheAppIdle() async throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: false)
        XCTAssertEqual(s.state, .idle)
        XCTAssertTrue(screen(app).contains("⏎ run"))
        app.handle(key(.enter))
        let ran = await waitUntil { h.daemons.count == 1 }
        XCTAssertTrue(ran)
    }

    func testEnterOnASelectedLineOpensItsLink() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("Error at lib/missing.dart:3", .error)
        _ = app.compose()
        app.handle(key(.char("o")))
        XCTAssertNotNil(app.viewport.selectedLineId)
        app.handle(key(.enter))
        XCTAssertTrue(s.logs.contains { $0.text.contains("Can't find a file for lib/missing.dart") })
    }

    func testClickOnALinkOpensIt() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("Error at lib/missing.dart:3", .error)
        _ = app.compose()
        let target = try XCTUnwrap(s.logs.last?.id)
        let row = try XCTUnwrap(app.viewport.visibleRows.enumerated().first { $0.element.lineId == target }?.offset)
        app.handle(.mouse(MouseEvent(button: .left, x: LogViewport.gutter + 10, y: 2 + row, pressed: true)))
        XCTAssertEqual(app.viewport.selectedLineId, target)
        XCTAssertTrue(s.logs.contains { $0.text.contains("Can't find a file for lib/missing.dart") })
    }

    func testQuitStopsFlutterThenExitsWithZero() async throws {
        let h = SessionHarness()
        let (app, _, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.char("q")))
        let exited = await waitUntil { !c.exitCodes.isEmpty }
        XCTAssertTrue(exited)
        XCTAssertEqual(c.exitCodes.first, 0)
        XCTAssertEqual(h.lastDaemon?.stopCalls, 1)
    }

    func testSecondCtrlCWithinTwoSecondsKills() async throws {
        let h = SessionHarness()
        let (app, _, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        app.handle(key(.ctrl("c")))
        c.now = c.now.addingTimeInterval(1)
        app.handle(key(.ctrl("c")))
        XCTAssertEqual(c.exitCodes.first, 130)
        XCTAssertEqual(h.lastDaemon?.terminated, true)
    }

    func testPasteInNormalModeTriggersNothing() async throws {
        let h = SessionHarness()
        let (app, s, c) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        h.lastDaemon?.send(.appStarted)
        _ = await waitUntil { s.state == .running }
        app.handle(.paste("rrq"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(h.lastDaemon?.restartCalls, [])
        XCTAssertTrue(c.exitCodes.isEmpty)
    }

    func testPasteIntoArgsReplacesNewlines() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        app.handle(key(.char("a")))
        XCTAssertEqual(app.mode, .input(.args))
        app.handle(key(.ctrl("u")))
        app.handle(.paste("--flavor\ndev"))
        app.handle(key(.enter))
        XCTAssertEqual(app.mode, .normal)
        XCTAssertEqual(s.extraArgs, "--flavor dev")
        XCTAssertNil(s.selectedLaunchConfigName)
    }

    func testSearchSelectsTheNewestMatch() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        s.log("needle one"); s.log("hay"); s.log("needle two")
        _ = app.compose()
        app.handle(key(.char("/")))
        for ch in "needle" { app.handle(key(.char(ch))) }
        app.handle(key(.enter))
        XCTAssertEqual(app.viewport.selectedLineId, s.logs.last?.id)
        app.handle(key(.char("N")))
        XCTAssertEqual(app.viewport.selectedLineId, s.logs[s.logs.count - 3].id)
    }

    func testCopyLineAndAll() throws {
        let h = SessionHarness()
        let (app, s, c) = try makeApp(h)
        s.log("Error at lib/a.dart:1", .error)
        _ = app.compose()
        app.handle(key(.char("o")))
        app.handle(key(.char("y")))
        XCTAssertEqual(c.copied.first, "Error at lib/a.dart:1")
        app.handle(key(.char("Y")))
        XCTAssertTrue(c.copied.last?.contains("Error at lib/a.dart:1") ?? false)
    }

    func testResizeBelowMinimumAndBackKeepsPicker() throws {
        let h = SessionHarness()
        let (app, _, _) = try makeApp(h)
        app.handle(key(.char("d")))
        app.resize(to: TerminalSize(width: 40, height: 10))
        XCTAssertTrue(screen(app).contains("Terminal too small (min 60×12)"))
        app.handle(key(.down))
        app.resize(to: TerminalSize(width: 100, height: 30))
        XCTAssertEqual(app.mode, .picker)
        XCTAssertTrue(screen(app).contains("Devices"))
    }

    func testFooterShowsStopWhileRunningAndHelpCloses() async throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h, savedDevice: "ios1")
        await app.start(autoRun: true)
        h.lastDaemon?.send(.appStarted)
        _ = await waitUntil { s.state == .running }
        XCTAssertTrue(screen(app).contains("s stop"))
        app.handle(key(.char("?")))
        XCTAssertEqual(app.mode, .help)
        XCTAssertTrue(screen(app).contains("Keyboard shortcuts"))
        app.handle(key(.char("x")))
        XCTAssertEqual(app.mode, .normal)
    }

    func testEscapeClosesPickerWithoutChoosing() throws {
        let h = SessionHarness()
        let (app, s, _) = try makeApp(h)
        app.handle(key(.char("c")))
        XCTAssertEqual(app.picker?.kind, .config)
        app.handle(key(.escape))
        XCTAssertEqual(app.mode, .normal)
        XCTAssertNil(app.picker)
        XCTAssertNil(s.selectedLaunchConfigName)
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter TUIAppTests`
Expected: build FAIL — `cannot find 'TUIApp' in scope`.

- [ ] **Step 3: Implement**

`Sources/HotplateTUI/TUIApp.swift`:
```swift
import Foundation
import Observation
import HotplateCore

/// The terminal front end: turns input into `Session` calls and draws the session into a screen buffer.
@MainActor
public final class TUIApp {
    public enum InputKind: Equatable, Sendable { case args, search }
    public enum Mode: Equatable, Sendable { case normal, picker, input(InputKind), help }

    public let session: Session
    public private(set) var mode: Mode = .normal
    public private(set) var viewport = LogViewport()
    public private(set) var picker: Picker?
    public private(set) var size: TerminalSize

    private var input = TextInput(text: "")
    private let output: (String) -> Void
    private let copy: (String) -> Void
    private let exit: (Int32) -> Void
    private let now: () -> Date
    private var renderer = Renderer()
    private var renderScheduled = false
    private var runAfterDevicePick = false
    /// Set while no project is open at start: the auto-run choice to apply once one is picked.
    private var startAfterProjectPick: Bool?
    private var quitRequestedAt: Date?
    private var quitting = false

    public init(session: Session, size: TerminalSize, output: @escaping (String) -> Void,
                copy: @escaping (String) -> Void, exit: @escaping (Int32) -> Void, now: @escaping () -> Date = Date.init) {
        self.session = session; self.size = size; self.output = output; self.copy = copy; self.exit = exit; self.now = now
    }

    // MARK: Start

    public func start(autoRun: Bool) async {
        render()
        guard session.project != nil else {
            startAfterProjectPick = autoRun
            openPicker(.project)
            return
        }
        await runStartup(autoRun: autoRun)
    }

    private func runStartup(autoRun: Bool) async {
        if case .needsDevice(let filter) = await session.startup(autoRun: autoRun) {
            runAfterDevicePick = autoRun
            openPicker(.device, filter: filter)
        }
        scheduleRender()
    }

    // MARK: Input

    public func handle(_ event: InputEvent) {
        defer { scheduleRender() }
        if event == .key(.ctrl("c")) { quit(); return }
        switch mode {
        case .help:
            if case .mouse(let m) = event, !m.pressed { return }
            mode = .normal
        case .picker:
            handlePicker(event)
        case .input(let kind):
            handleInput(event, kind: kind)
        case .normal:
            switch event {
            case .key(let key): if let action = KeyBindings.action(for: key) { perform(action) }
            case .mouse(let m): handleMouse(m)
            case .paste: break
            }
        }
    }

    func perform(_ action: Action) {
        switch action {
        case .enter:
            if let id = viewport.selectedLineId {
                openLink(onLine: id, link: nil)
            } else if session.selectedDevice == nil, session.project != nil, session.flutterPath != nil, !session.isRunning {
                runAfterDevicePick = true
                openPicker(.device)
            } else if session.canRun {
                Task { await session.run() }
            }
        case .reload: Task { await session.hotReload() }
        case .restart: Task { await session.hotRestart() }
        case .stop: Task { await session.stop() }
        case .quit: quit()
        case .devices: openPicker(.device)
        case .configs: openPicker(.config)
        case .editArgs: input = TextInput(text: session.extraArgs); mode = .input(.args)
        case .toggleAutoReload: session.setAutoReload(!session.autoReload)
        case .openProject: session.openInEditor()
        case .chooseEditor: openPicker(.editor)
        case .projects: openPicker(.project)
        case .jumpToLink: if let id = viewport.lastLinkLine() { viewport.select(lineId: id) }
        case .previousLink: if let id = viewport.linkLine(from: viewport.selectedLineId, forward: false) { viewport.select(lineId: id) }
        case .nextLink: if let id = viewport.linkLine(from: viewport.selectedLineId, forward: true) { viewport.select(lineId: id) }
        case .copyLine:
            if let id = viewport.selectedLineId, let e = viewport.entry(id) { copy(e.text) }
        case .copyAll:
            copy(session.logs.map { "\(LogPane.timeFormatter.string(from: $0.time))  \($0.text)" }.joined(separator: "\n"))
        case .search: input = TextInput(text: viewport.searchQuery ?? ""); mode = .input(.search)
        case .nextMatch: if let id = viewport.searchMatch(from: viewport.selectedLineId, forward: true) { viewport.select(lineId: id) }
        case .previousMatch: if let id = viewport.searchMatch(from: viewport.selectedLineId, forward: false) { viewport.select(lineId: id) }
        case .lineUp: viewport.selectedLineId != nil ? viewport.moveSelection(by: -1) : viewport.scroll(by: -1)
        case .lineDown: viewport.selectedLineId != nil ? viewport.moveSelection(by: 1) : viewport.scroll(by: 1)
        case .pageUp: viewport.scroll(by: -max(1, viewport.height - 1))
        case .pageDown: viewport.scroll(by: max(1, viewport.height - 1))
        case .halfPageUp: viewport.scroll(by: -max(1, viewport.height / 2))
        case .halfPageDown: viewport.scroll(by: max(1, viewport.height / 2))
        case .top: viewport.scrollToTop()
        case .bottom: viewport.select(lineId: nil); viewport.scrollToBottom()
        case .toggleFollow: viewport.setFollow(!viewport.follow)
        case .clearLog: session.clearLogs(); viewport.select(lineId: nil)
        case .cancel:
            if viewport.selectedLineId != nil { viewport.select(lineId: nil) } else { viewport.setSearch(nil) }
        case .redraw: renderer.invalidate()
        case .help: mode = .help
        }
    }

    private func openLink(onLine id: Int, link: LogLink?) {
        guard let link = link ?? viewport.links(onLine: id).first else { return }
        session.openLogLink(location: link.location, line: link.line, column: link.column)
    }

    private func handleMouse(_ m: MouseEvent) {
        switch m.button {
        case .wheelUp: viewport.scroll(by: -3)
        case .wheelDown: viewport.scroll(by: 3)
        case .left where m.pressed:
            guard let hit = viewport.hit(row: m.y - Layout.logTop, column: m.x) else { return }
            viewport.select(lineId: hit.lineId)
            if let link = hit.link { openLink(onLine: hit.lineId, link: link) }
        default: break
        }
    }

    private func handleInput(_ event: InputEvent, kind: InputKind) {
        switch event {
        case .paste(let s):
            input.insert(s.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " "))
        case .key(let key):
            switch input.handle(key) {
            case .editing: break
            case .cancel: mode = .normal
            case .submit:
                mode = .normal
                switch kind {
                case .args:
                    session.setArgs(input.text)
                case .search:
                    viewport.setSearch(input.text)
                    if let id = viewport.searchMatch(from: nil, forward: false) { viewport.select(lineId: id) }
                }
            }
        case .mouse: break
        }
    }

    // MARK: Pickers

    private func openPicker(_ kind: PickerKind, filter: String = "") {
        if kind == .editor { session.refreshInstalledEditors() }
        picker = Picker(kind: kind, items: items(for: kind), filter: filter)
        mode = .picker
    }

    private func closePicker() {
        picker = nil
        mode = .normal
    }

    private func handlePicker(_ event: InputEvent) {
        guard var p = picker else { mode = .normal; return }
        switch event {
        case .key(.escape):
            runAfterDevicePick = false
            closePicker()
            return
        case .key(.enter):
            closePicker()
            if let item = p.selected { choose(item, in: p.kind) }
            return
        case .key(.up), .key(.ctrl("p")): p.move(by: -1)
        case .key(.down), .key(.ctrl("n")), .key(.tab): p.move(by: 1)
        case .key(.backspace): p.backspace()
        case .key(.ctrl("r")): if p.kind == .device { Task { await session.refreshDevices() } }
        case .key(.char(let c)): p.type(c)
        case .paste(let s): s.filter { !$0.isNewline }.forEach { p.type($0) }
        case .mouse(let m):
            switch m.button {
            case .wheelUp: p.move(by: -1)
            case .wheelDown: p.move(by: 1)
            case .left where m.pressed:
                if let index = p.itemIndex(atX: m.x, y: m.y, in: size) {
                    p.select(index: index)
                    closePicker()
                    if let item = p.selected { choose(item, in: p.kind) }
                    return
                }
                if !p.contains(x: m.x, y: m.y, in: size) { runAfterDevicePick = false; closePicker(); return }
            default: break
            }
        default: break
        }
        picker = p
    }

    private func choose(_ item: PickerItem, in kind: PickerKind) {
        switch kind {
        case .device:
            session.chooseDevice(id: item.id)
            if runAfterDevicePick {
                runAfterDevicePick = false
                Task { await session.run() }
            }
        case .config:
            session.chooseLaunchConfig(name: item.id.isEmpty ? nil : item.id)
        case .editor:
            session.editorSelection = item.id
        case .project:
            if let autoRun = startAfterProjectPick {
                startAfterProjectPick = nil
                session.selectProject(path: item.id)
                Task { await runStartup(autoRun: autoRun) }
            } else {
                session.switchProject(path: item.id)
            }
        }
    }

    private func items(for kind: PickerKind) -> [PickerItem] {
        switch kind {
        case .device:
            return session.devices.map {
                PickerItem(id: $0.id, title: $0.displayName, detail: $0.targetPlatform, isCurrent: $0.id == session.selectedDeviceId)
            }
        case .config:
            return session.launchConfigs.map {
                PickerItem(id: $0.name, title: $0.name, detail: ArgumentSplitter.join($0.flutterRunArguments),
                           isCurrent: $0.name == session.selectedLaunchConfigName)
            } + [PickerItem(id: "", title: "Custom (keep current args)", detail: session.extraArgs,
                            isCurrent: session.selectedLaunchConfigName == nil)]
        case .editor:
            let selection = session.editorSelection
            var list = session.installedEditors.map {
                PickerItem(id: $0.appPath, title: $0.name, detail: "", isCurrent: selection == $0.appPath)
            }
            if let other = session.otherEditor {
                list.append(PickerItem(id: other.appPath, title: other.name, detail: "", isCurrent: selection == other.appPath))
            }
            list.append(PickerItem(id: "custom", title: "Custom command", detail: session.store.editorCustomCommand,
                                   isCurrent: selection == "custom"))
            return list
        case .project:
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return session.store.recents.map { p in
                let shown = p.path.hasPrefix(home) ? "~" + p.path.dropFirst(home.count) : p.path
                return PickerItem(id: p.path, title: p.name, detail: String(shown), isCurrent: p.path == session.project?.path)
            }
        }
    }

    // MARK: Quit

    /// `q`, Ctrl+C or a signal: stop flutter cleanly, then exit. A second request within 2 s kills flutter.
    public func quit() {
        let t = now()
        if let first = quitRequestedAt, t.timeIntervalSince(first) <= 2 {
            session.forceQuit()
            exit(130)
            return
        }
        quitRequestedAt = t
        guard !quitting else { return }
        quitting = true
        Task {
            await session.shutdown()
            exit(0)
        }
    }

    // MARK: Drawing

    public func resize(to newSize: TerminalSize) {
        size = newSize
        renderer.invalidate()
        render()
    }

    public func scheduleRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(16)) { [weak self] in
            MainActor.assumeIsolated {
                self?.renderScheduled = false
                self?.render()
            }
        }
    }

    /// Draws now and re-renders whenever anything the frame read from `Session` changes.
    public func render() {
        let frame = withObservationTracking {
            compose()
        } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.scheduleRender() } }
        }
        output(renderer.render(frame))
    }

    public func compose() -> ScreenBuffer {
        var buf = ScreenBuffer(width: size.width, height: size.height)
        guard size.width >= Layout.minWidth, size.height >= Layout.minHeight else {
            buf.put("Terminal too small (min \(Layout.minWidth)×\(Layout.minHeight))", x: 0, y: 0)
            return buf
        }
        viewport.update(lines: session.logs, width: size.width, height: size.height - 4)
        StatusBar.draw(StatusInfo(project: session.project?.name, state: session.state, statusText: session.statusText,
                                  flutterMissing: session.flutterPath == nil,
                                  device: session.selectedDevice?.displayName ?? session.selectedDeviceId,
                                  config: session.selectedLaunchConfigName, autoReload: session.autoReload), into: &buf)
        let rule = String(repeating: "─", count: size.width)
        buf.put(rule, x: 0, y: 1, style: Style(fg: .gray))
        buf.put(rule, x: 0, y: size.height - 2, style: Style(fg: .gray))
        LogPane.draw(viewport, into: &buf, top: Layout.logTop)
        if case .input(let kind) = mode {
            input.draw(into: &buf, y: size.height - 1, prompt: kind == .args ? "args: " : "/")
        } else {
            FooterBar.draw(KeyBindings.footerItems(width: size.width, isRunning: session.isRunning), into: &buf, y: size.height - 1)
        }
        if mode == .picker, var p = picker {
            p.setItems(items(for: p.kind))
            picker = p
            p.draw(into: &buf, busy: p.kind == .device && session.isLoadingDevices)
        }
        if mode == .help { HelpOverlay.draw(into: &buf) }
        return buf
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TUIAppTests`
Expected: PASS (15 testova). Zatim `swift test` — svi PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/HotplateTUI/TUIApp.swift Tests/HotplateTUITests/TUIAppTests.swift
git commit -m "feat(tui): TUIApp state machine, actions and screen composition"
```

---
### Task 11: Komanda `hotplate` (opcije, terminal, petlja, main)

**Files:**
- Create: `Sources/HotplateTUI/CommandLineOptions.swift`, `Sources/HotplateTUI/Terminal.swift`, `Sources/HotplateTUI/TerminalLoop.swift`, `Sources/HotplateTUI/Clipboard.swift`, `Sources/hotplate-cli/main.swift`
- Modify: `Package.swift`
- Test: `Tests/HotplateTUITests/CommandLineOptionsTests.swift`

**Interfaces:**
- Consumes: `TUIApp` (Task 10), `InputDecoder` (Task 5), `Session`, `ProjectStore`, `ProjectLocator`, `HotplateVersion`, `SessionOverrides`, `ArgumentSplitter`
- Produces: `struct CommandLineOptions { path, overrides, noRun, flutterPath, showHelp, showVersion; static parse([String]) throws -> CommandLineOptions; static usage; struct ParseError { message } }`, `final class Terminal { static isInteractive; enter() throws; restore(); write(_:); size() }`, `final class TerminalLoop { init(terminal:app:); start() }`, `enum Clipboard { static copy(_:) }`, izvršni fajl `hotplate-cli`

- [ ] **Step 1: Write the failing tests**

`Tests/HotplateTUITests/CommandLineOptionsTests.swift`:
```swift
import XCTest
import HotplateCore
@testable import HotplateTUI

final class CommandLineOptionsTests: XCTestCase {
    func testDefaults() throws {
        let o = try CommandLineOptions.parse([])
        XCTAssertNil(o.path)
        XCTAssertEqual(o.overrides, SessionOverrides())
        XCTAssertFalse(o.noRun)
        XCTAssertNil(o.flutterPath)
    }

    func testAllOptions() throws {
        let o = try CommandLineOptions.parse(["~/code/app", "-d", "iphone", "--config", "Dev", "--no-run",
                                              "--no-auto-reload", "--flutter", "/opt/flutter/bin/flutter"])
        XCTAssertEqual(o.path, "~/code/app")
        XCTAssertEqual(o.overrides, SessionOverrides(deviceQuery: "iphone", configName: "Dev", autoReload: false))
        XCTAssertTrue(o.noRun)
        XCTAssertEqual(o.flutterPath, "/opt/flutter/bin/flutter")
    }

    func testEverythingAfterDoubleDashGoesToFlutter() throws {
        let o = try CommandLineOptions.parse(["-c", "Dev", "--", "--flavor", "dev", "--dart-define=A=1 2", "-d", "x"])
        XCTAssertEqual(o.overrides.configName, "Dev")
        XCTAssertNil(o.overrides.deviceQuery)
        XCTAssertEqual(o.overrides.args, "--flavor dev \"--dart-define=A=1 2\" -d x")
        XCTAssertNil(try CommandLineOptions.parse(["--"]).overrides.args)
    }

    func testHelpAndVersion() throws {
        XCTAssertTrue(try CommandLineOptions.parse(["-h"]).showHelp)
        XCTAssertTrue(try CommandLineOptions.parse(["--version"]).showVersion)
        XCTAssertTrue(CommandLineOptions.usage.contains("--device"))
    }

    func testErrors() {
        XCTAssertThrowsError(try CommandLineOptions.parse(["--wat"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "unknown option --wat")
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(["-d"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "-d needs a value")
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(["-c", "--no-run"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "-c needs a value")
        }
        XCTAssertThrowsError(try CommandLineOptions.parse(["a", "b"])) {
            XCTAssertEqual(($0 as? CommandLineOptions.ParseError)?.message, "unexpected argument b")
        }
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter CommandLineOptionsTests`
Expected: build FAIL — `cannot find 'CommandLineOptions' in scope`.

- [ ] **Step 3: Implement options**

`Sources/HotplateTUI/CommandLineOptions.swift`:
```swift
import HotplateCore

public struct CommandLineOptions: Equatable, Sendable {
    public struct ParseError: Error, Equatable {
        public let message: String
    }

    public var path: String?
    public var overrides = SessionOverrides()
    public var noRun = false
    public var flutterPath: String?
    public var showHelp = false
    public var showVersion = false

    public init() {}

    public static func parse(_ args: [String]) throws -> CommandLineOptions {
        var o = CommandLineOptions()
        var i = 0
        func value(for flag: String) throws -> String {
            i += 1
            guard i < args.count, !args[i].hasPrefix("-") else { throw ParseError(message: "\(flag) needs a value") }
            return args[i]
        }
        while i < args.count {
            let a = args[i]
            switch a {
            case "--":
                let rest = Array(args[(i + 1)...])
                if !rest.isEmpty { o.overrides.args = ArgumentSplitter.join(rest) }
                return o
            case "-d", "--device": o.overrides.deviceQuery = try value(for: a)
            case "-c", "--config": o.overrides.configName = try value(for: a)
            case "--no-run": o.noRun = true
            case "--no-auto-reload": o.overrides.autoReload = false
            case "--flutter": o.flutterPath = try value(for: a)
            case "-h", "--help": o.showHelp = true
            case "--version": o.showVersion = true
            default:
                if a.hasPrefix("-") { throw ParseError(message: "unknown option \(a)") }
                guard o.path == nil else { throw ParseError(message: "unexpected argument \(a)") }
                o.path = a
            }
            i += 1
        }
        return o
    }

    public static let usage = """
    Usage: hotplate [path] [options] [-- <flutter run arguments>]

    Runs a Flutter app with hot reload on save, in your terminal.

    Options:
      -d, --device <id|name>   Device to run on (part of the name is enough)
      -c, --config <name>      Configuration from .vscode/launch.json
          --no-run             Open without starting the app
          --no-auto-reload     Don't hot reload on save in this session
          --flutter <path>     Path to the flutter executable
      -h, --help               Show this help
          --version            Show the version

    Options apply to this session only. Choices made inside hotplate are remembered per project.
    Press ? inside hotplate for keyboard shortcuts.

    """
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CommandLineOptionsTests`
Expected: PASS (5 testova).

- [ ] **Step 5: Terminal, petlja i clipboard** (sistemski I/O; proverava se ručno u Step 8)

`Sources/HotplateTUI/Terminal.swift`:
```swift
import Darwin

public enum TerminalError: Error { case notATerminal }

/// Raw mode, alternate screen, mouse and bracketed paste, with a restore that always runs on exit.
public final class Terminal {
    private static var active: Terminal?
    private var original = termios()
    private var isRaw = false

    public init() {}

    public static var isInteractive: Bool { isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1 }

    public func enter() throws {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { throw TerminalError.notATerminal }
        var raw = original
        raw.c_iflag &= ~tcflag_t(BRKINT | ICRNL | INPCK | ISTRIP | IXON)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | IEXTEN | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { cc in
            cc[Int(VMIN)] = 1
            cc[Int(VTIME)] = 0
        }
        guard tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0 else { throw TerminalError.notATerminal }
        isRaw = true
        Terminal.active = self
        atexit { Terminal.active?.restore() }
        // Alternate screen, hidden cursor, click + SGR mouse reporting, bracketed paste.
        write("\u{1B}[?1049h\u{1B}[?25l\u{1B}[?1000h\u{1B}[?1006h\u{1B}[?2004h")
    }

    /// Safe to call more than once.
    public func restore() {
        guard isRaw else { return }
        isRaw = false
        write("\u{1B}[?2004l\u{1B}[?1006l\u{1B}[?1000l\u{1B}[0m\u{1B}[?25h\u{1B}[?1049l")
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
    }

    public func write(_ s: String) {
        let bytes = Array(s.utf8)
        var offset = 0
        while offset < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(STDOUT_FILENO, $0.baseAddress! + offset, bytes.count - offset) }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return
            }
            offset += n
        }
    }

    public func size() -> TerminalSize {
        var ws = winsize()
        guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0, ws.ws_row > 0 else {
            return TerminalSize(width: 80, height: 24)
        }
        return TerminalSize(width: Int(ws.ws_col), height: Int(ws.ws_row))
    }
}
```

`Sources/HotplateTUI/TerminalLoop.swift`:
```swift
import Foundation

/// Feeds stdin, resize and termination signals into `TUIApp` on the main queue.
@MainActor
public final class TerminalLoop {
    private let terminal: Terminal
    private let app: TUIApp
    private var decoder = InputDecoder()
    private var sources: [DispatchSourceProtocol] = []
    private var input: DispatchSourceRead?

    public init(terminal: Terminal, app: TUIApp) { self.terminal = terminal; self.app = app }

    public func start() {
        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        input.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readInput() } }
        input.resume()
        self.input = input
        watch(SIGWINCH) { [weak self] in
            guard let self else { return }
            self.app.resize(to: self.terminal.size())
        }
        for sig in [SIGTERM, SIGHUP, SIGINT] { watch(sig) { [weak self] in self?.app.quit() } }
    }

    private func watch(_ sig: Int32, _ handler: @escaping @MainActor () -> Void) {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.resume()
        sources.append(source)
    }

    private func readInput() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(STDIN_FILENO, &buf, buf.count)
        if n == 0 {
            // The terminal went away: stop reading so EOF does not count as repeated quit requests.
            input?.cancel()
            app.quit()
            return
        }
        guard n > 0 else { return }
        for event in decoder.feed(Array(buf[0..<n])) { app.handle(event) }
        if decoder.hasPendingEscape {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for event in self.decoder.flushEscape() { self.app.handle(event) }
                }
            }
        }
    }
}
```

`Sources/HotplateTUI/Clipboard.swift`:
```swift
import Foundation

public enum Clipboard {
    public static func copy(_ text: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let pipe = Pipe()
        p.standardInput = pipe
        do {
            try p.run()
            pipe.fileHandleForWriting.write(Data(text.utf8))
            try pipe.fileHandleForWriting.close()
        } catch {}
    }
}
```

U `TUIApp.perform` posle oba `copy(…)` poziva dodaj povratnu informaciju u log, tako da `.copyLine` i `.copyAll` izgledaju ovako:
```swift
        case .copyLine:
            if let id = viewport.selectedLineId, let e = viewport.entry(id) {
                copy(e.text)
                session.log("Copied the selected line.", .info)
            }
        case .copyAll:
            copy(session.logs.map { "\(LogPane.timeFormatter.string(from: $0.time))  \($0.text)" }.joined(separator: "\n"))
            session.log("Copied the log (\(session.logs.count) lines).", .info)
```
(`testCopyLineAndAll` i dalje prolazi: proverava sadržaj kopiranog, ne log.)

- [ ] **Step 6: Executable target i `main.swift`**

U `Package.swift` dodaj red iza `.executableTarget(name: "Hotplate", …)`:
```swift
        .executableTarget(name: "hotplate-cli", dependencies: ["HotplateCore", "HotplateTUI"], path: "Sources/hotplate-cli"),
```

`Sources/hotplate-cli/main.swift`:
```swift
import Foundation
import HotplateCore
import HotplateTUI

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("hotplate: \(message)\n".utf8))
    exit(code)
}

let options: CommandLineOptions
do {
    options = try CommandLineOptions.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    let message = (error as? CommandLineOptions.ParseError)?.message ?? "\(error)"
    FileHandle.standardError.write(Data("hotplate: \(message)\n\n\(CommandLineOptions.usage)".utf8))
    exit(2)
}
if options.showHelp { print(CommandLineOptions.usage, terminator: ""); exit(0) }
if options.showVersion { print("hotplate \(HotplateVersion.current)"); exit(0) }
guard Terminal.isInteractive else { fail("needs an interactive terminal", code: 2) }

let cwd = FileManager.default.currentDirectoryPath
let start: String = {
    guard let p = options.path else { return cwd }
    let expanded = (p as NSString).expandingTildeInPath
    return expanded.hasPrefix("/") ? expanded : (cwd as NSString).appendingPathComponent(expanded)
}()

let loop: TerminalLoop = MainActor.assumeIsolated {
    let store = ProjectStore()
    let projectPath = ProjectLocator.find(from: start)
    if projectPath == nil, store.recents.isEmpty { fail("no Flutter project found at or above \(start)", code: 1) }

    let session = Session(store: store, hints: .terminal, flutterPathOverride: options.flutterPath, restoreLastProject: false)
    session.overrides = options.overrides
    if let projectPath {
        session.selectProject(path: projectPath)
    } else {
        session.log("No Flutter project at or above \(start). Pick a recent project.", .warning)
    }

    let terminal = Terminal()
    do { try terminal.enter() } catch { fail("needs an interactive terminal", code: 2) }
    let app = TUIApp(session: session, size: terminal.size(), output: terminal.write, copy: Clipboard.copy,
                     exit: { code in terminal.restore(); exit(code) })
    let loop = TerminalLoop(terminal: terminal, app: app)
    loop.start()
    Task { await app.start(autoRun: !options.noRun) }
    return loop
}

withExtendedLifetime(loop) { dispatchMain() }
```

- [ ] **Step 7: Build and run the unit tests**

Run: `swift build && swift test`
Expected: build OK, svi testovi PASS.

Run: `swift run hotplate-cli --version` → `hotplate 1.1.0`, izlazni kod 0.
Run: `swift run hotplate-cli --wat; echo "exit=$?"` → poruka `hotplate: unknown option --wat`, upotreba, `exit=2`.
Run: `swift run hotplate-cli < /dev/null > /dev/null; echo "exit=$?"` → `hotplate: needs an interactive terminal` na stderr, `exit=2`.

- [ ] **Step 8: Ručni smoke test u pravom terminalu**

Ovaj korak traži interaktivni terminal. Agent bez TTY-ja ga prijavljuje kao preskočen i ostavlja korisniku. U Flutter projektu pokreni `swift run --package-path <repo> hotplate-cli` i proveri:
1. Ekran se otvara: statusna traka, log, footer. App se pokreće na zapamćenom uređaju ili se otvara lista uređaja.
2. Snimi `.dart` fajl u `lib/` → u logu „Change detected in lib/ → hot reload“ i „Hot reload done“.
3. `r`, `R`, `d` (izbor, Ctrl+R), `c`, `a` (izmena + ⏎), `A`, `o` + ⏎ (otvara editor na liniji), klik na link, točkić, `/`, `y`, `?`.
4. Promena veličine prozora ispod 60×12 i nazad.
5. `q` → flutter staje, terminal je čist (vidljiv kursor, `echo` radi). Ponovi sa dvostrukim Ctrl+C → izlaz odmah.

- [ ] **Step 9: Commit**

```bash
git add Package.swift Sources/HotplateTUI Sources/hotplate-cli Tests/HotplateTUITests/CommandLineOptionsTests.swift
git commit -m "feat(cli): hotplate command with options, raw terminal and input loop"
```

---
### Task 12: „Install Command Line Tool…“ u GUI-ju

**Files:**
- Create: `Sources/HotplateCore/CommandLineToolStatus.swift`, `Sources/Hotplate/CommandLineInstaller.swift`
- Modify: `Sources/Hotplate/HotplateApp.swift`, `Sources/Hotplate/SettingsView.swift`
- Test: `Tests/HotplateCoreTests/CommandLineToolStatusTests.swift`

**Interfaces:**
- Produces: `enum CommandLineToolStatus: Equatable { installed, notInstalled, otherCopy(String), unavailable; static check(linkPath:helperPath:) ; static installScript(helperPath:linkPath:) -> String; static removeScript(linkPath:) -> String }`, `CommandLineInstaller.install()`, `.remove()`, `.status`, `CommandLineToolRow` (SwiftUI)

- [ ] **Step 1: Write the failing test**

`Tests/HotplateCoreTests/CommandLineToolStatusTests.swift`:
```swift
import XCTest
@testable import HotplateCore

final class CommandLineToolStatusTests: XCTestCase {
    private var dir: String!
    private var helper: String { "\(dir!)/Hotplate.app/Contents/Helpers/hotplate" }
    private var link: String { "\(dir!)/bin/hotplate" }

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath().path
        try FileManager.default.createDirectory(atPath: "\(dir!)/Hotplate.app/Contents/Helpers", withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: "\(dir!)/bin", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: helper, contents: Data())
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: dir) }

    func testNotInstalled() {
        XCTAssertEqual(CommandLineToolStatus.check(linkPath: link, helperPath: helper), .notInstalled)
    }

    func testInstalledWhenLinkPointsToThisHelper() throws {
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: helper)
        XCTAssertEqual(CommandLineToolStatus.check(linkPath: link, helperPath: helper), .installed)
    }

    func testOtherCopy() throws {
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: "/Applications/Old.app/Contents/Helpers/hotplate")
        XCTAssertEqual(CommandLineToolStatus.check(linkPath: link, helperPath: helper),
                       .otherCopy("/Applications/Old.app/Contents/Helpers/hotplate"))
        try FileManager.default.removeItem(atPath: link)
        FileManager.default.createFile(atPath: link, contents: Data())
        XCTAssertEqual(CommandLineToolStatus.check(linkPath: link, helperPath: helper), .otherCopy(link))
    }

    func testUnavailableWithoutHelper() {
        XCTAssertEqual(CommandLineToolStatus.check(linkPath: link, helperPath: "\(dir!)/missing"), .unavailable)
    }

    func testScriptsQuoteForShellAndAppleScript() {
        let script = CommandLineToolStatus.installScript(helperPath: "/Apps/It's \"Hot\".app/h", linkPath: "/usr/local/bin/hotplate")
        XCTAssertEqual(script, #"do shell script "mkdir -p '/usr/local/bin' && ln -sf '/Apps/It'\\''s \"Hot\".app/h' '/usr/local/bin/hotplate'" with administrator privileges"#)
        XCTAssertEqual(CommandLineToolStatus.removeScript(linkPath: "/usr/local/bin/hotplate"),
                       #"do shell script "rm -f '/usr/local/bin/hotplate'" with administrator privileges"#)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CommandLineToolStatusTests`
Expected: build FAIL — `cannot find 'CommandLineToolStatus' in scope`.

- [ ] **Step 3: Implement status**

`Sources/HotplateCore/CommandLineToolStatus.swift`:
```swift
import Foundation

/// Whether `/usr/local/bin/hotplate` points at the command line tool inside this copy of the app.
public enum CommandLineToolStatus: Equatable, Sendable {
    case installed
    case notInstalled
    /// Something else is at the link path: another app copy's tool or an unrelated file.
    case otherCopy(String)
    /// This build has no tool inside the bundle (e.g. `swift run`).
    case unavailable

    public static func check(linkPath: String, helperPath: String, fileManager fm: FileManager = .default) -> CommandLineToolStatus {
        guard fm.fileExists(atPath: helperPath) else { return .unavailable }
        if let destination = try? fm.destinationOfSymbolicLink(atPath: linkPath) {
            let resolved = URL(fileURLWithPath: destination).standardizedFileURL.path
            let helper = URL(fileURLWithPath: helperPath).standardizedFileURL.path
            return resolved == helper ? .installed : .otherCopy(destination)
        }
        return fm.fileExists(atPath: linkPath) ? .otherCopy(linkPath) : .notInstalled
    }

    public static func installScript(helperPath: String, linkPath: String) -> String {
        let dir = (linkPath as NSString).deletingLastPathComponent
        return adminScript("mkdir -p \(shellQuote(dir)) && ln -sf \(shellQuote(helperPath)) \(shellQuote(linkPath))")
    }

    public static func removeScript(linkPath: String) -> String {
        adminScript("rm -f \(shellQuote(linkPath))")
    }

    private static func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func adminScript(_ shell: String) -> String {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CommandLineToolStatusTests`
Expected: PASS (5 testova).

- [ ] **Step 5: GUI — installer, meni i Settings**

`Sources/Hotplate/CommandLineInstaller.swift`:
```swift
import AppKit
import SwiftUI
import HotplateCore

/// Installs `/usr/local/bin/hotplate` as a symlink to the tool inside this app, like VS Code's "Install 'code' command".
enum CommandLineInstaller {
    static let linkPath = "/usr/local/bin/hotplate"
    static var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/hotplate").path }
    static var status: CommandLineToolStatus { CommandLineToolStatus.check(linkPath: linkPath, helperPath: helperPath) }

    @MainActor static func install() {
        guard status != .unavailable else {
            alert("The command line tool is not in this build", "It ships inside Hotplate.app built with scripts/build_app.sh.")
            return
        }
        if run(CommandLineToolStatus.installScript(helperPath: helperPath, linkPath: linkPath)) {
            alert("Installed the hotplate command", "Open a new terminal tab and run hotplate in a Flutter project. Press ? inside for shortcuts.")
        }
    }

    @MainActor static func remove() {
        if run(CommandLineToolStatus.removeScript(linkPath: linkPath)) { alert("Removed the hotplate command", "") }
    }

    /// Runs an AppleScript; false when it failed or the user cancelled the password prompt.
    @MainActor private static func run(_ source: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return true }
        if (error[NSAppleScript.errorNumber] as? Int) != -128 {
            alert("Could not change the command line tool", error[NSAppleScript.errorMessage] as? String ?? "Unknown error")
        }
        return false
    }

    @MainActor private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

struct CommandLineToolRow: View {
    @State private var status = CommandLineInstaller.status

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(status == .installed ? "Reinstall" : "Install") {
                CommandLineInstaller.install(); status = CommandLineInstaller.status
            }
            .disabled(status == .unavailable)
            if status != .notInstalled, status != .unavailable {
                Button("Remove") { CommandLineInstaller.remove(); status = CommandLineInstaller.status }
            }
        }
        Text("Run hotplate in a Flutter project folder. Press ? inside for shortcuts.")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var label: String {
        switch status {
        case .installed: return "Installed at \(CommandLineInstaller.linkPath)"
        case .notInstalled: return "Not installed"
        case .otherCopy(let path): return "\(CommandLineInstaller.linkPath) points to another copy (\(path))"
        case .unavailable: return "Not available in this build"
        }
    }
}
```

U `Sources/Hotplate/HotplateApp.swift`, u `.commands { … }` pre `CommandGroup(replacing: .newItem)`, dodaj:
```swift
            CommandGroup(after: .appInfo) {
                Button("Install Command Line Tool…") { CommandLineInstaller.install() }
            }
```

U `Sources/Hotplate/SettingsView.swift`, posle `Section("Auto reload") { … }`, dodaj:
```swift
            Section("Command line") {
                CommandLineToolRow()
            }
```

- [ ] **Step 6: Build and test**

Run: `swift build && swift test`
Expected: build OK, svi testovi PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/HotplateCore/CommandLineToolStatus.swift Sources/Hotplate Tests/HotplateCoreTests/CommandLineToolStatusTests.swift
git commit -m "feat(app): install the hotplate command from the app menu and Settings"
```

---

### Task 13: Pakovanje, potpisivanje, verzija i dokumentacija

**Files:**
- Modify: `scripts/build_app.sh`, `Resources/Info.plist`, `Resources/README-dist.txt`, `README.md`, `CHANGELOG.md`

- [ ] **Step 1: Verzija u `Resources/Info.plist`**

Zameni `<key>CFBundleShortVersionString</key><string>1.0.0</string>` sa `<key>CFBundleShortVersionString</key><string>1.1.0</string>` i `<key>CFBundleVersion</key><string>1</string>` sa `<key>CFBundleVersion</key><string>2</string>`.

- [ ] **Step 2: `scripts/build_app.sh` — provera verzije i gradnja helpera**

Odmah posle reda `DMG="dist/Hotplate-$VERSION.dmg"` dodaj:
```bash
CORE_VERSION="$(sed -n 's/.*static let current = "\(.*\)".*/\1/p' Sources/HotplateCore/HotplateVersion.swift)"
if [ "$CORE_VERSION" != "$VERSION" ]; then
  echo "error: HotplateVersion.current ($CORE_VERSION) does not match Info.plist ($VERSION)" >&2; exit 1
fi
HELPER="$APP/Contents/Helpers/hotplate"
```

Zameni ceo blok od `if [ "${SKIP_BUILD:-0}" = "1" ] && [ -x "$APP/Contents/MacOS/Hotplate" ]; then` do zatvarajućeg `fi` (posle `cp "$BIN" "$APP/Contents/MacOS/Hotplate"`) sa:
```bash
if [ "${SKIP_BUILD:-0}" = "1" ] && [ -x "$APP/Contents/MacOS/Hotplate" ] && [ -x "$HELPER" ]; then
  echo "▸ SKIP_BUILD=1: reusing $APP"
  cp "$APP/Contents/MacOS/Hotplate" /tmp/hotplate-reuse.bin && cp "$HELPER" /tmp/hotplate-cli-reuse.bin
  rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
  mv /tmp/hotplate-reuse.bin "$APP/Contents/MacOS/Hotplate" && mv /tmp/hotplate-cli-reuse.bin "$HELPER"
else
echo "▸ Building release binaries (v$VERSION)…"
# Ask SwiftPM where the products land: the directory differs between toolchains.
if swift build -c release --arch arm64 --arch x86_64 >/tmp/hotplate-build.log 2>&1; then
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
else
  echo "  universal build failed (see /tmp/hotplate-build.log), falling back to native arch"
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
fi
BIN="$BIN_DIR/Hotplate"; CLI_BIN="$BIN_DIR/hotplate-cli"
for b in "$BIN" "$CLI_BIN"; do
  if [ ! -f "$b" ] || [ -n "$(find Sources -newer "$b" -name '*.swift' | head -1)" ]; then
    echo "error: $b is missing or older than the sources" >&2; exit 1
  fi
done
echo "  binaries: $BIN, $CLI_BIN"
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Hotplate"
cp "$CLI_BIN" "$HELPER"
fi
```

- [ ] **Step 3: `scripts/build_app.sh` — potpisivanje helpera pre aplikacije**

U Developer ID grani zameni telo `for attempt in 1 2 3 4 5; do … done` sa:
```bash
  for attempt in 1 2 3 4 5; do
    # The nested tool is signed first; signing the app seals it.
    codesign --force --options runtime --timestamp --entitlements Resources/Hotplate.entitlements \
             --identifier com.hrvojebencik.hotplate.cli --sign "$IDENTITY" "$HELPER"
    codesign --force --options runtime --timestamp --entitlements Resources/Hotplate.entitlements \
             --sign "$IDENTITY" "$APP"
    if codesign --verify --strict "$HELPER" 2>/dev/null && codesign -dvv "$HELPER" 2>&1 | grep -q "^Timestamp=" \
       && codesign --verify --deep --strict "$APP" 2>/dev/null && codesign -dvv "$APP" 2>&1 | grep -q "^Timestamp="; then break; fi
    echo "  signing attempt $attempt produced no timestamp, retrying in 5s…"; sleep 5
  done
```
U ad-hoc grani zameni `  codesign --force --sign - "$APP"` sa:
```bash
  codesign --force --identifier com.hrvojebencik.hotplate.cli --sign - "$HELPER"
  codesign --force --sign - "$APP"
```
Posle reda `codesign --verify --deep --strict "$APP"` (iza `fi`) dodaj:
```bash
codesign --verify --strict "$HELPER"
```

- [ ] **Step 4: Proveri build**

Run: `scripts/build_app.sh`
Expected: završava bez greške; `dist/Hotplate.app/Contents/Helpers/hotplate` postoji.
Run: `dist/Hotplate.app/Contents/Helpers/hotplate --version` → `hotplate 1.1.0`.
Run: `lipo -archs dist/Hotplate.app/Contents/Helpers/hotplate` → `x86_64 arm64` (ili samo native ako je universal build pao, što skripta javlja).
Run: `codesign -dv dist/Hotplate.app/Contents/Helpers/hotplate 2>&1 | grep Identifier` → `Identifier=com.hrvojebencik.hotplate.cli`.
Run: `sed -i '' 's/current = "1.1.0"/current = "9.9.9"/' Sources/HotplateCore/HotplateVersion.swift && scripts/build_app.sh; echo "exit=$?"; git checkout Sources/HotplateCore/HotplateVersion.swift`
Expected: `error: HotplateVersion.current (9.9.9) does not match Info.plist (1.1.0)`, `exit=1`, fajl vraćen.

- [ ] **Step 5: Dokumentacija**

U `CHANGELOG.md`, iznad `## 1.0.0 — 2026-09-18`, dodaj:
```markdown
## 1.1.0 — unreleased

- `hotplate` command: the whole app in your terminal. Run, hot reload on save, devices, launch.json configurations,
  run arguments and a log whose file links open your editor at the line, all from the keyboard (mouse works too).
- Options for one-off runs: `-d <device>`, `-c <config>`, `--no-run`, `--no-auto-reload`, `--flutter <path>`,
  and `-- <flutter run args>`. They never overwrite your saved settings.
- Hotplate → Install Command Line Tool… links `/usr/local/bin/hotplate`; Homebrew installs it automatically.
- The terminal and the app share settings: editor, debounce, and the device/args remembered per project.
```

U `README.md`, posle sekcije `## Build the distributable .app` (pre `## How it works`), dodaj:
````markdown
## Terminal

`hotplate` runs the same session in your terminal, so you never have to switch to the Hotplate window.

```bash
hotplate                      # the Flutter project in this folder (or a parent)
hotplate ~/code/my_app -d iphone -c Dev
hotplate -- --flavor dev --dart-define=API=staging
```

Install it with Hotplate → Install Command Line Tool… (Homebrew does it for you). Options apply to that run only;
choices you make inside hotplate are remembered per project, shared with the app.

| Key | Action | Key | Action |
|---|---|---|---|
| `⏎` | Run / open selected file | `o` `[` `]` | Newest error, previous/next file link |
| `r` / `R` | Hot reload / restart | `/` `n` `N` | Search the log |
| `s` | Stop | `y` / `Y` | Copy line / whole log |
| `q` | Stop and quit | `j` `k` `g` `G` `f` | Scroll, top, bottom, follow |
| `d` / `c` / `a` | Device / configuration / args | `K` | Clear the log |
| `A` | Reload on save on/off | `e` / `E` | Open in editor / choose editor |
| `p` | Recent projects | `?` | All shortcuts |

Click a file link to open it; Shift+drag selects text (Option+drag in iTerm2).
For development: `swift run hotplate-cli`.
````

Homebrew cask (`binary "#{appdir}/Hotplate.app/Contents/Helpers/hotplate"`) menja se u repou `hrvojebencik/homebrew-tap` pri izdavanju 1.1.0 i nije deo ovog plana.

U `README.md` u bloku `## Layout` dodaj dva reda iza `Sources/Hotplate       # SwiftUI app`:
```
Sources/HotplateTUI    # terminal UI (unit-tested)
Sources/hotplate-cli   # the `hotplate` command
```

Na kraj `Resources/README-dist.txt` dodaj:
```
Terminal: Hotplate → Install Command Line Tool… adds the `hotplate` command.
Run it inside a Flutter project; press ? for shortcuts.
```

- [ ] **Step 6: Commit**

```bash
git add scripts/build_app.sh Resources/Info.plist Resources/README-dist.txt README.md CHANGELOG.md
git commit -m "build: ship the hotplate command inside the app; version 1.1.0; docs"
```

---

### Task 14: Završna provera

**Files:** nema novih; samo provera i ispravke koje provera otkrije (svaka ispravka sa testom i sopstvenim commitom).

- [ ] **Step 1: Ceo test paket i build**

Run: `swift test 2>&1 | tail -5 && scripts/build_app.sh`
Expected: 0 failures; build i potpis prolaze.

- [ ] **Step 2: GUI regresija (ručno, korisnik)**

Otvori `dist/Hotplate.app` i prođi: izbor projekta, uređaji (osveži), launch.json konfiguracija, izmena argumenata, Run, reload na save, ⌘R/⌘⇧R, ⌃⌥R iz drugog programa, klik na link u logu otvara editor, menu bar panel, Settings → Command line → Install, pa `hotplate --version` u novom terminalu.

- [ ] **Step 3: Terminali (ručno, korisnik)**

U Terminal.app, iTerm2, Ghostty, kitty, WezTerm i u tmux-u unutar jednog od njih proveri: boje, klik na link, točkić, Shift-selekciju, resize ispod 60×12 i nazad, paste u `a` polje, `q` i dupli Ctrl+C (terminal posle izlaza mora biti normalan: kursor vidljiv, unos se prikazuje). U tmux-u miš radi samo uz `set -g mouse on`; zapiši to u README ako se potvrdi.

- [ ] **Step 4: Zajednička podešavanja**

Promeni uređaj u TUI-ju (`d`), zatvori `hotplate`, otvori GUI na istom projektu → isti uređaj je izabran. Pokreni `hotplate -d chrome`, izađi, otvori GUI → uređaj je i dalje onaj sačuvani (override se nije upisao).
