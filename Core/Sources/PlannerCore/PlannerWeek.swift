import Foundation

/// A week of the planner: seven days from its first day.
///
/// A week is one page, named by its first day (`week:2026-11-09`), so a week that falls in
/// two months (or two years) is the same page from both of them. The first day is the
/// first column of the month grid (Monday unless the user chooses otherwise), so with
/// another first weekday the same days would make another page.
public struct PlannerWeek: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let start: PlannerDate

    public init(start: PlannerDate) {
        self.start = start
    }

    /// The week that holds `date`, in weeks that start on `firstWeekday`.
    public init(containing date: PlannerDate, firstWeekday: Weekday = .defaultFirst) {
        start = date.adding(days: -date.weekday.column(firstWeekday: firstWeekday))
    }

    /// Parses the stable identifier: the first day, e.g. "2026-11-09".
    public init?(_ text: String) {
        guard let start = PlannerDate(text) else { return nil }
        self.start = start
    }

    public var firstWeekday: Weekday { start.weekday }

    /// The seven days, in order.
    public var days: [PlannerDate] {
        (0..<7).map { start.adding(days: $0) }
    }

    public var end: PlannerDate { start.adding(days: 6) }

    public func contains(_ date: PlannerDate) -> Bool {
        start <= date && date <= end
    }

    /// The month that holds most of its days (four or more): the month of its middle day.
    public var month: YearMonth { start.adding(days: 3).yearMonth }

    /// The months it has days in: one, or two in order.
    public var months: [YearMonth] {
        start.yearMonth == end.yearMonth ? [start.yearMonth] : [start.yearMonth, end.yearMonth]
    }

    /// True if one of its days is in `month`.
    public func touches(_ month: YearMonth) -> Bool {
        start.yearMonth == month || end.yearMonth == month
    }

    public func adding(weeks: Int) -> PlannerWeek {
        PlannerWeek(start: start.adding(days: 7 * weeks))
    }

    public var previous: PlannerWeek { adding(weeks: -1) }
    public var next: PlannerWeek { adding(weeks: 1) }

    /// The week's number by ISO 8601 (week 1 holds the year's first Thursday; some years
    /// have a week 53), taken from its middle day. For weeks that start on Monday this is
    /// exactly the ISO week; for weeks that start on Sunday it is the ISO week that shares
    /// six of their seven days.
    public var number: Int {
        let middle = start.adding(days: 3)
        let thursday = middle.adding(days: 3 - middle.weekday.column(firstWeekday: .monday))
        let dayOfYear = thursday.daysSince1970 - PlannerDate(year: thursday.year, month: 1, day: 1).daysSince1970
        return dayOfYear / 7 + 1
    }

    /// The weeks printed on a month page, top to bottom (the rows of its grid): 4, 5 or 6.
    /// WEEKLY button `n` opens the `n`-th.
    public static func weeks(of month: YearMonth, firstWeekday: Weekday = .defaultFirst) -> [PlannerWeek] {
        MonthGrid(month: month, firstWeekday: firstWeekday).weeks.compactMap { row in
            row.first.map { PlannerWeek(start: $0.date) }
        }
    }

    public static func < (lhs: PlannerWeek, rhs: PlannerWeek) -> Bool {
        lhs.start < rhs.start
    }

    /// Stable identifier: the first day, e.g. "2026-11-09".
    public var description: String { start.description }
}

/// The printed title of a week page: its days, e.g. "9 – 15 NOVEMBER", "30 MARCH – 5 APRIL"
/// or, in Greek, "9 – 15 ΝΟΕΜΒΡΙΟΥ" (the day first, like "03 MARCH" on the year page; the
/// month after a day takes its genitive form in Greek). Its year or years go above it.
public enum WeekTitle {
    /// In normal case: "9 – 15 November", "30 March – 5 April", "28 December – 3 January".
    public static func days(of week: PlannerWeek, locale: Locale) -> String {
        let names = PlannerLocale.calendar(locale: locale).monthSymbols
        let start = week.start, end = week.end
        if start.yearMonth == end.yearMonth {
            return "\(start.day) – \(end.day) \(names[end.month - 1])"
        }
        return "\(start.day) \(names[start.month - 1]) – \(end.day) \(names[end.month - 1])"
    }

    /// The printed title, in capitals.
    public static func text(for week: PlannerWeek, locale: Locale) -> String {
        PlannerText.uppercased(days(of: week, locale: locale), locale: locale)
    }

    /// "2026", or "2026 – 2027" for the week between two years.
    public static func years(of week: PlannerWeek) -> String {
        week.start.year == week.end.year ? String(week.start.year) : "\(week.start.year) – \(week.end.year)"
    }
}
