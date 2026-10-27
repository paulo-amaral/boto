import Foundation

/// Reads a Trello board as returned by the Trello REST API (the shape Kan's importer uses).
/// Every field is optional so a missing key never aborts the import. Whether the file produced by Trello's
/// "Export as JSON" has exactly these keys is not confirmed by the documentation I read; check with a real export.
public enum TrelloImporter {
    public enum ImportError: LocalizedError {
        case notATrelloBoard

        public var errorDescription: String? { "This file does not look like a Trello board export." }
    }

    // Colour names from Kan's `packages/api/src/utils/trello.ts`.
    private static let colours: [String: String] = [
        "green": "#4bce97", "yellow": "#f5cd47", "orange": "#fea362", "red": "#f87168", "purple": "#9f8fef",
        "blue": "#579dff", "sky": "#6cc3e0", "lime": "#94c748", "pink": "#e774bb", "black": "#8590a2",
        "green_dark": "#1f845a", "yellow_dark": "#946f00", "orange_dark": "#c25100", "red_dark": "#c9372c",
        "purple_dark": "#6e5dc6", "blue_dark": "#0c66e4", "sky_dark": "#227d9b", "lime_dark": "#5b7f24",
        "pink_dark": "#ae4787", "black_dark": "#626f86",
        "green_light": "#baf3db", "yellow_light": "#f8e6a0", "orange_light": "#fedec8", "red_light": "#ffd5d2",
        "purple_light": "#dfd8fd", "blue_light": "#cce0ff", "sky_light": "#c6edfb", "lime_light": "#d3f1a7",
        "pink_light": "#fdd0ec", "black_light": "#dcdfe4",
    ]
    private static let colourless = "#8590a2"
    private static let unknownColour = "#0d9488"

    static func colour(for name: String?) -> String {
        guard let name, !name.isEmpty else { return colourless }
        return colours[name] ?? unknownColour
    }

    private struct Board: Decodable {
        var name: String?
        var lists: [List]?
        var cards: [Card]?
        var labels: [Label]?
        var checklists: [Checklist]?
    }
    private struct List: Decodable { var id: String; var name: String?; var closed: Bool?; var pos: Double? }
    private struct Label: Decodable { var id: String?; var name: String?; var color: String? }
    private struct Card: Decodable {
        var id: String
        var name: String?
        var desc: String?
        var idList: String?
        var closed: Bool?
        var due: String?
        var pos: Double?
        var labels: [Label]?
    }
    private struct Checklist: Decodable { var idCard: String?; var name: String?; var pos: Double?; var checkItems: [CheckItem]? }
    private struct CheckItem: Decodable { var name: String?; var state: String?; var pos: Double? }

    /// Trello calls archived items "closed". They are dropped unless `includeArchived`, in which case they come in archived.
    public static func parse(_ data: Data, includeArchived: Bool = false) throws -> ImportedBoard {
        guard let board = try? JSONDecoder().decode(Board.self, from: data), board.lists != nil, board.cards != nil else {
            throw ImportError.notATrelloBoard
        }
        let checklists = Dictionary(grouping: board.checklists ?? [], by: { $0.idCard ?? "" })

        let lists = (board.lists ?? []).enumerated()
            .filter { includeArchived || $0.element.closed != true }
            .sorted { ($0.element.pos ?? Double($0.offset)) < ($1.element.pos ?? Double($1.offset)) }
            .map { listEntry -> ImportedBoard.List in
                let cards = (board.cards ?? []).enumerated()
                    .filter { $0.element.idList == listEntry.element.id && (includeArchived || $0.element.closed != true) }
                    .sorted { ($0.element.pos ?? Double($0.offset)) < ($1.element.pos ?? Double($1.offset)) }
                    .map { importedCard($0.element, checklists: checklists[$0.element.id] ?? []) }
                return ImportedBoard.List(
                    name: listEntry.element.name ?? "Untitled list", cards: cards, archived: listEntry.element.closed == true
                )
            }
        return ImportedBoard(name: board.name ?? "Trello board", lists: lists)
    }

    private static func importedCard(_ card: Card, checklists: [Checklist]) -> ImportedBoard.Card {
        ImportedBoard.Card(
            title: card.name ?? "Untitled",
            details: card.desc ?? "",
            due: card.due.flatMap(parseDate),
            labels: (card.labels ?? []).compactMap { label in
                // Same rule as Kan's importer: labels without a name are dropped.
                guard let name = label.name, !name.isEmpty else { return nil }
                return ImportedBoard.Label(name: name, colour: colour(for: label.color))
            },
            checklists: checklists.sorted { ($0.pos ?? 0) < ($1.pos ?? 0) }.map { checklist in
                ImportedBoard.Checklist(
                    name: checklist.name ?? "Checklist",
                    items: (checklist.checkItems ?? []).sorted { ($0.pos ?? 0) < ($1.pos ?? 0) }
                        .map { ($0.name ?? "", $0.state == "complete") }
                )
            },
            archived: card.closed == true
        )
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
