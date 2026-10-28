import KanbanCore
import SwiftData
import SwiftUI

struct ListView: View {
    @Bindable var list: BoardList
    let filter: CardFilter
    let showArchived: Bool
    @Binding var selection: Set<String>
    /// In a stacked board the list fills the width instead of being a fixed-width column.
    var fill = false
    @Environment(\.modelContext) private var context
    @Environment(\.isCompactWindow) private var compact
    @State private var adding = false
    @State private var pasting = false
    @State private var editingFlow = false
    @State private var confirmingDelete = false
    @State private var newTitle = ""
    @State private var emailTargeted = false
    @State private var dropProblem: String?
    private var listWidth: CGFloat { compact ? Theme.compactListWidth : Theme.listWidth }

    private var visibleCards: [Card] { list.visibleCards(showArchived: showArchived).filter { filter.matches($0) } }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                InlineEditText(text: $list.name, font: Theme.font(13, weight: .medium), placeholder: "List name")
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 8)
                WIPBadge(list: list)
                Button { adding = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain)
                    .help("Add card")
                    .accessibilityLabel("Add card")
                Menu {
                    Button { adding = true } label: { Label("Add a card", systemImage: "plus") }
                    Button { pasting = true } label: { Label("Paste cards from text...", systemImage: "doc.on.clipboard") }
                    Button { list.archivedAt = list.isArchived ? nil : Date() } label: {
                        Label(list.isArchived ? "Restore list" : "Archive list",
                              systemImage: list.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                    Button { editingFlow = true } label: { Label("Flow settings...", systemImage: "slider.horizontal.3") }
                    Divider()
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete list", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("List options")
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
            }
            .foregroundStyle(Theme.muted)

            if let policy = list.policy {
                Text(policy)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            if let dropProblem {
                Text(dropProblem)
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.overdue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .onTapGesture { self.dropProblem = nil }
            }

            // The list is as tall as its cards. Only when they no longer fit does the second option, a scroll view, win.
            ViewThatFits(in: .vertical) {
                VStack(spacing: 8) { cardRows }
                ScrollView { LazyVStack(spacing: 8) { cardRows } }.scrollIndicators(.hidden)
            }
            if adding { newCardField }
            if visibleCards.isEmpty && !adding { emptyState }
        }
        .padding(8)
        // A fixed width, not min and max: with min and max the list is measured with no width at all, so a card footer
        // that wraps is measured as one line and the list ends up shorter than its cards.
        .frame(width: fill ? nil : listWidth)
        .frame(maxWidth: fill ? .infinity : nil)
        .opacity(list.isArchived ? 0.6 : 1)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.list))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(emailTargeted ? Theme.text.opacity(0.8) : Theme.card, lineWidth: emailTargeted ? 2 : 1)
        )
        .frame(maxHeight: .infinity, alignment: .top)
        // One handler for everything dropped here: a card goes to the end of the list, a message from Mail becomes a card.
        .boardDrop(
            targeted: $emailTargeted,
            problem: $dropProblem,
            moveCard: { moveCard($0, atVisiblePosition: visibleCards.count) },
            addEmails: { emails in emails.forEach { list.addCard(fromEmail: $0) } },
            enrich: { emails in
                emails.forEach { email in list.orderedCards.forEach { $0.enrich(with: email, fillDescription: true) } }
            }
        )
        .sheet(isPresented: $pasting) { PasteCardsSheet(list: list) }
        .sheet(isPresented: $editingFlow) { ListFlowSheet(list: list) }
        .confirmationDialog("Delete \"\(list.name)\"?", isPresented: $confirmingDelete) {
            Button("Delete list", role: .destructive) { list.deletedAt = Date() }
        } message: {
            let count = list.cards.filter { $0.deletedAt == nil }.count
            Text("The list and its \(count) card\(count == 1 ? "" : "s") disappear from the board. Archive the list instead to keep them.")
        }
    }

    @ViewBuilder
    private var cardRows: some View {
        ForEach(Array(visibleCards.enumerated()), id: \.element.publicId) { position, card in
            CardTile(card: card, selection: $selection) { moveCard($0, atVisiblePosition: position) }
        }
    }

    private var emptyState: some View {
        Button { adding = true } label: {
            HStack(spacing: 6) { Image(systemName: "plus"); Text("Add a card") }
                .font(Theme.font(12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .rowHighlight()
        .help("Add a card, or drop one here")
    }

    private var newCardField: some View {
        TextField("Card title", text: $newTitle)
            .textFieldStyle(.plain)
            .font(Theme.font(13))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
            .onSubmit {
                let title = newTitle.trimmingCharacters(in: .whitespaces)
                if !title.isEmpty { list.addCard(title: title) }
                newTitle = ""
                adding = false
            }
            .onExitCommand { newTitle = ""; adding = false }
    }

    /// With a filter active the visible index is not the stored index, so translate it before placing.
    private func moveCard(_ id: String, atVisiblePosition position: Int) {
        guard let card = context.card(publicId: id) else { return }
        let all = list.orderedCards
        let target = position < visibleCards.count
            ? all.firstIndex { $0 === visibleCards[position] } ?? all.count
            : all.count
        list.place(card, at: target)
    }
}

public struct BoardView: View {
    @Bindable var board: Board
    let onChooseRoot: () -> Void
    let onDelete: () -> Void
    let onChangeIcon: (() -> Void)?
    let onDuplicate: (() -> Void)?
    let onDuplicateStructure: (() -> Void)?
    @State private var filter = CardFilter()
    @State private var selection: Set<String> = []
    @State private var showArchived = false
    @State private var menuOpen = false
    @State private var showFlow = false
    @State private var showTime = false
    @State private var noteFocusId: String?
    @State private var calendarMessage: String?
    @AppStorage("groupByImportance") private var groupByImportance = false
    @Environment(\.isCompactWindow) private var compact
    @Environment(\.stacksBoard) private var stacksBoard

    private var visibleLists: [BoardList] { board.visibleLists(showArchived: showArchived).filter(filter.showsList) }

    private var selectedCards: [Card] {
        board.orderedLists.flatMap(\.orderedCards).filter { selection.contains($0.publicId) }
    }

    public init(board: Board, onChooseRoot: @escaping () -> Void, onDelete: @escaping () -> Void, onChangeIcon: (() -> Void)? = nil,
                onDuplicate: (() -> Void)? = nil, onDuplicateStructure: (() -> Void)? = nil) {
        self.board = board
        self.onChooseRoot = onChooseRoot
        self.onDelete = onDelete
        self.onChangeIcon = onChangeIcon
        self.onDuplicate = onDuplicate
        self.onDuplicateStructure = onDuplicateStructure
    }

    public var body: some View {
        ZStack {
            Theme.background
            PatternedBackground()
            VStack(alignment: .leading, spacing: 24) {
                header
                if groupByImportance {
                    ImportanceBoardView(board: board, filter: filter, showArchived: showArchived, selection: $selection)
                } else if stacksBoard {
                    // A narrow window shows the lists one under another, like a plain list, instead of side by side.
                    ScrollView(.vertical) {
                        VStack(spacing: 16) {
                            if let project = board.project, !project.liveNotes.isEmpty {
                                NotesColumn(project: project, focusId: $noteFocusId, fill: true)
                            }
                            ForEach(visibleLists, id: \.publicId) {
                                ListView(list: $0, filter: filter, showArchived: showArchived, selection: $selection, fill: true)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            if let project = board.project, !project.liveNotes.isEmpty {
                                NotesColumn(project: project, focusId: $noteFocusId)
                            }
                            ForEach(visibleLists, id: \.publicId) {
                                ListView(list: $0, filter: filter, showArchived: showArchived, selection: $selection)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .scrollIndicators(.visible)
                }
            }
            .padding(compact ? 16 : 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            if !selectedCards.isEmpty {
                BulkActionBar(cards: selectedCards, lists: board.orderedLists) { selection = [] }
                    .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topTrailing) { menuOverlay }
        .sheet(isPresented: $showFlow) { FlowView(board: board) }
        .alert("Apple Calendar", isPresented: Binding(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
            Button("OK") { calendarMessage = nil }
        } message: { Text(calendarMessage ?? "") }
        .sheet(isPresented: $showTime) { if let project = board.project { HoursView(project: project) } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                titleView
                if board.project?.isArchived == true {
                    Label("Archived project", systemImage: "archivebox").font(Theme.font(11)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            // Keep the buttons at their natural width; the title is the part that gives way and truncates.
            HStack(spacing: 8) {
                Button { groupByImportance.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.split.1x2")
                        if !compact { Text("Group by importance") }
                    }
                }
                .buttonStyle(ToolbarButtonStyle(primary: false, active: groupByImportance))
                .help(groupByImportance ? "Back to lists" : "Group by importance")
                Button { showFlow = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line")
                        if !compact { Text("Flow") }
                    }
                }
                .buttonStyle(ToolbarButtonStyle(primary: false))
                .help("Flow metrics")
                if board.project != nil {
                    Button { showTime = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "hourglass")
                            if !compact { Text("Hours") }
                        }
                    }
                    .buttonStyle(ToolbarButtonStyle(primary: false))
                    .help("Hours worked in this project")
                    Button { noteFocusId = board.project?.addNote().publicId } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "note.text.badge.plus")
                            if !compact { Text("Note") }
                        }
                    }
                    .buttonStyle(ToolbarButtonStyle(primary: false))
                    .help("Add a sticky note to this board")
                }
                FilterButton(filter: $filter, labels: board.labels, lists: board.orderedLists, iconOnly: compact)
                Button {
                    board.lists.append(BoardList(name: "New list", index: board.orderedLists.count))
                } label: {
                    HStack(spacing: 8) { Image(systemName: "plus"); if !compact { Text("New list") } }
                }
                .buttonStyle(ToolbarButtonStyle(primary: true))
                .help("New list (C)")
                moreButton
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { board.project?.name ?? board.name },
            set: { if let project = board.project { project.name = $0 } else { board.name = $0 } }
        )
    }

    private var titleView: some View {
        InlineEditText(text: titleBinding, font: Theme.font(19, weight: .bold), placeholder: "Project name")
            .foregroundStyle(Theme.text)
    }

    private var moreButton: some View {
        Button { menuOpen.toggle() } label: { Image(systemName: "ellipsis") }
            .buttonStyle(ToolbarButtonStyle(primary: false))
            .help("More")
            .accessibilityLabel("More")
    }

    private func addDatedCardsToCalendar() {
        let cards = board.calendarCandidates
        guard !cards.isEmpty else { calendarMessage = "No open cards with a due date."; return }
        Task { @MainActor in
            do {
                let count = try await CalendarSync.shared.syncAll(cards)
                calendarMessage = "\(count) card\(count == 1 ? "" : "s") added to the Boto calendar."
            } catch {
                calendarMessage = error.localizedDescription
            }
        }
    }

    private var menuEntries: [DropdownEntry] {
        var entries = [DropdownEntry(icon: "eye", title: "Show archived cards and lists", checked: showArchived) {
            showArchived.toggle()
        }]
        entries.append(DropdownEntry(icon: "calendar.badge.plus", title: "Add dated cards to Apple Calendar", action: addDatedCardsToCalendar))
        if let project = board.project {
            entries.append(.divider)
            entries += ProjectMenu.entries(for: project, onChangeIcon: onChangeIcon, onDuplicate: onDuplicate,
                                          onDuplicateStructure: onDuplicateStructure, onChooseRoot: onChooseRoot, onDelete: onDelete)
        }
        return entries
    }

    /// Sits under the header's "..." button, right-aligned with it, over a transparent layer that closes it on click.
    @ViewBuilder
    private var menuOverlay: some View {
        if menuOpen {
            ZStack(alignment: .topTrailing) {
                Color.clear.contentShape(Rectangle()).onTapGesture { menuOpen = false }
                DropdownPanel(entries: menuEntries) { menuOpen = false }
                    .padding(.top, (compact ? 16 : 32) + 46)
                    .padding(.trailing, compact ? 16 : 32)
                Button("") { menuOpen = false }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            }
        }
    }
}
