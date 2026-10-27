import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class TimesheetTests: XCTestCase {
    private var container: ModelContainer?
    private let calendar = Calendar.current

    private func makeProject() throws -> (Project, BoardList) {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let project = Project(name: "Client")
        container.mainContext.insert(project)
        let list = BoardList(name: "L", index: 0)
        project.addBoard(name: "B").lists.append(list)
        return (project, list)
    }

    func testDurationParserAcceptsCommonForms() {
        let cases: [(String, Int?)] = [
            ("1:30", 5400), ("0:45", 2700), ("1.5", 5400), ("1,5", 5400), ("2", 7200), ("2h", 7200),
            ("90m", 5400), ("45 min", 2700), ("2h30", 9000), ("1h 30m", 5400), ("0", 0),
            ("", nil), ("abc", nil), ("-1", nil), ("25", nil), ("1:2:3", nil),
        ]
        for (text, expected) in cases { XCTAssertEqual(DurationParser.seconds(from: text), expected, "\"\(text)\"") }
    }

    func testGridHasDaysTotalsAndAlwaysAProjectRow() throws {
        let (project, list) = try makeProject()
        let monday = Timesheet.weekStart(containing: Date())
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let a = list.addCard(title: "Proposal")
        list.addCard(title: "Idle")
        a.logTime(seconds: 3600, on: monday)
        a.logTime(seconds: 1800, on: tuesday)
        project.logTime(seconds: 7200, on: tuesday, note: "workshop")
        a.logTime(seconds: 9999, on: calendar.date(byAdding: .day, value: 8, to: monday)!)

        let sheet = Timesheet(project: project, weekContaining: tuesday)
        XCTAssertEqual(sheet.days.count, 7)
        XCTAssertEqual(sheet.rows.map(\.title), ["Proposal", TimeReport.noCard], "cards with no time that week are hidden")
        XCTAssertEqual(sheet.rows[0].seconds, [3600, 1800, 0, 0, 0, 0, 0])
        XCTAssertEqual(sheet.columnTotals, [3600, 9000, 0, 0, 0, 0, 0])
        XCTAssertEqual(sheet.grandTotal, 12600)
        XCTAssertEqual(sheet.rows[1].entries[1].map(\.note), ["workshop"])
    }

    func testExtraCardGetsAnEmptyRowAndCanReceiveTime() throws {
        let (project, list) = try makeProject()
        let card = list.addCard(title: "New task")
        let sheet = Timesheet(project: project, weekContaining: Date(), extraCards: [card])
        let row = try XCTUnwrap(sheet.rows.first { $0.title == "New task" })
        XCTAssertEqual(row.total, 0)
        row.addEntry(on: sheet.days[2], seconds: 600, note: "x")
        XCTAssertEqual(Timesheet(project: project, weekContaining: Date()).rows.first?.seconds[2], 600)
    }

    func testProjectRowAddsToTheProject() throws {
        let (project, _) = try makeProject()
        let sheet = Timesheet(project: project, weekContaining: Date())
        sheet.rows.last?.addEntry(on: sheet.days[0], seconds: 3600, note: "admin")
        XCTAssertEqual(project.liveTimeEntries.count, 1)
    }

    func testCSVHasHeaderTaskLinesAndTotals() throws {
        let (project, list) = try makeProject()
        let sheet = Timesheet(project: project, weekContaining: Date())
        list.addCard(title: "Say \"hi\"").logTime(seconds: 5400, on: sheet.days[0])
        let csv = Timesheet(project: project, weekContaining: Date()).csv
        let lines = csv.split(separator: "\n")
        XCTAssertTrue(lines[0].hasPrefix("\"Task\",\""))
        XCTAssertTrue(lines[0].hasSuffix(",\"Total\""))
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[1].hasPrefix("\"Say \"\"hi\"\"\",\"1.50\""))
        XCTAssertTrue(lines[2].hasSuffix(",\"1.50\""))
    }
}
