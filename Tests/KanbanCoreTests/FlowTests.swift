import SwiftData
import XCTest
@testable import KanbanCore

@MainActor
final class FlowTests: XCTestCase {
    private var container: ModelContainer?
    private let day: TimeInterval = 86_400

    private func makeBoard() throws -> (Board, todo: BoardList, doing: BoardList, done: BoardList) {
        let container = try ModelContainer(
            for: Schema(KanbanSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let board = Board(name: "B")
        container.mainContext.insert(board)
        let lists = ["To do", "Doing", "Done"].enumerated().map { BoardList(name: $1, index: $0) }
        lists.forEach { board.lists.append($0) }
        return (board, lists[0], lists[1], lists[2])
    }

    func testStageIsInferredFromPositionUnlessChosen() throws {
        let (_, todo, doing, done) = try makeBoard()
        XCTAssertEqual([todo.stage, doing.stage, done.stage], [.backlog, .active, .done])
        doing.setStage(.done)
        XCTAssertEqual(doing.stage, .done)
        doing.setStage(nil)
        XCTAssertEqual(doing.stage, .active)
    }

    func testMovingThroughStagesStampsStartAndFinish() throws {
        let (_, todo, doing, done) = try makeBoard()
        let card = todo.addCard(title: "A")
        XCTAssertNil(card.startedAt)

        doing.place(card, at: 0)
        let started = try XCTUnwrap(card.startedAt)
        XCTAssertNil(card.finishedAt)

        done.place(card, at: 0)
        XCTAssertEqual(card.startedAt, started)
        XCTAssertNotNil(card.finishedAt)

        doing.place(card, at: 0)
        XCTAssertNil(card.finishedAt, "leaving a done list reopens the card")

        todo.place(card, at: 0)
        XCTAssertNil(card.startedAt, "going back to not started restarts the clock")
    }

    func testCompletingACardFinishesItAndReopeningClearsOutsideDoneLists() throws {
        let (_, _, doing, _) = try makeBoard()
        let card = doing.addCard(title: "A")
        card.setCompleted(true)
        XCTAssertNotNil(card.finishedAt)
        card.setCompleted(false)
        XCTAssertNil(card.finishedAt)
    }

    func testWIPLimitCountsOnlyVisibleCardsAndZeroMeansNoLimit() throws {
        let (_, _, doing, _) = try makeBoard()
        doing.setWIPLimit(2)
        let a = doing.addCard(title: "A")
        doing.addCard(title: "B")
        XCTAssertFalse(doing.isOverWIPLimit)
        doing.addCard(title: "C")
        XCTAssertTrue(doing.isOverWIPLimit)
        a.setArchived(true)
        XCTAssertFalse(doing.isOverWIPLimit)
        doing.setWIPLimit(0)
        XCTAssertNil(doing.wipLimit)
    }

    func testBlockAndUnblockRecordEventsAndAreIdempotent() throws {
        let (_, todo, _, _) = try makeBoard()
        let card = todo.addCard(title: "A")
        card.block(reason: "  waiting for legal  ")
        card.block(reason: "again")
        XCTAssertTrue(card.isBlocked)
        XCTAssertEqual(card.blockedReason, "waiting for legal")
        card.unblock()
        card.unblock()
        XCTAssertFalse(card.isBlocked)
        XCTAssertEqual(card.timeline.map(\.kind), [.created, .blocked, .unblocked])
    }

    func testPercentileUsesNearestRank() {
        let sorted = [1.0, 2, 3, 4, 5, 6, 7, 8, 9, 10]
        XCTAssertEqual(FlowMetrics.percentile(85, of: sorted), 9)
        XCTAssertEqual(FlowMetrics.percentile(50, of: sorted), 5)
        XCTAssertNil(FlowMetrics.percentile(85, of: []))
    }

    func testMetricsCycleTimeThroughputAgeAndSLE() throws {
        let (board, todo, doing, done) = try makeBoard()
        let now = Date()
        let finishedCard = todo.addCard(title: "Finished")
        done.place(finishedCard, at: 0)
        finishedCard.startedAt = now.addingTimeInterval(-4 * day)
        finishedCard.finishedAt = now.addingTimeInterval(-1 * day)

        let old = doing.addCard(title: "Old")
        old.startedAt = now.addingTimeInterval(-10 * day)
        let fresh = doing.addCard(title: "Fresh")
        fresh.startedAt = now.addingTimeInterval(-1 * day)
        let imported = doing.addCard(title: "Imported")
        imported.startedAt = nil

        let metrics = FlowMetrics(board: board, now: now)
        XCTAssertEqual(metrics.wip, 3)
        XCTAssertEqual(try XCTUnwrap(metrics.averageCycleDays), 3, accuracy: 0.01)
        XCTAssertEqual(metrics.sleDays, 3)
        XCTAssertEqual(metrics.throughput.count, 8)
        XCTAssertEqual(metrics.throughput.reduce(0) { $0 + $1.count }, 1)
        XCTAssertEqual(metrics.aging.map(\.card.title), ["Old", "Fresh"], "cards without a start are left out")
        XCTAssertEqual(metrics.aging.map(\.exceedsSLE), [true, false])
    }

    func testCumulativeFlowEndsWithCurrentCounts() throws {
        let (board, todo, doing, done) = try makeBoard()
        todo.addCard(title: "Waiting")
        doing.addCard(title: "Working")
        let finished = doing.addCard(title: "Finished")
        done.place(finished, at: 0)

        let last = try XCTUnwrap(FlowMetrics(board: board, flowDays: 5).cumulativeFlow.last)
        XCTAssertEqual([last.notStarted, last.inProgress, last.done], [1, 1, 1])
    }

    func testBlockedAndOverLimitAreListed() throws {
        let (board, _, doing, _) = try makeBoard()
        doing.setWIPLimit(1)
        doing.addCard(title: "A").block(reason: "")
        doing.addCard(title: "B")
        let metrics = FlowMetrics(board: board)
        XCTAssertEqual(metrics.blocked.map(\.title), ["A"])
        XCTAssertEqual(metrics.overLimitLists.map(\.name), ["Doing"])
    }
}
