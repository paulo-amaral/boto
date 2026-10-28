import Foundation

public enum SearchResult: Identifiable {
    case project(Project)
    case card(Card)
    case note(Note)

    public var id: String {
        switch self {
        case .project(let project): "project-\(project.publicId)"
        case .card(let card): "card-\(card.publicId)"
        case .note(let note): "note-\(note.publicId)"
        }
    }
}

/// Matches project names, card titles, descriptions and label names, and the text of sticky notes.
public enum Search {
    public static func results(for query: String, in projects: [Project], limit: Int = 20) -> [SearchResult] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        var scored: [(score: Int, isCard: Bool, title: String, result: SearchResult)] = []
        for project in projects where project.deletedAt == nil && !project.isArchived {
            if let score = score(project.name, needle) {
                scored.append((score, false, project.name, .project(project)))
            }
            for note in project.liveNotes {
                if let best = score(note.text, needle) { scored.append((best, true, note.title, .note(note))) }
            }
            for board in project.activeBoards {
                for list in board.visibleLists(showArchived: false) {
                    for card in list.visibleCards(showArchived: false) {
                        let best = [
                            score(card.title, needle),
                            score(card.details, needle).map { _ in 1 },
                            card.labels.contains { $0.name.lowercased().contains(needle) } ? 1 : nil,
                        ].compactMap { $0 }.max()
                        if let best { scored.append((best, true, card.title, .card(card))) }
                    }
                }
            }
        }

        return scored
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.isCard != $1.isCard { return !$0.isCard }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            .prefix(limit)
            .map(\.result)
    }

    /// 3 = prefix, 2 = contains, nil = no match.
    private static func score(_ text: String, _ needle: String) -> Int? {
        let lowered = text.lowercased()
        if lowered.hasPrefix(needle) { return 3 }
        return lowered.contains(needle) ? 2 : nil
    }
}
