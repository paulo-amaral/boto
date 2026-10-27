import Foundation

/// Where a list sits in the flow of work. Cycle time runs from a card entering an active list to entering a done list.
public enum ListStage: String, CaseIterable, Codable, Sendable {
    case backlog, active, done

    public var title: String {
        switch self {
        case .backlog: "Not started"
        case .active: "In progress"
        case .done: "Done"
        }
    }
}

extension BoardList {
    /// The chosen stage, or by position when none was chosen: first list not started, last list done, the rest in progress.
    public var stage: ListStage {
        if let chosen = stageRaw.flatMap(ListStage.init(rawValue:)) { return chosen }
        guard let lists = board?.orderedLists, lists.count > 1, let index = lists.firstIndex(where: { $0 === self }) else {
            return .active
        }
        if index == 0 { return .backlog }
        return index == lists.count - 1 ? .done : .active
    }

    public func setStage(_ stage: ListStage?) { stageRaw = stage?.rawValue }

    /// Cards counted against the limit: not deleted, not archived.
    public var wipCount: Int { visibleCards(showArchived: false).count }

    public var isOverWIPLimit: Bool { wipLimit.map { wipCount > $0 } ?? false }

    /// A limit of zero or less means no limit.
    public func setWIPLimit(_ limit: Int?) { wipLimit = (limit ?? 0) > 0 ? limit : nil }

    public func setPolicy(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        policy = trimmed.isEmpty ? nil : trimmed
    }
}

extension Card {
    /// Keeps the flow timestamps in step with the stage of the list the card was just put in. Safe to repeat: moving
    /// between two lists of the same stage changes nothing, and moving back to "not started" restarts the clock.
    func enter(_ list: BoardList, at now: Date = Date()) {
        switch list.stage {
        case .backlog:
            startedAt = nil
            finishedAt = nil
        case .active:
            startedAt = startedAt ?? now
            finishedAt = nil
        case .done:
            startedAt = startedAt ?? now
            finishedAt = finishedAt ?? now
        }
    }

    public var isBlocked: Bool { blockedAt != nil }

    public func block(reason: String) {
        guard !isBlocked else { return }
        blockedAt = Date()
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        blockedReason = trimmed.isEmpty ? nil : trimmed
        record(.blocked, trimmed)
    }

    public func unblock() {
        guard isBlocked else { return }
        record(.unblocked, blockedReason ?? "")
        blockedAt = nil
        blockedReason = nil
    }
}

/// The Kanban Guide's four minimum flow measures (WIP, throughput, work item age, cycle time), plus a service level
/// expectation from the 85th percentile of cycle time and a cumulative flow. Only cards with real timestamps count:
/// imported work and work that never started are left out rather than guessed.
public struct FlowMetrics {
    public struct AgingItem {
        public let card: Card
        public let ageDays: Double
        public let exceedsSLE: Bool
    }

    public struct WeekCount: Equatable {
        public let weekStart: Date
        public let count: Int
    }

    public struct DayCount: Equatable {
        public let day: Date
        public let notStarted: Int
        public let inProgress: Int
        public let done: Int
    }

    public let wip: Int
    /// Oldest week first; the last entry is the current week.
    public let throughput: [WeekCount]
    /// Days from start to finish for cards finished in the window, ascending.
    public let cycleTimeDays: [Double]
    /// Oldest first in progress cards, with the SLE check.
    public let aging: [AgingItem]
    public let blocked: [Card]
    public let overLimitLists: [BoardList]
    public let cumulativeFlow: [DayCount]

    public var finishedInWindow: Int { cycleTimeDays.count }
    public var averageCycleDays: Double? { cycleTimeDays.isEmpty ? nil : cycleTimeDays.reduce(0, +) / Double(cycleTimeDays.count) }
    public var medianCycleDays: Double? { Self.percentile(50, of: cycleTimeDays) }

    /// "85% of cards finish within this many days", rounded up to whole days, at least 1. Needs finished cards.
    public var sleDays: Int? { Self.percentile(85, of: cycleTimeDays).map { max(1, Int($0.rounded(.up))) } }

    /// Nearest-rank percentile of an ascending list.
    static func percentile(_ p: Double, of sorted: [Double]) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public init(board: Board, now: Date = Date(), calendar: Calendar = .current, weeks: Int = 8, flowDays: Int = 30) {
        let lists = board.lists.filter { $0.deletedAt == nil }
        let cards = lists.flatMap { $0.cards.filter { $0.deletedAt == nil } }
        let activeCards = lists.filter { $0.stage == .active && !$0.isArchived }
            .flatMap { $0.visibleCards(showArchived: false) }
        wip = activeCards.count
        blocked = lists.filter { !$0.isArchived }.flatMap { $0.visibleCards(showArchived: false) }.filter(\.isBlocked)
        overLimitLists = lists.filter { !$0.isArchived && $0.isOverWIPLimit }

        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let firstWeek = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let finished = cards.compactMap { card -> (start: Date, end: Date)? in
            guard let start = card.startedAt, let end = card.finishedAt, end >= start else { return nil }
            return (start, end)
        }

        throughput = (0..<weeks).map { offset in
            let start = calendar.date(byAdding: .weekOfYear, value: offset, to: firstWeek) ?? firstWeek
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return WeekCount(weekStart: start, count: finished.filter { $0.end >= start && $0.end < end }.count)
        }
        let times = finished.filter { $0.end >= firstWeek }.map { $0.end.timeIntervalSince($0.start) / 86_400 }.sorted()
        cycleTimeDays = times

        let sle = Self.percentile(85, of: times)
        aging = activeCards.compactMap { card -> AgingItem? in
            guard let start = card.startedAt else { return nil }
            let age = max(0, now.timeIntervalSince(start) / 86_400)
            return AgingItem(card: card, ageDays: age, exceedsSLE: sle.map { age > $0 } ?? false)
        }
        .sorted { $0.ageDays > $1.ageDays }

        cumulativeFlow = (0..<flowDays).reversed().compactMap { back -> DayCount? in
            guard let day = calendar.date(byAdding: .day, value: -back, to: calendar.startOfDay(for: now)),
                  let end = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            var counts = (notStarted: 0, inProgress: 0, done: 0)
            for card in cards where card.createdAt < end {
                if let finishedAt = card.finishedAt, finishedAt < end { counts.done += 1 }
                else if let startedAt = card.startedAt, startedAt < end { counts.inProgress += 1 }
                else { counts.notStarted += 1 }
            }
            return DayCount(day: day, notStarted: counts.notStarted, inProgress: counts.inProgress, done: counts.done)
        }
    }
}
