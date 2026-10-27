import AppKit
import XCTest
@testable import KanbanUI

@MainActor
final class LucideIconsTests: XCTestCase {
    override func setUp() {
        // Tests run from the package root; the app reads the same file from its Resources folder.
        LucideIcons.dataURL = URL(fileURLWithPath: "Resources/Lucide/icons.json")
    }

    func testTheBundledSetIsLoaded() {
        XCTAssertTrue(LucideIcons.isAvailable)
        XCTAssertNotNil(LucideIcons.version)
        XCTAssertGreaterThan(LucideIcons.names.count, 1500)
    }

    func testSearchFindsByNameAndByTag() {
        XCTAssertTrue(LucideIcons.search("briefcase").contains("briefcase"))
        XCTAssertTrue(LucideIcons.search("work").contains("briefcase"), "briefcase is tagged work")
        XCTAssertTrue(LucideIcons.search("  BRIEFCASE ").contains("briefcase"), "case and spaces do not matter")
        XCTAssertEqual(LucideIcons.search("").count, LucideIcons.names.count)
        XCTAssertTrue(LucideIcons.search("zzzz-no-such-icon").isEmpty)
    }

    func testEveryIconDrawsSomething() {
        for name in LucideIcons.names {
            guard let image = LucideIcons.image(name) else { XCTFail("\(name) did not load"); continue }
            XCTAssertTrue(image.isTemplate, name)
            XCTAssertEqual(image.size.width, 24, name)
        }
    }

    func testAnUnknownNameGivesNoImage() {
        XCTAssertNil(LucideIcons.image("not-an-icon"))
    }
}
