import XCTest
@testable import KanbanCore

final class ReferenceTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("boto-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    @discardableResult
    private func write(_ relative: String, in root: URL? = nil) throws -> URL {
        let url = (root ?? temp).appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testPlainFileUnderProjectRootStoresRelativePath() throws {
        let file = try write("client/brief.pdf")
        let reference = Reference.make(url: file, projectRoot: temp.appendingPathComponent("client"))
        XCTAssertEqual(reference.kind, .file)
        XCTAssertEqual(reference.relativePath, "brief.pdf")
    }

    func testNoteInsideVaultIsDetected() throws {
        let vault = temp.appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        let note = try write("Clients/Acme/kickoff.md", in: vault)
        let reference = Reference.make(url: note, projectRoot: nil)
        XCTAssertEqual(reference.kind, .obsidianNote)
        XCTAssertEqual(reference.vaultName, "Vault")
        XCTAssertEqual(reference.relativePath, "Clients/Acme/kickoff.md")
        XCTAssertEqual(
            reference.obsidianURL?.absoluteString,
            "obsidian://open?vault=Vault&file=Clients%2FAcme%2Fkickoff.md"
        )
    }

    func testMarkdownOutsideVaultIsPlainFile() throws {
        let note = try write("loose.md")
        XCTAssertEqual(Reference.make(url: note, projectRoot: nil).kind, .file)
    }

    func testFolderKind() throws {
        let folder = temp.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertEqual(Reference.make(url: folder, projectRoot: nil).kind, .folder)
    }

    func testResolvesAfterFileIsRenamedViaBookmark() throws {
        let file = try write("a.txt")
        let reference = Reference.make(url: file, projectRoot: nil)
        let renamed = temp.appendingPathComponent("b.txt")
        try FileManager.default.moveItem(at: file, to: renamed)
        let resolved = reference.resolvedURL(projectRoot: nil)
        XCTAssertEqual(resolved?.resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
    }

    func testResolvesViaNewProjectRootWhenBookmarkIsMissing() throws {
        let oldRoot = temp.appendingPathComponent("old")
        let file = try write("brief.pdf", in: oldRoot)
        let reference = Reference.make(url: file, projectRoot: oldRoot)
        reference.bookmarkData = nil
        let newRoot = temp.appendingPathComponent("new")
        try FileManager.default.moveItem(at: oldRoot, to: newRoot)
        XCTAssertEqual(
            reference.resolvedURL(projectRoot: newRoot)?.resolvingSymlinksInPath(),
            newRoot.appendingPathComponent("brief.pdf").resolvingSymlinksInPath()
        )
    }

    func testBrokenReferenceResolvesToNil() throws {
        let file = try write("gone.txt")
        let reference = Reference.make(url: file, projectRoot: nil)
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(reference.resolvedURL(projectRoot: nil))
    }
}
