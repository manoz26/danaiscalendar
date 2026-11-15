import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

/// Made-up events of March 2029, the month the UI tests open (the app's sample events
/// are the same kind).
enum SampleEvents {
    static let athens = PlannerLocale.calendar(locale: Locale(identifier: "el_GR"), timeZone: TimeZone(identifier: "Europe/Athens")!)

    static func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 3, calendar: Calendar = athens) -> Date {
        calendar.date(from: DateComponents(year: 2029, month: month, day: day, hour: hour, minute: minute))!
    }

    static func timed(_ title: String, day: Int, _ hour: Int, _ minute: Int = 0, minutes: Int = 60, month: Int = 3) -> CalendarEvent {
        let start = date(day, hour, minute, month: month)
        return CalendarEvent(eventID: "\(title)-\(month)-\(day)", title: title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)), calendarID: "home")
    }

    /// An all-day event as EventKit gives it: from midnight of the first day to 23:59:59 of the last.
    static func allDay(_ title: String, from first: Int, to last: Int, month: Int = 3, lastMonth: Int? = nil) -> CalendarEvent {
        let end = date(last, 23, 59, month: lastMonth ?? month).addingTimeInterval(59)
        return CalendarEvent(eventID: "\(title)-\(first)", title: title, start: date(first, month: month), end: end, isAllDay: true, calendarID: "home")
    }

    static func march(greek: Bool) -> [CalendarEvent] {
        func t(_ en: String, _ el: String) -> String { greek ? el : en }
        var events = [
            timed(t("Dentist", "Οδοντίατρος"), day: 5, 9, 30),
            timed(t("Lunch with Eleni", "Φαγητό με την Ελένη"), day: 5, 13),
            allDay(t("Holiday", "Αργία"), from: 12, to: 12),
            allDay(t("Trip to Crete", "Ταξίδι στην Κρήτη"), from: 14, to: 17),
            allDay(t("Easter holidays", "Διακοπές Πάσχα"), from: 25, to: 2, lastMonth: 4),
            allDay(t("Independence Day", "Εθνική εορτή"), from: 25, to: 25),
            timed(t("Concert", "Συναυλία"), day: 28, 22, minutes: 150),
        ]
        let busy = [
            (8, t("Gym", "Γυμναστήριο")), (10, t("Meeting", "Συνάντηση")), (12, t("Call the bank", "Τηλέφωνο στην τράπεζα")),
            (14, t("Pick up the kids", "Παιδιά από το σχολείο")), (16, t("Piano lesson", "Μάθημα πιάνου")),
            (18, t("Yoga", "Γιόγκα")), (20, t("Dinner", "Δείπνο")), (21, t("Film", "Ταινία")),
        ]
        events += busy.map { timed($0.1, day: 21, $0.0) }
        return events
    }
}

@Suite("Calendar events")
struct CalendarEventTests {
    init() {
        _ = TestFonts.registered
    }

    private let calendar = SampleEvents.athens
    private func day(_ day: Int, month: Int = 3) -> PlannerDate { PlannerDate(year: 2029, month: month, day: day) }

    // MARK: - Days of an event

    @Test func daysOfEvents() {
        let dentist = SampleEvents.timed("Dentist", day: 5, 9, 30)
        #expect(!dentist.isLong)
        #expect(dentist.printedDays(in: calendar) == day(5)...day(5))

        // EventKit ends all-day events at 23:59:59 of their last day.
        let trip = SampleEvents.allDay("Trip", from: 14, to: 17)
        #expect(trip.isLong)
        #expect(trip.firstDay(in: calendar) == day(14))
        #expect(trip.lastDay(in: calendar) == day(17))

        // Others end them at midnight after the last day: it belongs to the day before.
        let oneDay = CalendarEvent(eventID: "x", title: "x", start: SampleEvents.date(12), end: SampleEvents.date(13), isAllDay: true, calendarID: "c")
        #expect(oneDay.printedDays(in: calendar) == day(12)...day(12))

        // A short event over midnight is printed on the day it starts.
        let concert = SampleEvents.timed("Concert", day: 28, 22, minutes: 150)
        #expect(concert.lastDay(in: calendar) == day(29))
        #expect(concert.printedDays(in: calendar) == day(28)...day(28))

        // 24 hours or more: a bar over its days.
        let long = SampleEvents.timed("Conference", day: 7, 10, minutes: 26 * 60)
        #expect(long.isLong)
        #expect(long.printedDays(in: calendar) == day(7)...day(8))
    }

    @Test func barsKeepTheirLaneAcrossTheRow() {
        let row = (12...18).map { day($0) }
        let earlier = SampleEvents.allDay("Earlier", from: 11, to: 13)
        let holiday = SampleEvents.allDay("Holiday", from: 12, to: 12)
        let trip = SampleEvents.allDay("Trip", from: 14, to: 17)
        let dentist = SampleEvents.timed("Dentist", day: 12, 9, 30)
        let breakfast = SampleEvents.timed("Breakfast", day: 12, 8)
        let days = EventLayout.row(row, events: [trip, dentist, holiday, breakfast, earlier], calendar: calendar)

        let twelfth = days[day(12)]!
        #expect(twelfth.bars.map(\.event.title) == ["Earlier", "Holiday"])
        #expect(twelfth.bars.map(\.lane) == [0, 1])
        #expect(twelfth.bars[0].continuesBefore)
        #expect(twelfth.bars[0].showsTitle, "The first day of the row shows the title of a bar that started before it")
        #expect(twelfth.bars[0].daysInRow == 2)
        #expect(twelfth.timed.map(\.title) == ["Breakfast", "Dentist"])

        let thirteenth = days[day(13)]!
        #expect(thirteenth.bars.map(\.lane) == [0])
        #expect(!thirteenth.bars[0].showsTitle)
        #expect(!thirteenth.bars[0].continuesAfter)

        // The trip takes the first free lane and keeps it.
        for date in 14...17 {
            let bar = days[day(date)]!.bars[0]
            #expect(bar.event.title == "Trip" && bar.lane == 0)
            #expect(bar.showsTitle == (date == 14))
            #expect(bar.continuesBefore == (date > 14))
            #expect(bar.continuesAfter == (date < 17))
        }
        #expect(days[day(14)]!.bars[0].daysInRow == 4)
        #expect(days[day(18)] == nil)
    }

    @Test func aBarThatGoesOnPastTheRow() {
        let row = (26...31).map { day($0) }
        let easter = SampleEvents.allDay("Easter", from: 25, to: 2, lastMonth: 4)
        let days = EventLayout.row(row, events: [easter], calendar: calendar)
        let last = days[day(31)]!.bars[0]
        #expect(last.continuesAfter)
        #expect(days[day(26)]!.bars[0].daysInRow == 6)
    }

    @Test func daysWithEventsAndADaysList() {
        let events = SampleEvents.march(greek: false)
        let year = EventLayout.days(with: events, from: day(1, month: 1), through: day(31, month: 12), calendar: calendar)
        #expect(year.contains(day(5)))
        #expect(year.isSuperset(of: Set((14...17).map { day($0) })))
        #expect(year.contains(day(2, month: 4)))
        #expect(!year.contains(day(29)), "The concert is printed only on the day it starts")
        let march = EventLayout.days(with: events, from: day(1), through: day(31), calendar: calendar)
        #expect(!march.contains(day(1, month: 4)))

        let list = EventLayout.list(events, on: day(25), calendar: calendar)
        #expect(list.map(\.title) == ["Easter holidays", "Independence Day"])
        let fifth = EventLayout.list(events, on: day(5), calendar: calendar)
        #expect(fifth.map(\.title) == ["Dentist", "Lunch with Eleni"])
        let fifteenth = EventLayout.list(events, on: day(15), calendar: calendar)
        #expect(fifteenth.map(\.title) == ["Trip to Crete"])
    }

    // MARK: - Times

    @Test func timesOnBothClocks() {
        let clock24 = EventClock(calendar: calendar, uses24Hour: true)
        #expect(clock24.time(hour: 9, minute: 30) == "9:30")
        #expect(clock24.time(hour: 14, minute: 0) == "14:00")
        #expect(clock24.time(hour: 0, minute: 5) == "0:05")
        #expect(clock24.time(SampleEvents.date(5, 9, 30)) == "9:30")

        let english = EventClock(calendar: calendar, uses24Hour: false, amSymbol: "AM", pmSymbol: "PM")
        #expect(english.time(hour: 9, minute: 30) == "9:30am")
        #expect(english.time(hour: 14, minute: 0) == "2pm")
        #expect(english.time(hour: 0, minute: 0) == "12am")
        #expect(english.time(hour: 12, minute: 15) == "12:15pm")
        #expect(english.range(SampleEvents.date(5, 9, 30), SampleEvents.date(5, 10, 30)) == "9:30am – 10:30am")

        let greek = EventClock(calendar: calendar, uses24Hour: false, amSymbol: "π.μ.", pmSymbol: "μ.μ.")
        #expect(greek.time(hour: 9, minute: 30) == "9:30 π.μ.")
        #expect(greek.time(hour: 21, minute: 0) == "9 μ.μ.")
    }

    // MARK: - The form

    @Test func aNewEventStartsAtTheNextHourTodayAndAtNineOtherDays() {
        let now = SampleEvents.date(5, 14, 20)
        let today = EventDraft.new(on: day(5), now: now, calendar: calendar, calendarID: "home")
        #expect(today.start == SampleEvents.date(5, 15))
        #expect(today.end == SampleEvents.date(5, 16))
        #expect(today.calendarID == "home")
        #expect(!today.canSave, "An event needs a title")

        let other = EventDraft.new(on: day(9), now: now, calendar: calendar, calendarID: nil)
        #expect(other.start == SampleEvents.date(9, 9))
        #expect(other.end == SampleEvents.date(9, 10))
        #expect(!other.isAllDay)
    }

    @Test func movingTheStartKeepsTheLength() {
        var draft = EventDraft(title: "  Dentist ", start: SampleEvents.date(5, 9), end: SampleEvents.date(5, 10, 30))
        #expect(draft.canSave)
        #expect(draft.trimmedTitle == "Dentist")
        draft.moveStart(to: SampleEvents.date(5, 11))
        #expect(draft.end == SampleEvents.date(5, 12, 30))
        draft.setEnd(SampleEvents.date(5, 8))
        #expect(draft.end == draft.start, "The end is never before the start")
    }

    @Test func allDayOnAndOff() {
        var draft = EventDraft(
            title: "Trip", start: SampleEvents.date(14, 10), end: SampleEvents.date(17, 18),
            reminder: EventReminder(offset: -30 * 60)
        )
        draft.setAllDay(true, calendar: calendar)
        #expect(draft.isAllDay)
        #expect(draft.start == SampleEvents.date(14))
        #expect(draft.end == SampleEvents.date(17))
        #expect(draft.reminder == nil, "30 minutes before is not offered for all-day events")

        draft.reminder = EventReminder.allDayChoices[1]
        draft.setAllDay(false, calendar: calendar)
        #expect(draft.start == SampleEvents.date(14, 9))
        #expect(draft.end == SampleEvents.date(14, 10))
        #expect(draft.reminder == nil)

        let trip = SampleEvents.allDay("Trip", from: 14, to: 17)
        let fromEvent = EventDraft(trip, calendar: calendar)
        #expect(fromEvent.isAllDay)
        #expect(fromEvent.start == SampleEvents.date(14))
        #expect(fromEvent.end == SampleEvents.date(17))
    }

    @Test func remindersOfAllDayEventsAreAtNine() {
        let hours: [TimeInterval] = [9, -15, -39, -159]
        let offsets = EventReminder.allDayChoices.map(\.offset)
        #expect(offsets == hours.map { $0 * 3600 })
        #expect(EventReminder.timedChoices.first?.offset == 0)
        #expect(EventReminder.timedChoices.contains(EventReminder(offset: -3600)))
    }

    // MARK: - Printed

    @Test func aBusyDayEndsWithPlusN() {
        let busy = DayEvents(timed: (0..<8).map { SampleEvents.timed("E\($0)", day: 21, 8 + $0) })
        let plan = EventPrinter.CellPlan(busy, lineCount: 6)
        #expect(plan.timed == 5)
        #expect(plan.hidden == 3)
        #expect(plan.plusLine == 5)

        let fits = EventPrinter.CellPlan(DayEvents(timed: Array(busy.timed.prefix(6))), lineCount: 6)
        #expect(fits.timed == 6 && fits.hidden == 0 && fits.plusLine == nil)

        // Six weeks: 4 lines; five weeks: 6.
        #expect(EventPrinter.monthLineCount(cellHeight: 690 / 6) == 4)
        #expect(EventPrinter.monthLineCount(cellHeight: 690 / 5) == 6)
    }

    @Test func longTitlesAreCut() throws {
        let text = TemplateText("A very long title that will never fit in one cell", font: .medium, size: 9.5, tone: .text, anchor: .zero)
        let cut = try #require(EventPrinter.fitted(text, maxWidth: 80))
        #expect(cut.string.hasSuffix("…"))
        #expect(TemplateRenderer.width(of: cut) <= 80)
        #expect(EventPrinter.fitted(text, maxWidth: 1) == nil)
        let short = TemplateText("Gym", font: .medium, size: 9.5, tone: .text, anchor: .zero)
        #expect(EventPrinter.fitted(short, maxWidth: 80) == short)
    }

    @Test func theMonthPagePrintsEventsInTheirCells() throws {
        let march = YearMonth(year: 2029, month: 3)
        let clock = EventClock(calendar: calendar, uses24Hour: true)
        let template = MonthPageTemplate.make(
            month: march, locale: Locale(identifier: "en_US"), labels: .english,
            events: SampleEvents.march(greek: false), eventClock: clock
        )
        let layout = MonthPageLayout(month: march)
        let fifth = try #require(layout.cell(for: day(5))).frame
        let texts = template.texts
        let dentist = try #require(texts.first { $0.string == "Dentist" })
        #expect(fifth.contains(dentist.anchor))
        let time = try #require(texts.first { $0.string == "9:30" })
        #expect(fifth.contains(time.anchor))
        #expect(time.anchor.y > fifth.minY + EventPrinter.monthTop)

        // Eight events on the 21st: five, then "+3" (five weeks: six lines).
        let twentyFirst = try #require(layout.cell(for: day(21))).frame
        let inCell = texts.filter { twentyFirst.contains($0.anchor) }
        #expect(inCell.contains { $0.string == "+3" })
        #expect(!inCell.contains { $0.string == "Film" })

        // The trip is one bar from the 14th to the 17th, its title only on the 14th.
        #expect(texts.filter { $0.string.hasPrefix("Trip to") }.count == 1)
        let bars = template.shapes.compactMap { shape -> CGRect? in
            if case .rect(let rect, .button?, nil, _, _) = shape, rect.height == 11 { return rect }
            return nil
        }
        // Holiday (1 day), trip (4), Independence Day (1), Easter (25–31 March: 7).
        #expect(bars.count == 1 + 4 + 1 + 7)

        let bitmap = try PageBitmap(template, scale: 1)
        #expect(bitmap.isGreyscale)
        // Nothing printed in the cells of other months' days.
        let april = try #require(layout.cell(for: PlannerDate(year: 2029, month: 4, day: 1))).frame
        #expect(!texts.contains { april.contains($0.anchor) && $0.anchor.y > april.minY + 40 })
    }

    @Test func theWeekPagePrintsStartAndEnd() throws {
        let week = PlannerWeek(start: day(19))
        let clock = EventClock(calendar: calendar, uses24Hour: true)
        let template = WeekPageTemplate.make(
            week: week, locale: Locale(identifier: "en_US"), labels: .english,
            events: SampleEvents.march(greek: false), eventClock: clock
        )
        let layout = WeekPageLayout(week: week)
        let box = try #require(layout.box(for: day(21)))
        let texts = template.texts.filter { box.frame.contains($0.anchor) }
        #expect(texts.contains { $0.string == "8:00 – 9:00" })
        #expect(texts.contains { $0.string == "Gym" })
        // Eight events on eight lines: all of them, no "+N".
        #expect(!texts.contains { $0.string.hasPrefix("+") })
        let first = try #require(texts.first { $0.string == "8:00 – 9:00" })
        #expect(box.lines[0].contains(first.anchor) || abs(first.anchor.y - box.lines[0].midY) < 8)
        #expect(try PageBitmap(template, scale: 1).isGreyscale)
    }

    @Test func theYearPageDotsDaysWithEvents() {
        let events = SampleEvents.march(greek: false)
        let days = EventLayout.days(with: events, from: day(1, month: 1), through: day(31, month: 12), calendar: calendar)
        let plain = YearPageTemplate.make(year: 2029, locale: Locale(identifier: "en_US"))
        let dotted = YearPageTemplate.make(year: 2029, locale: Locale(identifier: "en_US"), eventDays: days)
        func circles(_ template: PageTemplate) -> Int {
            template.shapes.filter { if case .circle(_, 1.3, _, _, _) = $0 { true } else { false } }.count
        }
        #expect(circles(plain) == 0)
        #expect(circles(dotted) == days.count)
    }

    /// With PLANNER_RENDER_DIR set (the CI does), saves pages with events to look at.
    @Test func savesSamplePagesWithEvents() throws {
        guard let folder = ProcessInfo.processInfo.environment["PLANNER_RENDER_DIR"], !folder.isEmpty else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let english = Locale(identifier: "en_US"), greek = Locale(identifier: "el_GR")
        let greekLabels = MonthPageLabels(goals: "Στόχοι", todo: "Να κάνω", memo: "Σημειώσεις", weekly: "Εβδομάδες")
        let greekWeek = WeekPageLabels(week: "Εβδομάδα", notes: "Σημειώσεις")
        let twelve = EventClock(calendar: calendar, uses24Hour: false, amSymbol: "AM", pmSymbol: "PM")
        let twentyFour = EventClock(calendar: calendar, uses24Hour: true)
        let greekTwelve = EventClock(calendar: calendar, uses24Hour: false, amSymbol: "π.μ.", pmSymbol: "μ.μ.")
        let march = YearMonth(year: 2029, month: 3)
        let en = SampleEvents.march(greek: false), el = SampleEvents.march(greek: true)
        let samples: [(String, PageTemplate)] = [
            ("month-2029-03-en-events", MonthPageTemplate.make(
                month: march, locale: english, labels: .english, today: day(14),
                journalDays: [day(5)], sketchDays: [day(21)], events: en, eventClock: twelve
            )),
            ("month-2029-03-el-events", MonthPageTemplate.make(
                month: march, locale: greek, labels: greekLabels, sketchDays: [day(21)], events: el, eventClock: twentyFour
            )),
            ("month-2029-03-el-events-12h", MonthPageTemplate.make(
                month: march, locale: greek, labels: greekLabels, events: el, eventClock: greekTwelve
            )),
            ("week-2029-03-19-en-events", WeekPageTemplate.make(
                week: PlannerWeek(start: day(19)), locale: english, labels: .english, month: march, events: en, eventClock: twelve
            )),
            ("week-2029-03-12-el-events", WeekPageTemplate.make(
                week: PlannerWeek(start: day(12)), locale: greek, labels: greekWeek, month: march, events: el, eventClock: twentyFour
            )),
            ("week-2029-03-26-el-events", WeekPageTemplate.make(
                week: PlannerWeek(start: day(26)), locale: greek, labels: greekWeek, month: march, events: el, eventClock: twentyFour
            )),
            ("year-2029-en-events", YearPageTemplate.make(
                year: 2029, locale: english, today: day(14),
                eventDays: EventLayout.days(with: en, from: day(1, month: 1), through: day(31, month: 12), calendar: calendar)
            )),
        ]
        for (name, template) in samples {
            try PageBitmap(template, scale: 1.5).writePNG(to: directory.appending(path: "\(name).png"))
        }
    }
}
