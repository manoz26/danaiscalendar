import Foundation

/// The weeks of a month as printed on a planner page: 7 columns, starting on a chosen
/// weekday, with the last days of the previous month and the first days of the next
/// month filling the first and last rows. A month takes 4, 5 or 6 rows.
public struct MonthGrid: Sendable, Equatable {
    public struct Day: Sendable, Hashable {
        public let date: PlannerDate
        /// `false` for days of the previous or next month.
        public let isInMonth: Bool
    }

    public let month: YearMonth
    public let firstWeekday: Weekday
    /// Rows of 7 days each.
    public let weeks: [[Day]]

    public init(month: YearMonth, firstWeekday: Weekday = .defaultFirst) {
        self.month = month
        self.firstWeekday = firstWeekday

        let first = month.firstDay
        let leading = first.weekday.column(firstWeekday: firstWeekday)
        let rowCount = (leading + month.dayCount + 6) / 7
        let start = first.adding(days: -leading)
        weeks = (0..<rowCount).map { row in
            (0..<7).map { column in
                let date = start.adding(days: row * 7 + column)
                return Day(date: date, isInMonth: date.yearMonth == month)
            }
        }
    }

    /// 4, 5 or 6.
    public var weekCount: Int { weeks.count }

    /// Weekday of each column, left to right.
    public var columns: [Weekday] { Weekday.week(startingOn: firstWeekday) }

    /// Days of the previous month shown in the first row.
    public var leadingDays: [PlannerDate] {
        weeks.first?.prefix { !$0.isInMonth }.map(\.date) ?? []
    }

    /// Days of the next month shown in the last row.
    public var trailingDays: [PlannerDate] {
        guard let last = weeks.last else { return [] }
        return Array(last.reversed().prefix { !$0.isInMonth }.reversed().map(\.date))
    }

    /// Row and column of a day shown on this grid.
    public func position(of date: PlannerDate) -> (week: Int, column: Int)? {
        for (week, days) in weeks.enumerated() {
            if let column = days.firstIndex(where: { $0.date == date }) {
                return (week, column)
            }
        }
        return nil
    }
}
