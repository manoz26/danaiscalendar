import PencilKit
import PlannerCore
import SwiftUI
import UIKit

/// The four tabs of the iPhone.
enum PhoneTab: String, CaseIterable, Identifiable {
    case month, today, lists, journal

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .month: "calendar"
        case .today: "sun.max"
        case .lists: "checklist"
        case .journal: "book.closed"
        }
    }

    var title: String {
        switch self {
        case .month: String(localized: "Month", comment: "iPhone tab: the month page with the handwriting.")
        case .today: String(localized: "Today")
        case .lists: String(localized: "Lists", comment: "iPhone tab: to buy, to do, birthdays and the wishlist.")
        case .journal: String(localized: "Journal", comment: "The journal ('Τετράδιο'): free pages to write on. Top bar button, printed in capitals.")
        }
    }
}

/// Keys of the iPhone's own settings in UserDefaults (which list and notebook were open).
enum PhoneDefaults {
    static let list = "DCPhoneList"
    static let notebook = "DCPhoneNotebook"

    static let all = [list, notebook]
}

/// A sheet over the iPhone's tabs.
enum PhoneSheet: Identifiable {
    case settings
    /// A day: its handwriting (its cell cut out of the page), its events, and the way to its week.
    case day(PlannerDate, handwriting: UIImage?, showsWeek: Bool)
    /// Typed items of a list, as on the iPad.
    case list(TypedListKind, focusNew: Bool)
    /// The sketches pinned to a day, when there are several.
    case sketches(PlannerDate)

    var id: String {
        switch self {
        case .settings: "settings"
        case .day(let date, _, _): "day:\(date)"
        case .list(let kind, _): "list:\(kind.id)"
        case .sketches(let date): "sketches:\(date)"
        }
    }
}

/// The iPhone: what was written on the iPad, to look at, and typed things to add.
/// There is no drawing here.
///
/// - Month: the real month page with the handwriting (pinch or tap twice to zoom, swipe
///   for the next month); its year from the title, a day's sheet from a tap, the week
///   from there.
/// - Today: today's and the next days' events, the month's to-dos, quick adding.
/// - Lists: to buy, to do, birthdays and the wishlist, made for one hand.
/// - Journal: the journal's pages and the sketches, as pictures and in full.
///
/// One canvas shows every page (as on the iPad); the other tabs cover it.
struct PhoneRootView: View {
    let ink: InkController
    let birthdays: BirthdayBook
    let journal: JournalBook
    let sketches: SketchBook
    let lists: ListBook
    let wishlist: WishlistBook
    let appleCalendar: CalendarBook
    let sync: CloudSync
    let settings: SettingsBook
    let lock: AppLock

    @Environment(\.scenePhase) private var scenePhase
    @State private var now = AppClock.now
    @State private var tab: PhoneTab
    /// The Month tab's page: a month, its year, or one of its weeks.
    @State private var calendarPage: PlannerPage
    /// The month the week pages belong to and go back to.
    @State private var month: YearMonth
    /// A page being read in another tab: the handwritten To Buy page (Lists), a journal
    /// page or a sketch (Journal).
    @State private var reading: [PhoneTab: PlannerPage]
    @State private var sheet: PhoneSheet?
    @State private var keyboardShown = false
    #if DEBUG
    @State private var lastExport = ""
    #endif

    init(
        ink: InkController, birthdays: BirthdayBook, journal: JournalBook, sketches: SketchBook,
        lists: ListBook, wishlist: WishlistBook, appleCalendar: CalendarBook, sync: CloudSync,
        settings: SettingsBook, lock: AppLock
    ) {
        self.ink = ink
        self.settings = settings
        self.lock = lock
        self.birthdays = birthdays
        self.journal = journal
        self.sketches = sketches
        self.lists = lists
        self.wishlist = wishlist
        self.appleCalendar = appleCalendar
        self.sync = sync

        let current = YearMonth(date: AppClock.now, calendar: PlannerLocale.calendar(locale: AppLocale.current))
        var tab = PhoneTab.month
        var calendarPage = PlannerPage.month(current)
        var month = current
        var reading: [PhoneTab: PlannerPage] = [:]
        if LaunchOptions.openPageArgument == "journal", let first = journal.pages.first {
            tab = .journal
            reading[.journal] = first.page
        } else if let page = LaunchOptions.initialPage {
            switch page {
            case .year:
                calendarPage = page
            case .month(let opened):
                calendarPage = page
                month = opened
            case .week(let week):
                calendarPage = page
                month = week.month
            case .toBuy:
                tab = .lists
                reading[.lists] = page
            case .journal, .sketch:
                tab = .journal
                reading[.journal] = page
            }
        }
        if let name = LaunchOptions.phoneTabArgument, let chosen = PhoneTab(rawValue: name) {
            tab = chosen
        }
        _tab = State(initialValue: tab)
        _calendarPage = State(initialValue: calendarPage)
        _month = State(initialValue: month)
        _reading = State(initialValue: reading)
    }

    var body: some View {
        let locale = AppLocale.current
        let page = shownPage
        let content = PlannerPageContent(page: page, today: today, locale: locale, data: data(for: page), month: month)
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 0) {
                    pageBar(page, locale: locale)
                    PlannerCanvas(
                        ink: ink,
                        content: content,
                        drawWithFinger: false,
                        hidden: !showsPage,
                        onTap: { point in handleTap(at: point, in: content.template) },
                        onLongPress: { point in handleLongPress(at: point, in: content.template) },
                        onSwipe: { offset in step(offset) }
                    )
                    .overlay(alignment: .bottomTrailing) {
                        SyncBadge(sync: sync, page: page)
                            .padding(10)
                    }
                }
                .opacity(showsPage ? 1 : 0)
                .allowsHitTesting(showsPage)
                .accessibilityHidden(!showsPage)

                if !showsPage {
                    tabContent
                        .background(Paper.background)
                }
            }
            .overlay {
                // "Lock: journal and sketches": the Journal tab waits for Face ID.
                if lock.mode == .journal && lock.isLocked {
                    LockScreen(lock: lock, isWholeApp: false)
                }
            }
            if !keyboardShown {
                PhoneTabBar(tab: tab, onSelect: select)
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
        .onChange(of: showsNotebook, initial: true) { _, shows in
            lock.showsNotebook = shows
        }
        .onChange(of: journal.pages.map(\.id)) { _, ids in
            // The journal page being read was deleted on another device: back to the pages.
            if case .journal(let id)? = reading[.journal], !ids.contains(id) {
                AppLog.info("The open journal page was deleted on another device")
                reading[.journal] = nil
            }
        }
        .onChange(of: sketches.sketches.map(\.id)) { _, ids in
            if case .sketch(let id)? = reading[.journal], !ids.contains(id) {
                AppLog.info("The open sketch was deleted on another device")
                reading[.journal] = nil
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // The tabs make room for the keyboard (the field being typed in sits right above it).
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
    }

    // MARK: - State

    /// The Month tab always shows its page; the other tabs when a page is being read there.
    private var showsPage: Bool {
        tab == .month || reading[tab] != nil
    }

    /// The journal's pages or sketches are on screen (the Journal tab, or a day's sketches).
    private var showsNotebook: Bool {
        if tab == .journal { return true }
        if case .sketches? = sheet { return true }
        return false
    }

    /// The page on the canvas (under the other tabs it is whatever was shown last).
    private var shownPage: PlannerPage {
        tab == .month ? calendarPage : reading[tab] ?? calendarPage
    }

    private var calendar: Calendar {
        PlannerLocale.calendar(locale: AppLocale.current)
    }

    private var today: PlannerDate {
        PlannerDate(date: now, calendar: calendar)
    }

    private var currentMonth: YearMonth {
        YearMonth(date: now, calendar: calendar)
    }

    private func data(for page: PlannerPage) -> PlannerData {
        PlannerData(
            birthdays: birthdays.birthdays,
            journal: journal.journal,
            sketches: sketches.sketches,
            todos: lists.todos,
            toBuy: lists.toBuy,
            inkedWeeks: ink.inkedWeeks,
            events: events(on: page),
            eventClock: EventClock.current
        )
    }

    /// The events printed on a page: of its days (a week's, a month's, a year's).
    private func events(on page: PlannerPage) -> [CalendarEvent] {
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

    // MARK: - Tabs

    /// A tab; the open tab again goes back to its first screen (the current month, the lists, the pages).
    private func select(_ target: PhoneTab) {
        guard target == tab else {
            tab = target
            return
        }
        if reading[target] != nil {
            reading[target] = nil
        } else if target == .month {
            open(.month(currentMonth))
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .month:
            EmptyView()
        case .today:
            PhoneTodayView(
                appleCalendar: appleCalendar, lists: lists, birthdays: birthdays, today: today, now: now,
                onAdd: { kind in sheet = .list(kind, focusNew: true) },
                onSettings: { sheet = .settings }
            )
        case .lists:
            PhoneListsView(
                lists: lists, birthdays: birthdays, wishlist: wishlist, ink: ink, today: today,
                onOpenToBuyPage: { reading[.lists] = .toBuy },
                onSettings: { sheet = .settings }
            )
        case .journal:
            PhoneNotebooksView(
                journal: journal, sketches: sketches, ink: ink, today: today,
                onOpen: { page in reading[.journal] = page },
                onSettings: { sheet = .settings }
            )
        }
    }

    // MARK: - The bar above the page

    private func pageBar(_ page: PlannerPage, locale: Locale) -> some View {
        PhonePageBar(
            page: page,
            back: back(from: page, locale: locale),
            hasPrevious: neighbor(of: page, -1) != nil,
            hasNext: neighbor(of: page, 1) != nil,
            onPrevious: { step(-1) },
            onNext: { step(1) },
            onToday: { open(.month(currentMonth)) },
            onShare: share,
            onSettings: { sheet = .settings }
        )
    }

    /// Where "back" goes: from a month to its year, from a week to its month, and from a
    /// page read in another tab to that tab.
    private func back(from page: PlannerPage, locale: Locale) -> PhonePageBar.Back? {
        switch page {
        case .year:
            return nil
        case .month(let shown):
            return PhonePageBar.Back(label: String(shown.year), identifier: "nav.year", toYear: true) {
                open(.year(shown.year))
            }
        case .week:
            let target = month
            return PhonePageBar.Back(label: CalendarNames.monthName(target.month, locale: locale), identifier: "nav.back") {
                open(.month(target))
            }
        case .toBuy:
            return PhonePageBar.Back(label: PhoneTab.lists.title, identifier: "nav.back") {
                reading[.lists] = nil
            }
        case .journal:
            return PhonePageBar.Back(label: PhoneTab.journal.title, identifier: "nav.back") {
                reading[.journal] = nil
            }
        case .sketch:
            let title = String(localized: "Sketches", comment: "The sketches: top bar button (printed in capitals) and title of their grid.")
            return PhonePageBar.Back(label: title, identifier: "nav.back") {
                reading[.journal] = nil
            }
        }
    }

    // MARK: - Opening pages

    private func open(_ target: PlannerPage) {
        switch target {
        case .year:
            calendarPage = target
            tab = .month
        case .month(let opened):
            month = opened
            calendarPage = target
            tab = .month
        case .week(let week):
            // A week keeps the month she came from while it has days in it.
            if !week.touches(month) {
                month = week.month
            }
            calendarPage = target
            tab = .month
        case .toBuy:
            reading[.lists] = target
            tab = .lists
        case .journal, .sketch:
            reading[.journal] = target
            tab = .journal
        }
    }

    /// The page before or after: years, months, weeks, and the journal's pages.
    private func neighbor(of page: PlannerPage, _ offset: Int) -> PlannerPage? {
        switch page {
        case .journal(let id):
            return journal.journal.neighbor(of: id, offset: offset)?.page
        case .year, .month, .week:
            let next = offset < 0 ? page.previous : page.next
            return next == page ? nil : next
        case .toBuy, .sketch:
            return nil
        }
    }

    /// The arrows, and a swipe across a page that is not zoomed in.
    private func step(_ offset: Int) {
        guard let target = neighbor(of: shownPage, offset) else { return }
        open(target)
    }

    /// The journal page of a day, if it has one (pages are made on the iPad).
    private func openDayPage(_ date: PlannerDate) {
        guard let existing = journal.journal.page(on: date) else { return }
        open(existing.page)
    }

    // MARK: - Touches on the page

    /// A finger tap: the printed + of a list, the circle or box of a typed item, the sketch
    /// mark of a day, a day (its sheet), a WEEKLY button, the month's title (its year), or
    /// a small month on the year page.
    private func handleTap(at point: CGPoint, in template: PageTemplate) {
        let page = shownPage
        if let control = template.control(at: point) {
            switch control.id {
            case .addItem(let section):
                if let list = listKind(section, on: page) {
                    sheet = .list(list, focusNew: true)
                }
            case .itemMarker(let section, let line):
                if let list = listKind(section, on: page) {
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
                showDay(date, on: page, in: region.rect, template: template)
                return
            }
            if case .weekDay(let date) = region.id, page.week != nil {
                showDay(date, on: page, in: region.rect, template: template)
                return
            }
            if case .month(let target) = region.id {
                open(.month(target))
                return
            }
            if case .weekly(let number) = region.id, case .month(let shown) = page {
                let weeks = PlannerWeek.weeks(of: shown)
                if weeks.indices.contains(number - 1) {
                    open(.week(weeks[number - 1]))
                }
                return
            }
            if case .title = region.id, case .month(let shown) = page {
                open(.year(shown.year))
                return
            }
            // The text of a typed item opens its list (to change or delete it).
            for list in [listKind(.todo, on: page), listKind(.tobuy, on: page)].compactMap({ $0 }) {
                if let line = list.line(of: region.id), lists.items(list).contains(where: { $0.line == line }) {
                    sheet = .list(list, focusNew: false)
                    return
                }
            }
        }
    }

    /// A long press on a day opens its journal page, if it has one.
    private func handleLongPress(at point: CGPoint, in template: PageTemplate) {
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

    /// A day's sheet, with the day's box cut out of the page when it has handwriting.
    private func showDay(_ date: PlannerDate, on page: PlannerPage, in rect: CGRect, template: PageTemplate) {
        let drawing = ink.drawing(of: page)
        let hasInk = drawing.strokes.contains { stroke in
            let bounds = stroke.renderBounds
            return rect.contains(CGPoint(x: bounds.midX, y: bounds.midY))
        }
        let handwriting = hasInk ? PageExporter.crop(template: template, drawing: drawing, rect: rect, scale: 4) : nil
        sheet = .day(date, handwriting: handwriting, showsWeek: page.week == nil)
    }

    private func listKind(_ section: RegionID.Section, on page: PlannerPage) -> TypedListKind? {
        switch (section, page) {
        case (.todo, .month(let month)): .todo(month)
        case (.tobuy, .toBuy): .toBuy
        default: nil
        }
    }

    // MARK: - Sharing

    private func share(_ format: PageExportFormat) {
        let locale = AppLocale.current
        let page = shownPage
        let content = PlannerPageContent(page: page, today: today, locale: locale, data: data(for: page), month: month)
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
    private func sheetView(_ sheet: PhoneSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView(calendar: appleCalendar, sync: sync, settings: settings, ink: ink, lock: lock)
        case .day(let date, let handwriting, let showsWeek):
            PhoneDayView(
                book: appleCalendar, day: date, now: now,
                handwriting: handwriting,
                hasJournalPage: journal.journal.page(on: date) != nil,
                showsWeek: showsWeek,
                onOpenWeek: {
                    self.sheet = nil
                    open(.week(PlannerWeek(containing: date)))
                },
                onOpenJournalPage: {
                    self.sheet = nil
                    openDayPage(date)
                }
            )
        case .list(let kind, let focusNew):
            TypedListView(
                lists: lists, kind: kind,
                inkedLines: ink.inkedLines(of: kind, today: today, locale: AppLocale.current),
                focusNew: focusNew, title: PlannerPageContent.listTitle(kind)
            )
        case .sketches where lock.mode == .journal && lock.isLocked:
            LockScreen(lock: lock, isWholeApp: false)
        case .sketches(let date):
            SketchesView(
                book: sketches, ink: ink, filterDay: date, canDraw: false, today: today,
                onOpen: { id in
                    self.sheet = nil
                    open(.sketch(id))
                },
                onNew: {},
                onDelete: { id in
                    sketches.delete(id)
                    ink.deleteInk(of: .sketch(id))
                }
            )
        }
    }
}

/// The thin bar above a page on the iPhone: back, the arrows, this month, and a menu with
/// Share and Settings.
struct PhonePageBar: View {
    struct Back {
        let label: String
        let identifier: String
        /// A month goes back to its year.
        var toYear = false
        let action: () -> Void
    }

    let page: PlannerPage
    let back: Back?
    let hasPrevious: Bool
    let hasNext: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    let onShare: (PageExportFormat) -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let back {
                BackButton(label: back.label, identifier: back.identifier, action: back.action)
                    .accessibilityLabel(back.toYear ? Text("Back to the year") : Text("Back"))
                    .accessibilityValue(Text(verbatim: back.label))
            }
            Spacer(minLength: 4)
            if showsArrows {
                BarIconButton(systemName: "chevron.left", identifier: "nav.previous", compact: true, action: onPrevious)
                    .disabled(!hasPrevious)
                    .opacity(hasPrevious ? 1 : 0.3)
                    .accessibilityLabel(previousLabel)
                BarIconButton(systemName: "chevron.right", identifier: "nav.next", compact: true, action: onNext)
                    .disabled(!hasNext)
                    .opacity(hasNext ? 1 : 0.3)
                    .accessibilityLabel(nextLabel)
            }
            if page.isCalendarPage || page.week != nil {
                BarIconButton(systemName: "calendar.badge.clock", identifier: "nav.today", compact: true, action: onToday)
                    .accessibilityLabel(Text("This month"))
            }
            Menu {
                Menu {
                    Button {
                        onShare(.pdf)
                    } label: {
                        Label {
                            Text("PDF")
                        } icon: {
                            Image(systemName: "doc.richtext")
                        }
                    }
                    .accessibilityIdentifier("share.pdf")
                    Button {
                        onShare(.image)
                    } label: {
                        Label {
                            Text("Image")
                        } icon: {
                            Image(systemName: "photo")
                        }
                    }
                    .accessibilityIdentifier("share.image")
                } label: {
                    Label("Share page", systemImage: "square.and.arrow.up")
                }
                Button(action: onSettings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings.button")
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Paper.ink)
                    .frame(width: 42, height: 44)
                    .contentShape(Rectangle())
                    .background(ShareAnchorReader())
            }
            .accessibilityLabel(Text("More"))
            .accessibilityIdentifier("nav.more")
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(Paper.background)
    }

    private var showsArrows: Bool {
        switch page {
        case .year, .month, .week, .journal: true
        case .toBuy, .sketch: false
        }
    }

    private var previousLabel: Text {
        switch page {
        case .year: Text("Previous year")
        case .month: Text("Previous month")
        case .week: Text("Previous week")
        default: Text("Previous page")
        }
    }

    private var nextLabel: Text {
        switch page {
        case .year: Text("Next year")
        case .month: Text("Next month")
        case .week: Text("Next week")
        default: Text("Next page")
        }
    }
}

/// The iPhone's tabs along the bottom: black and white, small capitals like the printed labels.
struct PhoneTabBar: View {
    let tab: PhoneTab
    let onSelect: (PhoneTab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PhoneTab.allCases) { item in
                let isOpen = item == tab
                Button {
                    onSelect(item)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 20, weight: isOpen ? .semibold : .regular))
                            .frame(height: 24)
                        Text(verbatim: PlannerText.uppercased(item.title, locale: AppLocale.current))
                            .font(.inter(isOpen ? .bold : .semibold, size: 10))
                            .tracking(0.8)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(isOpen ? Paper.ink : Paper.tabLabel)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: item.title))
                .accessibilityAddTraits(isOpen ? .isSelected : [])
                .accessibilityIdentifier("phone.tab.\(item.rawValue)")
            }
        }
        .background(Paper.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Paper.hairline)
                .frame(height: 1)
        }
    }
}

/// A row of names in small capitals, the chosen one black and underlined (like JOURNAL and
/// SKETCHES of the iPad's bar), with the gear at its right end.
struct PhoneSegments<Value: Hashable>: View {
    struct Item {
        let value: Value
        let title: String
        let identifier: String
    }

    let items: [Item]
    let selection: Value
    let onSelect: (Value) -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(items, id: \.value) { item in
                        let isOpen = item.value == selection
                        Button {
                            onSelect(item.value)
                        } label: {
                            Text(verbatim: PlannerText.uppercased(item.title, locale: AppLocale.current))
                                .font(.inter(isOpen ? .bold : .semibold, size: 12, relativeTo: .caption))
                                .tracking(1.1)
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isOpen ? Paper.ink : Paper.tabLabel)
                                .padding(.horizontal, 9)
                                .frame(minHeight: 46)
                                .overlay(alignment: .bottom) {
                                    if isOpen {
                                        Rectangle()
                                            .fill(Paper.ink)
                                            .frame(height: 2)
                                            .padding(.horizontal, 9)
                                            .padding(.bottom, 9)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: item.title))
                        .accessibilityAddTraits(isOpen ? .isSelected : [])
                        .accessibilityIdentifier(item.identifier)
                    }
                }
                .padding(.horizontal, 6)
            }
            SettingsButton(compact: true, action: onSettings)
                .padding(.trailing, 4)
        }
        .frame(height: 48)
        .background(Paper.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Paper.hairline)
                .frame(height: 1)
        }
    }
}

extension InkController {
    /// The lines of a typed list's page that have handwriting: a new typed item never
    /// takes one of them.
    func inkedLines(of list: TypedListKind, today: PlannerDate, locale: Locale) -> Set<Int> {
        let template = PlannerPageContent(page: list.page, today: today, locale: locale).template
        return Set(inkedRegions(of: list.page, template: template).compactMap { list.line(of: $0) })
    }
}
