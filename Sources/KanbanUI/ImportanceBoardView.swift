import KanbanCore
import SwiftData
import SwiftUI

/// The board grouped by importance: a lane per importance (High, Medium, Low, None) crossing the lists, which stay
/// the columns. Dropping a card in a cell moves it to that list and gives it that importance.
struct ImportanceBoardView: View {
    let board: Board
    let filter: CardFilter
    let showArchived: Bool
    @Binding var selection: Set<String>
    @Environment(\.isCompactWindow) private var compact
    @Environment(\.stacksBoard) private var stacks
    @Environment(\.modelContext) private var context
    @State private var collapsed: Set<Importance> = []
    @State private var adding: String?
    @State private var newTitle = ""
    @State private var targetedKey: String?
    @State private var problemKey: String?
    @State private var problemText: String?

    private let gap: CGFloat = 20

    private var lists: [BoardList] { board.visibleLists(showArchived: showArchived).filter(filter.showsList) }
    private var lanes: [ImportanceLane] { ImportanceGrouping.lanes(lists: lists, showArchived: showArchived, filter: filter) }
    private var columnWidth: CGFloat { compact ? Theme.compactListWidth : Theme.listWidth }
    private var rowWidth: CGFloat { CGFloat(lists.count) * columnWidth + CGFloat(max(lists.count - 1, 0)) * gap }

    var body: some View {
        let lanes = self.lanes
        if stacks {
            // Narrow window: no column headers; each cell names its list and the lanes read top to bottom.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(lanes, id: \.importance) { laneView($0) }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        } else {
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 12) {
                    headerRow(lanes)
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(lanes, id: \.importance) { laneView($0) }
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .scrollIndicators(.visible)
        }
    }

    private func headerRow(_ lanes: [ImportanceLane]) -> some View {
        HStack(alignment: .top, spacing: gap) {
            ForEach(Array(lists.enumerated()), id: \.element.publicId) { index, list in
                HStack(spacing: 8) {
                    Text(list.name).font(Theme.font(13, weight: .semibold)).lineLimit(1)
                    countBadge(lanes.reduce(0) { $0 + $1.cells[index].cards.count })
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: columnWidth, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.list))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.card))
            }
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(Theme.font(11))
            .foregroundStyle(Theme.mutedStrong)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Theme.border))
    }

    private func laneView(_ lane: ImportanceLane) -> some View {
        let isCollapsed = collapsed.contains(lane.importance)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if isCollapsed { collapsed.remove(lane.importance) } else { collapsed.insert(lane.importance) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down").font(.system(size: 11, weight: .semibold))
                    Image(systemName: "exclamationmark").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.importanceColor(lane.importance))
                    Text(lane.importance.laneTitle).font(Theme.font(14, weight: .semibold))
                    countBadge(lane.count)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minWidth: stacks ? 0 : rowWidth, maxWidth: stacks ? .infinity : rowWidth, alignment: .leading)
                .rowHighlight()
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isCollapsed ? "Expand" : "Collapse")

            if !isCollapsed {
                if stacks {
                    VStack(spacing: 10) {
                        ForEach(lane.cells, id: \.list.publicId) { cell($0, lane.importance) }
                    }
                } else {
                    HStack(alignment: .top, spacing: gap) {
                        ForEach(lane.cells, id: \.list.publicId) { cell($0, lane.importance) }
                    }
                }
            }
        }
    }

    private func cell(_ cell: ImportanceLane.Cell, _ importance: Importance) -> some View {
        let key = "\(importance.rawValue)-\(cell.list.publicId)"
        return VStack(spacing: 8) {
            if stacks {
                Text(cell.list.name).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
            if problemKey == key, let problemText {
                Text(problemText).font(Theme.font(11)).foregroundStyle(Theme.overdue)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
            ForEach(cell.cards) { card in
                CardTile(card: card, selection: $selection) { moveCard($0, into: cell.list, importance: importance) }
            }
            if adding == key {
                TextField("Card title", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(Theme.font(13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
                    .onSubmit {
                        let title = newTitle.trimmingCharacters(in: .whitespaces)
                        if !title.isEmpty { cell.list.addCard(title: title).setImportance(importance) }
                        newTitle = ""
                        adding = nil
                    }
                    .onExitCommand { newTitle = ""; adding = nil }
            } else {
                Button { adding = key } label: {
                    HStack(spacing: 6) { Image(systemName: "plus"); Text("Add a card") }
                        .font(Theme.font(12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .rowHighlight()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
            }
        }
        .padding(8)
        .frame(minWidth: stacks ? 0 : columnWidth, maxWidth: stacks ? .infinity : columnWidth, alignment: .top)
        .frame(minHeight: 56, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.list))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(targetedKey == key ? Theme.text.opacity(0.8) : Theme.card, lineWidth: targetedKey == key ? 2 : 1)
        )
        // A card dropped here moves to this list with this importance; a message from Mail becomes a card here.
        .boardDrop(
            targeted: Binding(get: { targetedKey == key }, set: { targetedKey = $0 ? key : (targetedKey == key ? nil : targetedKey) }),
            problem: Binding(get: { problemKey == key ? problemText : nil }, set: { problemKey = $0 == nil ? nil : key; problemText = $0 }),
            moveCard: { moveCard($0, into: cell.list, importance: importance) },
            addEmails: { emails in emails.forEach { cell.list.addCard(fromEmail: $0).setImportance(importance) } },
            enrich: { emails in
                emails.forEach { email in cell.list.orderedCards.forEach { $0.enrich(with: email, fillDescription: true) } }
            }
        )
    }

    private func moveCard(_ id: String, into list: BoardList, importance: Importance) {
        guard let card = context.card(publicId: id) else { return }
        list.place(card, at: list.orderedCards.count)
        card.setImportance(importance)
    }
}
