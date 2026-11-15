import EventKit
import Foundation
import PlannerCore
import UIKit

/// What the app may do with the device's calendars.
enum CalendarAccess: String, Sendable {
    /// Never asked: the app asks only when she taps "Connect Apple Calendar".
    case notAsked
    case allowed
    /// Only adding events (iOS 17 "add events only"): the app can't read them.
    case writeOnly
    case denied
    /// Not allowed by a profile or Screen Time.
    case restricted
}

/// Which occurrences of a repeating event a change or a deletion is for.
enum EventSpan: Sendable {
    case thisEvent
    case futureEvents
}

/// The device's calendars (Apple Calendar, and the Google or Outlook accounts added to the
/// device). The app keeps no events of its own. Behind a protocol so that the UI tests and
/// the CI screenshots use made-up events without asking for access (`SampleCalendarSource`).
@MainActor
protocol CalendarSource: AnyObject {
    var access: CalendarAccess { get }
    /// Asks for full access (the system's dialog), once; then only the Settings app can change it.
    func requestAccess() async -> CalendarAccess
    func calendars() -> [EventCalendar]
    var defaultCalendarID: String? { get }
    /// Every event (each occurrence) that overlaps the interval, of every calendar.
    func events(from start: Date, to end: Date) -> [CalendarEvent]
    /// Adds an event, or changes `event` (for repeating ones, this occurrence or the future ones too).
    func save(_ draft: EventDraft, replacing event: CalendarEvent?, span: EventSpan) throws
    func delete(_ event: CalendarEvent, span: EventSpan) throws
    /// Called when the calendars change, also outside the app.
    var onChange: (() -> Void)? { get set }
}

enum CalendarSourceError: Error {
    case eventNotFound
    case noCalendar
}

// MARK: - EventKit

/// The real calendars, through EventKit with full access (iOS 17).
@MainActor
final class EventKitSource: CalendarSource {
    private var store = EKEventStore()
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onChange?()
            }
        }
    }

    var access: CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notAsked
        case .fullAccess: .allowed
        case .writeOnly: .writeOnly
        case .denied: .denied
        case .restricted: .restricted
        default: .allowed
        }
    }

    func requestAccess() async -> CalendarAccess {
        let granted: Bool = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    AppLog.error("Could not ask for calendar access", error)
                }
                continuation.resume(returning: granted)
            }
        }
        AppLog.info("Calendar access \(granted ? "allowed" : "not allowed")")
        if granted {
            // A store made before access sees no calendars.
            store = EKEventStore()
        }
        return access
    }

    func calendars() -> [EventCalendar] {
        guard access == .allowed else { return [] }
        return store.calendars(for: .event).map { calendar in
            EventCalendar(
                id: calendar.calendarIdentifier, title: calendar.title,
                source: calendar.source?.title ?? "", canEdit: calendar.allowsContentModifications
            )
        }
    }

    var defaultCalendarID: String? {
        guard access == .allowed else { return nil }
        return store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .allowed else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.event(from:))
    }

    func save(_ draft: EventDraft, replacing existing: CalendarEvent?, span: EventSpan) throws {
        let event: EKEvent
        if let existing {
            guard let found = find(existing) else { throw CalendarSourceError.eventNotFound }
            event = found
        } else {
            event = EKEvent(eventStore: store)
        }
        guard let calendar = draft.calendarID.flatMap(store.calendar(withIdentifier:)) ?? event.calendar ?? store.defaultCalendarForNewEvents else {
            throw CalendarSourceError.noCalendar
        }
        Self.apply(draft, to: event, calendar: calendar, original: existing)
        try store.save(event, span: span == .futureEvents ? .futureEvents : .thisEvent, commit: true)
        AppLog.info(existing == nil ? "Event added" : "Event changed")
    }

    func delete(_ existing: CalendarEvent, span: EventSpan) throws {
        guard let event = find(existing) else { throw CalendarSourceError.eventNotFound }
        try store.remove(event, span: span == .futureEvents ? .futureEvents : .thisEvent, commit: true)
        AppLog.info("Event deleted")
    }

    /// The occurrence of an event: the one with its identifier that starts (or started) then.
    private func find(_ event: CalendarEvent) -> EKEvent? {
        let around = store.predicateForEvents(
            withStart: event.occurrence.addingTimeInterval(-86_400), end: event.occurrence.addingTimeInterval(2 * 86_400), calendars: nil
        )
        let candidates = store.events(matching: around).filter { $0.eventIdentifier == event.eventID }
        return candidates.first { ($0.occurrenceDate ?? $0.startDate) == event.occurrence }
            ?? candidates.first { $0.startDate == event.start }
            ?? store.event(withIdentifier: event.eventID)
    }

    // MARK: Mapping (also used by the app's unit tests)

    static func event(from event: EKEvent) -> CalendarEvent {
        let id = event.eventIdentifier ?? event.calendarItemIdentifier
        let alarm = event.alarms?.first { $0.absoluteDate == nil }
        return CalendarEvent(
            eventID: id, title: event.title ?? "",
            start: event.startDate, end: event.endDate ?? event.startDate, isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier ?? "", calendarTitle: event.calendar?.title ?? "",
            canEdit: event.calendar?.allowsContentModifications ?? false,
            repeats: repeats(of: event.recurrenceRules ?? []),
            reminder: alarm.map { EventReminder(offset: $0.relativeOffset) },
            occurrence: event.occurrenceDate ?? event.startDate
        )
    }

    /// The form's choice for the event's rule; anything the form can't make is `custom`.
    static func repeats(of rules: [EKRecurrenceRule]) -> EventRepeat {
        guard let rule = rules.first else { return .never }
        guard rules.count == 1,
              rule.daysOfTheWeek == nil, rule.daysOfTheMonth == nil, rule.daysOfTheYear == nil,
              rule.weeksOfTheYear == nil, rule.monthsOfTheYear == nil, rule.setPositions == nil else { return .custom }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1): return .daily
        case (.weekly, 1): return .weekly
        case (.weekly, 2): return .biweekly
        case (.monthly, 1): return .monthly
        case (.yearly, 1): return .yearly
        default: return .custom
        }
    }

    static func rule(for repeats: EventRepeat) -> EKRecurrenceRule? {
        switch repeats {
        case .never, .custom: nil
        case .daily: EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly: EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly: EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly: EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }

    /// Puts the form's fields on the event. The repeat rule and the reminder are touched
    /// only when she changed them, so what Apple Calendar set (an end to the repeats, a
    /// second alert) stays.
    static func apply(_ draft: EventDraft, to event: EKEvent, calendar: EKCalendar, original: CalendarEvent?) {
        event.title = draft.trimmedTitle
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        // All-day: the form's last day; EventKit makes it the end of that day.
        event.endDate = draft.end
        event.calendar = calendar
        if original == nil || draft.repeats != original?.repeats {
            if draft.repeats != .custom {
                event.recurrenceRules = rule(for: draft.repeats).map { [$0] }
            }
        }
        if original == nil || draft.reminder != original?.reminder {
            event.alarms = draft.reminder.map { [EKAlarm(relativeOffset: $0.offset)] }
        }
    }
}
