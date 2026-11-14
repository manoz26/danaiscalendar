import SwiftUI
import UIKit
import PlannerCore

/// A sheet over the planner.
enum PlannerSheet: Identifiable {
    case settings
    case birthdays
    case journalPages
    case journalPage(UUID)
    /// All sketches, or those pinned to one day.
    case sketches(PlannerDate?)
    case pin(UUID)
    /// Typed items of a list; `inkedLines` are the page's lines with handwriting.
    case list(TypedListKind, inkedLines: Set<Int>, focusNew: Bool)

    var id: String {
        switch self {
        case .settings: "settings"
        case .birthdays: "birthdays"
        case .journalPages: "journalPages"
        case .journalPage(let id): "journalPage:\(id)"
        case .sketches(let day): "sketches:\(day?.description ?? "all")"
        case .pin(let id): "pin:\(id)"
        case .list(let kind, _, _): "list:\(kind.id)"
        }
    }
}

/// The planner: the bar on top, the open page (year, month, To Buy, a journal page or a
/// sketch) with the ink and the tool bar, and on planner pages the tabs on the right.
/// Opens on the current month.
struct RootView: View {
    let ink: InkController
    let birthdays: BirthdayBook
    let journal: JournalBook
    let sketches: SketchBook
    let lists: ListBook
    @AppStorage(InkDefaults.drawWithFinger) private var drawWithFinger = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var now = Date()
    @State private var page: PlannerPage
    /// The last year or month page: where other pages go back to, and whose tabs the To Buy page shows.
    @State private var calendarPage: PlannerPage
    /// The journal page last open: JOURNAL opens it again.
    @State private var lastJournalPage: UUID?
    /// Pages the app made without being asked for one (a day's page from a long press, a
    /// new sketch, the journal's first page): removed when left with no ink and no title.
    @State private var provisional: Set<PlannerPage> = []
    @State private var sheet: PlannerSheet?
    #if DEBUG
    @State private var lastExport = ""
    #endif

    init(ink: InkController, birthdays: BirthdayBook, journal: JournalBook, sketches: SketchBook, lists: ListBook) {
        self.ink = ink
        self.birthdays = birthdays
        self.journal = journal
        self.sketches = sketches
        self.lists = lists
        let month = YearMonth(date: Date(), calendar: PlannerLocale.calendar(locale: AppLocale.current))
        var first = LaunchOptions.initialPage ?? .month(month)
        if LaunchOptions.openPageArgument == "journal", let page = journal.pages.first {
            first = page.page
        }
        _page = State(initialValue: first)
        _calendarPage = State(initialValue: first.isCalendarPage ? first : .month(month))
        if case .journal(let id) = first {
            _lastJournalPage = State(initialValue: id)
        }
    }

    var body: some View {
        let locale = AppLocale.current
        let compact = horizontalSizeClass == .compact
        let content = PlannerPageContent(page: page, today: today, locale: locale, data: data)
        VStack(spacing: 0) {
            PlannerTopBar(
                page: page,
                calendarPage: calendarPage,
                locale: locale,
                compact: compact,
                canDraw: ink.canDraw,
                hasPrevious: hasNeighbor(-1),
                hasNext: hasNeighbor(1),
                actions: barActions
            )
            HStack(spacing: 0) {
                PlannerCanvas(
                    ink: ink,
                    content: content,
                    drawWithFinger: drawWithFinger,
                    onTap: { point in handleTap(at: point, in: content.template) },
                    onLongPress: { point in handleLongPress(at: point, in: content.template) },
                    onSwipe: { offset in handleSwipe(offset) }
                )
                .overlay {
                    if ink.canDraw {
                        InkToolbarOverlay(ink: ink)
                    }
                }
                if !page.isNotebookPage {
                    PlannerTabs(
                        page: page,
                        year: calendarPage.year ?? currentMonth.year,
                        locale: locale,
                        compact: compact,
                        onOpen: open
                    )
                }
            }
        }
        .background(Paper.background.ignoresSafeArea())
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // The last exported file, for the UI tests.
            Text(verbatim: lastExport.isEmpty ? "-" : lastExport)
                .font(.system(size: 2))
                .foregroundStyle(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("debug.lastExport")
        }
        #endif
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .onChange(of: page) { _, newPage in
            preloadNeighbors(of: newPage)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                now = Date()
                AppLog.info("App active")
            case .inactive:
                ink.saveSoon()
            case .background:
                ink.saveEverything()
                birthdays.waitUntilSaved()
                journal.waitUntilSaved()
                sketches.waitUntilSaved()
                lists.waitUntilSaved()
                AppLog.info("App in background")
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Midnight, time zone or clock change: move the "today" mark.
            now = Date()
        }
    }

    // MARK: - State

    private var data: PlannerData {
        PlannerData(
            birthdays: birthdays.birthdays,
            journal: journal.journal,
            sketches: sketches.sketches,
            todos: lists.todos,
            toBuy: lists.toBuy
        )
    }

    private var calendar: Calendar {
        PlannerLocale.calendar(locale: AppLocale.current)
    }

    /// The open journal page, if a journal page is open.
    private var openJournalID: UUID? {
        if case .journal(let id) = page { return id }
        return nil
    }

    private var today: PlannerDate {
        PlannerDate(date: now, calendar: calendar)
    }

    private var currentMonth: YearMonth {
        YearMonth(date: now, calendar: calendar)
    }

    private var barActions: PlannerBarActions {
        PlannerBarActions(
            open: open,
            previous: { step(-1) },
            next: { step(1) },
            today: { open(.month(currentMonth)) },
            birthdays: { sheet = .birthdays },
            toBuy: { open(page == .toBuy ? calendarPage : .toBuy) },
            journal: openJournal,
            sketches: { sheet = .sketches(nil) },
            newSketch: newSketch,
            newJournalPage: addJournalPage,
            journalPageSettings: {
                if case .journal(let id) = page { sheet = .journalPage(id) }
            },
            journalPages: { sheet = .journalPages },
            pinSketch: {
                if case .sketch(let id) = page { sheet = .pin(id) }
            },
            share: share,
            settings: { sheet = .settings }
        )
    }

    // MARK: - Opening pages

    private func open(_ target: PlannerPage) {
        guard target != page else { return }
        let leaving = page
        if target.isCalendarPage {
            calendarPage = target
        }
        if case .journal(let id) = target {
            lastJournalPage = id
        }
        page = target
        discardIfEmpty(leaving)
    }

    /// Previous/next: months and years, or the journal's pages.
    private func step(_ offset: Int) {
        if case .journal(let id) = page {
            if let neighbor = journal.journal.neighbor(of: id, offset: offset) {
                open(neighbor.page)
            }
        } else {
            open(offset < 0 ? page.previous : page.next)
        }
    }

    private func hasNeighbor(_ offset: Int) -> Bool {
        if case .journal(let id) = page {
            return journal.journal.neighbor(of: id, offset: offset) != nil
        }
        return (offset < 0 ? page.previous : page.next) != page
    }

    /// A page the app made by itself is removed when she leaves it without writing on it
    /// (no ink, and for a journal page no title).
    private func discardIfEmpty(_ leaving: PlannerPage) {
        guard provisional.remove(leaving) != nil else { return }
        switch leaving {
        case .journal(let id):
            guard let record = journal.page(id), record.trimmedTitle.isEmpty, !ink.hasInk(leaving) else { return }
            journal.delete(id)
            ink.deleteInk(of: leaving)
            if lastJournalPage == id {
                lastJournalPage = nil
            }
            AppLog.info("Left an empty journal page: removed")
        case .sketch(let id):
            guard !ink.hasInk(leaving) else { return }
            sketches.delete(id)
            ink.deleteInk(of: leaving)
            AppLog.info("Left an empty sketch: removed")
        default:
            break
        }
    }

    /// JOURNAL: the page last open, or the first one; a first page if there is none (iPad).
    /// On a journal page it shows all the pages.
    private func openJournal() {
        if case .journal = page {
            sheet = .journalPages
        } else if let id = lastJournalPage, journal.page(id) != nil {
            open(.journal(id))
        } else if let first = journal.pages.first {
            open(first.page)
        } else if ink.canDraw {
            let first = journal.addPage(date: today)
            provisional.insert(first.page)
            open(first.page)
        } else {
            sheet = .journalPages
        }
    }

    /// A new page dated today, right after the open journal page (or at the end).
    private func addJournalPage() {
        var after: UUID?
        if case .journal(let id) = page {
            after = id
        }
        let new = journal.addPage(date: today, after: after)
        open(new.page)
    }

    /// The page of a day (long press on the day): opened, or made if there is none.
    private func openDayPage(_ date: PlannerDate) {
        if let existing = journal.journal.page(on: date) {
            open(existing.page)
            return
        }
        guard ink.canDraw else { return }
        let new = journal.addPage(date: date)
        provisional.insert(new.page)
        open(new.page)
    }

    /// The sketch button: a blank page at once.
    private func newSketch() {
        let sketch = sketches.add()
        provisional.insert(sketch.page)
        open(sketch.page)
    }

    private func preloadNeighbors(of page: PlannerPage) {
        guard case .journal(let id) = page else { return }
        let neighbors = [-1, 1].compactMap { journal.journal.neighbor(of: id, offset: $0)?.page }
        ink.preload(neighbors)
    }

    // MARK: - Touches on the page

    /// A finger tap: the printed + of a list, the circle or box of a typed item, the sketch
    /// mark of a day, or a small month on the year page.
    private func handleTap(at point: CGPoint, in template: PageTemplate) {
        if let control = template.control(at: point) {
            switch control.id {
            case .addItem(let section):
                if let list = listKind(section) {
                    openList(list, template: template, focusNew: true)
                }
            case .itemMarker(let section, let line):
                if let list = listKind(section) {
                    lists.toggle(line: line, in: list)
                }
            case .sketchMark(let date):
                let pinned = sketches.pinned[date] ?? []
                if pinned.count == 1, let only = pinned.first {
                    open(only.page)
                } else if !pinned.isEmpty {
                    sheet = .sketches(date)
                }
            default:
                break
            }
            return
        }
        for region in template.regions(at: point) {
            if case .month(let month) = region.id {
                open(.month(month))
                return
            }
        }
    }

    /// A long press on a day (month page, or a small month on the year page) opens its page.
    private func handleLongPress(at point: CGPoint, in template: PageTemplate) {
        guard page.isCalendarPage else { return }
        for region in template.regions(at: point) {
            if case .day(let date) = region.id {
                openDayPage(date)
                return
            }
        }
    }

    /// A swipe turns the journal's pages.
    private func handleSwipe(_ offset: Int) {
        guard case .journal = page else { return }
        step(offset)
    }

    private func listKind(_ section: RegionID.Section) -> TypedListKind? {
        switch (section, page) {
        case (.todo, .month(let month)): .todo(month)
        case (.tobuy, .toBuy): .toBuy
        default: nil
        }
    }

    private func openList(_ list: TypedListKind, template: PageTemplate, focusNew: Bool) {
        let inked = Set(ink.inkedRegions(of: list.page, template: template).compactMap { list.line(of: $0) })
        sheet = .list(list, inkedLines: inked, focusNew: focusNew)
    }

    // MARK: - Deleting and copying

    private func deleteJournalPage(_ id: UUID) {
        let target = PlannerPage.journal(id)
        provisional.remove(target)
        if page == target {
            // Leave it first: the next page, the one before, or the calendar.
            let neighbor = journal.journal.neighbor(of: id, offset: 1) ?? journal.journal.neighbor(of: id, offset: -1)
            open(neighbor?.page ?? calendarPage)
        }
        journal.delete(id)
        ink.deleteInk(of: target)
        if lastJournalPage == id {
            lastJournalPage = nil
        }
    }

    private func duplicateJournalPage(_ id: UUID) {
        guard let copy = journal.duplicate(id) else { return }
        ink.copyInk(from: .journal(id), to: copy.page)
    }

    private func deleteSketch(_ id: UUID) {
        let target = PlannerPage.sketch(id)
        provisional.remove(target)
        if page == target {
            open(calendarPage)
        }
        sketches.delete(id)
        ink.deleteInk(of: target)
    }

    // MARK: - Sharing

    private func share(_ format: PageExportFormat) {
        let locale = AppLocale.current
        let content = PlannerPageContent(page: page, today: today, locale: locale, data: data)
        do {
            let url = try PageExporter.export(
                template: content.template, drawing: ink.drawing(of: page),
                name: exportName(locale: locale), format: format
            )
            #if DEBUG
            lastExport = PageExporter.lastExport
            #endif
            SharePresenter.present(url)
        } catch {
            AppLog.error("Could not export the page", error)
        }
    }

    /// The shared file's name: "November 2026", "2026", "To buy", the journal page's title
    /// or day, or "Sketch".
    private func exportName(locale: Locale) -> String {
        switch page {
        case .year(let year):
            return String(year)
        case .month(let month):
            return "\(CalendarNames.monthName(month.month, locale: locale)) \(month.year)"
        case .toBuy:
            return PlannerPageContent.toBuyTitle
        case .journal(let id):
            let record = journal.page(id)
            if let title = record?.trimmedTitle, !title.isEmpty { return title }
            if let date = record?.date { return JournalHeading.fullDate(date, locale: locale) }
            return String(localized: "Journal", comment: "The journal ('Τετράδιο'): free pages to write on. Top bar button, printed in capitals.")
        case .sketch:
            return PlannerPageContent.sketchTitle
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(_ sheet: PlannerSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .birthdays:
            BirthdaysView(book: birthdays)
        case .journalPages:
            JournalPagesView(
                journal: journal, ink: ink,
                currentPage: openJournalID,
                canDraw: ink.canDraw, today: today,
                onOpen: { id in
                    self.sheet = nil
                    open(.journal(id))
                },
                onAdd: {
                    self.sheet = nil
                    addJournalPage()
                },
                onDuplicate: duplicateJournalPage,
                onDelete: deleteJournalPage
            )
        case .journalPage(let id):
            JournalPageSettingsView(journal: journal, id: id, today: today) {
                deleteJournalPage(id)
            }
        case .sketches(let day):
            SketchesView(
                book: sketches, ink: ink, filterDay: day, canDraw: ink.canDraw, today: today,
                onOpen: { id in
                    self.sheet = nil
                    open(.sketch(id))
                },
                onNew: {
                    self.sheet = nil
                    newSketch()
                },
                onDelete: deleteSketch
            )
        case .pin(let id):
            SketchPinView(book: sketches, id: id, today: today)
        case .list(let kind, let inkedLines, let focusNew):
            TypedListView(lists: lists, kind: kind, inkedLines: inkedLines, focusNew: focusNew, title: listTitle(kind))
        }
    }

    private func listTitle(_ kind: TypedListKind) -> String {
        switch kind {
        case .todo(let month):
            let name = "\(CalendarNames.monthName(month.month, locale: AppLocale.current)) \(month.year)"
            return String(localized: "To-dos for \(name)", comment: "Title of the typed to-dos of a month, e.g. 'To-dos for November 2026'.")
        case .toBuy:
            return PlannerPageContent.toBuyTitle
        }
    }
}
