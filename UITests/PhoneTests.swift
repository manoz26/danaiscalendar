import XCTest

/// The iPhone's own screens (prompt 8): what was written on the iPad, to look at, and typed
/// things to add. Four tabs: Month (the real page, its year, weeks and days), Today, Lists
/// (to buy, to do, birthdays, wishlist) and Journal (pages and sketches).
///
/// `-DCToday 2029-03-21` makes the app believe it is that day, where the sample events,
/// birthdays, to-dos and journal pages are. `-DCPhoneTab <tab>` opens a tab.
final class PhoneTests: XCTestCase {
    private static let today = ["-DCToday", "2029-03-21"]

    // MARK: - Month

    /// The month page with handwriting and events: two taps zoom in and out; a day opens
    /// its sheet with its handwriting enlarged and its events; from there its week; the
    /// title opens the year; a swipe turns the months; a long press opens a day's journal page.
    @MainActor
    func testMonthTabEnglish() throws {
        guard !isPad else { throw XCTSkip("The iPhone's tabs are checked on the iPhone.") }
        continueAfterFailure = false
        let app = launch(language: "en", region: "US", extraArguments: Self.today + [
            "-DCSampleInk", "YES", "-DCSampleEvents", "YES", "-DCSampleNotebooks", "YES", "-DCSampleBirthdays", "YES",
            "-DCOpenPage", "month:2029-03",
        ])
        waitForPage(app, "2029-03")
        XCTAssertTrue(app.buttons["phone.tab.month"].isSelected, "The Month tab is not open")
        XCTAssertFalse(element(app, "toolbar").exists, "There is no drawing on the iPhone")
        XCTAssertFalse(element(app, "tab.year").exists, "The iPhone's page has the whole width")
        checkInk(app, page: "page.month", targets: ["section.goals", "day.2029-03-03", "day.2029-03-15"], minimum: 3)
        save(app, "en-portrait-phone-month")

        // Two taps on the 15th zoom in on its week; two more zoom back out.
        let day = element(app, "day.2029-03-15")
        let fitted = day.frame.width
        day.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        settle(1.2)
        XCTAssertGreaterThan(day.frame.width, fitted * 1.8, "Two taps did not zoom in")
        XCTAssertFalse(app.buttons["Select All"].exists || app.menuItems["Select All"].exists, "PencilKit's menu opened on the iPhone")
        save(app, "en-portrait-phone-month-zoom")
        element(app, "page.month").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
        settle(1.2)
        XCTAssertEqual(day.frame.width, fitted, accuracy: 2, "Two more taps did not zoom back out")

        // The 15th: its handwriting cut out of the page, and the trip to Crete.
        tapOnPage(app, "day.2029-03-15")
        XCTAssertTrue(element(app, "day.handwriting").waitForExistence(timeout: 10), "The day's sheet has no handwriting")
        XCTAssertTrue(row(app, "events.row", containing: "Trip to Crete").exists, "The trip is not in the day's events")
        settle()
        save(app, "en-portrait-phone-day")

        // Its week page, read only; back goes to March.
        tap(app, "day.week")
        waitForPage(app, "week:2029-03-12")
        XCTAssertEqual(value(app, "nav.back"), "March")
        save(app, "en-portrait-phone-week")
        tap(app, "nav.back")
        waitForPage(app, "2029-03")

        // A day without handwriting has only its events; a new event is added from there.
        tapOnPage(app, "day.2029-03-07")
        XCTAssertTrue(element(app, "events.empty").waitForExistence(timeout: 10), "The 7th should have no events")
        XCTAssertFalse(element(app, "day.handwriting").exists, "Nothing is written on the 7th")
        tap(app, "events.add")
        let title = app.textFields["event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The new event's form did not open")
        title.tap()
        title.typeText("Coffee with Maria")
        tap(app, "event.save")
        XCTAssertTrue(row(app, "events.row", containing: "Coffee with Maria").waitForExistence(timeout: 10), "The new event is not in the day's list")
        tap(app, "events.done")
        waitForPage(app, "2029-03")
        XCTAssertTrue(wait(app, "day.2029-03-07", contains: "Coffee with Maria"), value(app, "day.2029-03-07"))

        // The month's title opens its year; a small month opens that month; a swipe turns back.
        tapOnPage(app, "page.title")
        waitForPage(app, "2029")
        save(app, "en-portrait-phone-year")
        tapOnPage(app, "year.month.2029-04")
        waitForPage(app, "2029-04")
        element(app, "page.month").swipeRight()
        waitForPage(app, "2029-03")

        // A long press on the 5th opens its journal page, in the Journal tab; back shows the pages.
        longPressOnPage(app, "day.2029-03-05")
        waitForPage(app, "journal:1")
        XCTAssertTrue(app.buttons["phone.tab.journal"].isSelected, "The Journal tab is not open")
        XCTAssertTrue(element(app, "page.title").label.contains("Ideas"), element(app, "page.title").label)
        save(app, "en-portrait-phone-journal-page")
        tap(app, "nav.back")
        XCTAssertTrue(cells(app, "journal.pages.cell").firstMatch.waitForExistence(timeout: 10), "The pages did not appear")
        XCTAssertFalse(element(app, "page.title").exists, "The page is still found under the pages grid")

        // The Month tab still has March.
        tap(app, "phone.tab.month")
        waitForPage(app, "2029-03")
    }

    // MARK: - Today

    /// Today in Greek: the day's events and birthdays, the month's to-dos (ticked with a
    /// tap), and adding a thing to buy and an event.
    @MainActor
    func testTodayTabGreek() throws {
        guard !isPad else { throw XCTSkip("The iPhone's tabs are checked on the iPhone.") }
        continueAfterFailure = false
        let app = launch(language: "el", region: "GR", extraArguments: Self.today + [
            "-DCSampleEvents", "YES", "-DCSampleLists", "YES", "-DCSampleBirthdays", "YES", "-DCPhoneTab", "today",
        ])
        let heading = element(app, "today.heading")
        XCTAssertTrue(heading.waitForExistence(timeout: 20), "The Today tab did not open")
        XCTAssertTrue(heading.label.contains("21") && heading.label.contains("2029"), heading.label)
        XCTAssertTrue(app.buttons["phone.tab.today"].isSelected)
        XCTAssertFalse(element(app, "page.title").exists, "The page is found under the Today tab")
        XCTAssertGreaterThanOrEqual(cells(app, "today.event").count, 3, "The 21st has eight events")
        XCTAssertEqual(cells(app, "today.birthday").count, 2, "Μαρία and Νίκος have their birthday on the 21st")
        settle()
        save(app, "el-portrait-phone-today")

        // A new event today, from the +.
        tap(app, "today.add")
        let newEvent = app.buttons["Νέο συμβάν"].firstMatch
        XCTAssertTrue(newEvent.waitForExistence(timeout: 5), "No 'New event' in the + menu")
        newEvent.tap()
        let title = app.textFields["event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The new event's form did not open")
        title.tap()
        title.typeText("Βόλτα")
        tap(app, "event.save")
        XCTAssertTrue(row(app, "today.event", containing: "Βόλτα").waitForExistence(timeout: 10), "The new event is not in Today")

        // The month's typed to-dos: a tap ticks one.
        let todos = cells(app, "today.todo")
        scroll(app, to: app.buttons["today.addTodo"])
        XCTAssertEqual(todos.count, 3)
        let first = todos.element(boundBy: 0)
        XCTAssertEqual(first.value as? String, "Δεν έγινε")
        let name = first.label
        first.tap()
        let ticked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label == %@ AND value == %@", "today.todo", name, "Έγινε")).firstMatch
        XCTAssertTrue(ticked.waitForExistence(timeout: 10), "\(name) was not ticked")
        settle()
        save(app, "el-portrait-phone-today-todos")

        // A new thing to buy: the list opens with the keyboard ready.
        let count = element(app, "today.toBuyCount")
        scroll(app, to: count)
        XCTAssertTrue(count.label.hasSuffix(" 3"), count.label)
        tap(app, "today.addToBuy")
        let field = app.textFields["list.new"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The To Buy list did not open")
        field.tap()
        field.typeText("Καφές\n")
        tap(app, "list.done")
        XCTAssertTrue(wait(count, label: " 4"), count.label)
    }

    // MARK: - Lists

    /// The lists in English: To Buy with big rows (adding, ticking, the ticked ones below,
    /// deleting them), its handwritten page, the month's to-dos, birthdays and the wishlist.
    /// What was typed here is printed on the page's lines.
    @MainActor
    func testListsTabEnglish() throws {
        guard !isPad else { throw XCTSkip("The iPhone's tabs are checked on the iPhone.") }
        continueAfterFailure = false
        let app = launch(language: "en", region: "US", extraArguments: Self.today + [
            "-DCSampleLists", "YES", "-DCSampleBirthdays", "YES", "-DCSampleWishlist", "YES", "-DCPhoneTab", "lists",
        ])
        let items = cells(app, "phone.list.item")
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 20), "The To Buy list did not open")
        XCTAssertEqual(labels(items), ["Milk", "Batteries", "A gift for Maria", "Bread"], "Open items first, the ticked one last")
        XCTAssertEqual(items.element(boundBy: 3).value as? String, "Ticked")
        settle()
        save(app, "en-portrait-phone-tobuy")

        // Two new items, one after the other, from the field at the bottom.
        let field = app.textFields["phone.list.new"]
        field.tap()
        field.typeText("Coffee\n")
        field.typeText("Tea\n")
        XCTAssertTrue(wait(count: 6, of: items), "\(labels(items))")
        save(app, "en-portrait-phone-tobuy-typing")

        // A tap ticks Milk: it falls below, next to Bread. Then both are deleted at once.
        XCTAssertEqual(labels(items), ["Milk", "Batteries", "A gift for Maria", "Coffee", "Tea", "Bread"], "New items go last")
        app.swipeDown()
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 0"), object: app.keyboards)
        XCTAssertEqual(XCTWaiter().wait(for: [keyboardGone], timeout: 5), .completed, "The keyboard did not go away")
        settle()
        // In the middle of the row, away from its box and text: the whole row ticks.
        items.element(boundBy: 0).tap()
        let expected = ["Batteries", "A gift for Maria", "Coffee", "Tea", "Milk", "Bread"]
        let ticked = wait(labels: expected, of: items)
        app.swipeUp()
        settle()
        save(app, "en-portrait-phone-tobuy-ticked")
        XCTAssertTrue(ticked, "\(labels(items))")
        tap(app, "phone.list.deleteTicked")
        confirm(app, "phone.list.confirmDeleteTicked", label: "Delete")
        XCTAssertTrue(wait(labels: ["Batteries", "A gift for Maria", "Coffee", "Tea"], of: items), "\(labels(items))")

        // The page the iPad prints them on: each typed item on its own line.
        app.swipeDown()
        tap(app, "phone.list.page")
        waitForPage(app, "tobuy")
        XCTAssertEqual(element(app, "tobuy.item.3").label, "Batteries")
        XCTAssertEqual(element(app, "tobuy.item.4").label, "Coffee", "A new item takes the first free line")
        XCTAssertEqual(element(app, "tobuy.item.5").label, "Tea")
        XCTAssertEqual(element(app, "tobuy.item.37").label, "A gift for Maria")
        XCTAssertFalse(element(app, "tobuy.item.1").exists, "Milk was deleted")
        save(app, "en-portrait-phone-tobuy-page")
        tap(app, "nav.back")
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: 10), "Back did not return to the list")

        // To do: the to-dos of the month (March 2029 here), and the months around it.
        tap(app, "phone.lists.toDo")
        XCTAssertTrue(wait(element(app, "phone.todo.month"), label: "March 2029"), element(app, "phone.todo.month").label)
        XCTAssertTrue(wait(count: 3, of: items), "\(labels(items))")
        settle()
        save(app, "en-portrait-phone-todo")
        tap(app, "phone.todo.next")
        XCTAssertTrue(wait(element(app, "phone.todo.month"), label: "April 2029"))
        XCTAssertTrue(element(app, "phone.list.empty").waitForExistence(timeout: 10), "April should have no to-dos")

        // Birthdays: the same list as the gift of the iPad, without a Done.
        tap(app, "phone.lists.birthdays")
        XCTAssertTrue(cells(app, "birthday.row").firstMatch.waitForExistence(timeout: 10), "The birthdays did not appear")
        XCTAssertTrue(app.buttons["birthdays.add"].exists)
        XCTAssertFalse(app.buttons["birthdays.done"].exists)
        settle()
        save(app, "en-portrait-phone-birthdays")

        // The wishlist, with its +.
        tap(app, "phone.lists.wishlist")
        let photos = app.buttons.matching(identifier: "wishlist.cell")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10), "The wishlist's photos did not appear")
        XCTAssertEqual(photos.count, 5)
        XCTAssertTrue(app.buttons["wishlist.add"].exists)
        settle(2)
        save(app, "en-portrait-phone-wishlist")
        photos.element(boundBy: 0).tap()
        XCTAssertTrue(element(app, "wishlist.viewer.position").waitForExistence(timeout: 10), "The photo did not open")
        settle(1.5)
        save(app, "en-portrait-phone-wishlist-photo")
        tap(app, "wishlist.viewer.close")

        // The Settings open from the gear of the lists.
        tap(app, "settings.button")
        XCTAssertTrue(app.buttons["settings.version"].waitForExistence(timeout: 10), "Settings did not open")
        tap(app, "settings.done")
    }

    // MARK: - Journal

    /// The journal's pages and the sketches in Greek: the grids, a page in full with its
    /// handwriting, the arrows and a swipe, and a sketch.
    @MainActor
    func testJournalTabGreek() throws {
        guard !isPad else { throw XCTSkip("The iPhone's tabs are checked on the iPhone.") }
        continueAfterFailure = false
        let app = launch(language: "el", region: "GR", extraArguments: Self.today + [
            "-DCSampleNotebooks", "YES", "-DCSampleInk", "YES", "-DCPhoneTab", "journal",
        ])
        let pages = cells(app, "journal.pages.cell")
        XCTAssertTrue(pages.firstMatch.waitForExistence(timeout: 20), "The journal's pages did not appear")
        XCTAssertEqual(pages.count, 4)
        XCTAssertTrue(pages.element(boundBy: 0).label.hasPrefix("1. Ιδέες"), pages.element(boundBy: 0).label)
        settle()
        save(app, "el-portrait-phone-journal")

        pages.element(boundBy: 0).tap()
        waitForPage(app, "journal:1")
        XCTAssertTrue(element(app, "page.title").label.contains("Ιδέες"), element(app, "page.title").label)
        checkInk(app, page: "page.journal", targets: ["page.title"], minimum: 1)
        save(app, "el-portrait-phone-journal-page")
        tap(app, "nav.next")
        waitForPage(app, "journal:2")
        element(app, "page.journal").swipeLeft()
        waitForPage(app, "journal:3")
        XCTAssertTrue(element(app, "page.title").label.contains("Κήπος"), element(app, "page.title").label)
        tap(app, "nav.back")
        XCTAssertTrue(pages.firstMatch.waitForExistence(timeout: 10), "Back did not return to the pages")

        tap(app, "phone.notebooks.sketches")
        let sketches = cells(app, "sketches.cell")
        XCTAssertTrue(sketches.firstMatch.waitForExistence(timeout: 10), "The sketches did not appear")
        XCTAssertEqual(sketches.count, 2)
        settle()
        save(app, "el-portrait-phone-sketches")
        sketches.element(boundBy: 0).tap()
        waitForPage(app, "sketch")
        XCTAssertFalse(element(app, "nav.next").exists, "Sketches have no next page")
        save(app, "el-portrait-phone-sketch")
        tap(app, "nav.back")
        XCTAssertTrue(sketches.firstMatch.waitForExistence(timeout: 10), "Back did not return to the sketches")
    }

    // MARK: - Helpers

    /// Swipes up until something further down a list is on screen.
    @MainActor
    private func scroll(_ app: XCUIApplication, to target: XCUIElement) {
        for _ in 0..<8 where !(target.exists && target.isHittable) {
            app.swipeUp()
            settle(0.4)
        }
        XCTAssertTrue(target.exists, "Not found after scrolling: \(target)")
    }

    @MainActor
    private func cells(_ app: XCUIApplication, _ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    @MainActor
    private func labels(_ query: XCUIElementQuery) -> [String] {
        (0..<query.count).map { query.element(boundBy: $0).label }
    }

    /// An element with an identifier whose label contains a text (a row joins its texts).
    @MainActor
    private func row(_ app: XCUIApplication, _ identifier: String, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", identifier, text))
            .firstMatch
    }

    @MainActor
    private func wait(count: Int, of query: XCUIElementQuery) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while query.count != count, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return query.count == count
    }

    @MainActor
    private func wait(labels expected: [String], of query: XCUIElementQuery) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while labels(query) != expected, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return labels(query) == expected
    }

    /// Waits until an element's label ends with (or is) a text.
    @MainActor
    private func wait(_ element: XCUIElement, label suffix: String) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if element.exists, element.label.hasSuffix(suffix) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        return false
    }

    /// Waits until a page item's value contains a text (the page is printed again when the
    /// calendars change).
    @MainActor
    private func wait(_ app: XCUIApplication, _ identifier: String, contains text: String) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if value(app, identifier).contains(text) { return true }
            settle(0.3)
        }
        return false
    }

    /// The confirming button of a dialog, by identifier or else by label.
    @MainActor
    private func confirm(_ app: XCUIApplication, _ identifier: String, label: String) {
        var button = app.buttons.matching(identifier: identifier).firstMatch
        if !button.waitForExistence(timeout: 3) {
            button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5), "No confirmation \(label)")
        button.tap()
    }
}
