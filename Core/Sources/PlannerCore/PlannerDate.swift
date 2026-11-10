import Foundation

/// Days of the week, numbered like Foundation's `Calendar` (1 = Sunday … 7 = Saturday).
public enum Weekday: Int, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// Weeks start on Monday unless the user chooses otherwise.
    public static let defaultFirst: Weekday = .monday

    /// The seven days in column order, for weeks that start on `first`.
    public static func week(startingOn first: Weekday) -> [Weekday] {
        (0..<7).map { offset in Weekday(rawValue: (first.rawValue - 1 + offset) % 7 + 1)! }
    }

    /// Column of this day (0...6) in a week that starts on `first`.
    public func column(firstWeekday first: Weekday) -> Int {
        (rawValue - first.rawValue + 7) % 7
    }

    /// Stable English name used in identifiers, e.g. "monday".
    public var key: String {
        switch self {
        case .sunday: "sunday"
        case .monday: "monday"
        case .tuesday: "tuesday"
        case .wednesday: "wednesday"
        case .thursday: "thursday"
        case .friday: "friday"
        case .saturday: "saturday"
        }
    }

    public init?(key: String) {
        guard let day = Weekday.allCases.first(where: { $0.key == key }) else { return nil }
        self = day
    }
}

/// A day on the calendar without a time, e.g. 14 November 2026.
///
/// Arithmetic is proleptic Gregorian and needs no time zone; only `init(date:calendar:)`
/// looks at one, to find which day it is on the device.
public struct PlannerDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        precondition((1...12).contains(month), "month must be 1...12")
        precondition(day >= 1 && day <= YearMonth(year: year, month: month).dayCount, "day out of range")
        self.year = year
        self.month = month
        self.day = day
    }

    /// `nil` when the parts do not name a real day (e.g. 30 February).
    public init?(validYear year: Int, month: Int, day: Int) {
        guard (1...12).contains(month),
              day >= 1, day <= YearMonth(year: year, month: month).dayCount else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day that contains `date` in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Parses the stable identifier, e.g. "2026-11-14".
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count >= 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(validYear: year, month: month, day: day)
    }

    /// Days since 1 January 1970 (negative before it).
    public init(daysSince1970 days: Int) {
        let (year, month, day) = Civil.date(fromDays: days)
        self.init(year: year, month: month, day: day)
    }

    public var daysSince1970: Int {
        Civil.days(year: year, month: month, day: day)
    }

    public var yearMonth: YearMonth {
        YearMonth(year: year, month: month)
    }

    public var weekday: Weekday {
        // 1 January 1970 was a Thursday.
        let sundayBased = ((daysSince1970 + 4) % 7 + 7) % 7
        return Weekday(rawValue: sundayBased + 1)!
    }

    public func adding(days: Int) -> PlannerDate {
        PlannerDate(daysSince1970: daysSince1970 + days)
    }

    public static func < (lhs: PlannerDate, rhs: PlannerDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Stable identifier, e.g. "2026-11-14".
    public var description: String {
        String(format: "%04ld-%02ld-%02ld", year, month, day)
    }
}

extension YearMonth {
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public var isLeapYear: Bool { Self.isLeapYear(year) }

    /// 28...31.
    public var dayCount: Int {
        switch month {
        case 2: isLeapYear ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    public var firstDay: PlannerDate { PlannerDate(year: year, month: month, day: 1) }
    public var lastDay: PlannerDate { PlannerDate(year: year, month: month, day: dayCount) }

    public func adding(months: Int) -> YearMonth {
        let index = year * 12 + (month - 1) + months
        var newYear = index / 12
        var newMonth = index % 12
        if newMonth < 0 {
            newMonth += 12
            newYear -= 1
        }
        return YearMonth(year: newYear, month: newMonth + 1)
    }

    public var previous: YearMonth { adding(months: -1) }
    public var next: YearMonth { adding(months: 1) }

    /// Parses the stable identifier, e.g. "2026-11".
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count >= 4, parts[1].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), (1...12).contains(month) else { return nil }
        self.init(year: year, month: month)
    }
}

/// Conversions between a Gregorian date and a day count (Howard Hinnant's algorithms).
private enum Civil {
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = (month + 9) % 12 // March = 0
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    static func date(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
        let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}
