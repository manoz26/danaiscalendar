import SwiftUI
import UIKit
import PlannerCore

/// For now: one blank page with the current month's title.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var now = Date()

    var body: some View {
        GeometryReader { proxy in
            let scale = PageCanvas.scale(forWidth: proxy.size.width)
            ScrollView(.vertical) {
                BlankMonthPage(month: currentMonth, locale: AppLocale.current, scale: scale)
                    .frame(width: proxy.size.width, height: PageCanvas.size.height * scale)
            }
            .scrollIndicators(.hidden)
        }
        .background(Paper.background.ignoresSafeArea())
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = Date()
        }
    }

    private var currentMonth: YearMonth {
        YearMonth(date: now, calendar: PlannerLocale.calendar(locale: AppLocale.current))
    }
}

/// A white page on the 1000 x 1400 canvas, scaled to the view width.
struct BlankMonthPage: View {
    let month: YearMonth
    let locale: Locale
    let scale: CGFloat

    var body: some View {
        let title = MonthTitle.text(for: month, locale: locale)
        ZStack(alignment: .topLeading) {
            Paper.background
            Text(verbatim: title)
                .font(.inter(.bold, size: PageCanvas.titleFontSize * scale))
                .foregroundStyle(Paper.ink)
                .lineLimit(1)
                .fixedSize()
                .offset(x: PageCanvas.titleOrigin.x * scale, y: PageCanvas.titleOrigin.y * scale)
                .accessibilityIdentifier("page.title")
                .accessibilityAddTraits(.isHeader)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Month page for \(title)"))
        .accessibilityIdentifier("page.month")
    }
}
