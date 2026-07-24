import XCTest
@testable import Prosciutto

final class BrewUpdateInstallerTests: XCTestCase {
    func testLocatePicksFirstExisting() {
        let inst = BrewUpdateInstaller(brewPaths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"],
                                       fileExists: { $0 == "/usr/local/bin/brew" })
        XCTAssertEqual(inst.locateBrew(), "/usr/local/bin/brew")
    }
    func testLocateNilWhenNoneExist() {
        let inst = BrewUpdateInstaller(fileExists: { _ in false })
        XCTAssertNil(inst.locateBrew())
    }
    func testScriptWaitsUpgradesReopensLogs() {
        let inst = BrewUpdateInstaller()
        let s = inst.makeScript(brew: "/opt/homebrew/bin/brew", pid: 4242, logPath: "/tmp/u.log")
        XCTAssertTrue(s.contains("kill -0 4242"))
        XCTAssertTrue(s.contains("'/opt/homebrew/bin/brew' update"))   // refresh tap before upgrade
        XCTAssertTrue(s.contains("'/opt/homebrew/bin/brew' upgrade --cask amirchuosho/prosciutto/prosciutto"))
        XCTAssertTrue(s.contains("open -a Prosciutto"))
        XCTAssertTrue(s.contains("/tmp/u.log"))
    }
}
