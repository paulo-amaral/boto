import KanbanCore
import SwiftUI

struct LabelBadge: View {
    let name: String
    let colourCode: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: colourCode ?? Theme.defaultLabel)).frame(width: 8, height: 8)
            Text(name).font(Theme.font(10, weight: .medium))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(Theme.muted, lineWidth: 1))
        .foregroundStyle(Theme.text)
    }
}

struct ChecklistProgress: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(Theme.border, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(Double(done) / Double(max(total, 1)), 0.02))
                    .stroke(Theme.mutedStrong, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            Text("\(done)/\(total)").font(Theme.font(10)).foregroundStyle(Theme.mutedStrong)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 1))
    }
}

public struct CardView: View {
    let card: Card
    let isSelected: Bool
    @State private var hovering = false

    public init(card: Card, isSelected: Bool = false) {
        self.card = card
        self.isSelected = isSelected
    }

    private var isOverdue: Bool {
        guard let due = card.dueDate else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }

    private var hasFooter: Bool {
        !card.details.isEmpty || card.dueDate != nil || !card.references.isEmpty
            || card.checklistProgress.total > 0 || card.importance != .unset || card.isBlocked || card.totalSeconds() > 0
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if card.isCompleted {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(Color(hex: "#4bce97"))
                }
                Text(card.title)
                    .font(Theme.font(12))
                    .foregroundStyle(card.isCompleted ? Theme.mutedStrong : Theme.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !card.labels.isEmpty {
                HStack(spacing: 2) {
                    ForEach(card.labels) { LabelBadge(name: $0.name, colourCode: $0.colourCode) }
                }
            }

            if hasFooter {
                // Items wrap to a new line whole, so a narrow list never splits "Blocked" or "4/4" across lines.
                FlowLayout(spacing: 8) {
                    if card.isBlocked {
                        Label("Blocked", systemImage: "hand.raised.fill")
                            .font(Theme.font(11, weight: .medium))
                            .foregroundStyle(Theme.overdue)
                            .help(card.blockedReason ?? "Blocked")
                            .fixedSize()
                    }
                    if card.importance != .unset {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.importanceColor(card.importance))
                            .help("Importance: \(card.importance.title)")
                    }
                    if !card.details.isEmpty {
                        Image(systemName: "text.alignleft")
                    }
                    if let due = card.dueDate {
                        Label(due.formatted(.dateTime.day().month(.abbreviated)), systemImage: "clock")
                            .font(Theme.font(11))
                            .foregroundStyle(isOverdue ? Theme.overdue : Theme.muted)
                    }
                    if !card.references.isEmpty {
                        Label("\(card.references.count)", systemImage: "paperclip")
                            .font(Theme.font(11))
                    }
                    if card.totalSeconds() > 0 {
                        Label(TimeReport.clock(card.totalSeconds()), systemImage: card.runningTimer == nil ? "hourglass" : "timer")
                            .font(Theme.font(11))
                            .foregroundStyle(card.runningTimer == nil ? Theme.muted : Color(hex: "#6c8cff"))
                            .fixedSize()
                    }
                    let progress = card.checklistProgress
                    if progress.total > 0 {
                        ChecklistProgress(done: progress.done, total: progress.total).fixedSize()
                    }
                }
                .foregroundStyle(Theme.muted)
                .font(Theme.font(11))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(hovering ? Theme.cardHover : Theme.card)
                if let hex = card.colorHex {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Color(hex: hex).opacity(0.22))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius)
                .strokeBorder(
                    isSelected ? Theme.text : (card.colorHex.map { Color(hex: $0).opacity(0.55) } ?? .clear),
                    lineWidth: isSelected ? 2 : 1
                )
        )
        .onHover { hovering = $0 }
        .opacity(card.isArchived ? 0.55 : 1)
        .overlay(alignment: .topTrailing) {
            if card.isArchived {
                Image(systemName: "archivebox").font(.system(size: 10)).foregroundStyle(Theme.muted).padding(6)
            }
        }
    }
}
