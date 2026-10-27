import KanbanCore
import SwiftData
import SwiftUI

/// Identifies the card shown in a card window. Opening the same card twice brings its window forward.
public struct CardWindowID: Codable, Hashable {
    public var cardId: String

    public init(cardId: String) { self.cardId = cardId }
}

/// A card opens in its own window, not a sheet: a sheet is locked to the main window and cannot be moved,
/// while a window can be dragged aside to keep the board visible, and resized.
public struct CardWindowView: View {
    @Query private var cards: [Card]

    public init(cardId: String) {
        _cards = Query(filter: #Predicate<Card> { $0.publicId == cardId })
    }

    public var body: some View {
        if let card = cards.first, card.deletedAt == nil {
            CardDetailView(card: card)
                .navigationTitle(card.title.isEmpty ? "Card" : card.title)
        } else {
            Text("This card no longer exists.")
                .foregroundStyle(Theme.muted)
                .frame(minWidth: 460, minHeight: 440)
                .background(Theme.background)
        }
    }
}
