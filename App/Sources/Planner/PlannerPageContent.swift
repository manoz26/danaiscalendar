import Foundation
import UIKit
import PlannerCore

/// What one planner page shows: its printed template, and the parts VoiceOver and the
/// UI tests can find on it. Texts come from the String Catalog and the calendar of the
/// app's language.
struct PlannerPageContent: Equatable {
    let page: PlannerPage
    let template: PageTemplate
    let identifier: String
    /// Spoken name of the whole page, e.g. "Month page for NOVEMBER 2026".
    let accessibilityLabel: String
    let accessibilityItems: [PageAccessibilityItem]

    init(page: PlannerPage, today: PlannerDate, locale: Locale) {
        self.page = page
        switch page {
        case .year(let year):
            template = YearPageTemplate.make(year: year, locale: locale, today: today)
            identifier = "page.year"
            let name = String(year)
            accessibilityLabel = String(localized: "Year page for \(name)", comment: "VoiceOver: the year page, e.g. 'Year page for 2026'.")
            accessibilityItems = Self.yearItems(year: year, template: template, locale: locale)
        case .month(let month):
            template = MonthPageTemplate.make(month: month, locale: locale, labels: Self.labels, today: today)
            identifier = "page.month"
            let name = "\(MonthTitle.text(for: month, locale: locale)) \(month.year)"
            accessibilityLabel = String(localized: "Month page for \(name)", comment: "VoiceOver: the month page, e.g. 'Month page for NOVEMBER 2026'.")
            accessibilityItems = Self.monthItems(month: month, template: template, locale: locale)
        }
    }

    static var labels: MonthPageLabels {
        MonthPageLabels(
            goals: String(localized: "Goals", comment: "Label of the goals box on the month page."),
            todo: String(localized: "To do list", comment: "Label of the to-do list on the month page."),
            memo: String(localized: "Memo", comment: "Label of the memo box on the month page."),
            toBuy: String(localized: "To buy", comment: "Label of the shopping list on the month page."),
            weekly: String(localized: "Weekly", comment: "Label before the buttons 1-6 that open the weekly pages.")
        )
    }

    // MARK: - Accessibility

    private static func monthItems(month: YearMonth, template: PageTemplate, locale: Locale) -> [PageAccessibilityItem] {
        let title = MonthTitle.text(for: month, locale: locale)
        var items: [PageAccessibilityItem] = []
        if let region = template.region(.title) {
            items.append(PageAccessibilityItem(
                identifier: "page.title",
                label: title,
                value: month.description,
                rect: region.rect,
                traits: [.header, .staticText]
            ))
        }
        // The weekly pages arrive later; the buttons are printed but not yet active.
        for region in template.regions {
            guard case .weekly(let number) = region.id else { continue }
            items.append(PageAccessibilityItem(
                identifier: "month.weekly.\(number)",
                label: String(localized: "Week \(number)", comment: "VoiceOver: one of the WEEKLY 1-6 buttons on the month page."),
                value: nil,
                rect: region.rect,
                traits: [.button, .notEnabled]
            ))
        }
        return items
    }

    private static func yearItems(year: Int, template: PageTemplate, locale: Locale) -> [PageAccessibilityItem] {
        var items: [PageAccessibilityItem] = []
        if let region = template.region(.title) {
            items.append(PageAccessibilityItem(
                identifier: "page.title",
                label: String(year),
                value: String(year),
                rect: region.rect,
                traits: [.header, .staticText]
            ))
        }
        for region in template.regions {
            guard case .month(let month) = region.id else { continue }
            items.append(PageAccessibilityItem(
                identifier: "year.month.\(month)",
                label: "\(CalendarNames.monthName(month.month, locale: locale)) \(month.year)",
                value: nil,
                rect: region.rect,
                traits: .button
            ))
        }
        return items
    }
}

/// Launch arguments used by the UI tests, e.g. `-DCOpenPage year:2028`.
/// Read from the arguments directly, not from UserDefaults.
enum LaunchOptions {
    static var initialPage: PlannerPage? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-DCOpenPage"), index + 1 < arguments.count else { return nil }
        let page = PlannerPage(arguments[index + 1])
        if page == nil {
            AppLog.warning("Ignoring unknown -DCOpenPage \(arguments[index + 1])")
        }
        return page
    }
}
