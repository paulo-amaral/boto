import XCTest
@testable import KanbanCore

final class ColorContrastTests: XCTestCase {
    func testDarkColoursGetLightText() {
        XCTAssertTrue(ColorContrast.prefersLightText(onHex: "#3730a3"))
        XCTAssertTrue(ColorContrast.prefersLightText(onHex: "#000000"))
        XCTAssertTrue(ColorContrast.prefersLightText(onHex: "#1e3a8a"))
    }

    func testLightColoursGetDarkText() {
        XCTAssertFalse(ColorContrast.prefersLightText(onHex: "#f59e0b"))
        XCTAssertFalse(ColorContrast.prefersLightText(onHex: "#ffffff"))
        XCTAssertFalse(ColorContrast.prefersLightText(onHex: "#84cc16"))
    }

    func testAcceptsHashOrNoHashAndFallsBackToLightText() {
        XCTAssertEqual(ColorContrast.prefersLightText(onHex: "f59e0b"), ColorContrast.prefersLightText(onHex: "#f59e0b"))
        XCTAssertTrue(ColorContrast.prefersLightText(onHex: "not a colour"))
    }

    func testEveryPaletteSwatchReachesAtLeast3to1WithItsChosenText() {
        let swatches = ["#ef4444", "#f97316", "#f59e0b", "#84cc16", "#22c55e", "#14b8a6",
                        "#06b6d4", "#3b82f6", "#6366f1", "#8b5cf6", "#ec4899", "#6b7280"]
        for hex in swatches {
            let l = try! XCTUnwrap(ColorContrast.luminance(ofHex: hex))
            let ratio = ColorContrast.prefersLightText(onHex: hex) ? 1.05 / (l + 0.05) : (l + 0.05) / 0.058
            XCTAssertGreaterThanOrEqual(ratio, 3, "\(hex) text contrast is \(ratio)")
        }
    }
}
