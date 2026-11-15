import Foundation

// MARK: - Events of the Apple Calendar

/// How an event repeats, as the event form offers it. `custom` is any other rule made in
/// Apple Calendar (e.g. every weekday): it is kept as it is unless she picks another.
public enum EventRepeat: String, Sendable, CaseIterable, Hashable {
    case never, daily, weekly, biweekly, monthly, yearly, custom

    /// The choices of the form; `custom` shows only for an event that already has it.
    public static let choices: [EventRepeat] = [.never, .daily, .weekly, .biweekly, .monthly, .yearly]
}

/// A reminder of the Apple Calendar: an alert some time before (negative) or after the
/// event's start. The system shows it; the app has no notifications of its own. An all-day
/// event starts at midnight, so "on the day at 9:00" is 9 hours after its start.
public struct EventReminder: Sendable, Hashable {
    /// Seconds from the start; negative is before.
    public var offset: TimeInterval

    public init(offset: TimeInterval) {
        self.offset = offset
    }

    static let minute: TimeInterval = 60
    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86_400

    /// At the start, 5, 10, 15 and 30 minutes, 1 and 2 hours, 1 and 2 days, and a week before.
    public static let timedChoices: [EventReminder] = [
        0, -5 * minute, -10 * minute, -15 * minute, -30 * minute, -hour, -2 * hour, -day, -2 * day, -7 * day,
    ].map(EventReminder.init(offset:))

    /// At 9:00 on the day, and 1 day, 2 days and a week before at 9:00.
    public static let allDayChoices: [EventReminder] = [
        9 * hour, 9 * hour - day, 9 * hour - 2 * day, 9 * hour - 7 * day,
    ].map(EventReminder.init(offset:))

    public static func choices(allDay: Bool) -> [EventReminder] {
        allDay ? allDayChoices : timedChoices
    }
}

/// A calendar of the device (iCloud, Google, Outlook… accounts), as the settings list it.
public struct EventCalendar: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// The account, e.g. "iCloud" or the Gmail address.
    public var source: String
    /// False for subscribed calendars, holidays, birthdays: their events can't be changed.
    public var canEdit: Bool

    public init(id: String, title: String, source: String, canEdit: Bool) {
        self.id = id
        self.title = title
        self.source = source
        self.canEdit = canEdit
    }
}

/// One event (one occurrence of a repeating one) of the Apple Calendar, as the pages print
/// it. The app keeps no events of its own: these are read from the device's calendars.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    /// The occurrence: the event's identifier and the start of this occurrence.
    public var id: String
    /// Shared by every occurrence of a repeating event.
    public var eventID: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarID: String
    public var calendarTitle: String
    /// The calendar allows changes.
    public var canEdit: Bool
    public var repeats: EventRepeat
    public var reminder: EventReminder?
    /// The original start of this occurrence (it stays when one occurrence is moved), to find it again.
    public var occurrence: Date

    public init(
        eventID: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
        calendarID: String, calendarTitle: String = "", canEdit: Bool = true,
        repeats: EventRepeat = .never, reminder: EventReminder? = nil, occurrence: Date? = nil
    ) {
        let occurrence = occurrence ?? start
        id = "\(eventID)@\(Int(occurrence.timeIntervalSince1970))"
        self.eventID = eventID
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.canEdit = canEdit
        self.repeats = repeats
        self.reminder = reminder
        self.occurrence = occurrence
    }

    /// The title on one line, without spaces at the ends.
    public var trimmedTitle: String {
        title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Printed as a bar across its days: all-day, or 24 hours or longer. Shorter ones are a
    /// line with their time, on the day they start.
    public var isLong: Bool {
        isAllDay || end.timeIntervalSince(start) >= 86_400
    }

    public func firstDay(in calendar: Calendar) -> PlannerDate {
        PlannerDate(date: start, calendar: calendar)
    }

    /// The last day it covers. An end at midnight belongs to the day before; EventKit ends
    /// all-day events at 23:59:59 of their last day.
    public func lastDay(in calendar: Calendar) -> PlannerDate {
        let first = firstDay(in: calendar)
        guard end > start else { return first }
        return max(first, PlannerDate(date: end.addingTimeInterval(-1), calendar: calendar))
    }

    /// The days it is printed on: all its days when long, else the day it starts.
    public func printedDays(in calendar: Calendar) -> ClosedRange<PlannerDate> {
        let first = firstDay(in: calendar)
        return first...(isLong ? lastDay(in: calendar) : first)
    }
}

// MARK: - The form's event

/// The event form's fields. All-day events have the first and the last day at midnight
/// (the form shows days only); timed events their real start and end.
public struct EventDraft: Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var repeats: EventRepeat
    public var reminder: EventReminder?
    public var calendarID: String?

    public init(
        title: String = "", start: Date, end: Date, isAllDay: Bool = false,
        repeats: EventRepeat = .never, reminder: EventReminder? = nil, calendarID: String? = nil
    ) {
        self.title = title
        self.start = start
        self.end = max(start, end)
        self.isAllDay = isAllDay
        self.repeats = repeats
        self.reminder = reminder
        self.calendarID = calendarID
    }

    /// A new event on a day: one hour, today from the next full hour (if the day still has
    /// one), other days at 9:00.
    public static func new(on day: PlannerDate, now: Date, calendar: Calendar, calendarID: String?) -> EventDraft {
        let midnight = Self.midnight(of: day, calendar: calendar)
        var start = calendar.date(byAdding: .hour, value: 9, to: midnight) ?? midnight
        if PlannerDate(date: now, calendar: calendar) == day {
            let hour = calendar.component(.hour, from: now)
            if hour < 23, let next = calendar.date(bySettingHour: hour + 1, minute: 0, second: 0, of: now) {
                start = next
            }
        }
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        return EventDraft(start: start, end: end, calendarID: calendarID)
    }

    /// The form's fields of an existing event.
    public init(_ event: CalendarEvent, calendar: Calendar) {
        if event.isAllDay {
            self.init(
                title: event.title,
                start: Self.midnight(of: event.firstDay(in: calendar), calendar: calendar),
                end: Self.midnight(of: event.lastDay(in: calendar), calendar: calendar),
                isAllDay: true, repeats: event.repeats, reminder: event.reminder, calendarID: event.calendarID
            )
        } else {
            self.init(
                title: event.title, start: event.start, end: event.end, isAllDay: false,
                repeats: event.repeats, reminder: event.reminder, calendarID: event.calendarID
            )
        }
    }

    public var trimmedTitle: String {
        title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    /// An event needs a title.
    public var canSave: Bool { !trimmedTitle.isEmpty }

    /// A new start; the end moves with it, keeping the event's length.
    public mutating func moveStart(to date: Date) {
        let length = end.timeIntervalSince(start)
        start = date
        end = date.addingTimeInterval(length)
    }

    /// A new end, never before the start.
    public mutating func setEnd(_ date: Date) {
        end = max(start, date)
    }

    /// All-day on: the same days, at midnight. Off: 9:00 to 10:00 on the first day. A
    /// reminder that the other kind doesn't offer is removed.
    public mutating func setAllDay(_ on: Bool, calendar: Calendar) {
        guard on != isAllDay else { return }
        let firstDay = PlannerDate(date: start, calendar: calendar)
        if on {
            let lastDay = max(firstDay, PlannerDate(date: end, calendar: calendar))
            start = Self.midnight(of: firstDay, calendar: calendar)
            end = Self.midnight(of: lastDay, calendar: calendar)
        } else {
            let midnight = Self.midnight(of: firstDay, calendar: calendar)
            start = calendar.date(byAdding: .hour, value: 9, to: midnight) ?? midnight
            end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
        }
        isAllDay = on
        if let reminder, !EventReminder.choices(allDay: on).contains(reminder) {
            self.reminder = nil
        }
    }

    static func midnight(of day: PlannerDate, calendar: Calendar) -> Date {
        day.midnight(in: calendar)
    }
}

extension PlannerDate {
    /// The start of this day in the calendar's time zone.
    public func midnight(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }
}

// MARK: - Times as printed

/// How times are printed: "9:30" and "14:00" on a 24-hour clock, "9:30am" and "2pm" on a
/// 12-hour one (or "9:30 π.μ." when the symbols are not plain letters), in the device's
/// time zone.
public struct EventClock: Sendable, Equatable {
    public var calendar: Calendar
    public var uses24Hour: Bool
    public var amSymbol: String
    public var pmSymbol: String

    public init(calendar: Calendar, uses24Hour: Bool, amSymbol: String? = nil, pmSymbol: String? = nil) {
        self.calendar = calendar
        self.uses24Hour = uses24Hour
        self.amSymbol = amSymbol ?? calendar.amSymbol
        self.pmSymbol = pmSymbol ?? calendar.pmSymbol
    }

    /// 24-hour, English symbols, in the current time zone.
    public static let standard = EventClock(
        calendar: PlannerLocale.calendar(locale: Locale(identifier: "en_US")), uses24Hour: true, amSymbol: "AM", pmSymbol: "PM"
    )

    public func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    public func time(hour: Int, minute: Int) -> String {
        let minutes = minute < 10 ? "0\(minute)" : "\(minute)"
        if uses24Hour {
            return "\(hour):\(minutes)"
        }
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let base = minute == 0 ? "\(twelve)" : "\(twelve):\(minutes)"
        let symbol = hour < 12 ? amSymbol : pmSymbol
        let plain = !symbol.isEmpty && symbol.allSatisfy { $0.isASCII && $0.isLetter }
        return plain ? base + symbol.lowercased() : "\(base) \(symbol)"
    }

    /// "9:30 – 10:30".
    public func range(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }
}

// MARK: - Events of each day

/// The events of one day as printed: bars (long events) in lanes, and timed events.
public struct DayEvents: Sendable, Equatable {
    public struct Bar: Sendable, Equatable {
        public let event: CalendarEvent
        /// Its line among the bars; the same on every day of the row, so the bar joins up.
        public let lane: Int
        /// It started on an earlier day / goes on after this day.
        public let continuesBefore: Bool
        public let continuesAfter: Bool
        /// The days of the row it covers from this day on (1: only this one).
        public let daysInRow: Int
        /// Its title is printed here: on its first day, or the first day of the row.
        public let showsTitle: Bool
    }

    public var bars: [Bar] = []
    /// By start, then title.
    public var timed: [CalendarEvent] = []

    public init(bars: [Bar] = [], timed: [CalendarEvent] = []) {
        self.bars = bars
        self.timed = timed
    }

    public var isEmpty: Bool { bars.isEmpty && timed.isEmpty }
    public var count: Int { bars.count + timed.count }
    /// Lines the bars take, gaps included.
    public var laneCount: Int { (bars.map(\.lane).max() ?? -1) + 1 }
    /// Every event in printed order: bars by lane, then timed.
    public var all: [CalendarEvent] { bars.sorted { $0.lane < $1.lane }.map(\.event) + timed }
}

public enum EventLayout {
    /// The events of each day of a row of consecutive days (a week of the month grid, or
    /// the seven days of a week page). Long events are bars: the earlier and the longer get
    /// the upper lanes, and a bar keeps its lane on all its days of the row.
    public static func row(_ days: [PlannerDate], events: [CalendarEvent], calendar: Calendar) -> [PlannerDate: DayEvents] {
        guard let first = days.first, let last = days.last else { return [:] }
        let index = Dictionary(uniqueKeysWithValues: days.enumerated().map { ($0.element, $0.offset) })
        var result: [PlannerDate: DayEvents] = [:]

        struct Placed {
            let event: CalendarEvent
            let range: ClosedRange<PlannerDate>
        }
        let long = events
            .filter(\.isLong)
            .map { Placed(event: $0, range: $0.printedDays(in: calendar)) }
            .filter { $0.range.upperBound >= first && $0.range.lowerBound <= last }
            .sorted { a, b in
                if a.range.lowerBound != b.range.lowerBound { return a.range.lowerBound < b.range.lowerBound }
                if a.range.upperBound != b.range.upperBound { return a.range.upperBound > b.range.upperBound }
                return order(a.event, b.event)
            }

        // Lanes: each holds the row positions it is taken on.
        var lanes: [Set<Int>] = []
        for placed in long {
            let from = index[max(first, placed.range.lowerBound)] ?? 0
            let to = index[min(last, placed.range.upperBound)] ?? days.count - 1
            let span = Set(from...to)
            let lane = lanes.firstIndex { $0.isDisjoint(with: span) } ?? lanes.count
            if lane == lanes.count {
                lanes.append([])
            }
            lanes[lane].formUnion(span)
            for position in from...to {
                let day = days[position]
                result[day, default: DayEvents()].bars.append(DayEvents.Bar(
                    event: placed.event, lane: lane,
                    continuesBefore: placed.range.lowerBound < day,
                    continuesAfter: placed.range.upperBound > day,
                    daysInRow: to - position + 1,
                    showsTitle: position == from
                ))
            }
        }

        for event in events where !event.isLong {
            let day = event.firstDay(in: calendar)
            guard index[day] != nil else { continue }
            result[day, default: DayEvents()].timed.append(event)
        }
        for day in result.keys {
            result[day]?.bars.sort { $0.lane < $1.lane }
            result[day]?.timed.sort(by: order)
        }
        return result
    }

    /// The days from `first` through `last` with at least one printed event (the dots of
    /// the year page).
    public static func days(with events: [CalendarEvent], from first: PlannerDate, through last: PlannerDate, calendar: Calendar) -> Set<PlannerDate> {
        var days: Set<PlannerDate> = []
        for event in events {
            let range = event.printedDays(in: calendar)
            let from = max(first, range.lowerBound), to = min(last, range.upperBound)
            guard from <= to else { continue }
            for offset in 0...(to.daysSince1970 - from.daysSince1970) {
                days.insert(from.adding(days: offset))
            }
        }
        return days
    }

    /// A day's events for its list: the long ones (the longest first), then by start, then title.
    public static func list(_ events: [CalendarEvent], on day: PlannerDate, calendar: Calendar) -> [CalendarEvent] {
        events
            .filter { event in
                let first = event.firstDay(in: calendar)
                return first == day || (first < day && event.lastDay(in: calendar) >= day)
            }
            .sorted { a, b in
                if a.isLong != b.isLong { return a.isLong }
                if a.isLong, a.end != b.end, a.start == b.start { return a.end > b.end }
                return order(a, b)
            }
    }

    /// By start, then title, then id (always the same order).
    static func order(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
        return a.id < b.id
    }
}
