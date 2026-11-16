import XCTest

/// The week pages: opened from the WEEKLY buttons of the month page, turned with the
/// arrows and a swipe, a week across two months and across two years, the dots on the
/// WEEKLY buttons of weeks with ink, and a day's header that opens its journal page.
///
/// With `-DCSampleInk YES` every page opened without ink gets red rectangles in known
/// boxes (here the first and sixth days and the notes), checked against the printed boxes.
final class WeekTests: XCTestCase {
    private static func targets(_ week: String) -> [String] {
        let days = weekDays(week)
        return ["week.day.\(days[0])", "week.day.\(days[5])", "section.week-notes"]
    }

    /// The seven days from a Monday given as "yyyy-MM-dd".
    private static func weekDays(_ start: String) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let first = formatter.date(from: start)!
        return (0..<7).map { formatter.string(from: calendar.date(byAdding: .day, value: $0, to: first)!) }
    }

    @MainActor
    func testWeekPagesEnglish() throws {
        try captureWeeks(language: "en", region: "US", march: "March", april: "April")
    }

    @MainActor
    func testWeekPagesGreek() throws {
        try captureWeeks(language: "el", region: "GR", march: "Μάρτιος", april: "Απρίλιος")
    }

    @MainActor
    func testWeekAcrossTwoYearsEnglish() throws {
        try captureNewYearWeek(language: "en", region: "US", december: "DECEMBER", back: "December")
    }

    @MainActor
    func testWeekAcrossTwoYearsGreek() throws {
        try captureNewYearWeek(language: "el", region: "GR", december: "ΔΕΚΕΜΒΡΙΟΥ", back: "Δεκέμβριος")
    }

    // MARK: - Flows

    /// March 2026 → WEEKLY 4 (16-22 March, portrait and landscape) → next, next (30 March –
    /// 5 April, in both months) → swipe to 6-12 April → back to April, whose WEEKLY 1 and 2
    /// now have ink.
    @MainActor
    private func captureWeeks(language: String, region: String, march: String, april: String) throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait
        let app = launch(language: language, region: region, extraArguments: ["-DCSampleInk", "YES", "-DCOpenPage", "month:2026-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2026-03")
        XCTAssertEqual(value(app, "month.weekly.4"), "", "No week has ink yet")

        tapOnPage(app, "month.weekly.4")
        waitForPage(app, "week:2026-03-16")
        XCTAssertEqual(value(app, "nav.back"), march)
        if isPad {
            XCTAssertTrue(element(app, "tab.month.3").isSelected, "The week's month tab is not open")
        }
        save(app, "\(language)-portrait-week")
        checkInk(app, page: "page.week", targets: Self.targets("2026-03-16"), minimum: isPad ? 2 : 3)

        if isPad {
            device.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, "week:2026-03-16")
            save(app, "\(language)-landscape-week")
            checkInk(app, page: "page.week", targets: Self.targets("2026-03-16"), minimum: 1)
            device.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // The arrows turn the weeks; 30 March – 5 April is in March and in April.
        tap(app, "nav.next")
        waitForPage(app, "week:2026-03-23")
        tap(app, "nav.next")
        waitForPage(app, "week:2026-03-30")
        XCTAssertEqual(value(app, "nav.back"), march, "From March, the week across two months still belongs to March")
        save(app, "\(language)-portrait-week-two-months")
        checkInk(app, page: "page.week", targets: Self.targets("2026-03-30"), minimum: isPad ? 2 : 3)

        // A swipe turns to the next week, which is all in April.
        element(app, "page.week").swipeLeft()
        waitForPage(app, "week:2026-04-06")
        XCTAssertEqual(value(app, "nav.back"), april)
        if isPad {
            XCTAssertTrue(element(app, "tab.month.4").isSelected, "The April tab is not open")
        }

        // Back in April, the weeks she opened (and wrote on) have a dot.
        tap(app, "nav.back")
        waitForPage(app, "2026-04")
        XCTAssertNotEqual(value(app, "month.weekly.1"), "", "30 March – 5 April has ink")
        XCTAssertNotEqual(value(app, "month.weekly.2"), "", "6-12 April has ink")
        XCTAssertEqual(value(app, "month.weekly.3"), "", "13-19 April was never opened")
        save(app, "\(language)-portrait-month-weekly-ink")

        // The same page opens from April's WEEKLY 1.
        tapOnPage(app, "month.weekly.1")
        waitForPage(app, "week:2026-03-30")
        XCTAssertEqual(value(app, "nav.back"), april, "From April, the week belongs to April")
    }

    /// 28 December 2026 – 3 January 2027, opened directly. On iPad the header of 1 January
    /// opens its journal page, and back returns to the week, then to December.
    @MainActor
    private func captureNewYearWeek(language: String, region: String, december: String, back: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: language, region: region, extraArguments: ["-DCSampleInk", "YES", "-DCOpenPage", "week:2026-12-28"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "week:2026-12-28")
        let title = element(app, "page.title").label
        XCTAssertTrue(title.contains(december) && title.contains("2026 – 2027"), "Unexpected title '\(title)'")
        XCTAssertEqual(value(app, "nav.back"), back)
        save(app, "\(language)-portrait-week-two-years")
        checkInk(app, page: "page.week", targets: Self.targets("2026-12-28"), minimum: isPad ? 2 : 3)

        if isPad {
            tapOnPage(app, "week.header.2027-01-01")
            waitForPage(app, "journal:1")
            tap(app, "nav.back")
            waitForPage(app, "week:2026-12-28")
        }

        tap(app, "nav.back")
        waitForPage(app, "2026-12")
        XCTAssertNotEqual(value(app, "month.weekly.5"), "", "The week has ink")
        XCTAssertEqual(value(app, "month.weekly.4"), "")
    }
}
