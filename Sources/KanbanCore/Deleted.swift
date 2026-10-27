import Foundation

/// Deleting only sets `deletedAt`, so a deleted item can come back, but only into a parent that is still there:
/// a card restored into a deleted list would stay invisible.
extension BoardList {
    public var canRestore: Bool {
        guard deletedAt != nil, let board, board.deletedAt == nil, let project = board.project else { return false }
        return project.deletedAt == nil
    }
}

extension Card {
    public var canRestore: Bool {
        guard deletedAt != nil, let list, list.deletedAt == nil, let board = list.board, board.deletedAt == nil,
              let project = board.project else { return false }
        return project.deletedAt == nil
    }
}
