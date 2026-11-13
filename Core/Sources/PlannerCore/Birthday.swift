import Foundation

/// A friend's birthday: a name and a day of the year. There is no year: it comes back
/// every year. The month page marks the day and writes it in its notes.
public struct Birthday: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// 1...12.
    public var month: Int
    /// 1...31; 29 February is allowed.
    public var day: Int

    public init(id: UUID = UUID(), name: String, month: Int, day: Int) {
        self.id = id
        self.name = name
        self.month = month
        self.day = day
    }

    /// Days a month can have in any year (29 for February).
    public static func dayCount(ofMonth month: Int) -> Int {
        switch month {
        case 2: 29
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// The name without spaces or new lines at the ends.
    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A name, and a day that exists in some year.
    public var isValid: Bool {
        !trimmedName.isEmpty && (1...12).contains(month) && (1...Self.dayCount(ofMonth: month)).contains(day)
    }

    /// The day it falls on in `year`. Outside leap years, 29 February is on 28 February.
    public func date(in year: Int) -> PlannerDate {
        let days = YearMonth(year: year, month: month).dayCount
        return PlannerDate(year: year, month: month, day: min(day, days))
    }

    /// By day of the year, then by name.
    public static func sortedByDate(_ birthdays: [Birthday]) -> [Birthday] {
        birthdays.sorted { a, b in
            if a.month != b.month { return a.month < b.month }
            if a.day != b.day { return a.day < b.day }
            return a.trimmedName.localizedStandardCompare(b.trimmedName) == .orderedAscending
        }
    }

    /// Longest name printed on a page; longer ones end with "…".
    public static let longestPrintedName = 32

    /// The birthdays of `month`, by day then name, as lines for the month page's notes.
    /// `text` turns a name into the printed line, e.g. "Manos's birthday".
    public static func notes(
        for month: YearMonth, in birthdays: [Birthday], text: (String) -> String
    ) -> [BirthdayNote] {
        sortedByDate(birthdays.filter { $0.isValid && $0.month == month.month }).map { birthday in
            BirthdayNote(date: birthday.date(in: month.year), text: text(shortened(birthday.trimmedName)))
        }
    }

    static func shortened(_ name: String, to limit: Int = longestPrintedName) -> String {
        let oneLine = name.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard oneLine.count > limit else { return oneLine }
        return oneLine.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// One birthday as printed on a month page: a mark in the day's cell and a line in the notes.
public struct BirthdayNote: Sendable, Equatable {
    public var date: PlannerDate
    /// The printed line without the day, e.g. "Manos's birthday".
    public var text: String

    public init(date: PlannerDate, text: String) {
        self.date = date
        self.text = text
    }
}
