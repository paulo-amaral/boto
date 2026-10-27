import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class CalendarSyncTests: XCTestCase {
    private var container: ModelContainer?

    private func makeCard(title: String = "Ship report") throws -> Card {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let list = BoardList(name: "To do", index: 0)
        container.mainContext.insert(list)
        return list.addCard(title: title)
    }

    func testDraftIsNilWithoutDueDate() throws {
        XCTAssertNil(CalendarEventDraft(card: try makeCard()))
    }

    func testDraftIsAllDayOnTheDueDay() throws {
        let card = try makeCard()
        card.details = "Send to client"
        let calendar = Calendar(identifier: .gregorian)
        card.dueDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 17, minute: 45))
        let draft = try XCTUnwrap(CalendarEventDraft(card: card, calendar: calendar))
        XCTAssertEqual(draft.title, "Ship report")
        XCTAssertEqual(draft.notes, "Send to client")
        XCTAssertEqual(draft.start, calendar.date(from: DateComponents(year: 2026, month: 11, day: 3)))
        XCTAssertTrue(draft.isAllDay)
        XCTAssertEqual(draft.alertOffset, 9 * 3600, "all-day events alert at 09:00 by default")
    }

    func testTimedDraftStartsAtTheChosenTimeAndAlertsBefore() throws {
        let card = try makeCard()
        let calendar = Calendar(identifier: .gregorian)
        card.dueDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3))
        card.dueTimeMinutes = 14 * 60 + 30
        card.alertLeadMinutes = 10
        let draft = try XCTUnwrap(CalendarEventDraft(card: card, calendar: calendar))
        XCTAssertFalse(draft.isAllDay)
        XCTAssertEqual(draft.start, calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 14, minute: 30)))
        XCTAssertEqual(draft.end.timeIntervalSince(draft.start), 3600)
        XCTAssertEqual(draft.alertOffset, -600)
    }

    func testNoAlertAndAllDayLead() throws {
        let card = try makeCard()
        card.dueDate = Date()
        card.alertLeadMinutes = Card.noAlert
        XCTAssertNil(try XCTUnwrap(CalendarEventDraft(card: card)).alertOffset)
        card.alertLeadMinutes = 1440
        XCTAssertEqual(try XCTUnwrap(CalendarEventDraft(card: card)).alertOffset, 9 * 3600 - 86_400)
    }

    func testClearingTheDueDateClearsTheTime() throws {
        let card = try makeCard()
        card.setDueDate(Date())
        card.dueTimeMinutes = 600
        card.setDueDate(nil)
        XCTAssertNil(card.dueTimeMinutes)
    }

    func testCandidatesAreOpenDatedCardsInLiveLists() throws {
        let card = try makeCard()
        let board = Board(name: "B")
        let list = try XCTUnwrap(card.list)
        board.lists.append(list)
        card.dueDate = Date()
        let undated = list.addCard(title: "No date")
        let done = list.addCard(title: "Done")
        done.dueDate = Date()
        done.setCompleted(true)
        XCTAssertEqual(board.calendarCandidates.map(\.title), ["Ship report"])
        XCTAssertFalse(board.calendarCandidates.contains { $0 === undated })
    }
}
