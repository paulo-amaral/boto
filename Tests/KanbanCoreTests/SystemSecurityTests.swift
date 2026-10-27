import XCTest
@testable import KanbanCore

final class SystemSecurityTests: XCTestCase {
    func testParsesFileVaultOutput() {
        XCTAssertEqual(SystemSecurity.parseFileVault("FileVault is On.\n"), .on)
        XCTAssertEqual(SystemSecurity.parseFileVault("FileVault is Off.\n"), .off)
        XCTAssertEqual(SystemSecurity.parseFileVault("FileVault is On.\nEncryption in progress"), .on)
    }

    func testUnrecognisedOutputIsUnknownNotOff() {
        XCTAssertEqual(SystemSecurity.parseFileVault(""), .unknown)
        XCTAssertEqual(SystemSecurity.parseFileVault("error: something else"), .unknown)
    }
}
