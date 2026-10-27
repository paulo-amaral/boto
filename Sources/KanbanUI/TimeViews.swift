import AppKit
import KanbanCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Date, duration and what was done. Shared by the card and the project report; `onAdd` receives seconds, day and note.
/// The duration is typed ("1:30", "1.5", "90m", "2h30"), as in the timesheet, and Return in either field adds the entry.
struct TimeEntryFields: View {
    let onAdd: (Int, Date, String) -> Void
    @State private var day = Date()
    @State private var duration = ""
    @State private var note = ""

    private var seconds: Int? { DurationParser.seconds(from: duration).flatMap { $0 > 0 ? $0 : nil } }
    private var showsHint: Bool { !duration.trimmingCharacters(in: .whitespaces).isEmpty && seconds == nil }

    private func add() {
        guard let seconds else { return }
        onAdd(seconds, day, note)
        duration = ""
        note = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DatePicker("Date", selection: $day, displayedComponents: .date).labelsHidden().fixedSize()
                TextField("Time, e.g. 1:30", text: $duration)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit(add)
            }
            TextField("What did you work on?", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .onSubmit(add)
            HStack {
                if showsHint {
                    Text("Use 1:30, 1.5, 90m or 2h30, up to 24 hours.").font(Theme.font(11)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Add", action: add).disabled(seconds == nil)
            }
        }
        .font(Theme.font(12))
    }
}

/// Timer, manual entries and the log for one card; shown in a popover from the card detail.
struct TimeForm: View {
    @Bindable var card: Card
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                HStack {
                    Text(TimeReport.clock(card.totalSeconds(at: timeline.date))).font(Theme.font(20, weight: .bold))
                    Text("total").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    Spacer()
                    if card.runningTimer == nil {
                        Button { card.startTimer(in: context) } label: { Label("Start", systemImage: "play.fill") }
                    } else {
                        Button { card.stopTimer() } label: { Label("Stop", systemImage: "stop.fill") }
                    }
                }
            }
            Divider()
            Text("Add time worked").font(Theme.font(13, weight: .semibold))
            TimeEntryFields { seconds, day, note in card.logTime(seconds: seconds, on: day, note: note) }

            if !card.liveTimeEntries.isEmpty {
                Divider()
                ForEach(card.liveTimeEntries, id: \.publicId) { entry in
                    HStack {
                        Text(entry.day.formatted(.dateTime.day().month(.abbreviated))).foregroundStyle(Theme.muted)
                        Text(entry.isRunning ? "running" : TimeReport.clock(entry.seconds))
                        if !entry.note.isEmpty { Text(entry.note).foregroundStyle(Theme.muted).lineLimit(1) }
                        Spacer()
                        Button { entry.stop(); entry.deletedAt = Date() } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .help("Delete this entry")
                    }
                    .font(Theme.font(12))
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}

/// Hours per project between two dates, by day and by card, with a CSV export for invoicing.
/// Asks where to save, then writes the CSV. Shared by the report and the timesheet.
@MainActor
private func saveCSV(_ text: String, named name: String) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.commaSeparatedText]
    panel.nameFieldStringValue = name
    guard panel.runModal() == .OK, let url = panel.url else { return }
    try? text.write(to: url, atomically: true, encoding: .utf8)
}

struct TimeReportView: View {
    let project: Project
    @State private var from = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    @State private var to = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.end.addingTimeInterval(-1) ?? Date()
    @State private var target: Card?
    @State private var showingForm = false

    private let calendar = Calendar.current

    private func range(_ component: Calendar.Component, offset: Int) -> (start: Date, end: Date)? {
        guard let current = calendar.dateInterval(of: component, for: Date()),
              let start = calendar.date(byAdding: component, value: offset, to: current.start),
              let end = calendar.dateInterval(of: component, for: start)?.end else { return nil }
        return (start, end.addingTimeInterval(-1))
    }

    private func presetButton(_ title: String, _ component: Calendar.Component, offset: Int) -> some View {
        let period = range(component, offset: offset)
        let selected = period.map { calendar.isDate(from, inSameDayAs: $0.start) && calendar.isDate(to, inSameDayAs: $0.end) } ?? false
        return Button(title) {
            if let period { from = period.start; to = period.end }
        }
        .buttonStyle(.plain)
        .font(Theme.font(12, weight: .medium))
        .foregroundStyle(selected ? Theme.text : Theme.mutedStrong)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Theme.border : Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var body: some View {
        let report = TimeReport(project: project, from: from, to: to)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 6) {
                    presetButton("This week", .weekOfYear, offset: 0)
                    presetButton("Last week", .weekOfYear, offset: -1)
                    presetButton("This month", .month, offset: 0)
                    presetButton("Last month", .month, offset: -1)
                    Spacer()
                    DatePicker("From", selection: $from, displayedComponents: .date).fixedSize()
                    DatePicker("To", selection: $to, displayedComponents: .date).fixedSize()
                }
                .font(Theme.font(12))

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TimeReport.clock(report.totalSeconds)).font(Theme.font(26, weight: .bold))
                    Text("hours in this period").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Button { showingForm.toggle() } label: { Label("Add time", systemImage: showingForm ? "minus" : "plus") }
                    Button { saveCSV(report.csv, named: "\(project.name) hours.csv") } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                        .disabled(report.rows.isEmpty)
                }

                if showingForm {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("On", selection: $target) {
                            Text("The project (no card)").tag(Card?.none)
                            ForEach(project.timeableCards, id: \.publicId) { Text($0.title).tag(Card?.some($0)) }
                        }
                        .font(Theme.font(12))
                        TimeEntryFields { seconds, day, note in
                            if let target { target.logTime(seconds: seconds, on: day, note: note) }
                            else { project.logTime(seconds: seconds, on: day, note: note) }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
                }

                if report.rows.isEmpty {
                    Text("No time logged in this period. Add time above, or use a card's Time button.")
                        .font(Theme.font(12)).foregroundStyle(Theme.muted)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        panel("By day") {
                            let longest = report.byDay.map(\.seconds).max() ?? 1
                            ForEach(report.byDay, id: \.day) { entry in
                                barLine(entry.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), entry.seconds, of: longest)
                            }
                        }
                        panel("By card") {
                            let longest = report.byCard.map(\.seconds).max() ?? 1
                            ForEach(report.byCard, id: \.title) { barLine($0.title, $0.seconds, of: longest) }
                        }
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Entries").font(Theme.font(13, weight: .semibold))
                        ForEach(report.byDay, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(group.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                                    Spacer()
                                    Text(TimeReport.clock(group.seconds))
                                }
                                .font(Theme.font(11, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .padding(.trailing, ReportEntryLine.deleteColumnWidth)
                                Divider()
                                ForEach(report.rows.filter { $0.day == group.day }, id: \.entry.publicId) { ReportEntryLine(row: $0) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    private func panel<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.font(13, weight: .semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    /// A label and its time, with a bar sized against the longest line of the same list.
    private func barLine(_ title: String, _ seconds: Int, of longest: Int) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(Theme.font(12)).lineLimit(1)
                Spacer()
                Text(TimeReport.clock(seconds)).font(Theme.font(12, weight: .medium)).foregroundStyle(Theme.mutedStrong)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.divider)
                    Capsule().fill(Color.accentColor).frame(width: geometry.size.width * CGFloat(seconds) / CGFloat(max(longest, 1)))
                }
            }
            .frame(height: 4)
        }
    }
}

/// One logged entry. The delete button appears on hover so a stray click on a quiet row cannot remove time.
private struct ReportEntryLine: View {
    /// The delete button's width plus the gap before it, so day subtotals line up with the entry times.
    static let deleteColumnWidth: CGFloat = 22
    let row: TimeReport.Row
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.note.isEmpty ? row.cardTitle : row.note).lineLimit(2)
                if !row.note.isEmpty {
                    Text(row.cardTitle).font(Theme.font(11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            Text(TimeReport.clock(row.seconds)).foregroundStyle(Theme.mutedStrong)
            Button { row.entry.stop(); row.entry.deletedAt = Date() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .opacity(hovering ? 1 : 0)
                .help("Delete this entry")
                .accessibilityLabel("Delete this entry")
        }
        .font(Theme.font(12))
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// The Hours window: a weekly timesheet, or a report over any period.
struct HoursView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var showingReport = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Hours: \(project.name)").font(Theme.font(16, weight: .semibold)).lineLimit(1)
                Spacer()
                Picker("View", selection: $showingReport) {
                    Text("Timesheet").tag(false)
                    Text("Report").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)

            if showingReport { TimeReportView(project: project) } else { TimesheetView(project: project) }
        }
        .frame(width: 820, height: 620)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

/// A week at a time: a row per task, a column per day. Click a cell to see and edit what makes up that day.
struct TimesheetView: View {
    let project: Project
    @State private var weekDate = Date()
    @State private var extraCards: [Card] = []

    private let calendar = Calendar.current
    private let dayWidth: CGFloat = 62

    private func move(weeks: Int) {
        weekDate = calendar.date(byAdding: .weekOfYear, value: weeks, to: weekDate) ?? weekDate
        extraCards = []
    }

    private func zeroOrClock(_ seconds: Int) -> String { seconds == 0 ? "·" : TimeReport.clock(seconds) }

    var body: some View {
        let sheet = Timesheet(project: project, weekContaining: weekDate, extraCards: extraCards)
        let shown = Set(sheet.rows.compactMap { $0.card?.publicId })
        let addable = project.timeableCards.filter { !shown.contains($0.publicId) }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Button { move(weeks: -1) } label: { Image(systemName: "chevron.left") }.help("Previous week")
                    Text("\(sheet.days[0].formatted(.dateTime.day().month(.abbreviated))) to \(sheet.days[6].formatted(.dateTime.day().month(.abbreviated).year()))")
                        .font(Theme.font(14, weight: .semibold))
                    Button { move(weeks: 1) } label: { Image(systemName: "chevron.right") }.help("Next week")
                    Button("This week") { weekDate = Date(); extraCards = [] }
                    Spacer()
                    Menu {
                        ForEach(addable, id: \.publicId) { card in Button(card.title) { extraCards.append(card) } }
                    } label: { Label("Add task", systemImage: "plus") }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(addable.isEmpty)
                    Button {
                        let name = sheet.days[0].formatted(.iso8601.year().month().day())
                        saveCSV(sheet.csv, named: "\(project.name) timesheet \(name).csv")
                    } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .disabled(sheet.grandTotal == 0)
                }

                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Text("Task").frame(width: 190, alignment: .leading)
                        ForEach(sheet.days, id: \.self) { day in
                            VStack(spacing: 0) {
                                Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                Text(day.formatted(.dateTime.day())).foregroundStyle(Theme.muted)
                            }
                            .frame(width: dayWidth)
                            .foregroundStyle(calendar.isDateInToday(day) ? Theme.text : Theme.mutedStrong)
                        }
                        Text("Total").frame(width: dayWidth)
                    }
                    .font(Theme.font(11, weight: .semibold))
                    Divider().gridCellColumns(9)

                    ForEach(sheet.rows.indices, id: \.self) { index in
                        let row = sheet.rows[index]
                        GridRow {
                            Text(row.title)
                                .font(Theme.font(12))
                                .foregroundStyle(row.card == nil ? Theme.mutedStrong : Theme.text)
                                .lineLimit(1)
                                .help(row.title)
                                .frame(width: 190, alignment: .leading)
                            ForEach(sheet.days.indices, id: \.self) { dayIndex in
                                TimesheetCell(row: row, day: sheet.days[dayIndex], dayIndex: dayIndex, width: dayWidth)
                            }
                            Text(zeroOrClock(row.total))
                                .font(Theme.font(12, weight: .semibold))
                                .foregroundStyle(row.total == 0 ? Theme.muted : Theme.text)
                                .frame(width: dayWidth)
                        }
                    }

                    Divider().gridCellColumns(9)
                    GridRow {
                        Text("Total").frame(width: 190, alignment: .leading)
                        ForEach(sheet.columnTotals.indices, id: \.self) { Text(zeroOrClock(sheet.columnTotals[$0])).frame(width: dayWidth) }
                        Text(TimeReport.clock(sheet.grandTotal)).frame(width: dayWidth)
                    }
                    .font(Theme.font(12, weight: .semibold))
                }

                Text("Click a cell to add, change or delete what you did that day. Time can be typed as 1:30, 1.5, 90m or 2h30.")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }
}

private struct TimesheetCell: View {
    let row: Timesheet.Row
    let day: Date
    let dayIndex: Int
    let width: CGFloat
    @State private var open = false

    var body: some View {
        let seconds = row.seconds[dayIndex]
        Button { open = true } label: {
            Text(seconds == 0 ? "·" : TimeReport.clock(seconds))
                .font(Theme.font(12))
                .foregroundStyle(seconds == 0 ? Theme.muted : Theme.text)
                .frame(width: width, height: 28)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(seconds == 0 ? Theme.list : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius)
                    .strokeBorder(Calendar.current.isDateInToday(day) ? Theme.border : .clear))
        }
        .buttonStyle(.plain)
        .help("\(row.title), \(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))")
        .popover(isPresented: $open, arrowEdge: .bottom) { TimeCellEditor(row: row, day: day, entries: row.entries[dayIndex]) }
    }
}

/// What one task has on one day: every entry with its duration and description, and a line to add another.
private struct TimeCellEditor: View {
    let row: Timesheet.Row
    let day: Date
    let entries: [TimeEntry]
    @State private var duration = ""
    @State private var note = ""

    private var parsed: Int? { DurationParser.seconds(from: duration).flatMap { $0 > 0 ? $0 : nil } }

    private func add() {
        guard let seconds = parsed else { return }
        row.addEntry(on: day, seconds: seconds, note: note)
        duration = ""
        note = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(Theme.font(13, weight: .semibold)).lineLimit(1)
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
            ForEach(entries, id: \.publicId) { EntryEditRow(entry: $0) }
            if !entries.isEmpty { Divider() }
            HStack(spacing: 8) {
                TextField("1:30", text: $duration).frame(width: 64).onSubmit(add)
                TextField("What did you work on?", text: $note).onSubmit(add)
                Button("Add", action: add).disabled(parsed == nil)
            }
            .textFieldStyle(.roundedBorder)
            .font(Theme.font(12))
        }
        .padding(14)
        .frame(width: 380)
        .foregroundStyle(Theme.text)
        .preferredColorScheme(.dark)
    }
}

private struct EntryEditRow: View {
    @Bindable var entry: TimeEntry
    @State private var text = ""
    @FocusState private var focused: Bool

    private func commit() {
        if let seconds = DurationParser.seconds(from: text) {
            if seconds == 0 { entry.deletedAt = Date() } else { entry.seconds = seconds }
        }
        text = TimeReport.clock(entry.seconds)
    }

    var body: some View {
        HStack(spacing: 8) {
            if entry.isRunning {
                Text("running").font(Theme.font(12)).foregroundStyle(Color(hex: "#6c8cff")).frame(width: 64, alignment: .leading)
                Button("Stop") { entry.stop() }
            } else {
                TextField("0:00", text: $text)
                    .frame(width: 64)
                    .focused($focused)
                    .onSubmit(commit)
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            }
            TextField("What did you work on?", text: $entry.note)
            Button { entry.stop(); entry.deletedAt = Date() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Delete this entry")
        }
        .textFieldStyle(.roundedBorder)
        .font(Theme.font(12))
        .onAppear { text = TimeReport.clock(entry.seconds) }
    }
}
