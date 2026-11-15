import XCTest

/// The Apple Calendar on the pages. The CI has no calendars and can't answer the system's
/// permission dialog, so `-DCSampleEvents YES` gives the app made-up calendars and events of
/// March 2029 (and `ask`: the same after "Connect Apple Calendar", without the dialog).
///
/// In English: events in the day cells, a day's list, an event's form, adding an event
/// and deleting it, the week page and the year's dots, and Settings (events off). In Greek:
/// connecting from a day, then the month and the week with events.
final class CalendarTests: XCTestCase {
    @MainActor
    func testEventsOnThePagesEnglish() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCSampleEvents", "YES", "-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        XCTAssertTrue(value(app, "day.2029-03-05").contains("Dentist"), value(app, "day.2029-03-05"))
        XCTAssertTrue(value(app, "day.2029-03-14").contains("Trip to Crete"), value(app, "day.2029-03-14"))
        XCTAssertTrue(value(app, "day.2029-03-16").contains("Trip to Crete"), "The trip lasts four days")
        save(app, "en-portrait-month-events")
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, "2029-03")
            save(app, "en-landscape-month-events")
            XCUIDevice.shared.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // The 21st: its eight events in a list, and one event's form.
        tapOnPage(app, "day.2029-03-21")
        let rows = app.buttons.matching(identifier: "events.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "The day's events did not open")
        XCTAssertGreaterThanOrEqual(rows.count, 5)
        settle()
        save(app, "en-portrait-day-events")
        rows.firstMatch.tap()
        let title = app.textFields["event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The event's form did not open")
        XCTAssertEqual(title.value as? String, "Gym")
        settle()
        save(app, "en-portrait-event-form")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        tap(app, "events.done")
        waitForPage(app, "2029-03")

        // A new event on the 7th, printed in its cell.
        XCTAssertFalse(value(app, "day.2029-03-07").contains("Coffee"))
        tapOnPage(app, "day.2029-03-07")
        XCTAssertTrue(element(app, "events.empty").waitForExistence(timeout: 10), "The 7th should have no events")
        tap(app, "events.add")
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The new event's form did not open")
        XCTAssertFalse(app.buttons["event.save"].isEnabled, "An event needs a title")
        title.tap()
        title.typeText("Coffee with Maria")
        save(app, "en-portrait-event-new")
        tap(app, "event.save")
        XCTAssertTrue(row(app, containing: "Coffee with Maria").waitForExistence(timeout: 10), "The new event is not in the day's list")
        tap(app, "events.done")
        waitForPage(app, "2029-03")
        XCTAssertTrue(wait(app, "day.2029-03-07", contains: "Coffee with Maria"), value(app, "day.2029-03-07"))
        save(app, "en-portrait-month-new-event")

        // And deleted again, after a confirmation.
        tapOnPage(app, "day.2029-03-07")
        let coffee = row(app, containing: "Coffee with Maria")
        XCTAssertTrue(coffee.waitForExistence(timeout: 10))
        coffee.tap()
        XCTAssertTrue(app.buttons["event.delete"].waitForExistence(timeout: 10), "No Delete in the form")
        app.buttons["event.delete"].tap()
        confirm(app, identifier: "event.confirmDelete", label: "Delete event")
        XCTAssertTrue(element(app, "events.empty").waitForExistence(timeout: 10), "The event was not deleted")
        tap(app, "events.done")
        waitForPage(app, "2029-03")
        XCTAssertTrue(wait(app, "day.2029-03-07", lacks: "Coffee with Maria"), value(app, "day.2029-03-07"))

        // The week of the 19th: start and end of each event.
        tapOnPage(app, "month.weekly.4")
        waitForPage(app, "week:2029-03-19")
        XCTAssertTrue(value(app, "week.day.2029-03-21").contains("Gym"), value(app, "week.day.2029-03-21"))
        XCTAssertTrue(value(app, "week.day.2029-03-25").contains("Easter holidays"), value(app, "week.day.2029-03-25"))
        save(app, "en-portrait-week-events")

        // The year: a dot under the days with events.
        tap(app, "tab.year")
        waitForPage(app, "2029")
        save(app, "en-portrait-year-events")
    }

    @MainActor
    func testCalendarSettingsEnglish() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCSampleEvents", "YES", "-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        XCTAssertTrue(value(app, "day.2029-03-05").contains("Dentist"))

        tapBarButton(app, "settings.button", label: "Settings")
        let toggle = app.switches["settings.showEvents"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "No 'Show events in the cells' in Settings")
        settle()
        save(app, "en-portrait-settings-calendar")

        // Calendars: untick Work, and its lunch leaves the 5th.
        tap(app, "settings.calendars")
        let work = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "calendars.row", "Work")).firstMatch
        XCTAssertTrue(work.waitForExistence(timeout: 10), "No Work calendar in the list")
        save(app, "en-portrait-settings-calendars")
        work.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))

        // Events off: the pages are purely handwritten.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(wait(toggle, value: "0"), "The switch did not turn off: \(String(describing: toggle.value))")
        tap(app, "settings.done")
        waitForPage(app, "2029-03")
        XCTAssertFalse(value(app, "day.2029-03-05").contains("Dentist"), value(app, "day.2029-03-05"))

        // On again: the 5th has the dentist but not the lunch of the unticked calendar.
        tapBarButton(app, "settings.button", label: "Settings")
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(wait(toggle, value: "1"))
        tap(app, "settings.done")
        waitForPage(app, "2029-03")
        XCTAssertTrue(wait(app, "day.2029-03-05", contains: "Dentist"), value(app, "day.2029-03-05"))
        XCTAssertFalse(value(app, "day.2029-03-05").contains("Lunch"), "The Work calendar is unticked")
    }

    @MainActor
    func testConnectAndEventsGreek() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "el", region: "GR", extraArguments: ["-DCSampleEvents", "ask", "-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        XCTAssertFalse(value(app, "day.2029-03-05").contains("Οδοντίατρος"), "Events before access")

        // A day explains, and connects with one tap. (A Wednesday: Mondays may be under the tools.)
        tapOnPage(app, "day.2029-03-14")
        let connect = app.buttons["events.connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10), "No connect button before access")
        settle()
        save(app, "el-portrait-day-connect")
        connect.tap()
        XCTAssertTrue(row(app, containing: "Ταξίδι στην Κρήτη").waitForExistence(timeout: 10), "No events after connecting")
        settle()
        save(app, "el-portrait-day-events")
        tap(app, "events.done")
        waitForPage(app, "2029-03")
        XCTAssertTrue(wait(app, "day.2029-03-05", contains: "Οδοντίατρος"), value(app, "day.2029-03-05"))
        save(app, "el-portrait-month-events")
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, "2029-03")
            save(app, "el-landscape-month-events")
            XCUIDevice.shared.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // The week of the trip to Crete.
        tapOnPage(app, "month.weekly.3")
        waitForPage(app, "week:2029-03-12")
        XCTAssertTrue(value(app, "week.day.2029-03-15").contains("Ταξίδι στην Κρήτη"), value(app, "week.day.2029-03-15"))
        save(app, "el-portrait-week-events")
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, "week:2029-03-12")
            save(app, "el-landscape-week-events")
            XCUIDevice.shared.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }
    }

    // MARK: - Helpers

    /// A row of a day's events whose label contains a text (a row joins its texts).
    @MainActor
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "events.row", text)).firstMatch
    }

    /// Waits until a page item's value contains (or lacks) a text: the page is printed again
    /// when the calendars change.
    @MainActor
    private func wait(_ app: XCUIApplication, _ identifier: String, contains text: String? = nil, lacks missing: String? = nil) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let current = value(app, identifier)
            if let text, current.contains(text) { return true }
            if let missing, !current.contains(missing) { return true }
            settle(0.3)
        }
        return false
    }

    @MainActor
    private func wait(_ element: XCUIElement, value: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func confirm(_ app: XCUIApplication, identifier: String, label: String) {
        var button = app.buttons.matching(identifier: identifier).firstMatch
        if !button.waitForExistence(timeout: 3) {
            // The form's own Delete button has the same label: take the last one (the dialog's).
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
            button = matches.element(boundBy: max(0, matches.count - 1))
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No confirmation")
        button.tap()
    }
}
