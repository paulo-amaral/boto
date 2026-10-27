import Foundation

/// How the sidebar splits projects: starred ones first, then the rest, then archived (shown on request).
/// Deleted projects never appear. An archived project that is also starred is listed as archived.
public struct ProjectGroups {
    public let favorites: [Project]
    public let active: [Project]
    public let archived: [Project]

    public init(_ projects: [Project]) {
        let live = projects.filter { $0.deletedAt == nil }
        let unarchived = live.filter { !$0.isArchived }
        favorites = unarchived.filter(\.isFavorite).sorted { ($0.favoritedAt ?? .distantPast) < ($1.favoritedAt ?? .distantPast) }
        active = unarchived.filter { !$0.isFavorite }.sorted { $0.createdAt < $1.createdAt }
        archived = live.filter(\.isArchived).sorted { ($0.archivedAt ?? .distantPast) < ($1.archivedAt ?? .distantPast) }
    }

    /// Projects that can be selected: favourites, then the rest, then archived ones only when they are shown.
    public func selectable(showArchived: Bool) -> [Project] {
        favorites + active + (showArchived ? archived : [])
    }
}
