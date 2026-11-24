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
    /// The photos of things to buy (from the To Buy page).
    case wishlist
    /// A day's events of the Apple Calendar (a finger on a day).
    case day(PlannerDate)
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
        case .wishlist: "wishlist"
        case .day(let date): "day:\(date)"
        case .list(let kind, _, _): "list:\(kind.id)"
        }
    }
}

/// The planner: the bar on top, the open page (year, month, week, To Buy, a journal page
/// or a sketch) with the ink and the tool bar, and on planner pages the tabs on the right.
/// Opens on the current month.
struct RootView: View {
    let ink: InkController
    let birthdays: BirthdayBook
    let journal: JournalBook
    let sketches: SketchBook
    let lists: ListBook
    let wishlist: WishlistBook
    /// The events of the Apple Calendar, printed on the pages.
    let appleCalendar: CalendarBook
    /// iCloud sync: its discreet mark on the page, and Settings.
    let sync: CloudSync
    /// Her palette, pens, paper and lock (Settings).
    let settings: SettingsBook
    /// Face ID: the journal and sketches may be locked.
    let lock: AppLock
    @AppStorage(InkDefaults.drawWithFinger) private var drawWithFinger = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var now = AppClock.now
    @State private var page: PlannerPage
    /// The last year or month page: where other pages go back to, and whose tabs the To Buy
    /// page shows. On a week page it is the week's month: the one she came from while the
    /// week has days in it, otherwise the month with most of its days.
    @State private var calendarPage: PlannerPage
    /// The week page she left for the To Buy page, a journal page or a sketch: "back" goes there.
    @State private var returnWeek: PlannerWeek?
    /// The journal page last open: JOURNAL opens it again.
    @State private var lastJournalPage: UUID?
    /// Pages the app made without being asked for one (a day's page from a long press, a
    /// new sketch, the journal's first page): removed when left with no ink and no title.
    @State private var provisional: Set<PlannerPage> = []
    @State private var sheet: PlannerSheet?
    #if DEBUG
    @State private var lastExport = ""
    #endif

    init(
        ink: InkController, birthdays: BirthdayBook, journal: JournalBook, sketches: SketchBook,
        lists: ListBook, wishlist: WishlistBook, appleCalendar: CalendarBook, sync: CloudSync,
        settings: SettingsBook, lock: AppLock
    ) {
        self.ink = ink
        self.sync = sync
        self.settings = settings
        self.lock = lock
        self.wishlist = wishlist
        self.appleCalendar = appleCalendar
        self.birthdays = birthdays
        self.journal = journal
        self.sketches = sketches
        self.lists = lists
        let month = YearMonth(date: AppClock.now, calendar: PlannerLocale.calendar(locale: AppLocale.current))
        var first = LaunchOptions.initialPage ?? .month(month)
        if LaunchOptions.openPageArgument == "journal", let page = journal.pages.first {
            first = page.page
        }
        _page = State(initialValue: first)
        _calendarPage = State(initialValue: first.isCalendarPage ? first : .month(first.week?.month ?? month))
        if case .journal(let id) = first {
            _lastJournalPage = State(initialValue: id)
        }
    }

    var body: some View {
        let locale = AppLocale.current
        let compact = horizontalSizeClass == .compact
        let content = PlannerPageContent(page: page, today: today, locale: locale, data: data, month: calendarMonth)
        VStack(spacing: 0) {
            PlannerTopBar(
                page: page,
                backPage: backPage,
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
                .overlay(alignment: .bottomTrailing) {
                    SyncBadge(sync: sync, page: page)
                        .padding(12)
                }
                .overlay {
                    if ink.canDraw {
                        InkToolbarOverlay(ink: ink)
                    }
                }
                .overlay {
                    // "Lock: journal and sketches": the page waits for Face ID.
                    if lock.mode == .journal && lock.isLocked {
                        LockScreen(lock: lock, isWholeApp: false)
                    }
                }
                if !page.isNotebookPage {
                    PlannerTabs(
                        page: page.week == nil ? page : calendarPage,
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
        .overlay(alignment: .topTrailing) {
            // What the sync did since launch, for the UI tests.
            Text(verbatim: sync.debugSummary)
                .font(.system(size: 2))
                .foregroundStyle(.clear)
                .allowsHitTesting(false)
                .accessibilityIdentifier("debug.sync")
        }
        #endif
        .sheet(item: $sheet) { sheet in
            sheetView(sheet)
        }
        .onChange(of: page) { _, newPage in
            preloadNeighbors(of: newPage)
        }
        .onChange(of: showsNotebook, initial: true) { _, shows in
            lock.showsNotebook = shows
        }
        .onChange(of: journal.pages.map(\.id)) { _, ids in
            // The open journal page was deleted on another device: leave it.
            if case .journal(let id) = page, !ids.contains(id) {
                AppLog.info("The open journal page was deleted on another device")
                open(backPage)
            }
        }
        .onChange(of: sketches.sketches.map(\.id)) { _, ids in
            if case .sketch(let id) = page, !ids.contains(id) {
                AppLog.info("The open sketch was deleted on another device")
                open(backPage)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                now = AppClock.now
                appleCalendar.refreshAccess()
                sync.becameActive()
                AppLog.info("App active")
            case .inactive:
                ink.saveSoon()
            case .background:
                ink.saveEverything()
                birthdays.waitUntilSaved()
                journal.waitUntilSaved()
                sketches.waitUntilSaved()
                lists.waitUntilSaved()
                wishlist.waitUntilSaved()
                settings.waitUntilSaved()
                AppLog.info("App in background")
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            // Midnight, time zone or clock change: move the "today" mark.
            now = AppClock.now
        }
    }

    // MARK: - State

    /// A journal page or a sketch is on screen (the page, or a sheet with them).
    private var showsNotebook: Bool {
        if page.isNotebookPage { return true }
        switch sheet {
        case .journalPages?, .journalPage?, .sketches?, .pin?: return true
        default: return false
        }
    }

    private var data: PlannerData {
        PlannerData(
            birthdays: birthdays.birthdays,
            journal: journal.journal,
            sketches: sketches.sketches,
            todos: lists.todos,
            toBuy: lists.toBuy,
            inkedWeeks: ink.inkedWeeks,
            events: pageEvents,
            eventClock: EventClock.current
        )
    }

    /// The events printed on the open page: of its days (a week's, a month's, a year's).
    private var pageEvents: [CalendarEvent] {
        guard appleCalendar.showInCells else { return [] }
        switch page {
        case .year(let year):
            return appleCalendar.events(from: PlannerDate(year: year, month: 1, day: 1), through: PlannerDate(year: year, month: 12, day: 31))
        case .month(let month):
            return appleCalendar.events(from: month.firstDay, through: month.lastDay)
        case .week(let week):
            return appleCalendar.events(from: week.start, through: week.end)
        default:
            return []
        }
    }

    /// The month of `calendarPage`, when it is a month.
    private var calendarMonth: YearMonth? {
        if case .month(let month) = calendarPage { return month }
        return nil
    }

    /// Where "back" goes from a week page (its month), and from the To Buy page, journal
    /// pages and sketches (the week she left, or the last year or month page).
    private var backPage: PlannerPage {
        if page.week == nil, let returnWeek {
            return .week(returnWeek)
        }
        return calendarPage
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
            toBuy: { open(page == .toBuy ? backPage : .toBuy) },
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
            wishlist: { sheet = .wishlist },
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
            returnWeek = nil
        } else if let week = target.week {
            // A week keeps the month she came from while it has days in it.
            if !(calendarMonth.map(week.touches) ?? false) {
                calendarPage = .month(week.month)
            }
            returnWeek = nil
        } else if let week = leaving.week {
            returnWeek = week
        }
        if case .journal(let id) = target {
            lastJournalPage = id
        }
        page = target
        discardIfEmpty(leaving)
    }

    /// Previous/next: months, weeks and years, or the journal's pages.
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
    /// mark of a day, a day's header on the week page, a WEEKLY button, a small month on
    /// the year page, or a day (its events). With "Draw with finger too" a tap in a day
    /// writes (a dot): only the day's number opens its events, on the month page.
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
            case .dayPage(let date):
                openDayPage(date)
            default:
                break
            }
            return
        }
        for region in template.regions(at: point) {
            if case .day(let date) = region.id, case .month = page {
                if !drawWithFinger || MonthPageLayout.isOnDayNumber(point, cell: region.rect) {
                    sheet = .day(date)
                }
                return
            }
            if case .weekDay(let date) = region.id, page.week != nil {
                if !drawWithFinger {
                    sheet = .day(date)
                }
                return
            }
            if case .month(let month) = region.id {
                open(.month(month))
                return
            }
            if case .weekly(let number) = region.id, case .month(let month) = page {
                let weeks = PlannerWeek.weeks(of: month)
                if weeks.indices.contains(number - 1) {
                    open(.week(weeks[number - 1]))
                }
                return
            }
            // The text of a typed item opens its list (to change or delete it).
            for list in [listKind(.todo), listKind(.tobuy)].compactMap({ $0 }) {
                if let line = list.line(of: region.id), lists.items(list).contains(where: { $0.line == line }) {
                    openList(list, template: template, focusNew: false)
                    return
                }
            }
        }
    }

    /// A long press on a day (month or week page, or a small month on the year page) opens its page.
    private func handleLongPress(at point: CGPoint, in template: PageTemplate) {
        guard page.isCalendarPage || page.week != nil else { return }
        for region in template.regions(at: point) {
            switch region.id {
            case .day(let date), .weekDay(let date):
                openDayPage(date)
                return
            default:
                continue
            }
        }
    }

    /// A swipe turns the journal's pages and the weeks.
    private func handleSwipe(_ offset: Int) {
        switch page {
        case .journal, .week: step(offset)
        default: break
        }
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
            open(neighbor?.page ?? backPage)
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
            open(backPage)
        }
        sketches.delete(id)
        ink.deleteInk(of: target)
    }

    // MARK: - Sharing

    private func share(_ format: PageExportFormat) {
        let locale = AppLocale.current
        let content = PlannerPageContent(page: page, today: today, locale: locale, data: data, month: calendarMonth)
        do {
            let url = try PageExporter.export(
                template: content.template, drawing: ink.drawing(of: page),
                name: PlannerPageContent.exportName(of: page, journal: journal, locale: locale), format: format
            )
            #if DEBUG
            lastExport = PageExporter.lastExport
            #endif
            SharePresenter.present(url)
        } catch {
            AppLog.error("Could not export the page", error)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetView(_ sheet: PlannerSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView(calendar: appleCalendar, sync: sync, settings: settings, ink: ink, lock: lock)
        case .birthdays:
            BirthdaysView(book: birthdays)
        case .journalPages where lock.mode == .journal && lock.isLocked,
             .sketches where lock.mode == .journal && lock.isLocked:
            LockScreen(lock: lock, isWholeApp: false)
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
        case .wishlist:
            WishlistView(book: wishlist)
        case .day(let date):
            DayEventsView(book: appleCalendar, day: date, now: now)
        case .list(let kind, let inkedLines, let focusNew):
            TypedListView(lists: lists, kind: kind, inkedLines: inkedLines, focusNew: focusNew, title: PlannerPageContent.listTitle(kind))
        }
    }
}
