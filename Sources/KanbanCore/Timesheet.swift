import Foundation

/// Reads a duration typed by hand: "1:30", "1.5" or "1,5" (hours), "90m", "2h", "2h30", "1h 30m".
/// A bare number is hours. Zero is accepted (callers treat it as "remove"); negative, empty or over 24 hours is not.
public enum DurationParser {
    public static func seconds(from text: String) -> Int? {
        let t = text.lowercased().filter { !$0.isWhitespace }.replacingOccurrences(of: ",", with: ".")
        let total: Double?
        if let g = captures(#"(\d+):(\d{1,2})"#, in: t) {
            total = g[0] * 3600 + g[1] * 60
        } else if let g = captures(#"(\d+)h(\d{1,2})(?:m|min)?"#, in: t) {
            total = g[0] * 3600 + g[1] * 60
        } else if let g = captures(#"(\d+(?:\.\d+)?)(?:m|min|mins)"#, in: t) {
            total = g[0] * 60
        } else if let g = captures(#"(\d+(?:\.\d+)?)(?:h|hr|hrs)?"#, in: t) {
            total = g[0] * 3600
        } else {
            total = nil
        }
        guard let total, total <= 86_400 else { return nil }
        return Int(total.rounded())
    }

    /// The numbers captured by `pattern` when it matches the whole text, else nil.
    private static func captures(_ pattern: String, in text: String) -> [Double]? {
        guard let regex = try? NSRegularExpression(pattern: "^" + pattern + "$"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).flatMap { Double(text[$0]) } }
    }
}

/// One week of a project's time as a grid: a row per task (a card, or the project itself), a column per day.
/// A row exists for every card with time that week and for each card in `extraCards`; the project row is always there.
public struct Timesheet {
    public struct Row {
        public let card: Card?
        public let project: Project
        public let title: String
        /// Entries of each day of the week, in `days` order.
        public let entries: [[TimeEntry]]
        public let seconds: [Int]

        public var total: Int { seconds.reduce(0, +) }

        @discardableResult
        public func addEntry(on day: Date, seconds: Int, note: String = "") -> TimeEntry? {
            if let card { return card.logTime(seconds: seconds, on: day, note: note) }
            return project.logTime(seconds: seconds, on: day, note: note)
        }
    }

    public let days: [Date]
    public let rows: [Row]
    public let columnTotals: [Int]
    public var grandTotal: Int { columnTotals.reduce(0, +) }

    public static func weekStart(containing date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    public init(project: Project, weekContaining date: Date, extraCards: [Card] = [], now: Date = Date(), calendar: Calendar = .current) {
        let start = Self.weekStart(containing: date, calendar: calendar)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        self.days = days

        func row(card: Card?, entries: [TimeEntry], title: String) -> Row {
            let perDay = days.map { day in entries.filter { calendar.startOfDay(for: $0.day) == day } }
            return Row(card: card, project: project, title: title, entries: perDay,
                       seconds: perDay.map { $0.reduce(0) { $0 + $1.totalSeconds(at: now) } })
        }

        let allCards = project.boards.flatMap(\.lists).filter { $0.deletedAt == nil }.flatMap { $0.cards.filter { $0.deletedAt == nil } }
        let cardRows = allCards.compactMap { card -> Row? in
            let built = row(card: card, entries: card.liveTimeEntries, title: card.title)
            return built.total > 0 || extraCards.contains(where: { $0 === card }) ? built : nil
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        let allRows = cardRows + [row(card: nil, entries: project.liveTimeEntries, title: TimeReport.noCard)]
        rows = allRows
        columnTotals = days.indices.map { index in allRows.reduce(0) { $0 + $1.seconds[index] } }
    }

    /// For a spreadsheet: a header of ISO dates, a line per task with decimal hours, and a total line. Empty tasks are left out.
    public var csv: String {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withFullDate]
        func quoted(_ fields: [String]) -> String {
            fields.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }
        let header = quoted(["Task"] + days.map(date.string(from:)) + ["Total"])
        let body = rows.filter { $0.total > 0 }.map { quoted([$0.title] + $0.seconds.map(TimeReport.decimalHours) + [TimeReport.decimalHours($0.total)]) }
        let totals = quoted(["Total"] + columnTotals.map(TimeReport.decimalHours) + [TimeReport.decimalHours(grandTotal)])
        return ([header] + body + [totals]).joined(separator: "\n") + "\n"
    }
}
