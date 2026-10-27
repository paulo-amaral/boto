import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class KaizenTests: XCTestCase {
    private var container: ModelContainer?

    private func makeBoard() throws -> Board {
        let container = try ModelContainer(for: Schema(KanbanSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        self.container = container
        let board = Board(name: "B")
        container.mainContext.insert(board)
        return board
    }

    func testAddingRequiresAProblemAndAnExperiment() throws {
        let board = try makeBoard()
        XCTAssertNil(board.addImprovement(problem: " ", experiment: "x", expected: ""))
        XCTAssertNil(board.addImprovement(problem: "x", experiment: "", expected: ""))
        XCTAssertNotNil(board.addImprovement(problem: " Too much in progress ", experiment: "Limit Doing to 2", expected: "Fewer blocked cards"))
        XCTAssertEqual(board.orderedImprovements.first?.problem, "Too much in progress")
        XCTAssertEqual(board.orderedImprovements.first?.status, .running)
    }

    func testReviewIsDueOnlyWhileRunningAndAfterTheDate() throws {
        let board = try makeBoard()
        let now = Date()
        let item = try XCTUnwrap(board.addImprovement(problem: "p", experiment: "e", expected: "", reviewInDays: 7, from: now))
        XCTAssertFalse(item.isDueForReview(at: now.addingTimeInterval(6 * 86_400)))
        XCTAssertTrue(item.isDueForReview(at: now.addingTimeInterval(8 * 86_400)))
        item.conclude(.adopted, result: "worked", at: now)
        XCTAssertFalse(item.isDueForReview(at: now.addingTimeInterval(8 * 86_400)))
    }

    func testConcludeStoresTheLessonAndCannotBeRepeatedOrRunning() throws {
        let board = try makeBoard()
        let item = try XCTUnwrap(board.addImprovement(problem: "p", experiment: "e", expected: ""))
        item.conclude(.running, result: "nope")
        XCTAssertEqual(item.status, .running)
        item.conclude(.dropped, result: "  no effect  ")
        XCTAssertEqual(item.status, .dropped)
        XCTAssertEqual(item.result, "no effect")
        item.conclude(.adopted, result: "changed my mind")
        XCTAssertEqual(item.status, .dropped)
    }
}
