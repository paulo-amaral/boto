import SwiftUI

/// One row of a menu. The same entries feed the custom dropdown panel and the native context menu,
/// so the two can never drift apart.
struct DropdownEntry: Identifiable {
    let id = UUID()
    var icon = ""
    var title = ""
    var destructive = false
    var checked = false
    var isDivider = false
    var action: () -> Void = {}

    static var divider: DropdownEntry { DropdownEntry(isDivider: true) }
}

/// The panel under the board's "..." button: a dark rounded panel with an icon and a label
/// per row. A native macOS menu cannot be styled this way, and it hides icons unless asked.
struct DropdownPanel: View {
    let entries: [DropdownEntry]
    let close: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(entries) { entry in
                if entry.isDivider {
                    Rectangle().fill(Theme.divider).frame(height: 1).padding(.vertical, 4).padding(.horizontal, 4)
                } else {
                    DropdownRow(entry: entry, close: close)
                }
            }
        }
        .padding(6)
        .frame(width: 256)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border.opacity(0.7)))
        .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
    }
}

private struct DropdownRow: View {
    let entry: DropdownEntry
    let close: () -> Void

    var body: some View {
        Button {
            close()
            entry.action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.icon)
                    .font(.system(size: 15))
                    .frame(width: 20)
                    .foregroundStyle(entry.destructive ? Theme.overdue : Theme.muted)
                Text(entry.title).font(Theme.font(14))
                Spacer(minLength: 8)
                if entry.checked { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
            }
            .foregroundStyle(entry.destructive ? Theme.overdue : Theme.mutedStrong)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .rowHighlight()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
