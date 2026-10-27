import KanbanCore
import SwiftUI

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: digits).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }
}

/// Dark palette (dark-50 ... dark-1000).
public enum Theme {
    public static let background = Color(hex: "#161616")
    public static let list = Color(hex: "#1c1c1c")
    public static let card = Color(hex: "#232323")
    public static let cardHover = Color(hex: "#282828")
    public static let border = Color(hex: "#3e3e3e")
    public static let divider = Color(hex: "#2e2e2e")
    /// 4.5:1 or better on list, card and hover surfaces (checked).
    public static let muted = Color(hex: "#8e8e8e")
    public static let mutedStrong = Color(hex: "#bbbbbb")
    public static let text = Color(hex: "#ededed")
    public static let defaultLabel = "#3730a3"
    public static let overdue = Color(red: 0.97, green: 0.44, blue: 0.44)

    /// Status colours as hex, so a test can check each against every surface (4.5:1 or better).
    enum StatusHex {
        static let danger = "#f87168"
        static let warning = "#f5cd47"
        static let success = "#4bce97"
        /// One blue for progress, a running timer and links, so the same meaning never has two shades.
        static let info = "#579dff"
        /// Fill and text of the white primary button and of text on light label colours.
        static let onLight = "#161616"
        static let light = "#ffffff"
    }
    public static let danger = Color(hex: StatusHex.danger)
    public static let warning = Color(hex: StatusHex.warning)
    public static let success = Color(hex: StatusHex.success)
    public static let info = Color(hex: StatusHex.info)
    public static let onLight = Color(hex: StatusHex.onLight)
    public static let light = Color(hex: StatusHex.light)

    /// Same hues as the board's other status colours: red, gold and blue read on every surface.
    public static func importanceColor(_ importance: Importance) -> Color {
        switch importance {
        case .high: danger
        case .medium: warning
        case .low: info
        case .unset: muted
        }
    }

    public static let cornerRadius: CGFloat = 6
    public static let listWidth: CGFloat = 288
    public static let compactListWidth: CGFloat = 256
    /// Below this window width the layout switches to its compact form.
    public static let compactBreakpoint: CGFloat = 900
    /// Below this window width the kanban columns stack into one vertical list.
    public static let stackBreakpoint: CGFloat = 700

    static let fontFamily = "Plus Jakarta Sans"

    /// Registers the bundled font (SIL Open Font License, see Resources/Fonts/OFL.txt). Run from the app's init.
    /// Outside the .app, as in tests, there is nothing to register and SwiftUI falls back to the system font.
    public static func registerFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        files.filter { $0.pathExtension == "ttf" }.forEach { CTFontManagerRegisterFontsForURL($0 as CFURL, .process, nil) }
    }

    /// Single place to swap the UI font. Sizes snap to `TypeScale`; Plus Jakarta Sans is a variable font, so every
    /// weight is real, including semibold at small sizes.
    public static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(fontFamily, size: TypeScale.snap(size)).weight(weight)
    }
}
