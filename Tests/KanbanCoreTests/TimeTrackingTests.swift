import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class TimeTrackingTests: XCTestCase {
    private var container: ModelContainer?

    private func makeProject() throws -> (ModelContext, Project, BoardList) {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let project = Project(name: "Client")
        container.mainContext.insert(project)
        let board = project.addBoard(name: "B")
        let list = BoardList(name: "L", index: 0)
        board.lists.append(list)
        return (container.mainContext, project, list)
    }

    func testTimerAddsElapsedTimeWhenStopped() throws {
        let (context, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        let start = Date()
        card.startTimer(in: context, at: start)
        XCTAssertEqual(card.totalSeconds(at: start.addingTimeInterval(90)), 90, "running time counts live")
        card.stopTimer(at: start.addingTimeInterval(120))
        XCTAssertNil(card.runningTimer)
        XCTAssertEqual(card.totalSeconds(at: start.addingTimeInterval(500)), 120)
    }

    func testStartingATimerStopsTheOneRunningElsewhere() throws {
        let (context, _, list) = try makeProject()
        let a = list.addCard(title: "A")
        let b = list.addCard(title: "B")
        let start = Date()
        a.startTimer(in: context, at: start)
        b.startTimer(in: context, at: start.addingTimeInterval(60))
        XCTAssertNil(a.runningTimer)
        XCTAssertEqual(a.totalSeconds(at: start.addingTimeInterval(999)), 60)
        XCTAssertNotNil(b.runningTimer)
    }

    func testStartingTwiceKeepsTheSameTimer() throws {
        let (context, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        let first = card.startTimer(in: context)
        XCTAssertTrue(card.startTimer(in: context) === first)
        XCTAssertEqual(card.liveTimeEntries.count, 1)
    }

    func testManualEntryRejectsZeroAndTrimsNote() throws {
        let (_, _, list) = try makeProject()
        let card = list.addCard(title: "A")
        XCTAssertNil(card.logTime(seconds: 0, on: Date()))
        let entry = try XCTUnwrap(card.logTime(seconds: 3600, on: Date(), note: "  call  "))
        XCTAssertEqual(entry.note, "call")
    }

    func testReportFiltersByDayInclusiveAndTotals() throws {
        let (_, project, list) = try makeProject()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let lastMonth = calendar.date(byAdding: .day, value: -40, to: today)!
        let a = list.addCard(title: "A")
        let b = list.addCard(title: "B")
        a.logTime(seconds: 3600, on: today)
        a.logTime(seconds: 1800, on: yesterday)
        b.logTime(seconds: 7200, on: today)
        b.logTime(seconds: 9000, on: lastMonth)

        project.logTime(seconds: 600, on: today, note: "planning call")

        let report = TimeReport(project: project, from: yesterday, to: today)
        XCTAssertEqual(report.totalSeconds, 13200)
        XCTAssertEqual(report.byDay.map(\.seconds), [11400, 1800])
        XCTAssertEqual(report.byCard.map(\.title), ["B", "A", TimeReport.noCard])
        XCTAssertEqual(TimeReport.clock(5400), "1:30")
    }

    func testCSVQuotesFieldsAndUsesDecimalHours() throws {
        let (_, project, list) = try makeProject()
        let today = Date()
        list.addCard(title: "Say \"hi\", ok").logTime(seconds: 5400, on: today, note: "a,b")
        let csv = TimeReport(project: project, from: today, to: today).csv
        XCTAssertTrue(csv.hasPrefix("\"Date\",\"Card\",\"Note\",\"Hours\"\n"))
        XCTAssertTrue(csv.contains("\"Say \"\"hi\"\", ok\",\"a,b\",\"1.50\""))
    }

    func testProjectLevelTimeHasNoCardAndRejectsZero() throws {
        let (_, project, _) = try makeProject()
        XCTAssertNil(project.logTime(seconds: 0, on: Date()))
        let entry = try XCTUnwrap(project.logTime(seconds: 7200, on: Date(), note: "  workshop prep  "))
        XCTAssertNil(entry.card)
        XCTAssertEqual(entry.note, "workshop prep")
        let report = TimeReport(project: project, from: Date(), to: Date())
        XCTAssertEqual(report.rows.map(\.note), ["workshop prep"])
        XCTAssertTrue(report.csv.contains("\"No card\",\"workshop prep\",\"2.00\""))
    }
}
