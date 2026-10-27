import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class ImportTests: XCTestCase {
    private var container: ModelContainer?

    private let trello = """
    {
      "name": "Client roadmap",
      "labels": [{"id":"l1","name":"Urgent","color":"red"}],
      "lists": [
        {"id":"A","name":"Doing","closed":false,"pos":2},
        {"id":"B","name":"Backlog","closed":false,"pos":1},
        {"id":"C","name":"Old","closed":true,"pos":3}
      ],
      "cards": [
        {"id":"c1","name":"Second","desc":"details","idList":"B","closed":false,"pos":20,
         "due":"2026-11-01T12:30:00.000Z","labels":[{"name":"Urgent","color":"red"},{"name":"","color":"blue"}]},
        {"id":"c2","name":"First","desc":"","idList":"B","closed":false,"pos":10,"labels":[{"name":"Urgent","color":"red"}]},
        {"id":"c3","name":"Archived card","idList":"B","closed":true,"pos":5},
        {"id":"c4","name":"In old list","idList":"C","closed":false,"pos":1},
        {"id":"c5","name":null,"idList":"A","pos":1}
      ],
      "checklists": [
        {"idCard":"c1","name":"Steps","pos":1,"checkItems":[
          {"name":"b","state":"incomplete","pos":2},{"name":"a","state":"complete","pos":1}]}
      ]
    }
    """

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    func testTrelloListsAndCardsAreOrderedByPosAndClosedOnesDropped() throws {
        let board = try TrelloImporter.parse(Data(trello.utf8))
        XCTAssertEqual(board.name, "Client roadmap")
        XCTAssertEqual(board.lists.map(\.name), ["Backlog", "Doing"])
        XCTAssertEqual(board.lists[0].cards.map(\.title), ["First", "Second"])
        XCTAssertEqual(board.lists[1].cards.map(\.title), ["Untitled"])
        XCTAssertEqual(board.cardCount, 3)
    }

    func testTrelloLabelsDatesAndChecklists() throws {
        let card = try TrelloImporter.parse(Data(trello.utf8)).lists[0].cards[1]
        XCTAssertEqual(card.details, "details")
        XCTAssertEqual(card.labels, [ImportedBoard.Label(name: "Urgent", colour: "#f87168")])
        XCTAssertEqual(card.due, ISO8601DateFormatter().date(from: "2026-11-01T12:30:00Z"))
        XCTAssertEqual(card.checklists.count, 1)
        XCTAssertEqual(card.checklists[0].items.map(\.title), ["a", "b"])
        XCTAssertEqual(card.checklists[0].items.map(\.done), [true, false])
    }

    func testTrelloIncludeArchivedKeepsClosedListsAndCardsFlagged() throws {
        let board = try TrelloImporter.parse(Data(trello.utf8), includeArchived: true)
        XCTAssertEqual(board.lists.map(\.name), ["Backlog", "Doing", "Old"])
        XCTAssertEqual(board.lists.map(\.archived), [false, false, true])
        // Ordered by Trello's pos: the archived card has pos 5, before First (10) and Second (20).
        XCTAssertEqual(board.lists[0].cards.map(\.title), ["Archived card", "First", "Second"])
        XCTAssertEqual(board.lists[0].cards.map(\.archived), [true, false, false])
        XCTAssertEqual(board.cardCount, 5)
    }

    func testImportedArchivedItemsAreHiddenUntilShown() throws {
        let context = try makeContext()
        let project = Project(name: "Client")
        context.insert(project)
        let board = project.addBoard(from: try TrelloImporter.parse(Data(trello.utf8), includeArchived: true))

        XCTAssertEqual(board.visibleLists(showArchived: false).map(\.name), ["Backlog", "Doing"])
        XCTAssertEqual(board.visibleLists(showArchived: true).map(\.name), ["Backlog", "Doing", "Old"])
        let backlog = board.orderedLists[0]
        XCTAssertEqual(backlog.visibleCards(showArchived: false).map(\.title), ["First", "Second"])
        XCTAssertEqual(backlog.visibleCards(showArchived: true).count, 3)
    }

    func testTrelloColourFallbacks() {
        XCTAssertEqual(TrelloImporter.colour(for: nil), "#8590a2")
        XCTAssertEqual(TrelloImporter.colour(for: "blue_dark"), "#0c66e4")
        XCTAssertEqual(TrelloImporter.colour(for: "unheard_of"), "#0d9488")
    }

    func testRejectsFilesThatAreNotTrelloBoards() {
        for text in ["not json", "[]", #"{"name":"x"}"#, #"{"lists":[]}"#] {
            XCTAssertThrowsError(try TrelloImporter.parse(Data(text.utf8)), text)
        }
    }

    func testToleratesMissingOptionalFields() throws {
        let board = try TrelloImporter.parse(Data(#"{"lists":[{"id":"1"}],"cards":[{"id":"x","idList":"1"}]}"#.utf8))
        XCTAssertEqual(board.name, "Trello board")
        XCTAssertEqual(board.lists[0].name, "Untitled list")
        XCTAssertEqual(board.lists[0].cards.map(\.title), ["Untitled"])
    }

    func testAddBoardBuildsModelsAndSharesLabels() throws {
        let context = try makeContext()
        let project = Project(name: "Client")
        context.insert(project)
        let imported = try TrelloImporter.parse(Data(trello.utf8))
        let board = project.addBoard(from: imported)

        XCTAssertEqual(board.orderedLists.map(\.name), ["Backlog", "Doing"])
        let cards = board.orderedLists[0].orderedCards
        XCTAssertEqual(cards.map(\.title), ["First", "Second"])
        XCTAssertEqual(board.labels.count, 1, "the same label on two cards must be one Label")
        XCTAssertTrue(cards[0].labels[0] === cards[1].labels[0])
        XCTAssertEqual(cards[1].checklistProgress.done, 1)
        XCTAssertEqual(cards[1].checklistProgress.total, 2)
        XCTAssertEqual(project.activeBoards.count, 1)
    }

    func testAddBoardLinksGitHubIssues() throws {
        let context = try makeContext()
        let project = Project(name: "Repo")
        context.insert(project)
        let item = GitHubItem(kind: .issue, title: "Fix", state: "open", url: URL(string: "https://github.com/acme/app/issues/1")!)
        let imported = ImportedBoard(name: "acme/app", lists: [
            ImportedBoard.List(name: "Open", cards: [ImportedBoard.Card(title: "Fix", githubItem: item)])
        ])
        let card = project.addBoard(from: imported).orderedLists[0].orderedCards[0]
        XCTAssertEqual(card.references.count, 1)
        XCTAssertEqual(card.references[0].kind, .githubIssue)
        XCTAssertEqual(card.references[0].remoteState, "open")
    }
}
