import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class CardEventTests: XCTestCase {
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func kinds(_ card: Card) -> [CardEventKind] { card.timeline.map(\.kind) }

    func testNewCardRecordsCreationInItsList() throws {
        let context = try makeContext()
        let list = BoardList(name: "To do", index: 0)
        context.insert(list)
        let card = list.addCard(title: "A")
        XCTAssertEqual(kinds(card), [.created])
        XCTAssertEqual(card.timeline[0].text, "To do")
    }

    func testMovingBetweenListsIsRecordedButReorderingIsNot() throws {
        let context = try makeContext()
        let todo = BoardList(name: "To do", index: 0)
        let done = BoardList(name: "Done", index: 1)
        context.insert(todo)
        context.insert(done)
        let a = todo.addCard(title: "A")
        todo.addCard(title: "B")

        todo.place(a, at: 1)
        XCTAssertEqual(kinds(a), [.created])

        done.place(a, at: 0)
        XCTAssertEqual(kinds(a), [.created, .moved])
        XCTAssertEqual(a.timeline[1].text, "To do → Done")
    }

    func testBulkMoveRecordsOnEachCard() throws {
        let context = try makeContext()
        let source = BoardList(name: "A", index: 0)
        let target = BoardList(name: "B", index: 1)
        context.insert(source)
        context.insert(target)
        let cards = source.addCards(fromText: "x\ny")
        target.place(cards, at: 0)
        XCTAssertTrue(cards.allSatisfy { kinds($0) == [.created, .moved] })
    }

    func testArchiveRestoreAndDueDateOnlyRecordRealChanges() throws {
        let context = try makeContext()
        let list = BoardList(name: "L", index: 0)
        context.insert(list)
        let card = list.addCard(title: "A")

        card.setArchived(false)
        card.setArchived(true)
        card.setArchived(true)
        card.setArchived(false)
        card.setDueDate(nil)
        card.setDueDate(Date())
        card.setDueDate(nil)
        XCTAssertEqual(kinds(card), [.created, .archived, .restored, .dueDateSet, .dueDateCleared])
    }

    func testCompletingAndReopeningAreRecordedOnlyOnRealChanges() throws {
        let context = try makeContext()
        let list = BoardList(name: "L", index: 0)
        context.insert(list)
        let card = list.addCard(title: "A")
        card.setCompleted(false)
        card.setCompleted(true)
        card.setCompleted(true)
        XCTAssertTrue(card.isCompleted)
        card.setCompleted(false)
        XCTAssertFalse(card.isCompleted)
        XCTAssertEqual(kinds(card), [.created, .completed, .reopened])
    }

    func testQuickDueDateChangesFoldIntoOneEntry() throws {
        let context = try makeContext()
        let list = BoardList(name: "L", index: 0)
        context.insert(list)
        let card = list.addCard(title: "A")
        let day: TimeInterval = 86_400
        card.setDueDate(Date())
        card.setDueDate(Date().addingTimeInterval(day))
        card.setDueDate(Date().addingTimeInterval(2 * day))
        XCTAssertEqual(kinds(card), [.created, .dueDateSet])
        XCTAssertEqual(card.timeline[1].text, Date().addingTimeInterval(2 * day).formatted(date: .abbreviated, time: .omitted))
        card.setDueDate(nil)
        XCTAssertEqual(kinds(card), [.created, .dueDateSet, .dueDateCleared])
    }

    func testLabelsAttachDetachWithoutDuplicates() throws {
        let context = try makeContext()
        let list = BoardList(name: "L", index: 0)
        context.insert(list)
        let card = list.addCard(title: "A")
        let label = Label(name: "Urgent")
        card.attach(label)
        card.attach(label)
        XCTAssertEqual(card.labels.count, 1)
        card.detach(label)
        card.detach(label)
        XCTAssertTrue(card.labels.isEmpty)
        XCTAssertEqual(kinds(card), [.created, .labelAdded, .labelRemoved])
        XCTAssertEqual(card.timeline[1].text, "Urgent")
    }

    func testCommentsKeepOrderAndIgnoreBlank() throws {
        let context = try makeContext()
        let list = BoardList(name: "L", index: 0)
        context.insert(list)
        let card = list.addCard(title: "A")
        card.addComment("  first  ")
        card.addComment("   \n ")
        card.addComment("second")
        XCTAssertEqual(card.timeline.filter { $0.kind == .comment }.map(\.text), ["first", "second"])
        XCTAssertEqual(card.timeline.map(\.index), [0, 1, 2])
    }
}
