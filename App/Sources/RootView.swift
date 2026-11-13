import SwiftUI
import UIKit
import PlannerCore

/// The planner: the bar on top, the open page (year, month or the To Buy page) with the
/// ink and the tool bar, and the tabs on the right. Opens on the current month.
struct RootView: View {
    let ink: InkController
    let birthdays: BirthdayBook
    @AppStorage(InkDefaults.drawWithFinger) private var drawWithFinger = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var now = Date()
    @State private var page: PlannerPage
    /// The last year or month page: where the To Buy page goes back to, and whose tabs it shows.
    @State private var calendarPage: PlannerPage
    @State private var showSettings = false
    @State private var showBirthdays = false

    init(ink: InkController, birthdays: BirthdayBook) {
        self.ink = ink
        self.birthdays = birthdays
        let month = YearMonth(date: Date(), calendar: PlannerLocale.calendar(locale: AppLocale.current))
        let first = LaunchOptions.initialPage ?? .month(month)
        _page = State(initialValue: first)
        _calendarPage = State(initialValue: first.isCalendarPage ? first : .month(month))
    }

    var body: some View {
        let locale = AppLocale.current
        let compact = horizontalSizeClass == .compact
        let content = PlannerPageContent(page: page, today: today, locale: locale, birthdays: birthdays.birthdays)
        VStack(spacing: 0) {
            PlannerTopBar(
                page: page,
                calendarPage: calendarPage,
                locale: locale,
                compact: compact,
                onOpen: open,
                onToday: { open(.month(currentMonth)) },
                onBirthdays: { showBirthdays = true },
                onToBuy: { open(page == .toBuy ? calendarPage : .toBuy) },
                onSettings: { showSettings = true }
            )
            HStack(spacing: 0) {
                PlannerCanvas(
                    ink: ink,
                    content: content,
                    drawWithFinger: drawWithFinger,
                    onTap: { point in handleTap(at: point, in: content.template) }
                )
                .overlay {
                    if ink.canDraw {
                        InkToolbarOverlay(ink: ink)
                    }
                }
                PlannerTabs(
                    page: page,
                    year: calendarPage.year ?? currentMonth.year,
                    locale: locale,
                    compact: compact,
                    onOpen: open
                )
            }
        }
        .background(Paper.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showBirthdays) {
            BirthdaysView(book: birthdays)
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

    private var calendar: Calendar {
        PlannerLocale.calendar(locale: AppLocale.current)
    }

    private var today: PlannerDate {
        PlannerDate(date: now, calendar: calendar)
    }

    private var currentMonth: YearMonth {
        YearMonth(date: now, calendar: calendar)
    }

    private func open(_ target: PlannerPage) {
        guard target != page else { return }
        if target.isCalendarPage {
            calendarPage = target
        }
        page = target
    }

    /// A finger tap on the page: a small month on the year page opens that month.
    /// (The WEEKLY buttons are printed but the weekly pages come later.)
    private func handleTap(at point: CGPoint, in template: PageTemplate) {
        for region in template.regions(at: point) {
            if case .month(let month) = region.id {
                open(.month(month))
                return
            }
        }
    }
}
