import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class ProjectTests: XCTestCase {
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    func testAddBoardCreatesOrderedDefaultLists() throws {
        let context = try makeContext()
        let project = Project(name: "Acme")
        context.insert(project)
        let board = project.addBoard(name: "Main")
        XCTAssertEqual(board.orderedLists.map(\.name), ["To do", "In progress", "Done"])
        XCTAssertTrue(board.project === project)
        XCTAssertEqual(project.activeBoards.count, 1)
    }

    func testDeletedBoardsAreHidden() throws {
        let context = try makeContext()
        let project = Project(name: "Acme")
        context.insert(project)
        let board = project.addBoard(name: "Main")
        board.deletedAt = Date()
        XCTAssertTrue(project.activeBoards.isEmpty)
    }

    func testRootFolderSurvivesRename() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("boto-\(UUID().uuidString)")
        let original = temp.appendingPathComponent("client")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let project = Project(name: "Acme")
        project.setRootFolder(original)
        let renamed = temp.appendingPathComponent("client-2025")
        try FileManager.default.moveItem(at: original, to: renamed)

        XCTAssertEqual(project.rootFolderURL?.resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
    }

    func testClearingRootFolder() {
        let project = Project(name: "Acme")
        project.setRootFolder(FileManager.default.temporaryDirectory)
        project.setRootFolder(nil)
        XCTAssertNil(project.rootFolderURL)
    }
}
