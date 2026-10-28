import XCTest
@testable import KanbanCore
@testable import KanbanUI

final class ThemeContrastTests: XCTestCase {
    /// background, list, card and card hover: the surfaces status colours sit on.
    private let surfaces = ["#161616", "#1c1c1c", "#232323", "#282828"]

    private func contrast(_ a: String, _ b: String) throws -> Double {
        let la = try XCTUnwrap(ColorContrast.luminance(ofHex: a))
        let lb = try XCTUnwrap(ColorContrast.luminance(ofHex: b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testStatusColoursReadOnEverySurface() throws {
        let status = ["danger": Theme.StatusHex.danger, "warning": Theme.StatusHex.warning,
                      "success": Theme.StatusHex.success, "info": Theme.StatusHex.info]
        for (name, hex) in status {
            for surface in surfaces {
                XCTAssertGreaterThanOrEqual(try contrast(hex, surface), 4.5, "\(name) \(hex) on \(surface)")
            }
        }
    }

    func testLinksReadOnEveryNoteColour() throws {
        for colour in NoteColors.all {
            XCTAssertGreaterThanOrEqual(try contrast(Theme.StatusHex.linkOnLight, colour.hex), 4.5, colour.name)
        }
    }

    func testPrimaryButtonTextReadsOnItsFill() throws {
        XCTAssertGreaterThanOrEqual(try contrast(Theme.StatusHex.onLight, Theme.StatusHex.light), 4.5)
    }
}
