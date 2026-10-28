import Foundation
import KanbanCore
import SwiftData

struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

struct ToolDefinition {
    let name: String
    let description: String
    let properties: [String: [String: Any]]
    let required: [String]
    /// Changes data. Hidden and refused in read-only mode.
    let writes: Bool

    var json: [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any],
         "annotations": ["readOnlyHint": !writes, "destructiveHint": false] as [String: Any]]
    }
}

/// What an assistant can do with a Boto database. There is no delete tool on purpose: removing and restoring things
/// stays a decision made in the app. Inputs come from a model, so every text has a limit and every id is looked up.
@MainActor
final class BotoTools {
    private let context: ModelContext
    private let readOnly: Bool

    private static let titleLimit = 500
    private static let textLimit = 20_000

    init(context: ModelContext, readOnly: Bool) {
        self.context = context
        self.readOnly = readOnly
    }

    // MARK: Definitions

    private static func text(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func flag(_ description: String) -> [String: Any] { ["type": "boolean", "description": description] }
    private static let day = "A date as YYYY-MM-DD."

    private static let all: [ToolDefinition] = [
        ToolDefinition(name: "list_projects", description: "List projects with their boards and lists (ids, names, card counts).",
                       properties: ["include_archived": flag("Also list archived projects.")], required: [], writes: false),
        ToolDefinition(name: "get_board", description: "List the cards of a board, list by list.",
                       properties: ["board_id": text("Board id."), "include_archived": flag("Also list archived cards.")], required: ["board_id"], writes: false),
        ToolDefinition(name: "get_card", description: "Everything about one card: description, due date, labels, checklists, time and recent activity.",
                       properties: ["card_id": text("Card id.")], required: ["card_id"], writes: false),
        ToolDefinition(name: "search", description: "Find projects and cards by name, title, description or label.",
                       properties: ["query": text("Text to look for."), "limit": ["type": "integer", "description": "At most this many results (1 to 50, default 20)."]],
                       required: ["query"], writes: false),
        ToolDefinition(name: "get_card_activity", description: "A card's activity feed, oldest first: comments, moves, label and date changes. Use comments_only for just the comments.",
                       properties: ["card_id": text("Card id."), "comments_only": flag("Only comments."),
                                    "limit": ["type": "integer", "description": "The latest this many entries (1 to 200, default 50)."]],
                       required: ["card_id"], writes: false),
        ToolDefinition(name: "list_labels", description: "The labels of a board, with their colour and how many open cards carry each.",
                       properties: ["board_id": text("Board id.")], required: ["board_id"], writes: false),
        ToolDefinition(name: "list_notes", description: "A project's sticky notes, newest first. Notes are free text for things to remember that are not tasks.",
                       properties: ["project_id": text("Project id.")], required: ["project_id"], writes: false),
        ToolDefinition(name: "get_time_report", description: "Hours logged on a project between two dates, by day and by card.",
                       properties: ["project_id": text("Project id."), "from": text(day), "to": text(day)], required: ["project_id", "from", "to"], writes: false),
        ToolDefinition(name: "create_card", description: "Add a card at the end of a list.",
                       properties: ["list_id": text("List id."), "title": text("Card title."), "description": text("Markdown description."),
                                    "due_date": text(day), "importance": ["type": "string", "enum": ["high", "medium", "low"], "description": "Importance."]],
                       required: ["list_id", "title"], writes: true),
        ToolDefinition(name: "update_card", description: "Change a card's title, description, due date, importance or completed state. Send only what changes; due_date null clears it.",
                       properties: ["card_id": text("Card id."), "title": text("New title."), "description": text("New Markdown description."),
                                    "due_date": ["type": ["string", "null"], "description": "A date as YYYY-MM-DD, or null to clear."],
                                    "importance": ["type": "string", "enum": ["high", "medium", "low", "unset"], "description": "Importance."],
                                    "completed": flag("Mark done or reopen. Refused for a card that is on the Apple Calendar.")],
                       required: ["card_id"], writes: true),
        ToolDefinition(name: "move_card", description: "Move a card to a list, at a position (0 is the top; default is the end).",
                       properties: ["card_id": text("Card id."), "list_id": text("Target list id."), "position": ["type": "integer", "description": "Zero-based position."]],
                       required: ["card_id", "list_id"], writes: true),
        ToolDefinition(name: "set_card_archived", description: "Archive a card, or restore an archived one. Refused for a card that is on the Apple Calendar.",
                       properties: ["card_id": text("Card id."), "archived": flag("True to archive, false to restore.")], required: ["card_id", "archived"], writes: true),
        ToolDefinition(name: "add_checklist_item", description: "Add an item to a card's checklist, creating the checklist when it does not exist.",
                       properties: ["card_id": text("Card id."), "title": text("Item text."), "checklist": text("Checklist name. Default: the first one, or \"Checklist\".")],
                       required: ["card_id", "title"], writes: true),
        ToolDefinition(name: "set_checklist_item_completed", description: "Tick or untick a checklist item.",
                       properties: ["item_id": text("Checklist item id, from get_card."), "completed": flag("True when done.")], required: ["item_id", "completed"], writes: true),
        ToolDefinition(name: "create_note", description: "Add a sticky note to a project, for something to remember that is not a task.",
                       properties: ["project_id": text("Project id."), "text": text("The note."),
                                    "color": ["type": "string", "enum": NoteColors.all.map { $0.name.lowercased() }, "description": "Note colour. Default: the next one in turn."]],
                       required: ["project_id", "text"], writes: true),
        ToolDefinition(name: "duplicate_project", description: "Copy a project: boards, lists, labels and, unless structure_only, cards with their checklists and references. Hours, activity and calendar links stay with the original.",
                       properties: ["project_id": text("Project id."), "name": text("Name of the copy. Default: \"<name> copy\"."),
                                    "structure_only": flag("Copy only boards, lists and labels, as an empty template.")],
                       required: ["project_id"], writes: true),
        ToolDefinition(name: "log_time", description: "Log time worked on a card or on a project as a whole. Give card_id or project_id.",
                       properties: ["card_id": text("Card id."), "project_id": text("Project id, for time with no card."),
                                    "minutes": ["type": "integer", "description": "Minutes worked, 1 to 1440."], "date": text(day + " Default: today."), "note": text("What was done.")],
                       required: ["minutes"], writes: true),
    ]

    var definitions: [ToolDefinition] { Self.all.filter { !readOnly || !$0.writes } }

    func knows(_ name: String) -> Bool { definitions.contains { $0.name == name } }

    func call(_ name: String, _ arguments: [String: Any]) throws -> Any {
        switch name {
        case "list_projects": return try listProjects(arguments)
        case "get_board": return try getBoard(arguments)
        case "get_card": return try getCard(arguments)
        case "search": return try search(arguments)
        case "get_card_activity": return try cardActivity(arguments)
        case "list_labels": return try listLabels(arguments)
        case "list_notes": return try listNotes(arguments)
        case "create_note": return try createNote(arguments)
        case "get_time_report": return try timeReport(arguments)
        case "create_card": return try createCard(arguments)
        case "update_card": return try updateCard(arguments)
        case "move_card": return try moveCard(arguments)
        case "set_card_archived": return try setArchived(arguments)
        case "add_checklist_item": return try addChecklistItem(arguments)
        case "set_checklist_item_completed": return try setItemCompleted(arguments)
        case "duplicate_project": return try duplicateProject(arguments)
        case "log_time": return try logTime(arguments)
        default: throw ToolError("Unknown tool: \(name)")
        }
    }

    // MARK: Reading

    private func listProjects(_ args: [String: Any]) throws -> Any {
        let includeArchived = args["include_archived"] as? Bool ?? false
        let projects = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.createdAt)]))
        return ["projects": projects.filter { includeArchived || !$0.isArchived }.map(projectSummary)]
    }

    private func projectSummary(_ project: Project) -> [String: Any] {
        compact([
            "id": project.publicId, "name": project.name, "archived": project.isArchived ? true : nil,
            "boards": project.activeBoards.map { board in
                ["id": board.publicId, "name": board.name,
                 "lists": board.visibleLists(showArchived: false).map { ["id": $0.publicId, "name": $0.name, "cards": $0.visibleCards(showArchived: false).count] as [String: Any] }]
                    as [String: Any]
            },
        ])
    }

    private func getBoard(_ args: [String: Any]) throws -> Any {
        let id = try required(args, "board_id")
        guard let board = try context.fetch(FetchDescriptor<Board>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No board with id \(id)")
        }
        let includeArchived = args["include_archived"] as? Bool ?? false
        return ["id": board.publicId, "name": board.name, "lists": board.visibleLists(showArchived: false).map { list in
            ["id": list.publicId, "name": list.name, "cards": list.visibleCards(showArchived: includeArchived).map(summary)] as [String: Any]
        }]
    }

    private func getCard(_ args: [String: Any]) throws -> Any {
        let card = try findCard(try required(args, "card_id"))
        return compact([
            "id": card.publicId, "title": card.title, "description": card.details.isEmpty ? nil : card.details,
            "list": card.list.map { ["id": $0.publicId, "name": $0.name] as [String: Any] },
            "due_date": card.dueDate.map(dayText), "importance": card.importance == .unset ? nil : card.importance.rawValue,
            "completed": card.isCompleted, "archived": card.isArchived ? true : nil,
            "blocked": card.blockedAt == nil ? nil : (card.blockedReason ?? "blocked"),
            "labels": card.labels.map(\.name),
            "checklists": card.checklists.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index }.map { checklist in
                ["id": checklist.publicId, "name": checklist.name, "items": checklist.items.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index }
                    .map { ["id": $0.publicId, "title": $0.title, "completed": $0.completed] as [String: Any] }] as [String: Any]
            },
            "time": TimeReport.clock(card.totalSeconds()),
            "recent_activity": card.timeline.suffix(10).map { ["kind": $0.kind.rawValue, "text": $0.text, "at": ISO8601DateFormatter().string(from: $0.createdAt)] },
        ])
    }

    private func search(_ args: [String: Any]) throws -> Any {
        let query = try required(args, "query")
        let limit = min(max(args["limit"] as? Int ?? 20, 1), 50)
        let projects = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.deletedAt == nil }))
        return ["results": Search.results(for: query, in: projects, limit: limit).map { result -> [String: Any] in
            switch result {
            case .project(let project): ["type": "project", "id": project.publicId, "name": project.name]
            case .card(let card): compact(["type": "card", "id": card.publicId, "title": card.title,
                                           "list": card.list?.name, "project": card.list?.board?.project?.name])
            case .note(let note): compact(["type": "note", "id": note.publicId, "text": String(note.text.prefix(200)), "project": note.project?.name])
            }
        }]
    }

    private func cardActivity(_ args: [String: Any]) throws -> Any {
        let card = try findCard(try required(args, "card_id"))
        let commentsOnly = args["comments_only"] as? Bool ?? false
        let limit = min(max(args["limit"] as? Int ?? 50, 1), 200)
        let formatter = ISO8601DateFormatter()
        let events = card.timeline.filter { !commentsOnly || $0.kind == .comment }.suffix(limit)
        return ["card": card.title, "activity": events.map {
            ["id": $0.publicId, "kind": $0.kind.rawValue, "text": $0.text, "at": formatter.string(from: $0.createdAt)]
        }]
    }

    private func listLabels(_ args: [String: Any]) throws -> Any {
        let id = try required(args, "board_id")
        guard let board = try context.fetch(FetchDescriptor<Board>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No board with id \(id)")
        }
        return ["labels": board.labels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }.map { label in
            compact(["id": label.publicId, "name": label.name, "colour": label.colourCode,
                     "open_cards": label.cards.filter { $0.deletedAt == nil && !$0.isArchived }.count])
        }]
    }

    private func noteSummary(_ note: Note) -> [String: Any] {
        ["id": note.publicId, "text": note.text, "color": NoteColors.all.first { $0.hex == note.colorHex }?.name.lowercased() ?? note.colorHex]
    }

    private func listNotes(_ args: [String: Any]) throws -> Any {
        let project = try findProject(try required(args, "project_id"))
        return ["project": project.name, "notes": project.liveNotes.map(noteSummary)]
    }

    private func createNote(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let project = try findProject(try required(args, "project_id"))
        let text = try limited(try required(args, "text"), Self.textLimit, "text")
        let note = project.addNote(text: text)
        if let name = try optional(args, "color", limit: 16)?.lowercased() {
            guard let colour = NoteColors.all.first(where: { $0.name.lowercased() == name }) else {
                project.notes.removeAll { $0 === note }
                context.delete(note)
                throw ToolError("color must be one of \(NoteColors.all.map { $0.name.lowercased() }.joined(separator: ", "))")
            }
            note.colorHex = colour.hex
        }
        try context.save()
        return noteSummary(note)
    }

    private func timeReport(_ args: [String: Any]) throws -> Any {
        let project = try findProject(try required(args, "project_id"))
        let report = TimeReport(project: project, from: try parseDay(try required(args, "from")), to: try parseDay(try required(args, "to")))
        return ["total": TimeReport.clock(report.totalSeconds), "total_seconds": report.totalSeconds,
                "by_day": report.byDay.map { ["date": dayText($0.day), "hours": TimeReport.clock($0.seconds)] },
                "by_card": report.byCard.map { ["card": $0.title, "hours": TimeReport.clock($0.seconds)] }]
    }

    // MARK: Writing

    private func createCard(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let id = try required(args, "list_id")
        guard let list = try context.fetch(FetchDescriptor<BoardList>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No list with id \(id)")
        }
        let title = try limited(try required(args, "title"), Self.titleLimit, "title")
        let description = try optional(args, "description", limit: Self.textLimit)
        let due = try optional(args, "due_date", limit: 10).map(parseDay)
        let importance = try importance(args)
        let card = list.addCard(title: title)
        if let description { card.details = description }
        if let due { card.setDueDate(due) }
        if let importance { card.setImportance(importance) }
        try context.save()
        return summary(card)
    }

    private func updateCard(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let card = try findCard(try required(args, "card_id"))
        // Validate everything before changing anything, so a bad argument leaves the card as it was.
        let title = try optional(args, "title", limit: Self.titleLimit)
        if let title, title.isEmpty { throw ToolError("title cannot be empty") }
        let description = try optional(args, "description", limit: Self.textLimit)
        let clearsDue = args.keys.contains("due_date") && args["due_date"] is NSNull
        let due = clearsDue ? nil : try optional(args, "due_date", limit: 10).map(parseDay)
        let importance = try importance(args)
        let completed = args["completed"] as? Bool
        if completed != nil { try refuseCalendarCard(card, action: "complete or reopen") }

        if let title { card.title = title }
        if let description { card.details = description }
        if clearsDue { card.setDueDate(nil) } else if let due { card.setDueDate(due) }
        if let importance { card.setImportance(importance) }
        if let completed { card.setCompleted(completed) }
        try context.save()
        return summary(card)
    }

    private func moveCard(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let card = try findCard(try required(args, "card_id"))
        let id = try required(args, "list_id")
        guard let list = try context.fetch(FetchDescriptor<BoardList>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No list with id \(id)")
        }
        let count = list.orderedCards.filter { $0 !== card }.count
        let position = args["position"] as? Int ?? count
        guard (0...count).contains(position) else { throw ToolError("position must be between 0 and \(count)") }
        list.place(card, at: position)
        try context.save()
        return summary(card)
    }

    private func setArchived(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let card = try findCard(try required(args, "card_id"))
        guard let archived = args["archived"] as? Bool else { throw ToolError("archived must be true or false") }
        if archived { try refuseCalendarCard(card, action: "archive") }
        card.setArchived(archived)
        try context.save()
        return summary(card)
    }

    private func addChecklistItem(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let card = try findCard(try required(args, "card_id"))
        let title = try limited(try required(args, "title"), Self.titleLimit, "title")
        let name = try optional(args, "checklist", limit: Self.titleLimit)
        let existing = card.checklists.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index }
        let checklist: Checklist
        if let found = name.flatMap({ name in existing.first { $0.name == name } }) ?? (name == nil ? existing.first : nil) {
            checklist = found
        } else {
            checklist = Checklist(name: name ?? "Checklist", index: existing.count)
            card.checklists.append(checklist)
        }
        let item = ChecklistItem(title: title, index: checklist.items.count)
        checklist.items.append(item)
        try context.save()
        return ["item_id": item.publicId, "checklist": checklist.name, "title": item.title]
    }

    private func setItemCompleted(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let id = try required(args, "item_id")
        guard let item = try context.fetch(FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No checklist item with id \(id)")
        }
        guard let completed = args["completed"] as? Bool else { throw ToolError("completed must be true or false") }
        item.completed = completed
        try context.save()
        return ["item_id": item.publicId, "completed": completed]
    }

    private func duplicateProject(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        let project = try findProject(try required(args, "project_id"))
        let existing = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.deletedAt == nil })).map(\.name)
        let name = try optional(args, "name", limit: Self.titleLimit).flatMap { $0.isEmpty ? nil : $0 }
            ?? Project.copyName(of: project.name, among: existing)
        let copy = project.duplicate(named: name, withCards: !(args["structure_only"] as? Bool ?? false), in: context)
        try context.save()
        return projectSummary(copy)
    }

    private func logTime(_ args: [String: Any]) throws -> Any {
        try requireWritable()
        guard let minutes = args["minutes"] as? Int, (1...1440).contains(minutes) else { throw ToolError("minutes must be a whole number from 1 to 1440") }
        let cardId = try optional(args, "card_id", limit: 64)
        let projectId = try optional(args, "project_id", limit: 64)
        guard (cardId == nil) != (projectId == nil) else { throw ToolError("Give exactly one of card_id or project_id") }
        let date = try optional(args, "date", limit: 10).map(parseDay) ?? Calendar.current.startOfDay(for: Date())
        let note = try optional(args, "note", limit: Self.titleLimit) ?? ""
        let entry: TimeEntry?
        if let cardId { entry = try findCard(cardId).logTime(seconds: minutes * 60, on: date, note: note) }
        else { entry = try findProject(projectId ?? "").logTime(seconds: minutes * 60, on: date, note: note) }
        try context.save()
        return ["entry_id": entry?.publicId ?? "", "logged": TimeReport.clock(minutes * 60), "date": dayText(date)]
    }

    // MARK: Helpers

    private func requireWritable() throws {
        if readOnly { throw ToolError("This server is read-only") }
    }

    /// Completing or archiving a card removes its Apple Calendar event, which needs a calendar permission that only the
    /// app holds. A helper process must not trigger that prompt, so the app does it.
    private func refuseCalendarCard(_ card: Card, action: String) throws {
        if card.calendarEventID != nil {
            throw ToolError("This card is on the Boto calendar. Open it in Boto to \(action) it, so its calendar event is removed too.")
        }
    }

    private func findCard(_ id: String) throws -> Card {
        guard let card = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No card with id \(id)")
        }
        return card
    }

    private func findProject(_ id: String) throws -> Project {
        guard let project = try context.fetch(FetchDescriptor<Project>(predicate: #Predicate { $0.publicId == id && $0.deletedAt == nil })).first else {
            throw ToolError("No project with id \(id)")
        }
        return project
    }

    private func required(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = args[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError("\(key) is required") }
        return value
    }

    private func optional(_ args: [String: Any], _ key: String, limit: Int) throws -> String? {
        guard let value = args[key], !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw ToolError("\(key) must be text") }
        return try limited(text, limit, key)
    }

    private func limited(_ text: String, _ limit: Int, _ key: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= limit else { throw ToolError("\(key) is longer than \(limit) characters") }
        return trimmed
    }

    private func importance(_ args: [String: Any]) throws -> Importance? {
        guard let text = try optional(args, "importance", limit: 16) else { return nil }
        guard let value = Importance(rawValue: text) else { throw ToolError("importance must be high, medium, low or unset") }
        return value
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func parseDay(_ text: String) throws -> Date {
        guard let date = Self.dayFormatter.date(from: text), Self.dayFormatter.string(from: date) == text else {
            throw ToolError("\"\(text)\" is not a date; use YYYY-MM-DD")
        }
        return date
    }

    private func dayText(_ date: Date) -> String { Self.dayFormatter.string(from: date) }

    private func compact(_ values: [String: Any?]) -> [String: Any] { values.compactMapValues { $0 } }

    private func summary(_ card: Card) -> [String: Any] {
        let progress = card.checklistProgress
        return compact([
            "id": card.publicId, "title": card.title, "due_date": card.dueDate.map(dayText),
            "importance": card.importance == .unset ? nil : card.importance.rawValue,
            "completed": card.isCompleted ? true : nil, "archived": card.isArchived ? true : nil,
            "blocked": card.blockedAt == nil ? nil : true,
            "labels": card.labels.isEmpty ? nil : card.labels.map(\.name),
            "checklist": progress.total == 0 ? nil : "\(progress.done)/\(progress.total)",
            "list": card.list?.name,
        ])
    }
}
