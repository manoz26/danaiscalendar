import Foundation

/// Month and weekday names as printed on the pages, in the app's language.
///
/// Names come from the Gregorian calendar of the given locale, so they are always in
/// the same language as the rest of the UI (see `PlannerLocale`).
public enum CalendarNames {
    /// Column headers of the month page: "MON", "ΔΕΥ".
    public static func shortWeekdays(_ days: [Weekday], locale: Locale) -> [String] {
        let symbols = PlannerLocale.calendar(locale: locale).shortStandaloneWeekdaySymbols
        return days.map { printed(symbols[$0.rawValue - 1], locale: locale) }
    }

    /// Column headers of the small months on the year page: "M", "Δ".
    public static func narrowWeekdays(_ days: [Weekday], locale: Locale) -> [String] {
        let symbols = PlannerLocale.calendar(locale: locale).veryShortStandaloneWeekdaySymbols
        return days.map { printed(symbols[$0.rawValue - 1], locale: locale) }
    }

    /// Month tabs: "JAN", "ΙΑΝ".
    public static func shortMonth(_ month: Int, locale: Locale) -> String {
        let symbols = PlannerLocale.calendar(locale: locale).shortStandaloneMonthSymbols
        return printed(symbols[month - 1], locale: locale)
    }

    /// The month's name in normal case, for VoiceOver: "February", "Φεβρουάριος".
    public static func monthName(_ month: Int, locale: Locale) -> String {
        PlannerLocale.calendar(locale: locale).standaloneMonthSymbols[month - 1]
    }

    private static func printed(_ symbol: String, locale: Locale) -> String {
        PlannerText.uppercased(symbol.replacingOccurrences(of: ".", with: ""), locale: locale)
    }
}

extension MonthTitle {
    /// Title of a small month on the year page: "03 MARCH", "05 ΜΑΪΟΣ".
    public static func numbered(for month: YearMonth, locale: Locale) -> String {
        String(format: "%02ld ", month.month) + text(for: month, locale: locale)
    }
}
