import SwiftUI

/// Dot grid: 14.42 pt pitch, 0.45 pt radius, #3e3e3e, origin (10, 10).
struct PatternedBackground: View {
    var body: some View {
        Canvas { context, size in
            let pitch = 14.423223834988539
            let radius = 0.45072574484339184
            var dots = Path()
            var y = 10.0
            while y < size.height {
                var x = 10.0
                while x < size.width {
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    x += pitch
                }
                y += pitch
            }
            context.fill(dots, with: .color(Theme.border))
        }
        .allowsHitTesting(false)
    }
}

/// Lets the window be dragged from its background, not only from the title bar. Controls and cards still take their
/// own clicks and drags; only empty space moves the window.
struct MovableByBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.isMovableByWindowBackground = true }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// Lays its children out left to right and wraps to a new row when the width runs out (buttons, label chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// How much room the board has. Regular shows every button with its text and lists at full width; compact drops the
/// text and narrows the lists; narrow turns the lists into one column and moves the secondary buttons into the menu.
enum BoardTier: Equatable {
    case regular, compact, narrow

    /// The widest toolbar (every label) plus a title and the margins needs about 1,040 points; the icon-only toolbar
    /// plus a title fits down to about 600.
    static let regularMinimum: CGFloat = 1040
    static let compactMinimum: CGFloat = 600

    init(width: CGFloat) {
        self = width >= Self.regularMinimum ? .regular : (width >= Self.compactMinimum ? .compact : .narrow)
    }
}

/// True when the window is narrow: the sidebar folds away, toolbars drop their text and lists get narrower.
private struct CompactWindowKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var isCompactWindow: Bool {
        get { self[CompactWindowKey.self] }
        set { self[CompactWindowKey.self] = newValue }
    }
}

/// True when the window is so narrow that kanban columns turn into a vertical list.
private struct StacksBoardKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var stacksBoard: Bool {
        get { self[StacksBoardKey.self] }
        set { self[StacksBoardKey.self] = newValue }
    }
}

/// Hover and selected states for rows and sidebar buttons: one vocabulary everywhere.
private struct HoverHighlight: ViewModifier {
    let selected: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(selected ? Theme.card : (hovering ? Theme.card.opacity(0.6) : .clear)))
            .onHover { hovering = $0 }
    }
}

extension View {
    func rowHighlight(selected: Bool = false) -> some View { modifier(HoverHighlight(selected: selected)) }
}

/// Header buttons: white primary ("New list") and bordered secondary ("Filter").
struct ToolbarButtonStyle: ButtonStyle {
    let primary: Bool
    /// A toggle that is switched on gets a lighter outline.
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(13, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(primary ? Theme.onLight : Theme.text)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(primary ? Theme.light : Theme.background))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(primary ? .clear : (active ? Theme.mutedStrong : Theme.card)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
