import XCTest
@testable import HotplateCore

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
