import XCTest
@testable import KanbanUI

final class BoardTierTests: XCTestCase {
    func testTheTierFollowsTheBoardsOwnWidth() {
        XCTAssertEqual(BoardTier(width: 1600), .regular)
        XCTAssertEqual(BoardTier(width: BoardTier.regularMinimum), .regular)
        XCTAssertEqual(BoardTier(width: BoardTier.regularMinimum - 1), .compact)
        XCTAssertEqual(BoardTier(width: BoardTier.compactMinimum), .compact)
        XCTAssertEqual(BoardTier(width: BoardTier.compactMinimum - 1), .narrow)
        XCTAssertEqual(BoardTier(width: 320), .narrow)
    }

    func testTheTiersAreOrderedSoTheyNeverOverlap() {
        XCTAssertLessThan(BoardTier.compactMinimum, BoardTier.regularMinimum)
    }
}
