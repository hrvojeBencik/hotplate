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
