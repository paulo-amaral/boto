import EventKit
import Foundation

/// What a card looks like as a calendar event. Kept apart from EventKit so it can be tested without permissions.
public struct CalendarEventDraft: Equatable {
    /// An all-day event alerts at this hour of its day, since an all-day event has no time of its own.
    public static let allDayAlertHour = 9
    public static let timedDuration: TimeInterval = 3600

    public let title: String
    public let notes: String
    public let start: Date
    public let isAllDay: Bool
    public var end: Date { isAllDay ? start : start.addingTimeInterval(Self.timedDuration) }
    /// Seconds from `start` (the start of the day for all-day events); nil for no alert.
    public let alertOffset: TimeInterval?

    public init?(card: Card, calendar: Calendar = .current) {
        guard let due = card.dueDate else { return nil }
        title = card.title
        notes = card.details
        let day = calendar.startOfDay(for: due)
        isAllDay = card.dueTimeMinutes == nil
        start = card.dueTimeMinutes.flatMap { calendar.date(byAdding: .minute, value: $0, to: day) } ?? day
        let lead = card.alertLeadMinutes ?? 0
        let firing = TimeInterval(isAllDay ? Self.allDayAlertHour * 3600 : 0)
        alertOffset = lead == Card.noAlert ? nil : firing - TimeInterval(lead * 60)
    }
}

public enum CalendarSyncError: LocalizedError {
    case accessDenied
    case noCalendarSource

    public var errorDescription: String? {
        switch self {
        case .accessDenied: "Calendar access was denied. Allow Boto under System Settings > Privacy & Security > Calendars."
        case .noCalendarSource: "No account is available to hold a new calendar."
        }
    }
}

/// Mirrors card due dates as events (all-day unless the card has a time), with an optional alert, in a calendar named "Boto". One way only: the board
/// is the source of truth, so edits made to the events in Calendar are overwritten by the next sync.
@MainActor
public final class CalendarSync {
    public static let shared = CalendarSync()
    static let calendarTitle = "Boto"

    private let store = EKEventStore()

    /// Creates or updates the card's event and remembers its identifier on the card.
    public func sync(_ card: Card) async throws {
        guard let draft = CalendarEventDraft(card: card) else { return try await remove(card) }
        guard try await store.requestFullAccessToEvents() else { throw CalendarSyncError.accessDenied }

        let event = card.calendarEventID.flatMap(store.event(withIdentifier:)) ?? EKEvent(eventStore: store)
        if event.calendar == nil || event.calendar.title != Self.calendarTitle { event.calendar = try botoCalendar() }
        event.title = draft.title
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end
        event.alarms = draft.alertOffset.map { [EKAlarm(relativeOffset: $0)] } ?? []
        try store.save(event, span: .thisEvent, commit: true)
        card.calendarEventID = event.eventIdentifier
    }

    /// Puts every open card that has a due date on the calendar and returns how many were synced.
    public func syncAll(_ cards: [Card]) async throws -> Int {
        guard try await store.requestFullAccessToEvents() else { throw CalendarSyncError.accessDenied }
        for card in cards { try await sync(card) }
        return cards.count
    }

    /// Deletes the card's event, if it still exists, and forgets it.
    public func remove(_ card: Card) async throws {
        guard let id = card.calendarEventID else { return }
        guard try await store.requestFullAccessToEvents() else { throw CalendarSyncError.accessDenied }
        if let event = store.event(withIdentifier: id) { try store.remove(event, span: .thisEvent, commit: true) }
        card.calendarEventID = nil
    }

    private func botoCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == Self.calendarTitle }) { return existing }
        guard let source = store.defaultCalendarForNewEvents?.source else { throw CalendarSyncError.noCalendarSource }
        let created = EKCalendar(for: .event, eventStore: store)
        created.title = Self.calendarTitle
        created.source = source
        try store.saveCalendar(created, commit: true)
        return created
    }
}

extension Card {
    public static let noAlert = -1

    /// A finished or archived card has nothing left to remind about. Failures leave the link in place for a later retry.
    func dropCalendarEventIfClosed() {
        guard calendarEventID != nil, isCompleted || isArchived else { return }
        Task { @MainActor in try? await CalendarSync.shared.remove(self) }
    }
}

extension Board {
    /// Open cards with a due date, in lists that are neither archived nor deleted.
    public var calendarCandidates: [Card] {
        lists.filter { $0.deletedAt == nil && !$0.isArchived }
            .flatMap { $0.visibleCards(showArchived: false) }
            .filter { $0.dueDate != nil && !$0.isCompleted }
    }
}
