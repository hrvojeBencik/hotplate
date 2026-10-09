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
