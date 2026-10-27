import XCTest
@testable import KanbanCore

final class SearchTests: XCTestCase {
    private func makeProject() -> (Project, BoardList) {
        let project = Project(name: "Acme Consulting")
        let board = project.addBoard(name: "Main")
        return (project, board.orderedLists[0])
    }

    private func describe(_ results: [SearchResult]) -> [String] {
        results.map {
            switch $0 {
            case .project(let project): "P:\(project.name)"
            case .card(let card): "C:\(card.title)"
            }
        }
    }

    func testEmptyQueryReturnsNothing() {
        let (project, list) = makeProject()
        list.addCard(title: "Kickoff")
        XCTAssertTrue(Search.results(for: "  ", in: [project]).isEmpty)
    }

    func testMatchesProjectsAndCardsCaseInsensitively() {
        let (project, list) = makeProject()
        list.addCard(title: "Acme invoice")
        list.addCard(title: "Unrelated")
        XCTAssertEqual(describe(Search.results(for: "ACME", in: [project])), ["P:Acme Consulting", "C:Acme invoice"])
    }

    func testPrefixOutranksContains() {
        let (project, list) = makeProject()
        list.addCard(title: "Review plan")
        list.addCard(title: "Plan review")
        XCTAssertEqual(describe(Search.results(for: "plan", in: [project])), ["C:Plan review", "C:Review plan"])
    }

    func testMatchesDescriptionAndLabelButRanksBelowTitle() {
        let (project, list) = makeProject()
        let byDetails = list.addCard(title: "Alpha")
        byDetails.details = "needs budget approval"
        let byLabel = list.addCard(title: "Beta")
        byLabel.labels = [Label(name: "Budget")]
        list.addCard(title: "Budget sheet")
        XCTAssertEqual(describe(Search.results(for: "budget", in: [project])), ["C:Budget sheet", "C:Alpha", "C:Beta"])
    }

    func testSkipsDeletedCardsListsAndProjects() {
        let (project, list) = makeProject()
        list.addCard(title: "Keep").index = 0
        let gone = list.addCard(title: "Keep gone")
        gone.deletedAt = Date()
        XCTAssertEqual(describe(Search.results(for: "keep", in: [project])), ["C:Keep"])
        project.deletedAt = Date()
        XCTAssertTrue(Search.results(for: "keep", in: [project]).isEmpty)
    }

    func testArchivedCardsAndListsAreNotSearched() {
        let (project, list) = makeProject()
        list.addCard(title: "Visible plan")
        list.addCard(title: "Archived plan").archivedAt = Date()
        let archivedList = project.activeBoards[0].lists[1]
        archivedList.addCard(title: "Hidden plan")
        archivedList.archivedAt = Date()
        XCTAssertEqual(describe(Search.results(for: "plan", in: [project])), ["C:Visible plan"])
    }

    func testLimit() {
        let (project, list) = makeProject()
        for index in 0..<30 { list.addCard(title: "Task \(index)") }
        XCTAssertEqual(Search.results(for: "task", in: [project], limit: 5).count, 5)
    }
}
