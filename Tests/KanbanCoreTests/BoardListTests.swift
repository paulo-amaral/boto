import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class BoardListTests: XCTestCase {
    // The context does not retain its container; letting it deallocate traps inside SwiftData.
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func titles(_ list: BoardList) -> [String] { list.orderedCards.map(\.title) }

    func testAddCardAppendsInOrder() throws {
        let context = try makeContext()
        let list = BoardList(name: "Todo", index: 0)
        context.insert(list)
        list.addCard(title: "A")
        list.addCard(title: "B")
        XCTAssertEqual(titles(list), ["A", "B"])
    }

    func testPlaceReordersWithinList() throws {
        let context = try makeContext()
        let list = BoardList(name: "Todo", index: 0)
        context.insert(list)
        let a = list.addCard(title: "A")
        list.addCard(title: "B")
        list.addCard(title: "C")
        list.place(a, at: 2)
        XCTAssertEqual(titles(list), ["B", "C", "A"])
    }

    func testPlaceMovesCardBetweenLists() throws {
        let context = try makeContext()
        let todo = BoardList(name: "Todo", index: 0)
        let done = BoardList(name: "Done", index: 1)
        context.insert(todo)
        context.insert(done)
        let a = todo.addCard(title: "A")
        todo.addCard(title: "B")
        done.addCard(title: "X")
        done.place(a, at: 0)
        XCTAssertEqual(titles(todo), ["B"])
        XCTAssertEqual(titles(done), ["A", "X"])
    }

    func testPlaceClampsOutOfRangePosition() throws {
        let context = try makeContext()
        let list = BoardList(name: "Todo", index: 0)
        context.insert(list)
        let a = list.addCard(title: "A")
        list.addCard(title: "B")
        list.place(a, at: 99)
        XCTAssertEqual(titles(list), ["B", "A"])
    }

    func testChecklistProgressIgnoresDeletedItems() throws {
        let context = try makeContext()
        let card = Card(title: "A", index: 0)
        context.insert(card)
        let checklist = Checklist(name: "Steps", index: 0, card: card)
        let done = ChecklistItem(title: "1", index: 0, completed: true)
        let open = ChecklistItem(title: "2", index: 1)
        let removed = ChecklistItem(title: "3", index: 2, completed: true)
        removed.deletedAt = Date()
        checklist.items = [done, open, removed]
        XCTAssertEqual(card.checklistProgress.done, 1)
        XCTAssertEqual(card.checklistProgress.total, 2)
    }
}
