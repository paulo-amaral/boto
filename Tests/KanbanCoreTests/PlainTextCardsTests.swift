import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class PlainTextCardsTests: XCTestCase {
    private var container: ModelContainer?

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    func testOneTitlePerNonEmptyLine() {
        XCTAssertEqual(PlainTextCards.titles(in: "A\n\n  B  \r\nC"), ["A", "B", "C"])
    }

    func testStripsBulletsNumbersAndCheckboxes() {
        let text = "- one\n* two\n• three\n+ four\n1. five\n2) six\n[ ] seven\n- [x] eight\n  - nested nine"
        XCTAssertEqual(
            PlainTextCards.titles(in: text),
            ["one", "two", "three", "four", "five", "six", "seven", "eight", "nested nine"]
        )
    }

    func testKeepsHyphensAndNumbersInsideTitles() {
        XCTAssertEqual(PlainTextCards.titles(in: "Re-test 2024 plan\n3D model"), ["Re-test 2024 plan", "3D model"])
    }

    func testBlankInputGivesNoTitles() {
        XCTAssertTrue(PlainTextCards.titles(in: " \n\t\n").isEmpty)
    }

    func testAddCardsFromTextAppendsInOrder() throws {
        let context = try makeContext()
        let list = BoardList(name: "Todo", index: 0)
        context.insert(list)
        list.addCard(title: "Existing")
        let created = list.addCards(fromText: "- A\n- B")
        XCTAssertEqual(created.count, 2)
        XCTAssertEqual(list.orderedCards.map(\.title), ["Existing", "A", "B"])
    }

    func testPlaceSeveralCardsKeepsTheirOrder() throws {
        let context = try makeContext()
        let source = BoardList(name: "Todo", index: 0)
        let target = BoardList(name: "Done", index: 1)
        context.insert(source)
        context.insert(target)
        let cards = source.addCards(fromText: "A\nB\nC")
        target.addCard(title: "X")
        target.place([cards[2], cards[0]], at: 0)
        XCTAssertEqual(target.orderedCards.map(\.title), ["C", "A", "X"])
        XCTAssertEqual(source.orderedCards.map(\.title), ["B"])
    }
}
