import Foundation

/// A page of the planner the user can open.
public enum PlannerPage: Hashable, Sendable, CustomStringConvertible {
    case year(Int)
    case month(YearMonth)
    /// The shopping list: one page of its own, not tied to a date (the bag in the top bar).
    case toBuy
    /// A page of the journal ("Τετράδιο"): free writing on blank, lined, grid or dotted paper.
    case journal(UUID)
    /// A sketch: a blank page from the sketch button.
    case sketch(UUID)

    /// Years the app can show. There is no other limit.
    public static let years = 1...9999

    /// The year of a year or month page; `nil` for pages without a date.
    public var year: Int? {
        switch self {
        case .year(let year): year
        case .month(let month): month.year
        case .toBuy, .journal, .sketch: nil
        }
    }

    /// True for the year and month pages (the ones with previous/next and tabs).
    public var isCalendarPage: Bool { year != nil }

    /// True for journal pages and sketches: pages of their own notebooks, outside the planner.
    public var isNotebookPage: Bool {
        switch self {
        case .journal, .sketch: true
        default: false
        }
    }

    /// The year page this page belongs to (`nil` for pages without a date).
    public var yearPage: PlannerPage? { year.map { .year($0) } }

    /// The page before: the previous month, or the previous year. Stays inside `years`.
    /// Pages without a date have no previous page here (returns `self`); the journal's
    /// order is kept by the journal itself.
    public var previous: PlannerPage { step(-1) }

    /// The page after: the next month, or the next year. Stays inside `years`.
    /// Pages without a date have no next page here (returns `self`).
    public var next: PlannerPage { step(1) }

    private func step(_ delta: Int) -> PlannerPage {
        let candidate: PlannerPage
        switch self {
        case .year(let year): candidate = .year(year + delta)
        case .month(let month): candidate = .month(month.adding(months: delta))
        case .toBuy, .journal, .sketch: return self
        }
        guard let year = candidate.year, Self.years.contains(year) else { return self }
        return candidate
    }

    /// Stable identifier, e.g. "year:2026", "month:2026-11", "tobuy",
    /// "journal:<uuid>" or "sketch:<uuid>" (lowercase uuid).
    public var description: String {
        switch self {
        case .year(let year): String(format: "year:%04ld", year)
        case .month(let month): "month:\(month)"
        case .toBuy: "tobuy"
        case .journal(let id): "journal:\(id.uuidString.lowercased())"
        case .sketch(let id): "sketch:\(id.uuidString.lowercased())"
        }
    }

    /// Parses `description`.
    public init?(_ text: String) {
        if text.hasPrefix("year:"), let year = Int(text.dropFirst(5)), Self.years.contains(year) {
            self = .year(year)
        } else if text.hasPrefix("month:"), let month = YearMonth(String(text.dropFirst(6))),
                  Self.years.contains(month.year) {
            self = .month(month)
        } else if text == "tobuy" {
            self = .toBuy
        } else if text.hasPrefix("journal:"), let id = UUID(uuidString: String(text.dropFirst(8))) {
            self = .journal(id)
        } else if text.hasPrefix("sketch:"), let id = UUID(uuidString: String(text.dropFirst(7))) {
            self = .sketch(id)
        } else {
            return nil
        }
    }
}
