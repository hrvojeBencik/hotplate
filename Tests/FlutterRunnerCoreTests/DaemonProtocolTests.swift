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
