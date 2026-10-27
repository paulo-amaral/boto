import XCTest
@testable import KanbanCore

final class ProjectGroupsTests: XCTestCase {
    private func project(_ name: String, secondsAgo: TimeInterval = 0) -> Project {
        let project = Project(name: name)
        project.createdAt = Date().addingTimeInterval(-secondsAgo)
        return project
    }

    private func names(_ projects: [Project]) -> [String] { projects.map(\.name) }

    func testSplitsFavoritesActiveAndArchived() {
        let a = project("A", secondsAgo: 30)
        let b = project("B", secondsAgo: 20)
        let c = project("C", secondsAgo: 10)
        b.setFavorite(true)
        c.setArchived(true)
        let groups = ProjectGroups([c, a, b])
        XCTAssertEqual(names(groups.favorites), ["B"])
        XCTAssertEqual(names(groups.active), ["A"])
        XCTAssertEqual(names(groups.archived), ["C"])
    }

    func testFavoritesKeepTheOrderTheyWereStarred() {
        let a = project("A")
        let b = project("B")
        b.favoritedAt = Date().addingTimeInterval(-10)
        a.favoritedAt = Date()
        XCTAssertEqual(names(ProjectGroups([a, b]).favorites), ["B", "A"])
    }

    func testArchivedFavouriteIsListedOnlyAsArchived() {
        let a = project("A")
        a.setFavorite(true)
        a.setArchived(true)
        let groups = ProjectGroups([a])
        XCTAssertTrue(groups.favorites.isEmpty)
        XCTAssertEqual(names(groups.archived), ["A"])
    }

    func testDeletedProjectsNeverAppear() {
        let a = project("A")
        a.deletedAt = Date()
        let groups = ProjectGroups([a])
        XCTAssertTrue(groups.favorites.isEmpty && groups.active.isEmpty && groups.archived.isEmpty)
    }

    func testSelectableHidesArchivedUntilRequested() {
        let a = project("A")
        let b = project("B")
        b.setArchived(true)
        let groups = ProjectGroups([a, b])
        XCTAssertEqual(names(groups.selectable(showArchived: false)), ["A"])
        XCTAssertEqual(names(groups.selectable(showArchived: true)), ["A", "B"])
    }

    func testRestoringAndUnstarringIsIdempotent() {
        let a = project("A")
        a.setFavorite(true)
        let first = a.favoritedAt
        a.setFavorite(true)
        XCTAssertEqual(a.favoritedAt, first, "starring twice must keep the original order")
        a.setFavorite(false)
        a.setArchived(true)
        a.setArchived(false)
        XCTAssertFalse(a.isFavorite)
        XCTAssertFalse(a.isArchived)
    }

    func testArchivedProjectsAreNotSearched() {
        let a = project("Acme")
        XCTAssertEqual(Search.results(for: "acme", in: [a]).count, 1)
        a.setArchived(true)
        XCTAssertTrue(Search.results(for: "acme", in: [a]).isEmpty)
    }
}
