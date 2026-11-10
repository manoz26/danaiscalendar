import SwiftUI
import UIKit
import PlannerCore

/// The planner: the bar on top, the open page (year or month) and the tabs on the right.
/// Opens on the current month.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var now = Date()
    @State private var page: PlannerPage
    @State private var showSettings = false

    init() {
        let month = YearMonth(date: Date(), calendar: PlannerLocale.calendar(locale: AppLocale.current))
        _page = State(initialValue: LaunchOptions.initialPage ?? .month(month))
    }

    var body: some View {
        let locale = AppLocale.current
        let content = PlannerPageContent(page: page, today: today, locale: locale)
        VStack(spacing: 0) {
            PlannerTopBar(
                page: page,
                onOpen: open,
                onToday: { open(.month(currentMonth)) },
                onSettings: { showSettings = true }
            )
            HStack(spacing: 0) {
                PageCanvasView(
                    template: content.template,
                    identifier: content.identifier,
                    spokenLabel: content.accessibilityLabel,
                    accessibilityItems: content.accessibilityItems,
                    onTap: { point in handleTap(at: point, in: content.template) }
                )
                // A fresh view per page: each page opens at 1x, scrolled to the top.
                .id(page)
                PlannerTabs(
                    page: page,
                    locale: locale,
                    compact: horizontalSizeClass == .compact,
                    onOpen: open
                )
            }
        }
        .background(Paper.background.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                now = Date()
                AppLog.info("App active")
            case .background:
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
