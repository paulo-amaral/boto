import Foundation
import SwiftData

/// Duplicating a project copies what describes the work: boards, lists with their flow settings, labels, and cards with
/// their checklists, references, colour, importance and dates. It leaves behind what belongs to the original's
/// history: hours, activity, the Kaizen log, the Apple Calendar link (two cards cannot share one event) and the flow
/// timestamps, which imported work also goes without, so the copy does not inflate throughput or cycle time.
/// Deleted boards, lists and cards stay deleted. Archived ones stay archived. Without cards, only the structure is
/// copied (boards, lists with their flow settings, labels), which makes an empty template.
extension Project {
    /// "Name copy", then "Name copy 2", and so on, so a copy never takes a name that is already in use.
    public static func copyName(of name: String, among existing: [String]) -> String {
        let taken = Set(existing)
        let base = "\(name) copy"
        if !taken.contains(base) { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    @discardableResult
    public func duplicate(named newName: String, withCards: Bool = true, in context: ModelContext) -> Project {
        let copy = Project(name: newName)
        context.insert(copy)
        copy.rootFolderPath = rootFolderPath
        copy.rootFolderBookmark = rootFolderBookmark
        // An icon the person picked is kept. An automatic one is left for the app to assign, so the copy looks different.
        if iconName.flatMap(ProjectIcons.lucideName(in:)) != nil { copy.iconName = iconName }
        for board in activeBoards { copy.boards.append(board.copied(withCards: withCards)) }
        return copy
    }
}

extension Board {
    fileprivate func copied(withCards: Bool) -> Board {
        let copy = Board(name: name)
        var labels: [ObjectIdentifier: Label] = [:]
        for label in self.labels {
            let labelCopy = Label(name: label.name, colourCode: label.colourCode)
            copy.labels.append(labelCopy)
            labels[ObjectIdentifier(label)] = labelCopy
        }
        for list in lists.filter({ $0.deletedAt == nil }).sorted(by: { $0.index < $1.index }) {
            copy.lists.append(list.copied(labels, withCards: withCards))
        }
        return copy
    }
}

extension BoardList {
    fileprivate func copied(_ labels: [ObjectIdentifier: Label], withCards: Bool) -> BoardList {
        let copy = BoardList(name: name, index: index)
        copy.stageRaw = stageRaw
        copy.wipLimit = wipLimit
        copy.policy = policy
        copy.archivedAt = archivedAt
        if withCards { for card in orderedCards { card.copy(into: copy, labels) } }
        return copy
    }
}

extension Card {
    fileprivate func copy(into list: BoardList, _ labels: [ObjectIdentifier: Label]) {
        let copy = list.addCard(title: title)
        copy.details = details
        copy.dueDate = dueDate
        copy.dueTimeMinutes = dueTimeMinutes
        copy.alertLeadMinutes = alertLeadMinutes
        copy.colorHex = colorHex
        copy.importanceRaw = importanceRaw
        copy.completedAt = completedAt
        copy.archivedAt = archivedAt
        copy.blockedAt = blockedAt
        copy.blockedReason = blockedReason
        // `addCard` stamps the flow clock for the list it lands in; the original's history is not the copy's.
        copy.startedAt = nil
        copy.finishedAt = nil
        for label in self.labels { if let mapped = labels[ObjectIdentifier(label)] { copy.labels.append(mapped) } }
        for checklist in self.checklists.filter({ $0.deletedAt == nil }).sorted(by: { $0.index < $1.index }) {
            let checklistCopy = Checklist(name: checklist.name, index: copy.checklists.count)
            copy.checklists.append(checklistCopy)
            for item in checklist.items.filter({ $0.deletedAt == nil }).sorted(by: { $0.index < $1.index }) {
                checklistCopy.items.append(ChecklistItem(title: item.title, index: checklistCopy.items.count, completed: item.completed))
            }
        }
        for reference in references {
            copy.references.append(Reference(
                kind: reference.kind, displayPath: reference.displayPath, relativePath: reference.relativePath,
                vaultName: reference.vaultName, vaultRootPath: reference.vaultRootPath, bookmarkData: reference.bookmarkData,
                remoteTitle: reference.remoteTitle, remoteState: reference.remoteState
            ))
        }
    }
}
