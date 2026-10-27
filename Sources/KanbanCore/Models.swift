import Foundation
import SwiftData

/// Short stable id, same idea as the 12-char `publicId` columns in Kan's schema.
/// Stays constant across sync snapshots, unlike SwiftData's persistent identifier.
func makePublicId() -> String {
    String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
}

public enum KanbanSchema {
    public static let models: [any PersistentModel.Type] = [
        Project.self, Board.self, BoardList.self, Card.self,
        Label.self, Checklist.self, ChecklistItem.self, Reference.self, CardEvent.self,
    ]
}

@Model
public final class Project {
    @Attribute(.unique) public var publicId: String
    public var name: String
    /// The database only stores pointers: files stay where they are.
    public var rootFolderPath: String?
    public var rootFolderBookmark: Data?
    public var createdAt: Date
    public var deletedAt: Date?
    public var archivedAt: Date?
    /// Set when starred; also orders the favourites.
    public var favoritedAt: Date?
    /// SF Symbol name; nil means the default icon.
    public var iconName: String?
    @Relationship(deleteRule: .cascade, inverse: \Board.project) public var boards: [Board] = []
    /// Time logged on the project itself, for work that has no card.
    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.project) public var timeEntries: [TimeEntry] = []

    public init(name: String) {
        self.publicId = makePublicId()
        self.name = name
        self.createdAt = Date()
    }

    /// Bookmark first, so the root is still found after the folder is moved or renamed.
    public var rootFolderURL: URL? {
        if let rootFolderBookmark {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: rootFolderBookmark, bookmarkDataIsStale: &isStale),
               FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return rootFolderPath.map { URL(fileURLWithPath: $0) }
    }

    public var isArchived: Bool { archivedAt != nil }
    public var isFavorite: Bool { favoritedAt != nil }

    public var icon: String { iconName ?? ProjectIcons.default }

    public func setArchived(_ archived: Bool) {
        archivedAt = archived ? (archivedAt ?? Date()) : nil
    }

    public func setFavorite(_ favorite: Bool) {
        favoritedAt = favorite ? (favoritedAt ?? Date()) : nil
    }

    public var activeBoards: [Board] {
        boards.filter { $0.deletedAt == nil }.sorted { $0.createdAt < $1.createdAt }
    }

    public func setRootFolder(_ url: URL?) {
        rootFolderPath = url?.path
        rootFolderBookmark = url.flatMap { try? $0.bookmarkData() }
    }

    @discardableResult
    public func addBoard(name: String, listNames: [String] = ["To do", "In progress", "Done"]) -> Board {
        let board = Board(name: name)
        boards.append(board)
        for (index, listName) in listNames.enumerated() {
            board.lists.append(BoardList(name: listName, index: index))
        }
        return board
    }
}

@Model
public final class Board {
    @Attribute(.unique) public var publicId: String
    public var name: String
    public var createdAt: Date
    public var deletedAt: Date?
    public var project: Project?
    @Relationship(deleteRule: .cascade, inverse: \BoardList.board) public var lists: [BoardList] = []
    @Relationship(deleteRule: .cascade, inverse: \Label.board) public var labels: [Label] = []
    @Relationship(deleteRule: .cascade, inverse: \Improvement.board) public var improvements: [Improvement] = []

    public init(name: String) {
        self.publicId = makePublicId()
        self.name = name
        self.createdAt = Date()
    }

    public var orderedLists: [BoardList] {
        lists.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index }
    }

    public func visibleLists(showArchived: Bool) -> [BoardList] {
        orderedLists.filter { showArchived || !$0.isArchived }
    }
}

@Model
public final class BoardList {
    @Attribute(.unique) public var publicId: String
    public var name: String
    public var index: Int
    public var deletedAt: Date?
    /// Archived is not deleted: hidden by default, restorable, and kept out of search.
    public var archivedAt: Date?
    public var board: Board?
    /// `ListStage` raw value; nil means "infer from position" (see Flow.swift).
    public var stageRaw: String?
    /// Soft work-in-progress limit: going over it is allowed but shown, since Kanban asks that exceeding it be explicit.
    public var wipLimit: Int?
    /// The list's explicit policy, e.g. its definition of done.
    public var policy: String?
    @Relationship(deleteRule: .cascade, inverse: \Card.list) public var cards: [Card] = []

    public init(name: String, index: Int, board: Board? = nil) {
        self.publicId = makePublicId()
        self.name = name
        self.index = index
        self.board = board
    }

    public var isArchived: Bool { archivedAt != nil }

    /// Every card that is not deleted, archived ones included. Ordering operations use this so indexes stay consistent.
    public var orderedCards: [Card] {
        cards.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index }
    }

    public func visibleCards(showArchived: Bool) -> [Card] {
        orderedCards.filter { showArchived || !$0.isArchived }
    }

    /// Puts `card` at `position` in this list (moving it from another list if needed)
    /// and renumbers the list. Gaps left in the source list are harmless: order is by `index`.
    public func place(_ card: Card, at position: Int) {
        place([card], at: position)
    }

    /// Several cards at once, keeping their given order.
    public func place(_ moving: [Card], at position: Int) {
        var ordered = orderedCards.filter { existing in !moving.contains { $0 === existing } }
        ordered.insert(contentsOf: moving, at: min(max(position, 0), ordered.count))
        for card in moving {
            if let origin = card.list, origin !== self { card.record(.moved, "\(origin.name) → \(name)") }
            card.list = self
            card.enter(self)
        }
        for (offset, item) in ordered.enumerated() { item.index = offset }
    }

    @discardableResult
    public func addCard(title: String) -> Card {
        let card = Card(title: title, index: orderedCards.count)
        card.list = self
        card.record(.created, name)
        card.enter(self)
        return card
    }

    /// A card for a message: the subject is the title; sender, date and the start of the text go in the description,
    /// and the message is linked as "From email".
    @discardableResult
    public func addCard(fromEmail email: ParsedEmail) -> Card {
        let card = addCard(title: email.subject)
        card.details = email.descriptionText
        card.attach(email)
        return card
    }

    /// One card per non-empty line; bullets, numbers and checkboxes are stripped (see `PlainTextCards`).
    @discardableResult
    public func addCards(fromText text: String) -> [Card] {
        PlainTextCards.titles(in: text).map { addCard(title: $0) }
    }
}

@Model
public final class Card {
    @Attribute(.unique) public var publicId: String
    public var title: String
    public var details: String
    public var index: Int
    public var dueDate: Date?
    /// Optional whole-card colour (Kanbana-style), as "#rrggbb".
    public var colorHex: String?
    public var createdAt: Date
    public var deletedAt: Date?
    public var archivedAt: Date?
    /// The round checkbox next to a card's title, as in Trello. Independent of which list the card is in.
    public var completedAt: Date?
    /// `Importance` raw value; nil means unset. Optional so existing databases migrate without a default.
    public var importanceRaw: String?
    /// Flow timestamps, kept by the stage of the list the card is in (see `Card.enter`). Cycle time is finished minus started.
    public var startedAt: Date?
    public var finishedAt: Date?
    /// Set while the card cannot move forward; cleared by `unblock()`.
    public var blockedAt: Date?
    public var blockedReason: String?
    /// EventKit identifier of the card's event in the "Boto" calendar; nil when the card is not on the calendar.
    public var calendarEventID: String?
    /// Minutes after midnight of the due day for a timed calendar event; nil makes it an all-day event.
    public var dueTimeMinutes: Int?
    /// Minutes before the event to alert; nil means at the event, `Card.noAlert` means no alert.
    public var alertLeadMinutes: Int?
    public var list: BoardList?
    @Relationship(inverse: \Label.cards) public var labels: [Label] = []
    @Relationship(deleteRule: .cascade, inverse: \Checklist.card) public var checklists: [Checklist] = []
    @Relationship(deleteRule: .cascade, inverse: \Reference.card) public var references: [Reference] = []
    @Relationship(deleteRule: .cascade, inverse: \CardEvent.card) public var events: [CardEvent] = []
    @Relationship(deleteRule: .cascade, inverse: \TimeEntry.card) public var timeEntries: [TimeEntry] = []

    public init(title: String, index: Int, details: String = "") {
        self.publicId = makePublicId()
        self.title = title
        self.details = details
        self.index = index
        self.createdAt = Date()
    }

    public var isArchived: Bool { archivedAt != nil }

    /// Oldest first. Ordered by a per-card counter, since two events can share a timestamp.
    public var timeline: [CardEvent] { events.sorted { $0.index < $1.index } }

    public func record(_ kind: CardEventKind, _ text: String = "") {
        events.append(CardEvent(kind: kind, text: text, index: events.count))
    }

    public func setArchived(_ archived: Bool) {
        guard archived != isArchived else { return }
        archivedAt = archived ? Date() : nil
        record(archived ? .archived : .restored)
        dropCalendarEventIfClosed()
    }

    public var importance: Importance { importanceRaw.flatMap(Importance.init(rawValue:)) ?? .unset }

    public func setImportance(_ value: Importance) {
        guard value != importance else { return }
        importanceRaw = value == .unset ? nil : value.rawValue
        record(.importanceChanged, value.title)
    }

    public var isCompleted: Bool { completedAt != nil }

    public func setCompleted(_ completed: Bool) {
        guard completed != isCompleted else { return }
        completedAt = completed ? Date() : nil
        // Ticking the box finishes the card for flow purposes too; unticking it reopens it unless it sits in a done list.
        if completed {
            startedAt = startedAt ?? Date()
            finishedAt = finishedAt ?? Date()
        } else if list?.stage != .done {
            finishedAt = nil
        }
        record(completed ? .completed : .reopened)
        dropCalendarEventIfClosed()
    }

    public func setDueDate(_ date: Date?) {
        guard date != dueDate else { return }
        dueDate = date
        if date == nil { dueTimeMinutes = nil }
        let text = date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? ""
        // Browsing dates in a picker changes the value many times; fold those into one entry.
        if date != nil, let last = timeline.last, last.kind == .dueDateSet, Date().timeIntervalSince(last.createdAt) < 30 {
            last.text = text
            last.createdAt = Date()
            return
        }
        record(date == nil ? .dueDateCleared : .dueDateSet, text)
    }

    public func attach(_ label: Label) {
        guard !labels.contains(where: { $0 === label }) else { return }
        labels.append(label)
        record(.labelAdded, label.name)
    }

    /// Adds a "From email" reference. False when the message cannot be linked or is already on the card.
    @discardableResult
    public func attach(_ email: ParsedEmail) -> Bool {
        guard let reference = Reference.make(email: email),
              !references.contains(where: { $0.displayPath == reference.displayPath })
        else { return false }
        references.append(reference)
        return true
    }

    /// Details that arrive after the card exists, when the message's .eml is read: the sender goes on the "From email"
    /// reference, and a description is filled in only if there is none. Never overwrites what the user wrote.
    public func enrich(with email: ParsedEmail, fillDescription: Bool) {
        guard let id = email.messageID, let url = MailMessageLink.url(forMessageID: id),
              let reference = references.first(where: { $0.displayPath == url.absoluteString })
        else { return }
        if reference.remoteState == nil { reference.remoteState = email.from }
        if fillDescription, details.isEmpty { details = email.descriptionText }
        if title == "(no subject)", email.subject != "(no subject)" { title = email.subject }
    }

    public func detach(_ label: Label) {
        guard labels.contains(where: { $0 === label }) else { return }
        labels.removeAll { $0 === label }
        record(.labelRemoved, label.name)
    }

    public func addComment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { record(.comment, trimmed) }
    }

    public var checklistProgress: (done: Int, total: Int) {
        let items = checklists.filter { $0.deletedAt == nil }.flatMap(\.items).filter { $0.deletedAt == nil }
        return (items.filter(\.completed).count, items.count)
    }
}

@Model
public final class Label {
    @Attribute(.unique) public var publicId: String
    public var name: String
    public var colourCode: String?
    public var board: Board?
    public var cards: [Card] = []

    public init(name: String, colourCode: String? = nil, board: Board? = nil) {
        self.publicId = makePublicId()
        self.name = name
        self.colourCode = colourCode
        self.board = board
    }
}

@Model
public final class Checklist {
    @Attribute(.unique) public var publicId: String
    public var name: String
    public var index: Int
    public var deletedAt: Date?
    public var card: Card?
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.checklist) public var items: [ChecklistItem] = []

    public init(name: String, index: Int, card: Card? = nil) {
        self.publicId = makePublicId()
        self.name = name
        self.index = index
        self.card = card
    }
}

@Model
public final class ChecklistItem {
    @Attribute(.unique) public var publicId: String
    public var title: String
    public var completed: Bool
    public var index: Int
    public var deletedAt: Date?
    public var checklist: Checklist?

    public init(title: String, index: Int, completed: Bool = false) {
        self.publicId = makePublicId()
        self.title = title
        self.index = index
        self.completed = completed
    }
}

public enum CardEventKind: String, Codable, Sendable {
    case created, moved, archived, restored, dueDateSet, dueDateCleared, labelAdded, labelRemoved, comment
    case completed, reopened, importanceChanged, blocked, unblocked
}

/// One entry in a card's activity feed. `text` is the comment body, or the detail of the change (list names, label, date).
/// Edits made directly in a text field (title, description) are not logged.
@Model
public final class CardEvent {
    @Attribute(.unique) public var publicId: String
    public var kind: CardEventKind
    public var text: String
    public var index: Int
    public var createdAt: Date
    public var card: Card?

    public init(kind: CardEventKind, text: String = "", index: Int) {
        self.publicId = makePublicId()
        self.kind = kind
        self.text = text
        self.index = index
        self.createdAt = Date()
    }
}

public enum ReferenceKind: String, Codable, Sendable {
    case file, folder, obsidianNote, githubIssue, githubPullRequest, email

    public var isGitHub: Bool { self == .githubIssue || self == .githubPullRequest }

    /// Points at something outside the file system, so its address is a URL and never checked on disk.
    public var isRemote: Bool { isGitHub || self == .email }
}

/// Pointer to a local file, folder or Obsidian note. Replaces Kan's S3 attachments:
/// nothing is copied. Resolution (bookmark, then root + relativePath, then displayPath) comes in phase 2.
@Model
public final class Reference {
    @Attribute(.unique) public var publicId: String
    public var kind: ReferenceKind
    public var displayPath: String
    public var relativePath: String?
    public var vaultName: String?
    /// For notes, `relativePath` is relative to this folder instead of the project root.
    public var vaultRootPath: String?
    public var bookmarkData: Data?
    /// GitHub items only: last title and state fetched. `displayPath` holds the web URL.
    public var remoteTitle: String?
    public var remoteState: String?
    public var card: Card?

    public init(kind: ReferenceKind, displayPath: String, relativePath: String? = nil,
                vaultName: String? = nil, vaultRootPath: String? = nil, bookmarkData: Data? = nil,
                remoteTitle: String? = nil, remoteState: String? = nil) {
        self.publicId = makePublicId()
        self.kind = kind
        self.displayPath = displayPath
        self.relativePath = relativePath
        self.vaultName = vaultName
        self.vaultRootPath = vaultRootPath
        self.bookmarkData = bookmarkData
        self.remoteTitle = remoteTitle
        self.remoteState = remoteState
    }
}
