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
