import Foundation

/// How important a card is. The order of the cases is the order of the lanes when a board is grouped by importance.
public enum Importance: String, CaseIterable, Codable, Sendable {
    case high, medium, low, unset

    public var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        case .unset: "None"
        }
    }

    /// Heading of the lane that holds cards without an importance.
    public var laneTitle: String { self == .unset ? "No importance" : title }
}

public struct ImportanceLane {
    public struct Cell {
        public let list: BoardList
        public let cards: [Card]
    }

    public let importance: Importance
    public let cells: [Cell]

    public var count: Int { cells.reduce(0) { $0 + $1.cards.count } }
}

public enum ImportanceGrouping {
    /// One lane per importance, high first; one cell per list in each lane, so the lists stay the columns.
    /// Cards keep the order they have in their list. Archived cards are hidden unless asked for, and the filter applies.
    public static func lanes(lists: [BoardList], showArchived: Bool, filter: CardFilter) -> [ImportanceLane] {
        Importance.allCases.map { importance in
            ImportanceLane(
                importance: importance,
                cells: lists.map { list in
                    ImportanceLane.Cell(
                        list: list,
                        cards: list.visibleCards(showArchived: showArchived).filter { $0.importance == importance && filter.matches($0) }
                    )
                }
            )
        }
    }
}
