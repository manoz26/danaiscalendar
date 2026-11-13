import Foundation
import Testing
@testable import PlannerCore

@Suite("Calendar days")
struct PlannerDateTests {
    @Test("Leap years", arguments: [
        (2000, true), (1900, false), (2024, true), (2026, false), (2028, true), (2100, false), (2400, true),
    ])
    func leapYears(year: Int, isLeap: Bool) {
        #expect(YearMonth.isLeapYear(year) == isLeap)
        #expect(YearMonth(year: year, month: 2).dayCount == (isLeap ? 29 : 28))
    }

    @Test func monthLengths() {
        let lengths = (1...12).map { YearMonth(year: 2026, month: $0).dayCount }
        #expect(lengths == [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31])
    }

    @Test("Known weekdays", arguments: [
        ("1970-01-01", Weekday.thursday),
        ("2000-01-01", .saturday),
        ("2026-11-10", .tuesday),
        ("2026-03-01", .sunday),
        ("2027-02-01", .monday),
        ("2028-02-29", .tuesday),
        ("1900-01-01", .monday),
    ])
    func knownWeekdays(text: String, weekday: Weekday) throws {
        let date = try #require(PlannerDate(text))
        #expect(date.weekday == weekday)
    }

    @Test func matchesFoundationEveryDayFrom1990To2040() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        var date = PlannerDate(year: 1990, month: 1, day: 1)
        let end = PlannerDate(year: 2040, month: 12, day: 31)
        var checked = 0
        while date <= end {
            let instant = try #require(calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day)))
            let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: instant)
            #expect(parts.year == date.year && parts.month == date.month && parts.day == date.day)
            #expect(parts.weekday == date.weekday.rawValue, "\(date)")
            #expect(PlannerDate(daysSince1970: date.daysSince1970) == date)
            date = date.adding(days: 1)
            checked += 1
        }
        #expect(checked == 18_628)
    }

    @Test func addingDaysCrossesMonthsYearsAndLeapDays() {
        #expect(PlannerDate(year: 2028, month: 2, day: 28).adding(days: 1) == PlannerDate(year: 2028, month: 2, day: 29))
        #expect(PlannerDate(year: 2027, month: 2, day: 28).adding(days: 1) == PlannerDate(year: 2027, month: 3, day: 1))
        #expect(PlannerDate(year: 2026, month: 12, day: 31).adding(days: 1) == PlannerDate(year: 2027, month: 1, day: 1))
        #expect(PlannerDate(year: 2026, month: 1, day: 1).adding(days: -1) == PlannerDate(year: 2025, month: 12, day: 31))
        #expect(PlannerDate(year: 1969, month: 12, day: 31).daysSince1970 == -1)
    }

    @Test func identifiersRoundTrip() {
        let date = PlannerDate(year: 2026, month: 11, day: 14)
        #expect(date.description == "2026-11-14")
        #expect(PlannerDate("2026-11-14") == date)
        #expect(PlannerDate("2026-02-30") == nil)
        #expect(PlannerDate("2026-2-3") == nil)
        #expect(PlannerDate("hello") == nil)
        #expect(YearMonth("2028-02") == YearMonth(year: 2028, month: 2))
        #expect(YearMonth("2028-13") == nil)
    }

    @Test func dayOnTheDeviceFollowsTheTimeZone() throws {
        // 30 Nov 2026, 23:30 UTC is already 1 December in Athens.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-30T23:30:00Z"))
        let athens = PlannerLocale.calendar(locale: Locale(identifier: "el_GR"), timeZone: try #require(TimeZone(identifier: "Europe/Athens")))
        #expect(PlannerDate(date: instant, calendar: athens) == PlannerDate(year: 2026, month: 12, day: 1))
    }

    @Test func monthArithmetic() {
        let november = YearMonth(year: 2026, month: 11)
        #expect(november.next == YearMonth(year: 2026, month: 12))
        #expect(november.adding(months: 2) == YearMonth(year: 2027, month: 1))
        #expect(YearMonth(year: 2026, month: 1).previous == YearMonth(year: 2025, month: 12))
        #expect(november.adding(months: -23) == YearMonth(year: 2024, month: 12))
        #expect(november.adding(months: 25) == YearMonth(year: 2028, month: 12))
    }
}

@Suite("Month grid")
struct MonthGridTests {
    @Test("Weeks per month, weeks starting on Monday", arguments: [
        (2027, 2, 4), // starts on Monday, 28 days
        (2026, 2, 5),
        (2028, 2, 5), // leap February
        (2026, 3, 6), // starts on Sunday, 31 days
        (2026, 8, 6), // starts on Saturday, 31 days
        (2026, 11, 6), // starts on Sunday, 30 days
        (2026, 6, 5),
    ])
    func weeksStartingMonday(year: Int, month: Int, weeks: Int) {
        #expect(MonthGrid(month: YearMonth(year: year, month: month)).weekCount == weeks)
    }

    @Test("Weeks per month, weeks starting on Sunday", arguments: [
        (2026, 2, 4), // starts on Sunday, 28 days
        (2026, 3, 5),
        (2026, 11, 5),
        (2026, 8, 6),
        (2027, 2, 5),
    ])
    func weeksStartingSunday(year: Int, month: Int, weeks: Int) {
        #expect(MonthGrid(month: YearMonth(year: year, month: month), firstWeekday: .sunday).weekCount == weeks)
    }

    @Test func defaultFirstWeekdayIsMonday() {
        let grid = MonthGrid(month: YearMonth(year: 2026, month: 11))
        #expect(grid.firstWeekday == .monday)
        #expect(grid.columns == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
    }

    @Test func previousAndNextMonthDaysFillTheFirstAndLastWeek() {
        let grid = MonthGrid(month: YearMonth(year: 2026, month: 11))
        #expect(grid.weeks.first?.first?.date == PlannerDate(year: 2026, month: 10, day: 26))
        #expect(grid.weeks.last?.last?.date == PlannerDate(year: 2026, month: 12, day: 6))
        #expect(grid.leadingDays.map(\.day) == [26, 27, 28, 29, 30, 31])
        #expect(grid.trailingDays.map(\.day) == [1, 2, 3, 4, 5, 6])
        #expect(grid.weeks[0][6] == MonthGrid.Day(date: PlannerDate(year: 2026, month: 11, day: 1), isInMonth: true))
        #expect(grid.weeks[0][5].isInMonth == false)
    }

    @Test func changingTheFirstWeekdayShiftsTheGrid() {
        let november = YearMonth(year: 2026, month: 11)
        let sunday = MonthGrid(month: november, firstWeekday: .sunday)
        #expect(sunday.columns.first == .sunday)
        #expect(sunday.leadingDays.isEmpty)
        #expect(sunday.weeks[0][0].date == november.firstDay)
        #expect(sunday.weeks.last?.last?.date == PlannerDate(year: 2026, month: 12, day: 5))

        let saturday = MonthGrid(month: november, firstWeekday: .saturday)
        #expect(saturday.columns == [.saturday, .sunday, .monday, .tuesday, .wednesday, .thursday, .friday])
        #expect(saturday.weeks[0][0].date == PlannerDate(year: 2026, month: 10, day: 31))
    }

    @Test func januaryShowsDecemberOfThePreviousYear() {
        let grid = MonthGrid(month: YearMonth(year: 2027, month: 1)) // 1 Jan 2027 is a Friday
        #expect(grid.leadingDays == (28...31).map { PlannerDate(year: 2026, month: 12, day: $0) })
    }

    @Test func everyDayAppearsOnceInOrderForEveryFirstWeekday() {
        for first in Weekday.allCases {
            for year in [2026, 2027, 2028] {
                for number in 1...12 {
                    let month = YearMonth(year: year, month: number)
                    let grid = MonthGrid(month: month, firstWeekday: first)
                    let days = grid.weeks.joined().map(\.date)
                    #expect((4...6).contains(grid.weekCount))
                    #expect(grid.weeks.allSatisfy { $0.count == 7 })
                    // Consecutive days, starting on the first weekday.
                    #expect(days.first?.weekday == first)
                    #expect(zip(days, days.dropFirst()).allSatisfy { $0.adding(days: 1) == $1 })
                    // The month's days, once each; no week is all from another month.
                    #expect(grid.weeks.joined().filter(\.isInMonth).map(\.date.day) == Array(1...month.dayCount))
                    #expect(grid.weeks.allSatisfy { $0.contains(where: \.isInMonth) })
                }
            }
        }
    }

    @Test func positionOfADay() {
        let grid = MonthGrid(month: YearMonth(year: 2026, month: 11))
        #expect(grid.position(of: PlannerDate(year: 2026, month: 11, day: 10))! == (week: 2, column: 1))
        #expect(grid.position(of: PlannerDate(year: 2026, month: 12, day: 7)) == nil)
    }
}

@Suite("Planner pages")
struct PlannerPageTests {
    @Test func stepping() {
        #expect(PlannerPage.month(YearMonth(year: 2026, month: 12)).next == .month(YearMonth(year: 2027, month: 1)))
        #expect(PlannerPage.month(YearMonth(year: 2026, month: 1)).previous == .month(YearMonth(year: 2025, month: 12)))
        #expect(PlannerPage.year(2026).next == .year(2027))
        #expect(PlannerPage.month(YearMonth(year: 2026, month: 3)).yearPage == .year(2026))
        #expect(PlannerPage.year(9999).next == .year(9999))
        #expect(PlannerPage.month(YearMonth(year: 1, month: 1)).previous == .month(YearMonth(year: 1, month: 1)))
    }

    @Test func identifiersRoundTrip() {
        #expect(PlannerPage.year(2028).description == "year:2028")
        #expect(PlannerPage.month(YearMonth(year: 2027, month: 2)).description == "month:2027-02")
        #expect(PlannerPage("year:2028") == .year(2028))
        #expect(PlannerPage("month:2027-02") == .month(YearMonth(year: 2027, month: 2)))
        #expect(PlannerPage("month:2027-14") == nil)
        #expect(PlannerPage("day:2027-02-01") == nil)
        #expect(PlannerPage.toBuy.description == "tobuy")
        #expect(PlannerPage("tobuy") == .toBuy)
    }

    @Test func theToBuyPageHasNoDateAndNoNeighbours() {
        #expect(PlannerPage.toBuy.year == nil)
        #expect(PlannerPage.toBuy.yearPage == nil)
        #expect(!PlannerPage.toBuy.isCalendarPage)
        #expect(PlannerPage.month(YearMonth(year: 2026, month: 11)).isCalendarPage)
        #expect(PlannerPage.toBuy.previous == .toBuy)
        #expect(PlannerPage.toBuy.next == .toBuy)
        #expect(PlannerPage.toBuy.neighbors.isEmpty)
        #expect(PlannerPage.month(YearMonth(year: 2026, month: 11)).neighbors.contains(.year(2026)))
    }
}
