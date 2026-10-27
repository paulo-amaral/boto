import AppKit
import KanbanCore
import SwiftUI

/// Card back after Trello's: the list as a button in the top bar, a round "complete" box beside the title,
/// buttons for Add / Labels / Dates / Checklist, the description, and a lighter side panel with comments and activity.
/// There is no Members button: Boto has a single user.
struct CardDetailView: View {
    private enum Chip { case list, add, labels, dates, checklist, colour, importance, blocked, time }

    @Bindable var card: Card
    @State private var popover: Chip?
    @State private var newLabelName = ""
    @State private var blockReason = ""
    @State private var newChecklistName = ""
    @State private var commentText = ""
    @State private var showDetails = true
    @State private var addingGitHub = false
    @State private var calendarError: String?
    @State private var confirmingDelete = false

    private var board: Board? { card.list?.board }
    private var projectRoot: URL? { board?.project?.rootFolderURL }

    /// Accent of the list button, the gold of Trello's list pill.
    private let accent = Theme.warning

    /// The card lives in its own window, so closing means closing that window.
    private func closeWindow() { NSApp.keyWindow?.performClose(nil) }

    /// Width below which the side panel goes under the main column instead of beside it.
    private let wideBreakpoint: CGFloat = 760

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                topBar
                Rectangle().fill(Theme.divider).frame(height: 1)
                if geo.size.width >= wideBreakpoint { wide } else { narrow }
            }
        }
        .frame(minWidth: 460, minHeight: 440)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in add(urls); return !urls.isEmpty }
        // A new window puts keyboard focus, with the text selected, in its first field. Start with nothing focused.
        .background(MovableByBackground())
        .onAppear { DispatchQueue.main.async { NSApp.keyWindow?.makeFirstResponder(nil) } }
    }

    private func isShowing(_ chip: Chip) -> Binding<Bool> {
        Binding(get: { popover == chip }, set: { if !$0 && popover == chip { popover = nil } })
    }

    // MARK: Layout

    private var wide: some View {
        HStack(spacing: 0) {
            ScrollView { mainColumn.padding(28) }.frame(maxWidth: .infinity)
            Rectangle().fill(Theme.divider).frame(width: 1)
            ScrollView { activityPanel.padding(20) }
                .frame(width: 360)
                .background(Theme.list)
        }
    }

    private var narrow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                mainColumn
                activityPanel
            }
            .padding(20)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button { popover = .list } label: {
                HStack(spacing: 6) {
                    Text(card.list?.name ?? "No list").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                }
                .font(Theme.font(15, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(accent.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(accent.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .help("Move to another list")
            .popover(isPresented: isShowing(.list), arrowEdge: .bottom) { listChoices }
            Spacer()
            Menu {
                Button { card.setArchived(!card.isArchived); closeWindow() } label: {
                    Label(card.isArchived ? "Restore" : "Archive",
                          systemImage: card.isArchived ? "arrow.uturn.backward" : "archivebox")
                }
                Divider()
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .labelStyle(.titleAndIcon)
            .fixedSize()
            Button { closeWindow() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close card")
        }
        .foregroundStyle(Theme.mutedStrong)
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var listChoices: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Move card to").font(Theme.font(11, weight: .semibold)).foregroundStyle(Theme.muted).padding(.bottom, 4)
            ForEach(board?.orderedLists ?? []) { list in
                Button {
                    list.place(card, at: list.orderedCards.count)
                    popover = nil
                } label: {
                    HStack {
                        Text(list.name).font(Theme.font(14))
                        Spacer(minLength: 16)
                        if list === card.list { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .rowHighlight()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 220)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    // MARK: Main column

    private var mainColumn: some View {
        VStack(alignment: .leading, spacing: 26) {
            titleRow
            chipsRow
            attachedSummary
            descriptionSection
            checklistsSection
            referencesSection
        }
    }

    private var titleRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Button { card.setCompleted(!card.isCompleted) } label: {
                Image(systemName: card.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(card.isCompleted ? Theme.success : Theme.muted)
            }
            .buttonStyle(.plain)
            .padding(.top, 5)
            .help(card.isCompleted ? "Mark incomplete" : "Mark complete")
            TextField("Title", text: $card.title, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.font(28, weight: .bold))
        }
    }

    private var chipsRow: some View {
        FlowLayout(spacing: 8) {
            chip("Add", "plus", .add) { addChoices }
            chip("Labels", "tag", .labels) { labelsEditor }
            chip("Importance", "exclamationmark.circle", .importance) { importanceChoices }
            chip("Dates", "clock", .dates) { datePicker }
            chip(card.totalSeconds() > 0 ? "Time \(TimeReport.clock(card.totalSeconds()))" : "Time", "hourglass", .time) { TimeForm(card: card) }
            chip(card.isBlocked ? "Blocked" : "Block", card.isBlocked ? "hand.raised.fill" : "hand.raised", .blocked) { blockForm }
            chip("Checklist", "checkmark.square", .checklist) { newChecklistForm }
        }
    }

    private func chip<Content: View>(_ title: String, _ icon: String, _ which: Chip,
                                     @ViewBuilder content: @escaping () -> Content) -> some View {
        Button { popover = which } label: {
            HStack(spacing: 8) { Image(systemName: icon); Text(title) }
                .font(Theme.font(14))
                .foregroundStyle(Theme.mutedStrong)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .rowHighlight()
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isShowing(which), arrowEdge: .bottom, content: content)
    }

    /// Labels and the due date appear under the buttons once they are set, as in Trello.
    @ViewBuilder
    private var attachedSummary: some View {
        if !card.labels.isEmpty || card.dueDate != nil || card.colorHex != nil || card.importance != .unset {
            FlowLayout(spacing: 28) {
                if card.importance != .unset {
                    summaryBlock("Importance") {
                        Button { popover = .importance } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark")
                                Text(card.importance.title)
                            }
                            .font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(Theme.importanceColor(card.importance))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.importanceColor(card.importance).opacity(0.18)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !card.labels.isEmpty {
                    summaryBlock("Labels") {
                        FlowLayout(spacing: 6) {
                            ForEach(card.labels) { label in
                                Button { popover = .labels } label: { LabelChip(label: label) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let due = card.dueDate {
                    summaryBlock("Due date") {
                        Button { popover = .dates } label: {
                            HStack(spacing: 8) {
                                Text(due.formatted(date: .abbreviated, time: .omitted))
                                if due < Calendar.current.startOfDay(for: Date()) {
                                    Text("Overdue")
                                        .font(Theme.font(11, weight: .semibold))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.overdue.opacity(0.25)))
                                        .foregroundStyle(Theme.overdue)
                                }
                            }
                            .font(Theme.font(14))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let hex = card.colorHex {
                    summaryBlock("Colour") {
                        Button { popover = .colour } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: isShowing(.colour), arrowEdge: .bottom) { ColorChoice(hex: $card.colorHex).padding(14) }
                    }
                }
            }
        }
    }

    private func summaryBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func sectionHeader(_ icon: String, _ title: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.mutedStrong).frame(width: 24)
            Text(title).font(Theme.font(17, weight: .semibold))
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("text.alignleft", "Description")
            TextEditor(text: $card.details)
                .font(Theme.font(14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 110)
                .overlay(alignment: .topLeading) {
                    if card.details.isEmpty {
                        Text("Add a more detailed description...").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            .padding(.leading, 13).padding(.top, 8).allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
        }
    }

    @ViewBuilder
    private var checklistsSection: some View {
        let lists = card.checklists.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index }
        ForEach(lists) { ChecklistSection(checklist: $0) }
    }

    @ViewBuilder
    private var referencesSection: some View {
        if !card.references.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader("paperclip", "Attachments")
                    Spacer()
                    Button("Add", action: chooseReferences).buttonStyle(.plain).foregroundStyle(Theme.mutedStrong)
                }
                ForEach(card.references) { reference in
                    ReferenceRow(reference: reference, projectRoot: projectRoot) {
                        card.references.removeAll { $0 === reference }
                    }
                }
                Text("Nothing is copied; Boto only keeps a link. Drop files or folders anywhere on this card to add them.")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Popovers

    private var importanceChoices: some View {
        DropdownPanel(entries: Importance.allCases.map { value in
            DropdownEntry(
                icon: value == .unset ? "minus.circle" : "exclamationmark.circle",
                title: value.title,
                checked: card.importance == value
            ) { card.setImportance(value) }
        }) { popover = nil }
    }

    private var addChoices: some View {
        DropdownPanel(entries: [
            DropdownEntry(icon: "paperclip", title: "File, folder or note...") { chooseReferences() },
            DropdownEntry(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub issue or PR...") { addingGitHub = true },
            DropdownEntry(icon: "paintpalette", title: "Colour...") { popover = .colour },
        ]) { popover = nil }
        .sheet(isPresented: $addingGitHub) { AddGitHubSheet(card: card) }
        .confirmationDialog("Delete this card?", isPresented: $confirmingDelete) {
            Button("Delete card", role: .destructive) { card.deletedAt = Date(); closeWindow() }
        } message: {
            Text("The card disappears from the board. Linked files are not touched. Archive it instead to keep it.")
        }
    }

    private var labelsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labels").font(Theme.font(13, weight: .semibold))
            ForEach(board?.labels.sorted { $0.name < $1.name } ?? []) { LabelRow(label: $0, card: card) }
            HStack {
                TextField("New label", text: $newLabelName).textFieldStyle(.roundedBorder).onSubmit(createLabel)
                Button("Add", action: createLabel).disabled(board == nil)
            }
        }
        .padding(14)
        .frame(width: 280)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private func createLabel() {
        let name = newLabelName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let board else { return }
        let label = KanbanCore.Label(name: name, colourCode: Palette.swatches[board.labels.count % Palette.swatches.count].hex)
        board.labels.append(label)
        card.attach(label)
        newLabelName = ""
    }

    private var datePicker: some View {
        VStack(spacing: 10) {
            DatePicker("", selection: Binding(get: { card.dueDate ?? Date() }, set: { setDue($0) }), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
            if card.dueDate != nil {
                Toggle("Add to Apple Calendar", isOn: Binding(get: { card.calendarEventID != nil }, set: setOnCalendar))
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if card.calendarEventID != nil { calendarOptions }
                if let calendarError {
                    Text(calendarError).font(Theme.font(11)).foregroundStyle(Theme.mutedStrong)
                        .frame(maxWidth: 240, alignment: .leading)
                }
            }
            HStack {
                if card.dueDate == nil {
                    Button("Set due date") { setDue(Calendar.current.startOfDay(for: Date())) }
                } else {
                    Button("Remove") { setDue(nil); popover = nil }
                }
                Spacer()
                Button("Done") { popover = nil }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .preferredColorScheme(.dark)
    }

    private static let alertChoices: [(minutes: Int, title: String)] = [
        (Card.noAlert, "No alert"), (0, "At time"), (5, "5 minutes before"), (10, "10 minutes before"),
        (30, "30 minutes before"), (60, "1 hour before"), (1440, "1 day before"),
    ]

    /// Without a time the event is all-day and "At time" means 9:00.
    @ViewBuilder
    private var calendarOptions: some View {
        Toggle("Set a time", isOn: Binding(
            get: { card.dueTimeMinutes != nil },
            set: { card.dueTimeMinutes = $0 ? 9 * 60 : nil; resync() }
        ))
        .toggleStyle(.checkbox)
        .frame(maxWidth: .infinity, alignment: .leading)
        if let minutes = card.dueTimeMinutes {
            DatePicker("", selection: Binding(
                get: { Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
                set: {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    card.dueTimeMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    resync()
                }
            ), displayedComponents: .hourAndMinute)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        Picker("Alert", selection: Binding(get: { card.alertLeadMinutes ?? 0 }, set: { card.alertLeadMinutes = $0; resync() })) {
            ForEach(Self.alertChoices, id: \.minutes) { Text($0.title).tag($0.minutes) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resync() { runCalendar { try await CalendarSync.shared.sync(card) } }

    /// A card already on the calendar keeps its event in step with the due date.
    private func setDue(_ date: Date?) {
        card.setDueDate(date)
        guard card.calendarEventID != nil else { return }
        runCalendar { date == nil ? try await CalendarSync.shared.remove(card) : try await CalendarSync.shared.sync(card) }
    }

    private func setOnCalendar(_ on: Bool) {
        runCalendar { on ? try await CalendarSync.shared.sync(card) : try await CalendarSync.shared.remove(card) }
    }

    private func runCalendar(_ work: @escaping @MainActor () async throws -> Void) {
        calendarError = nil
        Task { @MainActor in
            do { try await work() } catch { calendarError = error.localizedDescription }
        }
    }

    private var blockForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            if card.isBlocked {
                Text("Blocked").font(Theme.font(13, weight: .semibold))
                if let reason = card.blockedReason { Text(reason).font(Theme.font(12)).foregroundStyle(Theme.mutedStrong) }
                Button("Unblock") { card.unblock(); popover = nil }.keyboardShortcut(.defaultAction)
            } else {
                Text("Block this card").font(Theme.font(13, weight: .semibold))
                TextField("What is it waiting for?", text: $blockReason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(blockCard)
                Button("Block", action: blockCard).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 260)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private func blockCard() {
        card.block(reason: blockReason)
        blockReason = ""
        popover = nil
    }

    private var newChecklistForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add checklist").font(Theme.font(13, weight: .semibold))
            TextField("Title", text: $newChecklistName).textFieldStyle(.roundedBorder).onSubmit(createChecklist)
            Button("Add", action: createChecklist).keyboardShortcut(.defaultAction)
        }
        .padding(14)
        .frame(width: 260)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }

    private func createChecklist() {
        let name = newChecklistName.trimmingCharacters(in: .whitespaces)
        card.checklists.append(Checklist(name: name.isEmpty ? "Checklist" : name, index: card.checklists.count))
        newChecklistName = ""
        popover = nil
    }

    private func chooseReferences() {
        add(FilePanel.choose(files: true, directories: true, multiple: true))
    }

    private func add(_ urls: [URL]) {
        for url in urls where !card.references.contains(where: { $0.displayPath == url.path }) {
            card.references.append(Reference.make(url: url, projectRoot: projectRoot))
        }
    }

    // MARK: Comments and activity

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "text.bubble").font(.system(size: 18)).foregroundStyle(Theme.mutedStrong)
                Text("Comments and activity").font(Theme.font(15, weight: .semibold)).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                Button { showDetails.toggle() } label: {
                    Image(systemName: showDetails ? "eye" : "eye.slash")
                        .frame(width: 32, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.mutedStrong)
                .help(showDetails ? "Hide details: show only comments" : "Show details: also show changes")
            }
            commentBox
            VStack(alignment: .leading, spacing: 16) {
                ForEach(card.timeline.reversed().filter { showDetails || $0.kind == .comment }) { EventRow(event: $0) }
            }
        }
    }

    private var commentBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Write a comment...", text: $commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.font(14))
                .lineLimit(1...6)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            if !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Save") {
                    card.addComment(commentText)
                    commentText = ""
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save comment (⌘↩)")
            }
        }
    }
}

/// A label as a solid chip, like Trello's. Text is light or dark, whichever contrasts more with the colour.
private struct LabelChip: View {
    let label: KanbanCore.Label

    var body: some View {
        let hex = label.colourCode ?? Theme.defaultLabel
        Text(label.name)
            .font(Theme.font(13, weight: .semibold))
            .foregroundStyle(ColorContrast.prefersLightText(onHex: hex) ? Theme.light : Theme.onLight)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: hex)))
    }
}

/// The macOS account name and its initials, shown beside each entry the way Trello shows the member's avatar.
private enum CurrentUser {
    static let name: String = NSFullUserName().isEmpty ? "You" : NSFullUserName()

    static var initials: String {
        let parts = name.split(separator: " ")
        let letters = [parts.first, parts.count > 1 ? parts.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }
}

private struct EventRow: View {
    let event: CardEvent

    private var summary: String {
        switch event.kind {
        case .created: "added this card to \(event.text)"
        case .moved: "moved this card from \(event.text)"
        case .archived: "archived this card"
        case .restored: "restored this card"
        case .dueDateSet: "set the due date to \(event.text)"
        case .dueDateCleared: "removed the due date"
        case .labelAdded: "added the label \(event.text)"
        case .labelRemoved: "removed the label \(event.text)"
        case .completed: "marked this card complete"
        case .reopened: "marked this card incomplete"
        case .importanceChanged: "set the importance to \(event.text)"
        case .blocked: event.text.isEmpty ? "blocked this card" : "blocked this card: \(event.text)"
        case .unblocked: "unblocked this card"
        case .comment: "commented"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(CurrentUser.initials)
                .font(Theme.font(13, weight: .semibold))
                .foregroundStyle(Theme.light)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color(hex: Theme.defaultLabel)))
            VStack(alignment: .leading, spacing: 4) {
                (Text(CurrentUser.name).font(Theme.font(14, weight: .semibold)) + Text(" \(summary)").font(Theme.font(14)))
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.createdAt.formatted(.relative(presentation: .named)))
                    .font(Theme.font(12))
                    .underline()
                    .foregroundStyle(Theme.info)
                if event.kind == .comment {
                    Text(event.text)
                        .font(Theme.font(14))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        .padding(.top, 2)
                }
            }
        }
    }
}

struct LabelRow: View {
    @Bindable var label: KanbanCore.Label
    let card: Card
    @State private var pickingColour = false

    private var isOn: Bool { card.labels.contains { $0 === label } }

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { on in
                    if on { card.attach(label) } else { card.detach(label) }
                }
            ))
            .labelsHidden()
            Button { pickingColour = true } label: {
                Circle().fill(Color(hex: label.colourCode ?? Theme.defaultLabel)).frame(width: 14, height: 14)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $pickingColour) { ColorChoice(hex: $label.colourCode).padding(12) }
            TextField("Label", text: $label.name).textFieldStyle(.plain)
        }
    }
}

struct ChecklistSection: View {
    @Bindable var checklist: Checklist
    @State private var newItem = ""

    private var items: [ChecklistItem] { checklist.items.filter { $0.deletedAt == nil }.sorted { $0.index < $1.index } }
    private var progress: Double {
        items.isEmpty ? 0 : Double(items.filter(\.completed).count) / Double(items.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.square").font(.system(size: 18)).foregroundStyle(Theme.mutedStrong).frame(width: 24)
                InlineEditText(text: $checklist.name, font: Theme.font(17, weight: .semibold), placeholder: "Checklist")
                Spacer(minLength: 8)
                Button("Delete") { checklist.deletedAt = Date() }
                    .buttonStyle(.plain)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.mutedStrong)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.border))
            }
            HStack(spacing: 10) {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted).frame(width: 36, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.card)
                        Capsule().fill(progress == 1 ? Theme.success : Theme.info)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 6)
            }
            ForEach(items) { ChecklistItemRow(item: $0) }
            TextField("Add an item", text: $newItem)
                .textFieldStyle(.plain)
                .font(Theme.font(14))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                .onSubmit {
                    let title = newItem.trimmingCharacters(in: .whitespaces)
                    guard !title.isEmpty else { return }
                    checklist.items.append(ChecklistItem(title: title, index: checklist.items.count))
                    newItem = ""
                }
        }
    }
}

struct ChecklistItemRow: View {
    @Bindable var item: ChecklistItem

    var body: some View {
        HStack {
            Toggle("", isOn: $item.completed).labelsHidden()
            TextField("Item", text: $item.title)
                .textFieldStyle(.plain)
                .strikethrough(item.completed)
                .foregroundStyle(item.completed ? Theme.muted : Theme.text)
            Button { item.deletedAt = Date() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                .accessibilityLabel("Delete checklist item")
        }
    }
}

struct ReferenceRow: View {
    let reference: Reference
    let projectRoot: URL?
    let onRemove: () -> Void

    @State private var refreshMessage: String?

    private var resolved: URL? { reference.resolvedURL(projectRoot: projectRoot) }

    private var icon: String {
        switch reference.kind {
        case .file: "doc"
        case .folder: "folder"
        case .obsidianNote: "note.text"
        case .githubIssue: "smallcircle.filled.circle"
        case .githubPullRequest: "arrow.triangle.pull"
        case .email: "envelope"
        }
    }

    private var title: String {
        reference.kind.isRemote
            ? (reference.remoteTitle ?? reference.displayPath)
            : URL(fileURLWithPath: reference.displayPath).lastPathComponent
    }

    private var subtitle: String {
        if let refreshMessage { return refreshMessage }
        if reference.kind == .email {
            return ["From email", reference.remoteState].compactMap { $0 }.joined(separator: " - ")
        }
        if reference.kind.isGitHub {
            let slug = GitHubLink.parse(reference.displayPath)?.slug ?? reference.displayPath
            return [slug, reference.remoteState].compactMap { $0 }.joined(separator: " - ")
        }
        if resolved == nil { return "Missing: \(reference.displayPath)" }
        return reference.vaultName.map { "Vault: \($0)" } ?? reference.displayPath
    }

    private var isProblem: Bool { refreshMessage != nil || resolved == nil }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(isProblem ? Theme.overdue : Theme.mutedStrong)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(13)).lineLimit(2)
                Text(subtitle)
                    .font(Theme.font(10))
                    .foregroundStyle(isProblem ? Theme.overdue : Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("Open", action: open).disabled(resolved == nil)
            if reference.kind.isGitHub {
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }.help("Refresh from GitHub")
            } else if reference.kind != .email {
                Button { if let resolved { NSWorkspace.shared.activateFileViewerSelecting([resolved]) } } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Reveal in Finder")
                .disabled(resolved == nil)
            }
            Button(action: onRemove) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.muted)
        }
    }

    private func refresh() {
        guard let link = GitHubLink.parse(reference.displayPath) else { return }
        refreshMessage = nil
        Task {
            do { reference.apply(try await GitHubAccess.client().fetch(link)) }
            catch { refreshMessage = error.localizedDescription }
        }
    }

    private func open() {
        if let url = reference.obsidianURL, NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
        } else if let resolved {
            NSWorkspace.shared.open(resolved)
        }
    }
}
