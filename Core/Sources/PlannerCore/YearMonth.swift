import Foundation

/// A calendar month, e.g. November 2026. `month` is 1...12.
public struct YearMonth: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month must be 1...12")
        self.year = year
        self.month = month
    }

    /// The month that contains `date` in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year!, month: parts.month!)
    }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// Stable identifier, e.g. "2026-11". Used later for page file names.
    public var description: String {
        String(format: "%04d-%02d", year, month)
    }
}

/// The printed title of a month page, e.g. "NOVEMBER" or "ΝΟΕΜΒΡΙΟΣ".
public enum MonthTitle {
    public static func text(for month: YearMonth, locale: Locale) -> String {
        let calendar = PlannerLocale.calendar(locale: locale)
        // Stand-alone form: "Νοέμβριος", not the genitive "Νοεμβρίου".
        let name = calendar.standaloneMonthSymbols[month.month - 1]
        return PlannerText.uppercased(name, locale: locale)
    }
}
