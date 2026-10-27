import Foundation
import SwiftData

/// Time worked on a card. `seconds` is what has been logged; a running timer adds the time since `runningSince`.
/// The entry belongs to the day it started, even if the timer runs past midnight.
@Model
public final class TimeEntry {
    @Attribute(.unique) public var publicId: String
    public var createdAt: Date
    public var deletedAt: Date?
    /// Start of the day this time is attributed to.
    public var day: Date
    public var seconds: Int
    public var runningSince: Date?
    public var note: String
    /// An entry belongs to a card or, for work without one, straight to the project.
    public var card: Card?
    public var project: Project?

    public init(day: Date, seconds: Int, note: String = "", calendar: Calendar = .current) {
        self.publicId = makePublicId()
        self.createdAt = Date()
        self.day = calendar.startOfDay(for: day)
        self.seconds = max(0, seconds)
        self.note = note
    }

    public var isRunning: Bool { runningSince != nil }

    public func totalSeconds(at now: Date = Date()) -> Int {
        seconds + (runningSince.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0)
    }

    public func stop(at now: Date = Date()) {
        guard let started = runningSince else { return }
        seconds += max(0, Int(now.timeIntervalSince(started)))
        runningSince = nil
    }
}

extension Card {
    public var liveTimeEntries: [TimeEntry] { timeEntries.filter { $0.deletedAt == nil }.sorted { $0.createdAt > $1.createdAt } }
    public var runningTimer: TimeEntry? { liveTimeEntries.first(where: \.isRunning) }

    public func totalSeconds(at now: Date = Date()) -> Int {
        liveTimeEntries.reduce(0) { $0 + $1.totalSeconds(at: now) }
    }

    /// Starts a timer here and stops any other one, so a single clock is ever running across every project.
    @discardableResult
    public func startTimer(in context: ModelContext, at now: Date = Date()) -> TimeEntry {
        if let running = runningTimer { return running }
        let others = (try? context.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.runningSince != nil }))) ?? []
        others.forEach { $0.stop(at: now) }
        let entry = TimeEntry(day: now, seconds: 0)
        entry.runningSince = now
        timeEntries.append(entry)
        return entry
    }

    public func stopTimer(at now: Date = Date()) { runningTimer?.stop(at: now) }

    /// A manual entry, for time worked away from the app. Zero or negative durations are ignored.
    @discardableResult
    public func logTime(seconds: Int, on day: Date, note: String = "") -> TimeEntry? {
        guard seconds > 0 else { return nil }
        let entry = TimeEntry(day: day, seconds: seconds, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        timeEntries.append(entry)
        return entry
    }
}

extension Project {
    public var liveTimeEntries: [TimeEntry] { timeEntries.filter { $0.deletedAt == nil } }

    /// Time worked on the project as a whole, with what was done in `note`.
    @discardableResult
    public func logTime(seconds: Int, on day: Date, note: String = "") -> TimeEntry? {
        guard seconds > 0 else { return nil }
        let entry = TimeEntry(day: day, seconds: seconds, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        timeEntries.append(entry)
        return entry
    }

    /// Cards that can receive time, for the picker in the hours report.
    public var timeableCards: [Card] {
        boards.flatMap(\.orderedLists).flatMap { $0.visibleCards(showArchived: false) }
    }
}

/// Time worked in a project between two days, both included.
public struct TimeReport {
    public struct Row {
        public let entry: TimeEntry
        public let day: Date
        public let cardTitle: String
        public let note: String
        public let seconds: Int
    }

    /// Title shown for time logged on the project rather than on a card.
    public static let noCard = "No card"

    public let rows: [Row]
    public let totalSeconds: Int
    /// Newest day first.
    public let byDay: [(day: Date, seconds: Int)]
    /// Most time first.
    public let byCard: [(title: String, seconds: Int)]

    public init(project: Project, from: Date, to: Date, now: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: to)
        let cards = project.boards.flatMap(\.lists).filter { $0.deletedAt == nil }.flatMap { $0.cards.filter { $0.deletedAt == nil } }
        let owned = cards.flatMap { card in card.liveTimeEntries.map { (title: card.title, entry: $0) } }
            + project.liveTimeEntries.map { (title: Self.noCard, entry: $0) }
        rows = owned.compactMap { owner -> Row? in
            let entry = owner.entry
            guard entry.day >= start, entry.day <= last else { return nil }
            return Row(entry: entry, day: entry.day, cardTitle: owner.title, note: entry.note, seconds: entry.totalSeconds(at: now))
        }
        .sorted { ($1.day, $0.cardTitle) < ($0.day, $1.cardTitle) }
        totalSeconds = rows.reduce(0) { $0 + $1.seconds }
        byDay = Dictionary(grouping: rows, by: \.day).map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds }) }.sorted { $0.0 > $1.0 }
        byCard = Dictionary(grouping: rows, by: \.cardTitle).map { ($0.key, $0.value.reduce(0) { $0 + $1.seconds }) }
            .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
    }

    /// Spreadsheet-friendly: ISO dates, hours as decimals with a dot, fields quoted.
    public var csv: String {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withFullDate]
        let lines = rows.map { row in
            [date.string(from: row.day), row.cardTitle, row.note, Self.decimalHours(row.seconds)]
                .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }.joined(separator: ",")
        }
        return (["\"Date\",\"Card\",\"Note\",\"Hours\""] + lines).joined(separator: "\n") + "\n"
    }

    static func decimalHours(_ seconds: Int) -> String { String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(seconds) / 3600) }

    /// 5400 -> "1:30".
    public static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 3600, seconds % 3600 / 60) }
}
