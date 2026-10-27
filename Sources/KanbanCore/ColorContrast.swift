import Foundation

/// Picks readable text for a solid colour (a label chip), by WCAG contrast.
public enum ColorContrast {
    /// Relative luminance of "#rrggbb" per WCAG 2.x; nil when the text is not a hex colour.
    static func luminance(ofHex hex: String) -> Double? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else { return nil }
        func channel(_ shift: UInt64) -> Double {
            let c = Double((value >> shift) & 0xff) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// True when white text has more contrast than near-black (#161616, luminance about 0.008) on this colour.
    public static func prefersLightText(onHex hex: String) -> Bool {
        guard let luminance = luminance(ofHex: hex) else { return true }
        let againstWhite = 1.05 / (luminance + 0.05)
        let againstDark = (luminance + 0.05) / 0.058
        return againstWhite >= againstDark
    }
}
