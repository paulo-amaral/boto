import AppKit
import XCTest
@testable import KanbanCore
@testable import KanbanUI

@MainActor
final class FileTypeInfoTests: XCTestCase {
    private func reference(_ kind: ReferenceKind, _ path: String) -> Reference { Reference(kind: kind, displayPath: path) }

    func testKindsThatAreNotFilesNameThemselves() {
        XCTAssertEqual(FileTypeInfo.name(for: reference(.folder, "/Clients/Northwind")), "Folder")
        XCTAssertEqual(FileTypeInfo.name(for: reference(.obsidianNote, "/Vault/Notes/Plan.md")), "Obsidian note")
        XCTAssertEqual(FileTypeInfo.name(for: reference(.githubIssue, "https://github.com/a/b/issues/1")), "GitHub issue")
        XCTAssertEqual(FileTypeInfo.name(for: reference(.githubPullRequest, "https://github.com/a/b/pull/2")), "GitHub pull request")
        XCTAssertEqual(FileTypeInfo.name(for: reference(.email, "message://x")), "Email")
    }

    func testAFileIsNamedByItsType() {
        XCTAssertTrue(FileTypeInfo.fileTypeName(forPath: "/x/brief.pdf").localizedCaseInsensitiveContains("pdf"))
        XCTAssertFalse(FileTypeInfo.fileTypeName(forPath: "/x/ledger.xlsx").isEmpty)
        XCTAssertEqual(FileTypeInfo.fileTypeName(forPath: "/x/data.zzqq9"), "ZZQQ9 file", "a type the system does not know")
        XCTAssertEqual(FileTypeInfo.fileTypeName(forPath: "/x/Makefile"), "File", "no extension")
        XCTAssertEqual(FileTypeInfo.fileTypeName(forPath: "/x/a.pdf").first?.isUppercase, true)
    }

    func testFilesAndFoldersGetTheirTypeIconEvenWhenMissing() {
        XCTAssertNotNil(FileTypeInfo.image(for: reference(.file, "/gone/brief.pdf"), resolved: nil))
        XCTAssertNotNil(FileTypeInfo.image(for: reference(.folder, "/gone/Client"), resolved: nil))
        XCTAssertNotNil(FileTypeInfo.image(for: reference(.obsidianNote, "/gone/Plan.md"), resolved: nil))
        XCTAssertNotNil(FileTypeInfo.image(for: reference(.file, "/gone/noextension"), resolved: nil))
    }

    func testAnExistingFileUsesItsOwnIcon() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")
        XCTAssertNotNil(FileTypeInfo.image(for: reference(.file, url.path), resolved: url))
    }

    func testRemoteThingsUseASymbolInstead() {
        XCTAssertNil(FileTypeInfo.image(for: reference(.githubIssue, "https://github.com/a/b/issues/1"), resolved: nil))
        XCTAssertNil(FileTypeInfo.image(for: reference(.email, "message://x"), resolved: nil))
        for kind: ReferenceKind in [.file, .folder, .obsidianNote, .githubIssue, .githubPullRequest, .email] {
            XCTAssertNotNil(NSImage(systemSymbolName: FileTypeInfo.symbol(for: kind), accessibilityDescription: nil), "\(kind)")
        }
    }
}
