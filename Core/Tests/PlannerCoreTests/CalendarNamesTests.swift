import Foundation
import Testing
@testable import PlannerCore

@Suite("Calendar names")
struct CalendarNamesTests {
    private let english = Locale(identifier: "en_US")
    private let greek = Locale(identifier: "el_GR")
    private let mondayFirst = Weekday.week(startingOn: .monday)

    @Test func englishWeekdays() {
        #expect(CalendarNames.shortWeekdays(mondayFirst, locale: english) == ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"])
        #expect(CalendarNames.narrowWeekdays(mondayFirst, locale: english) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(CalendarNames.shortWeekdays(Weekday.week(startingOn: .sunday), locale: english).first == "SUN")
    }

    @Test func greekWeekdaysAreCapitalsWithoutAccents() {
        #expect(CalendarNames.shortWeekdays(mondayFirst, locale: greek) == ["ΔΕΥ", "ΤΡΙ", "ΤΕΤ", "ΠΕΜ", "ΠΑΡ", "ΣΑΒ", "ΚΥΡ"])
        #expect(CalendarNames.narrowWeekdays(mondayFirst, locale: greek) == ["Δ", "Τ", "Τ", "Π", "Π", "Σ", "Κ"])
    }

    @Test func shortMonths() {
        #expect((1...12).map { CalendarNames.shortMonth($0, locale: english) } == [
            "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC",
        ])
        let greekMonths = (1...12).map { CalendarNames.shortMonth($0, locale: greek) }
        #expect(greekMonths.first == "ΙΑΝ")
        #expect(greekMonths[4] == "ΜΑΪ")
        for name in greekMonths {
            #expect(name.range(of: "^[Α-ΩΪΫ]+$", options: .regularExpression) != nil, "\(name)")
        }
    }

    @Test func numberedMonthTitles() {
        #expect(MonthTitle.numbered(for: YearMonth(year: 2026, month: 3), locale: english) == "03 MARCH")
        #expect(MonthTitle.numbered(for: YearMonth(year: 2026, month: 5), locale: greek) == "05 ΜΑΪΟΣ")
        #expect(MonthTitle.numbered(for: YearMonth(year: 2026, month: 12), locale: greek) == "12 ΔΕΚΕΜΒΡΙΟΣ")
    }

    @Test func fullMonthNamesForVoiceOver() {
        #expect(CalendarNames.monthName(2, locale: english) == "February")
        #expect(CalendarNames.monthName(2, locale: greek) == "Φεβρουάριος")
    }
}
