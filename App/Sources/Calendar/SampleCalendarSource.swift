#if DEBUG
import Foundation
import PlannerCore

/// Made-up calendars and events in March 2029, for the UI tests and the CI screenshots
/// (`-DCSampleEvents YES`; with `ask` the app starts without access and gets it when she
/// taps "Connect Apple Calendar", without the system's dialog). Kept in memory only:
/// adding, changing and deleting work, until the app closes.
@MainActor
final class SampleCalendarSource: CalendarSource {
    private(set) var access: CalendarAccess
    var onChange: (() -> Void)?

    private struct Master {
        var id: String
        var title: String
        var start: Date
        var end: Date
        var isAllDay: Bool
        var calendarID: String
        var repeats: EventRepeat = .never
        var reminder: EventReminder?
        /// Occurrences deleted one by one.
        var skipped: Set<Date> = []
    }

    private var masters: [Master] = []
    private let sampleCalendars: [EventCalendar]
    private let calendar: Calendar

    init(allowed: Bool, greek: Bool, calendar: Calendar) {
        access = allowed ? .allowed : .notAsked
        self.calendar = calendar
        func t(_ english: String, _ greekText: String) -> String { greek ? greekText : english }
        sampleCalendars = [
            EventCalendar(id: "home", title: t("Home", "Σπίτι"), source: "iCloud", canEdit: true),
            EventCalendar(id: "work", title: t("Work", "Δουλειά"), source: "iCloud", canEdit: true),
            EventCalendar(id: "holidays", title: t("Holidays", "Αργίες"), source: t("Subscribed", "Συνδρομές"), canEdit: false),
        ]

        func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 3) -> Date {
            calendar.date(from: DateComponents(year: 2029, month: month, day: day, hour: hour, minute: minute)) ?? Date()
        }
        func timed(_ title: String, _ day: Int, _ hour: Int, _ minute: Int = 0, minutes: Int = 60, in calendarID: String = "home") -> Master {
            let start = date(day, hour, minute)
            return Master(id: UUID().uuidString, title: title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), isAllDay: false, calendarID: calendarID)
        }
        func allDay(_ title: String, _ first: Int, _ last: Int, lastMonth: Int = 3, in calendarID: String = "home") -> Master {
            Master(id: UUID().uuidString, title: title, start: date(first), end: date(last, 23, 59, month: lastMonth).addingTimeInterval(59), isAllDay: true, calendarID: calendarID)
        }

        masters = [
            timed(t("Dentist", "Οδοντίατρος"), 5, 9, 30),
            timed(t("Lunch with Eleni", "Φαγητό με την Ελένη"), 5, 13, in: "work"),
            allDay(t("Holiday", "Αργία"), 12, 12, in: "holidays"),
            allDay(t("Trip to Crete", "Ταξίδι στην Κρήτη"), 14, 17),
            allDay(t("Easter holidays", "Διακοπές Πάσχα"), 25, 2, lastMonth: 4),
            allDay(t("Independence Day", "Εθνική εορτή"), 25, 25, in: "holidays"),
            timed(t("Concert", "Συναυλία"), 28, 22, minutes: 150),
        ]
        var swimming = timed(t("Swimming", "Κολύμβηση"), 6, 18, 30)
        swimming.repeats = .weekly
        swimming.reminder = EventReminder(offset: -3600)
        masters.append(swimming)
        let busy = [
            (8, t("Gym", "Γυμναστήριο")), (10, t("Meeting", "Συνάντηση")), (12, t("Call the bank", "Τηλέφωνο στην τράπεζα")),
            (14, t("Pick up the kids", "Παιδιά από το σχολείο")), (16, t("Piano lesson", "Μάθημα πιάνου")),
            (18, t("Yoga", "Γιόγκα")), (20, t("Dinner", "Δείπνο")), (21, t("Film", "Ταινία")),
        ]
        masters += busy.map { timed($0.1, 21, $0.0, in: $0.0 == 10 ? "work" : "home") }
    }

    func requestAccess() async -> CalendarAccess {
        access = .allowed
        AppLog.info("Sample calendar access allowed")
        return access
    }

    func calendars() -> [EventCalendar] {
        access == .allowed ? sampleCalendars : []
    }

    var defaultCalendarID: String? { "home" }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        guard access == .allowed else { return [] }
        return masters.flatMap { master in
            occurrences(of: master, from: start, to: end).map { occurrence in
                let length = master.end.timeIntervalSince(master.start)
                let info = sampleCalendars.first { $0.id == master.calendarID }
                return CalendarEvent(
                    eventID: master.id, title: master.title,
                    start: occurrence, end: occurrence.addingTimeInterval(length), isAllDay: master.isAllDay,
                    calendarID: master.calendarID, calendarTitle: info?.title ?? "", canEdit: info?.canEdit ?? true,
                    repeats: master.repeats, reminder: master.reminder, occurrence: occurrence
                )
            }
        }
    }

    func save(_ draft: EventDraft, replacing event: CalendarEvent?, span: EventSpan) throws {
        var master = Master(
            id: UUID().uuidString, title: draft.trimmedTitle, start: draft.start, end: draft.end,
            isAllDay: draft.isAllDay, calendarID: draft.calendarID ?? "home",
            repeats: draft.repeats == .custom ? .never : draft.repeats, reminder: draft.reminder
        )
        if draft.isAllDay {
            // Like EventKit: to 23:59:59 of the last day.
            let next = calendar.date(byAdding: .day, value: 1, to: draft.end) ?? draft.end
            master.end = next.addingTimeInterval(-1)
        }
        if let event {
            guard let index = masters.firstIndex(where: { $0.id == event.eventID }) else { throw CalendarSourceError.eventNotFound }
            if masters[index].repeats != .never, span == .thisEvent {
                // This occurrence only: it becomes an event of its own.
                masters[index].skipped.insert(event.occurrence)
                masters.append(master)
            } else {
                master.id = masters[index].id
                master.skipped = masters[index].skipped
                masters[index] = master
            }
        } else {
            masters.append(master)
        }
        onChange?()
    }

    func delete(_ event: CalendarEvent, span: EventSpan) throws {
        guard let index = masters.firstIndex(where: { $0.id == event.eventID }) else { throw CalendarSourceError.eventNotFound }
        if masters[index].repeats != .never, span == .thisEvent {
            masters[index].skipped.insert(event.occurrence)
        } else {
            masters.remove(at: index)
        }
        onChange?()
    }

    /// The starts of a master's occurrences that overlap the interval.
    private func occurrences(of master: Master, from start: Date, to end: Date) -> [Date] {
        let length = master.end.timeIntervalSince(master.start)
        let step: DateComponents? = switch master.repeats {
        case .never, .custom: nil
        case .daily: DateComponents(day: 1)
        case .weekly: DateComponents(day: 7)
        case .biweekly: DateComponents(day: 14)
        case .monthly: DateComponents(month: 1)
        case .yearly: DateComponents(year: 1)
        }
        var result: [Date] = []
        var occurrence = master.start
        var count = 0
        while occurrence < end, count < 5000 {
            if occurrence.addingTimeInterval(max(length, 1)) > start, !master.skipped.contains(occurrence) {
                result.append(occurrence)
            }
            guard let step else { break }
            count += 1
            // Counted from the first one, so a monthly event on the 31st stays on month ends.
            guard let next = calendar.date(byAdding: multiplied(step, by: count), to: master.start) else { break }
            occurrence = next
        }
        return result
    }

    private func multiplied(_ step: DateComponents, by count: Int) -> DateComponents {
        DateComponents(year: step.year.map { $0 * count }, month: step.month.map { $0 * count }, day: step.day.map { $0 * count })
    }
}
#endif
