import Foundation

/// A page of the planner the user can open.
public enum PlannerPage: Hashable, Sendable, CustomStringConvertible {
    case year(Int)
    case month(YearMonth)

    /// Years the app can show. There is no other limit.
    public static let years = 1...9999

    public var year: Int {
        switch self {
        case .year(let year): year
        case .month(let month): month.year
        }
    }

    /// The year page this page belongs to.
    public var yearPage: PlannerPage { .year(year) }

    /// The page before: the previous month, or the previous year. Stays inside `years`.
    public var previous: PlannerPage { step(-1) }

    /// The page after: the next month, or the next year. Stays inside `years`.
    public var next: PlannerPage { step(1) }

    private func step(_ delta: Int) -> PlannerPage {
        let candidate: PlannerPage = switch self {
        case .year(let year): .year(year + delta)
        case .month(let month): .month(month.adding(months: delta))
        }
        return Self.years.contains(candidate.year) ? candidate : self
    }

    /// Stable identifier, e.g. "year:2026" or "month:2026-11".
    public var description: String {
        switch self {
        case .year(let year): String(format: "year:%04ld", year)
        case .month(let month): "month:\(month)"
        }
    }

    /// Parses `description`.
    public init?(_ text: String) {
        if text.hasPrefix("year:"), let year = Int(text.dropFirst(5)), Self.years.contains(year) {
            self = .year(year)
        } else if text.hasPrefix("month:"), let month = YearMonth(String(text.dropFirst(6))),
                  Self.years.contains(month.year) {
            self = .month(month)
        } else {
            return nil
        }
    }
}
