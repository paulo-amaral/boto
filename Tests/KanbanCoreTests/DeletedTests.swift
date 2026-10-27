import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class DeletedTests: XCTestCase {
    private var container: ModelContainer?

    private func makeProject() throws -> (Project, Board, BoardList) {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let project = Project(name: "P")
        container.mainContext.insert(project)
        let board = project.addBoard(name: "B")
        let list = BoardList(name: "L", index: 0)
        board.lists.append(list)
        return (project, board, list)
    }

    func testNothingIsRestorableUntilItIsDeleted() throws {
        let (_, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        XCTAssertFalse(card.canRestore)
        XCTAssertFalse(list.canRestore)
    }

    func testADeletedCardComesBackToItsList() throws {
        let (_, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        card.deletedAt = Date()
        XCTAssertTrue(card.canRestore)
        XCTAssertTrue(list.orderedCards.isEmpty)
        card.deletedAt = nil
        XCTAssertEqual(list.orderedCards.map(\.title), ["A"])
    }

    func testACardInADeletedListCannotBeRestoredOnItsOwn() throws {
        let (_, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        card.deletedAt = Date()
        list.deletedAt = Date()
        XCTAssertFalse(card.canRestore, "it would reappear inside a list nobody can see")
        XCTAssertTrue(list.canRestore)
        list.deletedAt = nil
        XCTAssertTrue(card.canRestore)
    }

    func testRestoringAListBringsItsCardsWithIt() throws {
        let (_, board, list) = try makeProject()
        list.addCard(title: "A")
        list.addCard(title: "B")
        list.deletedAt = Date()
        XCTAssertFalse(board.orderedLists.contains { $0 === list })
        list.deletedAt = nil
        XCTAssertEqual(board.orderedLists.first { $0 === list }?.orderedCards.map(\.title), ["A", "B"])
    }

    func testNothingInsideADeletedProjectIsRestorableOnItsOwn() throws {
        let (project, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        card.deletedAt = Date()
        list.deletedAt = Date()
        project.deletedAt = Date()
        XCTAssertFalse(card.canRestore)
        XCTAssertFalse(list.canRestore)
    }
}
