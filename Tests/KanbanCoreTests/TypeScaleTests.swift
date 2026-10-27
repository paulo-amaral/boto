import XCTest
@testable import KanbanCore

final class TypeScaleTests: XCTestCase {
    func testStepsAreAscendingAndUnique() {
        XCTAssertEqual(TypeScale.steps, TypeScale.steps.sorted())
        XCTAssertEqual(Set(TypeScale.steps).count, TypeScale.steps.count)
    }

    func testStepsMapToThemselves() {
        for step in TypeScale.steps { XCTAssertEqual(TypeScale.snap(step), step) }
    }

    func testEverySizeUsedTodayLandsOnAStep() {
        let used: [CGFloat] = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 24, 28]
        let expected: [CGFloat] = [11, 11, 11, 12, 13, 14, 16, 16, 16, 20, 20, 20, 20, 26, 26]
        XCTAssertEqual(used.map(TypeScale.snap), expected)
    }

    func testTiesRoundUp() {
        XCTAssertEqual(TypeScale.snap(15), 16)
        XCTAssertEqual(TypeScale.snap(18), 20)
        XCTAssertEqual(TypeScale.snap(23), 26, "23 is 3 from 20 and 3 from 26")
    }

    func testOutOfRangeSizesClampToTheEnds() {
        XCTAssertEqual(TypeScale.snap(1), 11)
        XCTAssertEqual(TypeScale.snap(100), 26)
    }
}
