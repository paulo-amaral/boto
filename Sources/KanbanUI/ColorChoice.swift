import AppKit
import SwiftUI

extension Color {
    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(
            format: "#%02x%02x%02x",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}

public enum Palette {
    /// Tailwind 500 shades.
    public static let swatches: [(name: String, hex: String)] = [
        ("Red", "#ef4444"), ("Orange", "#f97316"), ("Amber", "#f59e0b"), ("Lime", "#84cc16"),
        ("Green", "#22c55e"), ("Teal", "#14b8a6"), ("Cyan", "#06b6d4"), ("Blue", "#3b82f6"),
        ("Indigo", "#6366f1"), ("Violet", "#8b5cf6"), ("Pink", "#ec4899"), ("Gray", "#6b7280"),
    ]
}

/// Swatch row with a "none" option and a free colour picker for custom colours.
struct ColorChoice: View {
    @Binding var hex: String?

    var body: some View {
        HStack(spacing: 8) {
            Button { hex = nil } label: {
                Image(systemName: "nosign").foregroundStyle(Theme.muted)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(hex == nil ? Theme.text : .clear, lineWidth: 2).padding(-3))
            }
            .buttonStyle(.plain)
            .help("No colour")

            ForEach(Palette.swatches, id: \.hex) { swatch in
                Button { hex = swatch.hex } label: {
                    Circle().fill(Color(hex: swatch.hex)).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(hex == swatch.hex ? Theme.text : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }

            ColorPicker(
                "Custom colour",
                selection: Binding(get: { Color(hex: hex ?? "#808080") }, set: { hex = $0.hexString }),
                supportsOpacity: false
            )
            .labelsHidden()
        }
    }
}
