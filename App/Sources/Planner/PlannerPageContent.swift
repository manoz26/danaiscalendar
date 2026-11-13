import Foundation
import UIKit
import PlannerCore

/// What one planner page shows: its printed template, and the parts VoiceOver and the
/// UI tests can find on it. Texts come from the String Catalog and the calendar of the
/// app's language. Month pages also print the month's birthdays.
struct PlannerPageContent: Equatable {
    let page: PlannerPage
    let template: PageTemplate
    let identifier: String
    /// The printed layout, saved with the page's ink.
    let layout: PageLayoutStamp
    /// Spoken name of the whole page, e.g. "Month page for NOVEMBER 2026".
    let accessibilityLabel: String
    let accessibilityItems: [PageAccessibilityItem]

    init(page: PlannerPage, today: PlannerDate, locale: Locale, birthdays: [Birthday] = []) {
        self.page = page
        layout = PageLayoutStamp.current(for: page)
        switch page {
        case .year(let year):
            template = YearPageTemplate.make(year: year, locale: locale, today: today)
            identifier = "page.year"
            let name = String(year)
            accessibilityLabel = String(localized: "Year page for \(name)", comment: "VoiceOver: the year page, e.g. 'Year page for 2026'.")
            accessibilityItems = Self.yearItems(year: year, template: template, locale: locale)
        case .month(let month):
            let notes = Self.birthdayNotes(for: month, in: birthdays)
            template = MonthPageTemplate.make(month: month, locale: locale, labels: Self.labels, today: today, birthdays: notes)
            identifier = "page.month"
            let name = "\(MonthTitle.text(for: month, locale: locale)) \(month.year)"
            accessibilityLabel = String(localized: "Month page for \(name)", comment: "VoiceOver: the month page, e.g. 'Month page for NOVEMBER 2026'.")
            accessibilityItems = Self.monthItems(month: month, template: template, locale: locale, birthdays: notes)
        case .toBuy:
            template = ToBuyPageTemplate.make(locale: locale, title: Self.toBuyTitle)
            identifier = "page.tobuy"
            accessibilityLabel = String(localized: "To buy page", comment: "VoiceOver: the shopping list page.")
            accessibilityItems = Self.toBuyItems(template: template, locale: locale)
        }
    }

    /// Title of the shopping list page and label of the bag button.
    static var toBuyTitle: String {
        String(localized: "To buy", comment: "Title of the shopping list page (printed in capitals) and VoiceOver label of the bag button in the top bar.")
    }

    /// The month's birthdays as printed lines, e.g. "Manos's birthday".
    static func birthdayNotes(for month: YearMonth, in birthdays: [Birthday]) -> [BirthdayNote] {
        Birthday.notes(for: month, in: birthdays) { name in
            String(localized: "\(name)'s birthday", comment: "A friend's birthday, printed in the notes of the month page next to the day, e.g. 'Manos's birthday'.")
        }
    }

    static var labels: MonthPageLabels {
        MonthPageLabels(
            goals: String(localized: "Goals", comment: "Label of the goals box on the month page."),
            todo: String(localized: "To do list", comment: "Label of the to-do list on the month page."),
            memo: String(localized: "Memo", comment: "Label of the memo box on the month page."),
            weekly: String(localized: "Weekly", comment: "Label before the buttons 1-6 that open the weekly pages.")
        )
    }

    // MARK: - Accessibility

    private static func monthItems(
        month: YearMonth, template: PageTemplate, locale: Locale, birthdays: [BirthdayNote]
    ) -> [PageAccessibilityItem] {
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

        // Boxes and days, where the ink goes (the UI tests check the ink against them).
        let labels = Self.labels
        func addSection(_ section: RegionID.Section, _ label: String) {
            guard let region = template.region(.section(section)) else { return }
            items.append(PageAccessibilityItem(
                identifier: "section.\(section.rawValue)",
                label: label,
                value: nil,
                rect: region.rect,
                traits: .staticText
            ))
        }
        addSection(.goals, labels.goals)
        let days = DayNames(locale: locale)
        for region in template.regions {
            guard case .day(let date) = region.id else { continue }
            // A day of this month with birthdays says whose.
            let birthdaysOfDay = date.yearMonth == month ? birthdays.filter { $0.date == date }.map(\.text) : []
            items.append(PageAccessibilityItem(
                identifier: "day.\(date)",
                label: days.name(of: date),
                value: birthdaysOfDay.isEmpty ? nil : birthdaysOfDay.joined(separator: ", "),
                rect: region.rect,
                traits: .staticText
            ))
        }
        addSection(.todo, labels.todo)
        addSection(.memo, labels.memo)

        // The birthdays printed in the notes, one item per line.
        let memo = MonthPageLayout(month: month).memo
        let (slots, shown) = MonthPageTemplate.birthdaySlots(count: birthdays.count, in: memo)
        for (index, (note, slot)) in zip(birthdays.prefix(shown), slots).enumerated() {
            items.append(PageAccessibilityItem(
                identifier: "memo.birthday.\(index + 1)",
                label: "\(days.name(of: note.date)): \(note.text)",
                value: nil,
                rect: slot,
                traits: .staticText
            ))
        }
        return items
    }

    private static func toBuyItems(template: PageTemplate, locale: Locale) -> [PageAccessibilityItem] {
        var items: [PageAccessibilityItem] = []
        if let region = template.region(.title) {
            items.append(PageAccessibilityItem(
                identifier: "page.title",
                label: PlannerText.uppercased(toBuyTitle, locale: locale),
                value: PlannerPage.toBuy.description,
                rect: region.rect,
                traits: [.header, .staticText]
            ))
        }
        if let region = template.region(.section(.tobuy)) {
            items.append(PageAccessibilityItem(
                identifier: "section.tobuy",
                label: toBuyTitle,
                value: nil,
                rect: region.rect,
                traits: .staticText
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
        for region in template.regions {
            guard case .monthNotes(let month) = region.id else { continue }
            let name = CalendarNames.monthName(month.month, locale: locale)
            items.append(PageAccessibilityItem(
                identifier: "year.notes.\(month)",
                label: String(localized: "Notes for \(name)", comment: "VoiceOver: the grey notes box under a small month on the year page, e.g. 'Notes for March'."),
                value: nil,
                rect: region.rect,
                traits: .staticText
            ))
        }
        return items
    }
}

/// Spoken names of days, e.g. "Saturday 14 November 2026", in the app's language.
private struct DayNames {
    private let formatter: DateFormatter
    private let calendar: Calendar

    init(locale: Locale) {
        calendar = PlannerLocale.calendar(locale: locale)
        formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMMy")
    }

    func name(of date: PlannerDate) -> String {
        let components = DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)
        guard let day = calendar.date(from: components) else { return date.description }
        return formatter.string(from: day)
    }
}

/// Launch arguments used by the UI tests, e.g. `-DCOpenPage year:2028`.
/// Read from the arguments directly, not from UserDefaults.
enum LaunchOptions {
    #if DEBUG
    /// `-DCResetData YES`: start without saved pages or birthdays, and with the default tools.
    static var resetData: Bool { ProcessInfo.processInfo.arguments.contains("-DCResetData") }

    /// `-DCSampleInk YES`: sample strokes on every opened page without ink (see `SampleInk`).
    static var sampleInk: Bool { ProcessInfo.processInfo.arguments.contains("-DCSampleInk") }

    /// `-DCSampleBirthdays YES`: a few made-up birthdays, if there are none (see `BirthdayBook`).
    static var sampleBirthdays: Bool { ProcessInfo.processInfo.arguments.contains("-DCSampleBirthdays") }

    /// Called at launch, before the ink is loaded.
    @MainActor
    static func prepareTestData() {
        guard resetData else { return }
        try? FileManager.default.removeItem(at: InkLibrary.defaultFolder)
        try? FileManager.default.removeItem(at: BirthdayBook.defaultFolder)
        for key in InkDefaults.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
        AppLog.info("Test data reset")
    }
    #endif

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
