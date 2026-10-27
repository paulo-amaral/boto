import KanbanCore
import SwiftUI

struct PasteCardsSheet: View {
    let list: BoardList
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var count: Int { PlainTextCards.titles(in: text).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create cards from text").font(Theme.font(15, weight: .semibold))
            Text("One card per line. Bullets, numbers and checkboxes are removed.")
                .font(Theme.font(11)).foregroundStyle(Theme.muted)
            TextEditor(text: $text)
                .font(Theme.font(13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(height: 220)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
            HStack {
                Text("\(count) card\(count == 1 ? "" : "s") in \"\(list.name)\"")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { list.addCards(fromText: text); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
            }
        }
        .padding(22)
        .frame(width: 460)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

/// Appears while cards are selected (⌘-click). Moves keep the order the cards have on the board.
struct BulkActionBar: View {
    let cards: [Card]
    let lists: [BoardList]
    let onClear: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            Text("\(cards.count) selected").font(Theme.font(13, weight: .semibold))
            Menu("Move to") {
                ForEach(lists) { list in
                    Button(list.name) { list.place(cards, at: list.orderedCards.count); onClear() }
                }
            }
            .fixedSize()
            Menu("Colour") {
                Button("None") { cards.forEach { $0.colorHex = nil } }
                ForEach(Palette.swatches, id: \.hex) { swatch in
                    Button(swatch.name) { cards.forEach { $0.colorHex = swatch.hex } }
                }
            }
            .fixedSize()
            Button(cards.allSatisfy(\.isArchived) ? "Restore" : "Archive") {
                let archive = !cards.allSatisfy(\.isArchived)
                cards.forEach { $0.setArchived(archive) }
                onClear()
            }
            Button("Delete", role: .destructive) { confirmingDelete = true }
            Button("Clear", action: onClear).keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(Theme.text)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.list))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .confirmationDialog("Delete \(cards.count) card\(cards.count == 1 ? "" : "s")?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                cards.forEach { $0.deletedAt = Date() }
                onClear()
            }
        } message: {
            Text("The cards disappear from the board. Linked files are not touched.")
        }
    }
}
