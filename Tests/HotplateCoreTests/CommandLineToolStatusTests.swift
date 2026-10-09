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
