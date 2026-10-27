import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class DuplicateTests: XCTestCase {
    private var container: ModelContainer?

    private func makeOriginal() throws -> (Project, Board, BoardList, Card) {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let project = Project(name: "Northwind")
        container.mainContext.insert(project)
        project.rootFolderPath = "/Clients/Northwind"
        let board = project.addBoard(name: "Roadmap")
        let doing = board.orderedLists[1]
        doing.setWIPLimit(2)
        doing.setPolicy("Finish before starting")
        let label = Label(name: "Research", colourCode: "#3b82f6")
        board.labels.append(label)
        let card = doing.addCard(title: "Baseline cost analysis")
        card.details = "Compare spend"
        card.dueDate = Date(timeIntervalSince1970: 1_800_000_000)
        card.dueTimeMinutes = 600
        card.colorHex = "#22c55e"
        card.setImportance(.high)
        card.attach(label)
        let checklist = Checklist(name: "Steps", index: 0)
        card.checklists.append(checklist)
        checklist.items.append(ChecklistItem(title: "Export", index: 0, completed: true))
        checklist.items.append(ChecklistItem(title: "Compare", index: 1))
        card.references.append(Reference(kind: .file, displayPath: "/Clients/Northwind/ledger.xlsx"))
        return (project, board, doing, card)
    }

    func testCopyNamesNeverCollide() {
        XCTAssertEqual(Project.copyName(of: "A", among: ["A"]), "A copy")
        XCTAssertEqual(Project.copyName(of: "A", among: ["A", "A copy"]), "A copy 2")
        XCTAssertEqual(Project.copyName(of: "A", among: ["A", "A copy", "A copy 2"]), "A copy 3")
    }

    func testTheCopyHasTheSameStructureAndContent() throws {
        let (project, _, _, _) = try makeOriginal()
        let copy = project.duplicate(named: "Northwind copy", in: try XCTUnwrap(container).mainContext)
        try XCTUnwrap(container).mainContext.save()
        XCTAssertEqual(copy.name, "Northwind copy")
        XCTAssertNotEqual(copy.publicId, project.publicId)
        XCTAssertEqual(copy.rootFolderPath, "/Clients/Northwind")
        let board = try XCTUnwrap(copy.activeBoards.first)
        XCTAssertEqual(board.orderedLists.map(\.name), ["To do", "In progress", "Done"])
        let doing = board.orderedLists[1]
        XCTAssertEqual(doing.wipLimit, 2)
        XCTAssertEqual(doing.policy, "Finish before starting")
        let card = try XCTUnwrap(doing.orderedCards.first)
        XCTAssertEqual(card.title, "Baseline cost analysis")
        XCTAssertEqual(card.details, "Compare spend")
        XCTAssertEqual(card.dueTimeMinutes, 600)
        XCTAssertEqual(card.colorHex, "#22c55e")
        XCTAssertEqual(card.importance, .high)
        // A to-many relationship has no order of its own after a save; the app sorts by `index`, and so does the test.
        let items = try XCTUnwrap(card.checklists.first).items.sorted { $0.index < $1.index }
        XCTAssertEqual(items.map(\.title), ["Export", "Compare"])
        XCTAssertEqual(items.map(\.completed), [true, false])
        XCTAssertEqual(items.map(\.index), [0, 1])
        XCTAssertEqual(card.references.map(\.displayPath), ["/Clients/Northwind/ledger.xlsx"])
    }

    func testTheCopyIsIndependentOfTheOriginal() throws {
        let (project, board, _, card) = try makeOriginal()
        let copy = project.duplicate(named: "Copy", in: try XCTUnwrap(container).mainContext)
        let copyBoard = try XCTUnwrap(copy.activeBoards.first)
        let copyCard = try XCTUnwrap(copyBoard.orderedLists[1].orderedCards.first)

        copyCard.title = "Changed in the copy"
        copyCard.checklists.first?.items.first?.completed = false
        XCTAssertEqual(card.title, "Baseline cost analysis")
        XCTAssertTrue(card.checklists.first?.items.first?.completed ?? false)

        let label = try XCTUnwrap(copyCard.labels.first)
        XCTAssertEqual(label.name, "Research")
        XCTAssertFalse(board.labels.contains { $0 === label }, "labels are copied, not shared between boards")
        XCTAssertTrue(copyBoard.labels.contains { $0 === label })
        XCTAssertEqual(board.labels.first?.cards.count, 1, "the original label still has only the original card")
    }

    func testHistoryAndTheCalendarLinkStayWithTheOriginal() throws {
        let (project, _, _, card) = try makeOriginal()
        card.logTime(seconds: 3600, on: Date())
        project.logTime(seconds: 1800, on: Date())
        card.addComment("Waiting on finance")
        card.calendarEventID = "event-1"
        card.startedAt = Date().addingTimeInterval(-86_400)
        card.finishedAt = Date()

        let copy = project.duplicate(named: "Copy", in: try XCTUnwrap(container).mainContext)
        let copied = try XCTUnwrap(copy.activeBoards.first?.orderedLists[1].orderedCards.first)
        XCTAssertTrue(copy.timeEntries.isEmpty)
        XCTAssertTrue(copied.timeEntries.isEmpty)
        XCTAssertNil(copied.calendarEventID)
        XCTAssertNil(copied.startedAt)
        XCTAssertNil(copied.finishedAt)
        XCTAssertFalse(copied.timeline.contains { $0.kind == .comment }, "comments belong to the original card")
        XCTAssertEqual(card.calendarEventID, "event-1")
        XCTAssertEqual(project.timeEntries.count, 1)
    }

    func testDeletedStaysDeletedAndArchivedStaysArchived() throws {
        let (project, board, list, _) = try makeOriginal()
        let archived = list.addCard(title: "Archived")
        archived.setArchived(true)
        list.addCard(title: "Deleted").deletedAt = Date()
        board.orderedLists[0].deletedAt = Date()
        let extra = project.addBoard(name: "Old board")
        extra.deletedAt = Date()

        let copy = project.duplicate(named: "Copy", in: try XCTUnwrap(container).mainContext)
        XCTAssertEqual(copy.activeBoards.count, 1)
        let copyBoard = try XCTUnwrap(copy.activeBoards.first)
        XCTAssertEqual(copyBoard.orderedLists.map(\.name), ["In progress", "Done"], "a deleted list is not copied")
        let cards = try XCTUnwrap(copyBoard.orderedLists.first).orderedCards
        XCTAssertEqual(cards.map(\.title), ["Baseline cost analysis", "Archived"])
        XCTAssertEqual(cards.map(\.isArchived), [false, true])
    }

    func testOnlyAPickedIconIsKept() throws {
        let (project, _, _, _) = try makeOriginal()
        project.iconName = "briefcase"
        let context = try XCTUnwrap(container).mainContext
        XCTAssertNil(project.duplicate(named: "A", in: context).iconName, "an automatic icon is reassigned")
        project.iconName = ProjectIcons.lucideIcon("rocket")
        XCTAssertEqual(project.duplicate(named: "B", in: context).iconName, "lucide:rocket")
    }

    func testDuplicatingTwiceGivesTwoIndependentCopies() throws {
        let (project, _, _, _) = try makeOriginal()
        let context = try XCTUnwrap(container).mainContext
        let first = project.duplicate(named: "One", in: context)
        let second = project.duplicate(named: "Two", in: context)
        XCTAssertNotEqual(first.publicId, second.publicId)
        first.activeBoards.first?.orderedLists[1].orderedCards.first?.title = "Only the first"
        XCTAssertEqual(second.activeBoards.first?.orderedLists[1].orderedCards.first?.title, "Baseline cost analysis")
    }
}
