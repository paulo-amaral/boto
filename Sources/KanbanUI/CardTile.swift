import AppKit
import KanbanCore
import SwiftUI

/// A card on the board: click opens its window, command-click selects, it can be dragged, and things can be dropped on it.
/// Shared by the list columns and the importance lanes so both behave the same.
struct CardTile: View {
    let card: Card
    @Binding var selection: Set<String>
    /// A card dropped on this one: the list or lane decides where it goes.
    let onMoveHere: (String) -> Void
    @Environment(\.openWindow) private var openWindow
    @State private var targeted = false
    @State private var problem: String?

    var body: some View {
        CardView(card: card, isSelected: selection.contains(card.publicId))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.text.opacity(targeted ? 0.8 : 0), lineWidth: 2))
            .overlay(alignment: .bottom) {
                if let problem {
                    Text(problem)
                        .font(Theme.font(11))
                        .foregroundStyle(Theme.overdue)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.background.opacity(0.95)))
                }
            }
            .onTapGesture {
                // Once a selection exists, plain clicks keep adding to it, like a file list.
                if NSEvent.modifierFlags.contains(.command) || !selection.isEmpty {
                    selection.formSymmetricDifference([card.publicId])
                } else {
                    openWindow(value: CardWindowID(cardId: card.publicId))
                }
            }
            .draggable(card.publicId)
            // A message from Mail dropped on a card is added to that card; a card dropped on it is placed by the list.
            .boardDrop(
                targeted: $targeted,
                problem: $problem,
                moveCard: onMoveHere,
                addEmails: { emails in emails.forEach { card.attach($0) } },
                enrich: { emails in emails.forEach { card.enrich(with: $0, fillDescription: false) } }
            )
    }
}
