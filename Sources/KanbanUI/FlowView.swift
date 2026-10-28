import Charts
import KanbanCore
import SwiftUI

/// Count in the list header; turns red when the soft WIP limit is exceeded.
struct WIPBadge: View {
    let list: BoardList

    var body: some View {
        let count = list.wipCount
        Text(list.wipLimit.map { "\(count)/\($0)" } ?? "\(count)")
            .font(Theme.font(11, weight: .medium))
            .foregroundStyle(list.isOverWIPLimit ? Theme.overdue : Theme.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(list.isOverWIPLimit ? Theme.overdue : Theme.border, lineWidth: 1))
            .help(list.isOverWIPLimit ? "Over the WIP limit of \(list.wipLimit ?? 0). Finish something before starting more." : "Cards in this list")
    }
}

struct ListFlowSheet: View {
    @Bindable var list: BoardList
    @Environment(\.dismiss) private var dismiss
    @State private var limit = 0
    @State private var policy = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Flow settings for \"\(list.name)\"").font(Theme.font(16, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Stage").font(Theme.font(12, weight: .medium))
                Picker("Stage", selection: Binding(get: { list.stage }, set: { list.setStage($0) })) {
                    ForEach(ListStage.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("Cycle time starts when a card enters an In progress list and stops when it enters a Done list.")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 4) {
                Stepper(value: $limit, in: 0...99) {
                    Text(limit == 0 ? "WIP limit: none" : "WIP limit: \(limit)").font(Theme.font(12, weight: .medium))
                }
                Text("A soft limit: you can go over it, and the count turns red. Personal Kanban suggests 1 to 3 items in progress.")
                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Policy").font(Theme.font(12, weight: .medium))
                TextField("When is a card ready to leave this list?", text: $policy, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    list.setWIPLimit(limit)
                    list.setPolicy(policy)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 400)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            limit = list.wipLimit ?? 0
            policy = list.policy ?? ""
        }
    }
}

struct FlowView: View {
    let board: Board
    @Environment(\.dismiss) private var dismiss

    private func days(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value < 10 ? String(format: "%.1f d", value) : String(format: "%.0f d", value)
    }

    var body: some View {
        let metrics = FlowMetrics(board: board)
        VStack(spacing: 0) {
            HStack {
                Text("Flow").font(Theme.font(16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(22)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        stat("In progress", "\(metrics.wip)", note: "right now")
                        stat("Finished", "\(metrics.finishedInWindow)", note: "last 8 weeks")
                        stat("Median cycle", days(metrics.medianCycleDays), note: "start to finish")
                        stat("85% within", metrics.sleDays.map { "\($0) d" } ?? "-", note: "your service level")
                    }

                    KaizenSection(board: board, metrics: metrics)

                    section("Throughput per week") {
                        if metrics.finishedInWindow == 0 {
                            empty("Move cards to a Done list to see how many you finish each week.")
                        } else {
                            Chart(metrics.throughput, id: \.weekStart) {
                                BarMark(x: .value("Week", $0.weekStart, unit: .weekOfYear), y: .value("Cards", $0.count))
                                    .foregroundStyle(Theme.mutedStrong)
                            }
                            .frame(height: 120)
                        }
                    }

                    section("Cumulative flow, last 30 days") {
                        Chart {
                            ForEach(metrics.cumulativeFlow, id: \.day) { point in
                                AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Cards", point.done), series: .value("Stage", "Done"))
                                    .foregroundStyle(by: .value("Stage", "Done"))
                                AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Cards", point.inProgress), series: .value("Stage", "In progress"))
                                    .foregroundStyle(by: .value("Stage", "In progress"))
                                AreaMark(x: .value("Day", point.day, unit: .day), y: .value("Cards", point.notStarted), series: .value("Stage", "Not started"))
                                    .foregroundStyle(by: .value("Stage", "Not started"))
                            }
                        }
                        .chartForegroundStyleScale(["Done": Theme.success, "In progress": Theme.info, "Not started": Theme.border])
                        .frame(height: 140)
                        Text("A band that keeps widening means work is piling up in that stage.")
                            .font(Theme.font(11)).foregroundStyle(Theme.muted)
                    }

                    section("Oldest work in progress") {
                        if metrics.aging.isEmpty {
                            empty("Nothing in progress.")
                        } else {
                            ForEach(Array(metrics.aging.prefix(6)), id: \.card.publicId) { item in
                                HStack {
                                    Text(item.card.title).font(Theme.font(12)).lineLimit(1)
                                    Spacer()
                                    Text(days(item.ageDays))
                                        .font(Theme.font(12, weight: .medium))
                                        .foregroundStyle(item.exceedsSLE ? Theme.overdue : Theme.muted)
                                }
                            }
                            if metrics.sleDays != nil {
                                Text("Red: older than 85% of the cards you have finished.")
                                    .font(Theme.font(11)).foregroundStyle(Theme.muted)
                            }
                        }
                    }

                    if !metrics.blocked.isEmpty || !metrics.overLimitLists.isEmpty {
                        section("Needs attention") {
                            ForEach(metrics.blocked, id: \.publicId) {
                                Label("\($0.title)" + ($0.blockedReason.map { ": \($0)" } ?? ""), systemImage: "hand.raised.fill")
                                    .font(Theme.font(12)).foregroundStyle(Theme.overdue)
                            }
                            ForEach(metrics.overLimitLists, id: \.publicId) {
                                Label("\($0.name) is over its limit (\($0.wipCount)/\($0.wipLimit ?? 0))", systemImage: "exclamationmark.triangle")
                                    .font(Theme.font(12)).foregroundStyle(Theme.overdue)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
        }
        .frame(minWidth: 520, idealWidth: 620, minHeight: 480, idealHeight: 700)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func stat(_ title: String, _ value: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.font(11)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.font(20, weight: .bold))
            Text(note).font(Theme.font(11)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Theme.font(13, weight: .semibold))
            content()
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).font(Theme.font(12)).foregroundStyle(Theme.muted)
    }
}

/// The weekly look: compare this week with the last, review experiments that are due, and start a new one.
private struct KaizenSection: View {
    let board: Board
    let metrics: FlowMetrics
    @State private var adding = false

    private var thisWeek: Int { metrics.throughput.last?.count ?? 0 }
    private var lastWeek: Int { metrics.throughput.dropLast().last?.count ?? 0 }

    var body: some View {
        let items = board.orderedImprovements
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Kaizen: small experiments").font(Theme.font(13, weight: .semibold))
                Spacer()
                Button { adding = true } label: { Label("New experiment", systemImage: "plus") }
            }
            Text("Finished \(thisWeek) this week and \(lastWeek) last week. Pick one thing that slowed you down, try a small change, and review it on a date.")
                .font(Theme.font(11)).foregroundStyle(Theme.muted)
            if items.isEmpty {
                Text("No experiments yet. Example: \"Cards wait too long in Doing\", try \"limit Doing to 2 cards\".")
                    .font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
            ForEach(items, id: \.publicId) { ImprovementRow(improvement: $0) }
        }
        .sheet(isPresented: $adding) { NewImprovementSheet(board: board) }
    }
}

private struct ImprovementRow: View {
    @Bindable var improvement: Improvement
    @State private var result = ""

    var body: some View {
        let due = improvement.isDueForReview()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(improvement.problem).font(Theme.font(12, weight: .medium))
                Spacer()
                Text(due ? "Review due" : improvement.status == .running
                     ? "Review \(improvement.reviewDate.formatted(.dateTime.day().month(.abbreviated)))"
                     : improvement.status.title)
                    .font(Theme.font(11))
                    .foregroundStyle(due ? Theme.overdue : Theme.muted)
            }
            Text("Try: \(improvement.experiment)").font(Theme.font(12)).foregroundStyle(Theme.mutedStrong)
            if !improvement.expected.isEmpty {
                Text("Expect: \(improvement.expected)").font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
            if let outcome = improvement.result {
                Text("Learned: \(outcome)").font(Theme.font(11)).foregroundStyle(Theme.muted)
            }
            if improvement.status == .running {
                HStack(spacing: 8) {
                    TextField("What happened?", text: $result).textFieldStyle(.roundedBorder)
                    ForEach([ImprovementStatus.adopted, .adjusted, .dropped], id: \.self) { outcome in
                        Button(outcome.title) { improvement.conclude(outcome, result: result) }
                    }
                }
                .font(Theme.font(11))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.card))
    }
}

private struct NewImprovementSheet: View {
    let board: Board
    @Environment(\.dismiss) private var dismiss
    @State private var problem = ""
    @State private var experiment = ""
    @State private var expected = ""
    @State private var days = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New experiment").font(Theme.font(16, weight: .semibold))
            field("What slowed you down?", "Plan: the problem you saw", $problem)
            field("What will you change?", "Do: one small change", $experiment)
            field("What do you expect?", "Check: how you will know it worked", $expected)
            Stepper("Review in \(days) days", value: $days, in: 1...30).font(Theme.font(12))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start") {
                    board.addImprovement(problem: problem, experiment: experiment, expected: expected, reviewInDays: days)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem.trimmingCharacters(in: .whitespaces).isEmpty || experiment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 420)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    private func field(_ title: String, _ prompt: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.font(12, weight: .medium))
            TextField(prompt, text: text, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
        }
    }
}
