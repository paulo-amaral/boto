import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class ImportanceTests: XCTestCase {
    private var container: ModelContainer?

    private func makeBoard() throws -> Board {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let project = Project(name: "P")
        container.mainContext.insert(project)
        return project.addBoard(name: "B", listNames: ["To do", "Doing"])
    }

    func testCardsStartUnsetAndChangesAreRecordedOnce() throws {
        let board = try makeBoard()
        let card = board.orderedLists[0].addCard(title: "A")
        XCTAssertEqual(card.importance, .unset)
        card.setImportance(.unset)
        card.setImportance(.high)
        card.setImportance(.high)
        card.setImportance(.unset)
        XCTAssertEqual(card.importance, .unset)
        XCTAssertNil(card.importanceRaw, "unset stores nothing")
        XCTAssertEqual(card.timeline.map(\.kind), [.created, .importanceChanged, .importanceChanged])
        XCTAssertEqual(card.timeline.map(\.text), ["To do", "High", "None"])
    }

    func testLanesAreOrderedHighToNoneWithOneCellPerList() throws {
        let board = try makeBoard()
        let lanes = ImportanceGrouping.lanes(lists: board.orderedLists, showArchived: false, filter: CardFilter())
        XCTAssertEqual(lanes.map(\.importance), [.high, .medium, .low, .unset])
        XCTAssertTrue(lanes.allSatisfy { $0.cells.map(\.list.name) == ["To do", "Doing"] })
        XCTAssertTrue(lanes.allSatisfy { $0.count == 0 })
    }

    func testCardsLandInTheCellOfTheirListAndImportanceInListOrder() throws {
        let board = try makeBoard()
        let todo = board.orderedLists[0], doing = board.orderedLists[1]
        let a = todo.addCard(title: "A")
        let b = todo.addCard(title: "B")
        let c = doing.addCard(title: "C")
        todo.addCard(title: "D")
        a.setImportance(.high)
        b.setImportance(.high)
        c.setImportance(.medium)

        let lanes = ImportanceGrouping.lanes(lists: board.orderedLists, showArchived: false, filter: CardFilter())
        XCTAssertEqual(lanes[0].cells[0].cards.map(\.title), ["A", "B"])
        XCTAssertEqual(lanes[0].cells[1].cards.map(\.title), [])
        XCTAssertEqual(lanes[1].cells[1].cards.map(\.title), ["C"])
        XCTAssertEqual(lanes[3].cells[0].cards.map(\.title), ["D"])
        XCTAssertEqual(lanes.map(\.count), [2, 1, 0, 1])
    }

    func testArchivedCardsAndTheFilterApply() throws {
        let board = try makeBoard()
        let todo = board.orderedLists[0]
        let kept = todo.addCard(title: "Kept")
        let archived = todo.addCard(title: "Archived")
        kept.setImportance(.low)
        archived.setImportance(.low)
        archived.setArchived(true)

        XCTAssertEqual(ImportanceGrouping.lanes(lists: board.orderedLists, showArchived: false, filter: CardFilter())[2].count, 1)
        XCTAssertEqual(ImportanceGrouping.lanes(lists: board.orderedLists, showArchived: true, filter: CardFilter())[2].count, 2)

        var filter = CardFilter()
        filter.dueDates = [.noDueDate]
        kept.setDueDate(Date())
        XCTAssertEqual(ImportanceGrouping.lanes(lists: board.orderedLists, showArchived: false, filter: filter)[2].count, 0)
    }

    func testMovingAcrossListsKeepsImportance() throws {
        let board = try makeBoard()
        let todo = board.orderedLists[0], doing = board.orderedLists[1]
        let card = todo.addCard(title: "A")
        card.setImportance(.medium)
        doing.place(card, at: 0)
        XCTAssertEqual(card.importance, .medium)
        XCTAssertEqual(ImportanceGrouping.lanes(lists: board.orderedLists, showArchived: false, filter: CardFilter())[1].cells[1].cards.count, 1)
    }
}
