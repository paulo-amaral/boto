import XCTest
@testable import KanbanCore

final class CardFilterTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // Monday 2026-10-26 15:00 UTC
    private let now = Date(timeIntervalSince1970: 1_793_026_800)

    private func card(dueInDays days: Int?, hoursOffset: Int = 0) -> Card {
        let card = Card(title: "c", index: 0)
        if let days {
            let start = calendar.startOfDay(for: now)
            card.dueDate = calendar.date(byAdding: .hour, value: days * 24 + hoursOffset, to: start)
        }
        return card
    }

    private func matches(_ filter: DueDateFilter, _ card: Card) -> Bool {
        var f = CardFilter()
        f.dueDates = [filter]
        return f.matches(card, now: now, calendar: calendar)
    }

    func testEmptyFilterMatchesEverything() {
        XCTAssertTrue(CardFilter().matches(card(dueInDays: nil), now: now, calendar: calendar))
    }

    func testOverdueIsStrictlyBeforeToday() {
        XCTAssertTrue(matches(.overdue, card(dueInDays: -1)))
        XCTAssertFalse(matches(.overdue, card(dueInDays: 0)))
        XCTAssertFalse(matches(.overdue, card(dueInDays: nil)))
    }

    func testTodayAndTomorrowUseHalfOpenDayRanges() {
        XCTAssertTrue(matches(.today, card(dueInDays: 0, hoursOffset: 23)))
        XCTAssertFalse(matches(.today, card(dueInDays: 1)))
        XCTAssertTrue(matches(.tomorrow, card(dueInDays: 1)))
        XCTAssertFalse(matches(.tomorrow, card(dueInDays: 2)))
    }

    func testNextWeekAndNextMonthDoNotOverlap() {
        XCTAssertTrue(matches(.nextWeek, card(dueInDays: 7)))
        XCTAssertFalse(matches(.nextWeek, card(dueInDays: 8)))
        XCTAssertTrue(matches(.nextMonth, card(dueInDays: 8)))
        XCTAssertFalse(matches(.nextMonth, card(dueInDays: 31)))
    }

    func testNoDueDate() {
        XCTAssertTrue(matches(.noDueDate, card(dueInDays: nil)))
        XCTAssertFalse(matches(.noDueDate, card(dueInDays: 0)))
    }

    func testLabelsAreOrWithinGroupAndAndAcrossGroups() {
        let urgent = Label(name: "Urgent")
        let other = Label(name: "Other")
        let tagged = card(dueInDays: 0)
        tagged.labels = [urgent]

        var filter = CardFilter()
        filter.labelIds = [urgent.publicId, other.publicId]
        XCTAssertTrue(filter.matches(tagged, now: now, calendar: calendar))

        filter.dueDates = [.tomorrow]
        XCTAssertFalse(filter.matches(tagged, now: now, calendar: calendar))
    }

    func testListFilterAndCount() {
        let shown = BoardList(name: "A", index: 0)
        let hidden = BoardList(name: "B", index: 1)
        var filter = CardFilter()
        XCTAssertTrue(filter.showsList(hidden))
        filter.listIds = [shown.publicId]
        XCTAssertTrue(filter.showsList(shown))
        XCTAssertFalse(filter.showsList(hidden))
        filter.dueDates = [.today]
        XCTAssertEqual(filter.count, 2)
        filter.clear()
        XCTAssertEqual(filter.count, 0)
    }
}
