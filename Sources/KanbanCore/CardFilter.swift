import Foundation

/// Ranges are [start, end).
public enum DueDateFilter: String, CaseIterable, Sendable {
    case overdue, today, tomorrow, nextWeek, nextMonth, noDueDate

    public var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Due today"
        case .tomorrow: "Due tomorrow"
        case .nextWeek: "Due next week"
        case .nextMonth: "Due next month"
        case .noDueDate: "No dates"
        }
    }

    func matches(_ due: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let due else { return self == .noDueDate }
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        switch self {
        case .overdue: return due < today
        case .today: return due >= today && due < day(1)
        case .tomorrow: return due >= day(1) && due < day(2)
        case .nextWeek: return due >= today && due < day(8)
        case .nextMonth: return due >= day(8) && due < day(31)
        case .noDueDate: return false
        }
    }
}

/// Groups are ANDed; inside a group any selected value matches (OR).
public struct CardFilter: Equatable {
    public var labelIds: Set<String> = []
    public var listIds: Set<String> = []
    public var dueDates: Set<DueDateFilter> = []

    public init() {}

    public var count: Int { labelIds.count + listIds.count + dueDates.count }

    public mutating func clear() { self = CardFilter() }

    public func showsList(_ list: BoardList) -> Bool {
        listIds.isEmpty || listIds.contains(list.publicId)
    }

    public func matches(_ card: Card, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if !labelIds.isEmpty, !card.labels.contains(where: { labelIds.contains($0.publicId) }) { return false }
        if !dueDates.isEmpty, !dueDates.contains(where: { $0.matches(card.dueDate, now: now, calendar: calendar) }) {
            return false
        }
        return true
    }
}
