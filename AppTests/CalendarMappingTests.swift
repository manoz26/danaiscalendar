import EventKit
import Foundation
import PlannerCore
import Testing
@testable import DanaisCalendar

/// The Apple Calendar through EventKit's own classes (no access needed to make them):
/// the form's fields on an event and back, and the repeat rules.
@Suite("Apple Calendar")
@MainActor
struct CalendarMappingTests {
    @Test func repeatRulesBothWays() throws {
        for choice in EventRepeat.choices where choice != .never {
            let rule = try #require(EventKitSource.rule(for: choice))
            #expect(EventKitSource.repeats(of: [rule]) == choice)
        }
        #expect(EventKitSource.repeats(of: []) == .never)
        // Rules the form can't make are "custom", and saving leaves them alone.
        let mondays = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil
        )
        #expect(EventKitSource.repeats(of: [mondays]) == .custom)
        #expect(EventKitSource.repeats(of: [EKRecurrenceRule(recurrenceWith: .daily, interval: 3, end: nil)]) == .custom)
        #expect(EventKitSource.rule(for: .custom) == nil)
    }

    @Test func theFormsFieldsOnAnEventAndBack() {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        let calendar = EKCalendar(for: .event, eventStore: store)
        let start = Date(timeIntervalSince1970: 1_900_000_000)
        let draft = EventDraft(
            title: " Dentist \n", start: start, end: start.addingTimeInterval(3600),
            repeats: .weekly, reminder: EventReminder(offset: -900)
        )
        EventKitSource.apply(draft, to: event, calendar: calendar, original: nil)
        #expect(event.title == "Dentist")
        #expect(event.startDate == start)
        #expect(event.endDate == start.addingTimeInterval(3600))
        #expect(!event.isAllDay)
        #expect(event.recurrenceRules?.first?.frequency == .weekly)
        #expect(event.alarms?.first?.relativeOffset == -900)

        let back = EventKitSource.event(from: event)
        #expect(back.title == "Dentist")
        #expect(back.start == start)
        #expect(back.repeats == .weekly)
        #expect(back.reminder == EventReminder(offset: -900))

        // Unchanged repeat and reminder: what Apple Calendar set stays (here, a second alert).
        event.addAlarm(EKAlarm(relativeOffset: -86_400))
        var renamed = EventDraft(back, calendar: PlannerLocale.calendar(locale: Locale(identifier: "en_US")))
        renamed.title = "Dentist (moved)"
        EventKitSource.apply(renamed, to: event, calendar: calendar, original: back)
        #expect(event.title == "Dentist (moved)")
        #expect(event.alarms?.count == 2)
        #expect(event.recurrenceRules?.count == 1)

        // Repeat off, reminder off.
        var plain = renamed
        plain.repeats = .never
        plain.reminder = nil
        EventKitSource.apply(plain, to: event, calendar: calendar, original: back)
        #expect(event.recurrenceRules?.isEmpty ?? true)
        #expect(event.alarms?.isEmpty ?? true)
    }

    @Test func calendarTextsAreInGreek() throws {
        let greekPath = try #require(Bundle.main.path(forResource: "el", ofType: "lproj"))
        let greek = try #require(Bundle(path: greekPath))
        #expect(greek.localizedString(forKey: "Connect Apple Calendar", value: nil, table: nil) == "Σύνδεση με το Ημερολόγιο της Apple")
        #expect(greek.localizedString(forKey: "All day", value: nil, table: nil) == "Ολοήμερο")
        // The permission's text, shown by iOS.
        let info = Bundle.main.infoDictionary ?? [:]
        #expect((info["NSCalendarsFullAccessUsageDescription"] as? String)?.isEmpty == false)
        let permission = greek.localizedString(forKey: "NSCalendarsFullAccessUsageDescription", value: nil, table: "InfoPlist")
        #expect(permission.hasPrefix("Το Danai's Calendar"), "Greek permission text: \(permission)")
    }
}
