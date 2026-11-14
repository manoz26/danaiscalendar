import Foundation
import UIKit
import PlannerCore

/// Everything of the user's that pages print: birthdays, journal pages (a dot on their
/// day), pinned sketches (a mark on their day) and typed list items.
struct PlannerData: Equatable {
    var birthdays: [Birthday] = []
    var journal = Journal()
    var sketches: [Sketch] = []
    var todos: [ListItem] = []
    var toBuy: [ListItem] = []
}

/// What one planner page shows: its printed template, and the parts VoiceOver and the
/// UI tests can find on it. Texts come from the String Catalog and the calendar of the
/// app's language. Month pages also print the month's birthdays, the days with journal
/// pages and pinned sketches, and typed to-dos; the To Buy page its typed items.
struct PlannerPageContent: Equatable {
    let page: PlannerPage
    let template: PageTemplate
    let identifier: String
    /// The printed layout, saved with the page's ink.
    let layout: PageLayoutStamp
    /// Spoken name of the whole page, e.g. "Month page for NOVEMBER 2026".
    let accessibilityLabel: String
    let accessibilityItems: [PageAccessibilityItem]

    init(page: PlannerPage, today: PlannerDate, locale: Locale, data: PlannerData = PlannerData()) {
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
            let notes = Self.birthdayNotes(for: month, in: data.birthdays)
            let todos = TypedLists.printed(data.todos.filter { $0.month == month }, lineCount: MonthPageLayout.listRowCount)
            let pinned = Sketch.pinned(data.sketches)
            template = MonthPageTemplate.make(
                month: month, locale: locale, labels: Self.labels, today: today, birthdays: notes,
                journalDays: data.journal.datedDays, sketchDays: Set(pinned.keys),
                todos: todos.items, todoOverflow: todos.overflow
            )
            identifier = "page.month"
            let name = "\(MonthTitle.text(for: month, locale: locale)) \(month.year)"
            accessibilityLabel = String(localized: "Month page for \(name)", comment: "VoiceOver: the month page, e.g. 'Month page for NOVEMBER 2026'.")
            accessibilityItems = Self.monthItems(
                month: month, template: template, locale: locale, birthdays: notes,
                journalDays: data.journal.datedDays, pinned: pinned, todos: todos.items
            )
        case .toBuy:
            let items = TypedLists.printed(data.toBuy, lineCount: TypedListKind.toBuy.lineCount)
            template = ToBuyPageTemplate.make(locale: locale, title: Self.toBuyTitle, items: items.items, overflow: items.overflow)
            identifier = "page.tobuy"
            accessibilityLabel = String(localized: "To buy page", comment: "VoiceOver: the shopping list page.")
            accessibilityItems = Self.toBuyItems(template: template, locale: locale, items: items.items)
        case .journal(let id):
            let record = data.journal.page(id)
            let texts = JournalHeading.texts(title: record?.title ?? "", date: record?.date, locale: locale)
            template = JournalPageTemplate.make(paper: record?.paper ?? .defaultStyle, label: texts.label, heading: texts.heading)
            identifier = "page.journal"
            let number = (data.journal.index(of: id) ?? 0) + 1
            accessibilityLabel = String(localized: "Journal page \(number)", comment: "VoiceOver: a page of the journal, e.g. 'Journal page 3'.")
            accessibilityItems = Self.journalItems(template: template, number: number, label: texts.label, heading: texts.heading)
        case .sketch:
            template = SketchPageTemplate.make()
            identifier = "page.sketch"
            accessibilityLabel = Self.sketchTitle
            accessibilityItems = [
                PageAccessibilityItem(
                    identifier: "page.title", label: Self.sketchTitle, value: "sketch",
                    rect: CGRect(x: 50, y: 0, width: 900, height: 50), traits: [.header, .staticText]
                ),
                PageAccessibilityItem(
                    identifier: "sketch.body", label: Self.sketchTitle, value: nil,
                    rect: SketchPageTemplate.body, traits: .staticText
                ),
            ]
        }
    }

    /// Title of the shopping list page and label of the bag button.
    static var toBuyTitle: String {
        String(localized: "To buy", comment: "Title of the shopping list page (printed in capitals) and VoiceOver label of the bag button in the top bar.")
    }

    static var sketchTitle: String {
        String(localized: "Sketch", comment: "A sketch (a blank page from the sketch button): VoiceOver name of the page.")
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
        month: YearMonth, template: PageTemplate, locale: Locale, birthdays: [BirthdayNote],
        journalDays: Set<PlannerDate>, pinned: [PlannerDate: [Sketch]], todos: [PrintedItem]
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
            // A day of this month says whose birthdays, and whether it has a journal page
            // or pinned sketches.
            var parts: [String] = []
            if date.yearMonth == month {
                parts += birthdays.filter { $0.date == date }.map(\.text)
                if journalDays.contains(date) {
                    parts.append(String(localized: "Journal page", comment: "VoiceOver: this day has a journal page (it shows a dot)."))
                }
                if let count = pinned[date]?.count {
                    parts.append(count == 1
                        ? String(localized: "Pinned sketch", comment: "VoiceOver: one sketch is pinned to this day.")
                        : String(localized: "Pinned sketches: \(count)", comment: "VoiceOver: how many sketches are pinned to this day."))
                }
            }
            items.append(PageAccessibilityItem(
                identifier: "day.\(date)",
                label: days.name(of: date),
                value: parts.isEmpty ? nil : parts.joined(separator: ", "),
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

        items += typedItems(todos, section: .todo, template: template, prefix: "todo")
        if let add = template.control(.addItem(.todo)) {
            items.append(PageAccessibilityItem(
                identifier: "todo.add",
                label: String(localized: "Add a typed to-do", comment: "VoiceOver: the printed + next to the to-do list of the month page."),
                value: nil,
                rect: add.rect,
                traits: .button
            ))
        }
        for control in template.controls {
            guard case .sketchMark(let date) = control.id else { continue }
            items.append(PageAccessibilityItem(
                identifier: "day.sketches.\(date)",
                label: String(localized: "Sketches of \(days.name(of: date))", comment: "VoiceOver: the small sketch mark in a day of the month page, e.g. 'Sketches of Saturday 21 March 2029'."),
                value: nil,
                rect: control.rect,
                traits: .button
            ))
        }
        return items
    }

    /// The circles or boxes of typed items: a finger on one ticks or unticks it.
    private static func typedItems(
        _ printed: [PrintedItem], section: RegionID.Section, template: PageTemplate, prefix: String
    ) -> [PageAccessibilityItem] {
        printed.compactMap { item in
            guard let control = template.control(.itemMarker(section, item.line)) else { return nil }
            return PageAccessibilityItem(
                identifier: "\(prefix).item.\(item.line)",
                label: item.text,
                value: item.done
                    ? String(localized: "Ticked", comment: "VoiceOver: a typed to-do or thing to buy is ticked (done).")
                    : String(localized: "Not ticked", comment: "VoiceOver: a typed to-do or thing to buy is not ticked yet."),
                rect: control.rect,
                traits: .button
            )
        }
    }

    private static func toBuyItems(template: PageTemplate, locale: Locale, items printed: [PrintedItem]) -> [PageAccessibilityItem] {
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
        items += typedItems(printed, section: .tobuy, template: template, prefix: "tobuy")
        if let add = template.control(.addItem(.tobuy)) {
            items.append(PageAccessibilityItem(
                identifier: "tobuy.add",
                label: String(localized: "Add a typed item", comment: "VoiceOver: the printed + at the top of the To Buy page."),
                value: nil,
                rect: add.rect,
                traits: .button
            ))
        }
        return items
    }

    private static func journalItems(template: PageTemplate, number: Int, label: String, heading: String) -> [PageAccessibilityItem] {
        var items: [PageAccessibilityItem] = []
        if let region = template.region(.title) {
            let spoken = [label, heading].filter { !$0.isEmpty }.joined(separator: ", ")
            items.append(PageAccessibilityItem(
                identifier: "page.title",
                label: spoken.isEmpty
                    ? String(localized: "Journal page \(number)", comment: "VoiceOver: a page of the journal, e.g. 'Journal page 3'.")
                    : spoken,
                value: "journal:\(number)",
                rect: region.rect,
                traits: [.header, .staticText]
            ))
        }
        if let region = template.region(.section(.body)) {
            items.append(PageAccessibilityItem(
                identifier: "journal.body",
                label: String(localized: "Journal page \(number)", comment: "VoiceOver: a page of the journal, e.g. 'Journal page 3'."),
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
struct DayNames {
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
    /// `-DCResetData YES`: start without saved pages, lists or birthdays, and with the default tools.
    static var resetData: Bool { ProcessInfo.processInfo.arguments.contains("-DCResetData") }

    /// `-DCSampleInk YES`: sample strokes on every opened page without ink (see `SampleInk`).
    static var sampleInk: Bool { ProcessInfo.processInfo.arguments.contains("-DCSampleInk") }

    /// `-DCSampleBirthdays YES`: a few made-up birthdays, if there are none (see `BirthdayBook`).
    static var sampleBirthdays: Bool { ProcessInfo.processInfo.arguments.contains("-DCSampleBirthdays") }

    /// `-DCSampleNotebooks YES`: four journal pages (one of each paper; days 5, 12 and 21 of
    /// March 2029) and two sketches (one pinned to 21 March 2029), if there are none.
    static var sampleNotebooks: Bool { ProcessInfo.processInfo.arguments.contains("-DCSampleNotebooks") }

    /// `-DCSampleLists YES`: typed to-dos for March 2029 and typed things to buy, if there are none.
    static var sampleLists: Bool { ProcessInfo.processInfo.arguments.contains("-DCSampleLists") }

    /// Called at launch, before the ink is loaded.
    @MainActor
    static func prepareTestData() {
        guard resetData else { return }
        try? FileManager.default.removeItem(at: InkLibrary.defaultFolder)
        try? FileManager.default.removeItem(at: BirthdayBook.defaultFolder)
        try? FileManager.default.removeItem(at: ListsFolder.url)
        for key in InkDefaults.all {
            UserDefaults.standard.removeObject(forKey: key)
        }
        AppLog.info("Test data reset")
    }
    #endif

    /// `-DCOpenPage <page>`: a page identifier (`year:2028`, `month:2027-02`, `tobuy`), or
    /// `journal` for the first journal page.
    static var openPageArgument: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-DCOpenPage"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var initialPage: PlannerPage? {
        guard let argument = openPageArgument, argument != "journal" else { return nil }
        let page = PlannerPage(argument)
        if page == nil {
            AppLog.warning("Ignoring unknown -DCOpenPage \(argument)")
        }
        return page
    }
}
