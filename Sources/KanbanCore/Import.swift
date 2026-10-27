import Foundation

/// Source-neutral shape both importers produce, so Trello and GitHub share one code path into the models.
public struct ImportedBoard {
    public struct Label: Hashable {
        public var name: String
        public var colour: String?
    }

    public struct Checklist {
        public var name: String
        public var items: [(title: String, done: Bool)]
    }

    public struct Card {
        public var title: String
        public var details: String = ""
        public var due: Date?
        public var labels: [Label] = []
        public var checklists: [Checklist] = []
        public var githubItem: GitHubItem?
        public var archived = false
    }

    public struct List {
        public var name: String
        public var cards: [Card]
        public var archived = false
    }

    public var name: String
    public var lists: [List]

    public var cardCount: Int { lists.reduce(0) { $0 + $1.cards.count } }
}

extension Project {
    /// Adds the imported lists, cards, labels and checklists as a new board. Labels are shared per board by name and colour.
    @discardableResult
    public func addBoard(from imported: ImportedBoard) -> Board {
        let board = Board(name: imported.name)
        boards.append(board)

        var labels: [ImportedBoard.Label: Label] = [:]
        func label(for key: ImportedBoard.Label) -> Label {
            if let existing = labels[key] { return existing }
            let created = Label(name: key.name, colourCode: key.colour)
            board.labels.append(created)
            labels[key] = created
            return created
        }

        for (listIndex, importedList) in imported.lists.enumerated() {
            let list = BoardList(name: importedList.name, index: listIndex)
            list.archivedAt = importedList.archived ? Date() : nil
            board.lists.append(list)
            for importedCard in importedList.cards {
                let card = list.addCard(title: importedCard.title)
                card.details = importedCard.details
                card.dueDate = importedCard.due
                card.archivedAt = importedCard.archived ? Date() : nil
                // Imported work has no real history here; stamping it "started and finished now" would fake the metrics.
                card.startedAt = nil
                card.finishedAt = nil
                card.labels = importedCard.labels.map(label(for:))
                for (checklistIndex, importedChecklist) in importedCard.checklists.enumerated() {
                    let checklist = Checklist(name: importedChecklist.name, index: checklistIndex)
                    card.checklists.append(checklist)
                    for (itemIndex, item) in importedChecklist.items.enumerated() {
                        checklist.items.append(ChecklistItem(title: item.title, index: itemIndex, completed: item.done))
                    }
                }
                if let item = importedCard.githubItem { card.references.append(Reference.make(item: item)) }
            }
        }
        return board
    }
}
