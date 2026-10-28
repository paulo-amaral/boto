import KanbanCore
import SwiftData
import SwiftUI

/// Everything deleted that can still come back. Deleting only marks an item, so restoring clears the mark; nothing
/// here is ever erased from the database. A card or list whose parent is also deleted waits for its parent.
struct RecentlyDeletedView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Project> { $0.deletedAt != nil }, sort: [SortDescriptor(\Project.deletedAt, order: .reverse)])
    private var projects: [Project]
    @Query(filter: #Predicate<BoardList> { $0.deletedAt != nil }, sort: [SortDescriptor(\BoardList.deletedAt, order: .reverse)])
    private var allLists: [BoardList]
    @Query(filter: #Predicate<Card> { $0.deletedAt != nil }, sort: [SortDescriptor(\Card.deletedAt, order: .reverse)])
    private var allCards: [Card]
    @Query(filter: #Predicate<Note> { $0.deletedAt != nil }, sort: [SortDescriptor(\Note.deletedAt, order: .reverse)])
    private var allNotes: [Note]

    private struct Item: Identifiable {
        let id: String
        let title: String
        let context: String?
        let deletedAt: Date?
        let restore: () -> Void
    }

    var body: some View {
        let projectItems = projects.map { project in
            Item(id: project.publicId, title: project.name, context: nil, deletedAt: project.deletedAt) { project.deletedAt = nil }
        }
        let listItems = allLists.filter(\.canRestore).map { list in
            let count = list.cards.filter { $0.deletedAt == nil }.count
            return Item(id: list.publicId, title: list.name, context: "\(list.board?.project?.name ?? "") \u{00B7} \(count) card\(count == 1 ? "" : "s")",
                        deletedAt: list.deletedAt) { list.deletedAt = nil }
        }
        let cardItems = allCards.filter(\.canRestore).map { card in
            Item(id: card.publicId, title: card.title, context: [card.list?.board?.project?.name, card.list?.name].compactMap { $0 }.joined(separator: " / "),
                 deletedAt: card.deletedAt) { card.deletedAt = nil }
        }
        let noteItems = allNotes.filter(\.canRestore).map { note in
            Item(id: note.publicId, title: note.title.isEmpty ? "Empty note" : note.title, context: note.project?.name, deletedAt: note.deletedAt) { note.deletedAt = nil }
        }
        VStack(spacing: 0) {
            HStack {
                Text("Recently deleted").font(Theme.font(16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)

            if projectItems.isEmpty && listItems.isEmpty && cardItems.isEmpty && noteItems.isEmpty {
                Text("Nothing to restore. Deleted projects, lists, cards and notes appear here, and each one can come back.")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(22)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        section("Projects", projectItems)
                        section("Lists", listItems)
                        section("Cards", cardItems)
                        section("Notes", noteItems)
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
            }
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 480)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [Item]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.font(13, weight: .semibold))
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title.isEmpty ? "Untitled" : item.title).font(Theme.font(12)).lineLimit(1)
                            if let context = item.context, !context.isEmpty {
                                Text(context).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                        }
                        Spacer()
                        if let deletedAt = item.deletedAt {
                            Text(deletedAt.formatted(.relative(presentation: .named))).font(Theme.font(11)).foregroundStyle(Theme.muted)
                        }
                        Button("Restore", action: item.restore)
                            .accessibilityLabel("Restore \(item.title)")
                    }
                    .padding(.vertical, 6)
                    Divider()
                }
            }
        }
    }
}
