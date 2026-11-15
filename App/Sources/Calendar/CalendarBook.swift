import Foundation
import Observation
import PlannerCore

/// Keys of the calendar settings in UserDefaults.
enum CalendarDefaults {
    /// Settings → "Show events in the cells".
    static let showInCells = "DCShowEventsInCells"
    /// Calendars she turned off in Settings → Calendars.
    static let hiddenCalendars = "DCHiddenCalendars"

    static let all = [showInCells, hiddenCalendars]
}

/// The Apple Calendar in the app: access, which calendars are shown, and their events
/// (read through a `CalendarSource`, never copied). Pages print the events of the shown
/// calendars under the ink; the day's sheet lists, adds, changes and deletes them.
///
/// Event titles are the user's content: they are never written to the log.
@MainActor
@Observable
final class CalendarBook {
    private(set) var access: CalendarAccess
    private(set) var calendars: [EventCalendar]
    /// Grows on every change of the calendars (also outside the app): pages read again.
    private(set) var revision = 0
    /// Settings → "Show events in the cells". Off: pages stay purely handwritten.
    var showInCells: Bool {
        didSet {
            guard showInCells != oldValue else { return }
            UserDefaults.standard.set(showInCells, forKey: CalendarDefaults.showInCells)
            AppLog.info("Events in the cells: \(showInCells ? "on" : "off")")
        }
    }
    private(set) var hiddenCalendars: Set<String>

    @ObservationIgnored private let source: CalendarSource
    @ObservationIgnored private var cache: [ClosedRange<PlannerDate>: [CalendarEvent]] = [:]

    init(source: CalendarSource? = nil) {
        let source = source ?? Self.makeSource()
        self.source = source
        let defaults = UserDefaults.standard
        showInCells = defaults.object(forKey: CalendarDefaults.showInCells) as? Bool ?? true
        hiddenCalendars = Set(defaults.stringArray(forKey: CalendarDefaults.hiddenCalendars) ?? [])
        access = source.access
        calendars = source.calendars()
        source.onChange = { [weak self] in
            self?.sourceChanged()
        }
        AppLog.info("Calendar access: \(access.rawValue), \(calendars.count) calendars")
    }

    private static func makeSource() -> CalendarSource {
        #if DEBUG
        if let sample = LaunchOptions.sampleEvents {
            let greek = AppLocale.current.language.languageCode?.identifier == "el"
            return SampleCalendarSource(allowed: sample != "ask", greek: greek, calendar: PlannerLocale.calendar(locale: AppLocale.current))
        }
        #endif
        return EventKitSource()
    }

    var isAllowed: Bool { access == .allowed }

    /// Calendars she can add events to.
    var writableCalendars: [EventCalendar] { calendars.filter(\.canEdit) }

    /// Where new events go: the device's default calendar, or the first she can write to.
    var defaultCalendarID: String? {
        let writable = writableCalendars
        if let id = source.defaultCalendarID, writable.contains(where: { $0.id == id }) { return id }
        return writable.first?.id
    }

    func calendar(_ id: String) -> EventCalendar? {
        calendars.first { $0.id == id }
    }

    func isShown(_ calendarID: String) -> Bool {
        !hiddenCalendars.contains(calendarID)
    }

    func setShown(_ shown: Bool, calendar id: String) {
        guard shown == hiddenCalendars.contains(id) else { return }
        if shown {
            hiddenCalendars.remove(id)
        } else {
            hiddenCalendars.insert(id)
        }
        UserDefaults.standard.set(hiddenCalendars.sorted(), forKey: CalendarDefaults.hiddenCalendars)
        cache = [:]
        revision += 1
    }

    /// Asks for access (the system's dialog, the first time).
    func requestAccess() async {
        access = await source.requestAccess()
        sourceChanged()
    }

    /// The Settings app may have changed the access while she was away.
    func refreshAccess() {
        let current = source.access
        guard current != access else { return }
        AppLog.info("Calendar access is now \(current.rawValue)")
        access = current
        sourceChanged()
    }

    /// The events of the shown calendars printed on the days from `first` through `last`.
    func events(from first: PlannerDate, through last: PlannerDate) -> [CalendarEvent] {
        // Read so that views follow them.
        _ = revision
        let hidden = hiddenCalendars
        guard access == .allowed, first <= last else { return [] }
        let key = first...last
        if let cached = cache[key] { return cached }
        let calendar = PlannerLocale.calendar(locale: AppLocale.current)
        let events = source
            .events(from: first.midnight(in: calendar), to: last.adding(days: 1).midnight(in: calendar))
            .filter { !hidden.contains($0.calendarID) }
        if cache.count > 40 {
            cache = [:]
        }
        cache[key] = events
        return events
    }

    /// One day's events in the order of its list.
    func events(on day: PlannerDate) -> [CalendarEvent] {
        EventLayout.list(events(from: day, through: day), on: day, calendar: PlannerLocale.calendar(locale: AppLocale.current))
    }

    func save(_ draft: EventDraft, replacing event: CalendarEvent?, span: EventSpan) throws {
        do {
            try source.save(draft, replacing: event, span: span)
        } catch {
            AppLog.error("Could not save an event", error)
            throw error
        }
        sourceChanged()
    }

    func delete(_ event: CalendarEvent, span: EventSpan) throws {
        do {
            try source.delete(event, span: span)
        } catch {
            AppLog.error("Could not delete an event", error)
            throw error
        }
        sourceChanged()
    }

    private func sourceChanged() {
        cache = [:]
        calendars = source.calendars()
        revision += 1
    }
}

extension EventClock {
    /// The device's clock (12 or 24 hours, as set in the iPad's settings) in the app's language.
    @MainActor
    static var current: EventClock {
        let cycle = Locale.current.hourCycle
        return EventClock(
            calendar: PlannerLocale.calendar(locale: AppLocale.current),
            uses24Hour: cycle == .zeroToTwentyThree || cycle == .oneToTwentyFour
        )
    }
}
