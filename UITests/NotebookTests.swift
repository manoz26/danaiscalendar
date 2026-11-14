import XCTest

/// The journal ("Τετράδιο"), day pages, sketches, typed list items and sharing a page.
///
/// `-DCSampleNotebooks YES` puts four journal pages (lined "Ideas" on 5 March 2029, grid on
/// the 12th, dotted "Garden" without a date, blank on the 21st) and two sketches (one
/// pinned to 21 March 2029); `-DCSampleLists YES` typed to-dos for March 2029 and typed
/// things to buy.
final class NotebookTests: XCTestCase {
    /// Journal pages: opened from their day, turned with a swipe and the arrows, every
    /// paper, the pages grid (duplicate, delete), a new page with its title and paper.
    @MainActor
    func testJournalPagesEnglish() throws {
        guard isPad else { throw XCTSkip("Journal pages are written on the iPad.") }
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: [
            "-DCSampleNotebooks", "YES", "-DCSampleInk", "YES", "-DCOpenPage", "month:2029-03",
        ])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")

        // Days with a page have a dot; the 21st also has a pinned sketch.
        XCTAssertTrue(value(app, "day.2029-03-05").contains("Journal page"), value(app, "day.2029-03-05"))
        XCTAssertTrue(value(app, "day.2029-03-21").contains("Journal page"), value(app, "day.2029-03-21"))
        XCTAssertTrue(value(app, "day.2029-03-21").contains("Pinned sketch"), value(app, "day.2029-03-21"))
        XCTAssertFalse(value(app, "day.2029-03-06").contains("Journal page"))
        XCTAssertTrue(element(app, "day.sketches.2029-03-21").exists, "No sketch mark on the 21st")
        save(app, "en-portrait-month-notebooks")

        // A long press on the 5th opens its page: lined, "Ideas". PencilKit's own menu stays closed.
        longPressOnPage(app, "day.2029-03-05")
        waitForPage(app, "journal:1")
        XCTAssertFalse(pencilKitMenuIsOpen(app), "PencilKit's menu opened over the day's page. \(element(app, "debug.inkGeometry").label)")
        XCTAssertTrue(element(app, "page.title").label.contains("Ideas"), element(app, "page.title").label)
        XCTAssertFalse(element(app, "tab.year").exists, "Journal pages have no month tabs")
        checkInk(app, page: "page.journal", targets: ["page.title"], minimum: 1)
        save(app, "en-portrait-journal-lined")

        device.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        waitForPage(app, "journal:1")
        checkInk(app, page: "page.journal", targets: ["page.title"], minimum: 1)
        save(app, "en-landscape-journal-lined")
        device.orientation = .portrait
        waitForOrientation(app, landscape: false)

        // Swipe to the next pages: grid, then dotted ("Garden", no date); the arrows go on to blank.
        element(app, "page.journal").swipeLeft()
        waitForPage(app, "journal:2")
        save(app, "en-portrait-journal-grid")
        element(app, "page.journal").swipeLeft()
        waitForPage(app, "journal:3")
        XCTAssertTrue(element(app, "page.title").label.contains("Garden"), element(app, "page.title").label)
        save(app, "en-portrait-journal-dotted")
        tap(app, "nav.next")
        waitForPage(app, "journal:4")
        save(app, "en-portrait-journal-blank")
        XCTAssertFalse(element(app, "nav.next").isEnabled, "The last page has no next page")
        element(app, "page.journal").swipeRight()
        waitForPage(app, "journal:3")

        // All pages: duplicate the first, then delete the copy.
        tap(app, "nav.journal.pages")
        XCTAssertTrue(cells(app, "journal.pages.cell").firstMatch.waitForExistence(timeout: 10), "The pages grid did not open")
        settle()
        XCTAssertEqual(cells(app, "journal.pages.cell").count, 4)
        save(app, "en-portrait-journal-pages")
        cells(app, "journal.pages.cell").element(boundBy: 0).press(forDuration: 1.3)
        tapMenuItem(app, "Duplicate")
        waitForCount(app, "journal.pages.cell", 5)
        cells(app, "journal.pages.cell").element(boundBy: 1).press(forDuration: 1.3)
        tapMenuItem(app, "Delete")
        confirm(app, "journal.confirmDelete", label: "Delete")
        waitForCount(app, "journal.pages.cell", 4)
        tap(app, "journal.done")

        // A new page after the open one: today's date, then a title and grid paper.
        tap(app, "nav.journal.new")
        waitForPage(app, "journal:4")
        tap(app, "nav.journal.settings")
        let title = app.textFields["journal.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "The page details did not open")
        tap(app, "journal.paper.grid")
        title.tap()
        title.typeText("Plans\n")
        settle()
        save(app, "en-portrait-journal-settings")
        tap(app, "journal.settings.done")
        waitForPage(app, "journal:4")
        XCTAssertTrue(element(app, "page.title").label.contains("Plans"), element(app, "page.title").label)
        save(app, "en-portrait-journal-new")

        tap(app, "nav.back")
        waitForPage(app, "2029-03")
    }

    /// A day without a page gets one with a long press, and loses it again when left
    /// empty; a new sketch left empty is not kept; a pinned sketch opens from its mark and
    /// is unpinned; the month page is shared as a PDF.
    @MainActor
    func testDayPageSketchesAndSharingEnglish() throws {
        guard isPad else { throw XCTSkip("Day pages and sketches are drawn on the iPad.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCSampleNotebooks", "YES", "-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")

        longPressOnPage(app, "day.2029-03-08")
        waitForPage(app, "journal:5")
        XCTAssertFalse(pencilKitMenuIsOpen(app), "PencilKit's menu opened over the day's page")
        XCTAssertTrue(element(app, "page.title").label.contains("THURSDAY, MARCH 8"), element(app, "page.title").label)
        save(app, "en-portrait-journal-day")
        tap(app, "nav.back")
        waitForPage(app, "2029-03")
        XCTAssertFalse(value(app, "day.2029-03-08").contains("Journal page"), "An empty day page was kept")

        // New sketch: a blank page at once, not kept when left empty.
        tap(app, "nav.newSketch")
        waitForPage(app, "sketch")
        XCTAssertFalse(element(app, "tab.year").exists, "Sketches have no month tabs")
        save(app, "en-portrait-sketch-new")
        tap(app, "nav.back")
        waitForPage(app, "2029-03")
        tap(app, "nav.sketches")
        XCTAssertTrue(cells(app, "sketches.cell").firstMatch.waitForExistence(timeout: 10), "The sketches did not open")
        settle()
        XCTAssertEqual(cells(app, "sketches.cell").count, 2, "The empty sketch was kept")
        save(app, "en-portrait-sketches")
        tap(app, "sketches.done")

        // The sketch mark of the 21st opens its sketch; unpin it there.
        tapOnPage(app, "day.sketches.2029-03-21")
        waitForPage(app, "sketch")
        tap(app, "nav.sketch.pin")
        XCTAssertTrue(element(app, "pin.save").waitForExistence(timeout: 10), "The pin sheet did not open")
        settle()
        save(app, "en-portrait-sketch-pin")
        tap(app, "pin.remove")
        tap(app, "nav.back")
        waitForPage(app, "2029-03")
        XCTAssertFalse(value(app, "day.2029-03-21").contains("Pinned sketch"), "The sketch is still pinned")
        XCTAssertFalse(element(app, "day.sketches.2029-03-21").exists, "The sketch mark is still there")

        // Share the month page as a PDF.
        tap(app, "nav.share")
        tapMenuItem(app, "PDF")
        let export = element(app, "debug.lastExport")
        let exported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "pdf "), object: export)
        XCTAssertEqual(XCTWaiter().wait(for: [exported], timeout: 15), .completed, "No PDF was made: \(export.label)")
        let size = Int(export.label.split(separator: " ").last ?? "") ?? 0
        XCTAssertGreaterThan(size, 10_000, "The PDF is too small: \(export.label)")
        settle(2)
        save(app, "en-portrait-share")
    }

    /// Typed to-dos and things to buy: added from the printed +, printed on the lines,
    /// ticked with a finger on the page.
    @MainActor
    func testTypedItemsEnglish() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")

        tapOnPage(app, "todo.add")
        let field = app.textFields["list.new"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The to-do list did not open")
        field.tap()
        field.typeText("Call the bank\n")
        field.typeText("Buy flowers\n")
        settle()
        save(app, "en-portrait-todo-list")
        tap(app, "list.done")

        let first = element(app, "todo.item.1")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The typed to-do is not on the page")
        XCTAssertEqual(first.label, "Call the bank")
        XCTAssertEqual(element(app, "todo.item.2").label, "Buy flowers")
        XCTAssertEqual(first.value as? String, "Not ticked")
        tapOnPage(app, "todo.item.1")
        let ticked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ticked"), object: first)
        XCTAssertEqual(XCTWaiter().wait(for: [ticked], timeout: 10), .completed, "Tapping the circle did not tick it")
        settle()
        save(app, "en-portrait-month-typed")

        tap(app, "nav.tobuy")
        waitForPage(app, "tobuy")
        tapOnPage(app, "tobuy.add")
        let item = app.textFields["list.new"]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "The To Buy list did not open")
        item.tap()
        item.typeText("Milk\n")
        tap(app, "list.done")
        let milk = element(app, "tobuy.item.1")
        XCTAssertTrue(milk.waitForExistence(timeout: 10), "The typed item is not on the To Buy page")
        XCTAssertEqual(milk.label, "Milk")
        settle()
        save(app, "en-portrait-tobuy-typed")
    }

    /// Danai could not find how to delete a typed thing to buy: each row of the list has a bin,
    /// the ticked ones go all at once, and the text of a printed item opens its list.
    @MainActor
    func testDeletingTypedItems() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "tobuy"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")

        tapOnPage(app, "tobuy.add")
        let field = app.textFields["list.new"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "The To Buy list did not open")
        field.tap()
        for thing in ["Milk", "Bread", "Eggs", "Soap"] {
            field.typeText("\(thing)\n")
        }
        tap(app, "list.done")
        XCTAssertTrue(element(app, "tobuy.item.4").waitForExistence(timeout: 10), "The typed items are not on the page")

        // The text of a printed item (right of its box) opens the list; a bin deletes "Bread".
        tapText(app, "tobuy.item.2")
        let bins = cells(app, "list.item.delete")
        XCTAssertTrue(bins.firstMatch.waitForExistence(timeout: 10), "The list did not open from the item's text")
        XCTAssertEqual(bins.count, 4)
        settle()
        save(app, "en-portrait-tobuy-list-bins")
        bins.element(boundBy: 1).tap()
        waitForCount(app, "list.item.delete", 3)
        tap(app, "list.done")
        waitUntilGone(app, "tobuy.item.2")
        XCTAssertEqual(element(app, "tobuy.item.1").label, "Milk")
        XCTAssertEqual(element(app, "tobuy.item.3").label, "Eggs")

        // Tick two on the page, then delete the ticked ones at once (after a confirmation).
        for line in [1, 3] {
            let item = element(app, "tobuy.item.\(line)")
            tapOnPage(app, "tobuy.item.\(line)")
            let ticked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Ticked"), object: item)
            XCTAssertEqual(XCTWaiter().wait(for: [ticked], timeout: 10), .completed, "Item \(line) was not ticked")
        }
        tapText(app, "tobuy.item.4")
        XCTAssertTrue(element(app, "list.deleteTicked").waitForExistence(timeout: 10), "No Delete ticked items")
        settle()
        save(app, "en-portrait-tobuy-list-ticked")
        tap(app, "list.deleteTicked")
        confirm(app, "list.confirmDeleteTicked", label: "Delete")
        waitForCount(app, "list.item.delete", 1)
        XCTAssertFalse(element(app, "list.deleteTicked").exists, "Delete ticked items is still there with nothing ticked")
        tap(app, "list.done")
        waitUntilGone(app, "tobuy.item.1")
        waitUntilGone(app, "tobuy.item.3")
        XCTAssertEqual(element(app, "tobuy.item.4").label, "Soap")
        settle()
        save(app, "en-portrait-tobuy-after-delete")
    }

    /// Danai's drag of a page in the pages grid did not move it: page 1 dragged onto page 3
    /// goes to third place, and stays there after the app is closed (`journal.json`).
    @MainActor
    func testDraggingAJournalPage() throws {
        guard isPad else { throw XCTSkip("The pages grid is checked on the iPad.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var app = launch(language: "en", region: "US", extraArguments: ["-DCSampleNotebooks", "YES", "-DCOpenPage", "journal"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "journal:1")
        tap(app, "nav.journal.pages")
        let grid = cells(app, "journal.pages.cell")
        XCTAssertTrue(grid.firstMatch.waitForExistence(timeout: 10), "The pages grid did not open")
        settle()
        XCTAssertEqual(grid.count, 4)
        XCTAssertTrue(grid.element(boundBy: 0).label.hasPrefix("1. Ideas"), grid.element(boundBy: 0).label)
        XCTAssertTrue(grid.element(boundBy: 2).label.hasPrefix("3. Garden"), grid.element(boundBy: 2).label)

        let from = grid.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        let to = grid.element(boundBy: 2).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        from.press(forDuration: 1.0, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.8)
        settle(1.5)
        save(app, "en-portrait-journal-pages-dragged")
        let order = pageOrder(app)
        XCTAssertEqual(order.count, 4, "\(order)")
        XCTAssertTrue(order[2].hasPrefix("3. Ideas"), "Page 1 did not move to third place: \(order)")
        XCTAssertTrue(order[0].hasPrefix("1. "), "\(order)")
        XCTAssertTrue(order[1].hasPrefix("2. Garden"), "\(order)")
        tap(app, "journal.done")

        XCUIDevice.shared.press(.home)
        settle(2)
        app.terminate()
        app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "journal"], reset: false)
        waitForOrientation(app, landscape: false)
        waitForPage(app, "journal:1")
        tap(app, "nav.journal.pages")
        XCTAssertTrue(cells(app, "journal.pages.cell").firstMatch.waitForExistence(timeout: 10), "The pages grid did not open")
        settle()
        XCTAssertEqual(pageOrder(app), order, "The new order was not kept")
    }

    /// In Greek, with sample pages, sketches and typed items: the month page, the To Buy
    /// page, a journal page, the pages grid and the sketches (on iPhone through the … menu).
    @MainActor
    func testNotebooksGreek() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "el", region: "GR", extraArguments: [
            "-DCSampleNotebooks", "YES", "-DCSampleLists", "YES", "-DCOpenPage", "month:2029-03",
        ])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        XCTAssertEqual(element(app, "todo.item.1").label, "Τηλέφωνο στην τράπεζα")
        XCTAssertEqual(value(app, "todo.item.2"), "Έγινε")
        XCTAssertTrue(value(app, "day.2029-03-12").contains("Σελίδα τετραδίου"), value(app, "day.2029-03-12"))
        save(app, "el-portrait-month-notebooks")

        tap(app, "nav.tobuy")
        waitForPage(app, "tobuy")
        XCTAssertEqual(element(app, "tobuy.item.37").label, "Δώρο για τη Μαρία")
        save(app, "el-portrait-tobuy-typed")

        tapBarButton(app, "nav.journal", label: "Τετράδιο")
        waitForPage(app, "journal:1")
        XCTAssertTrue(element(app, "page.title").label.contains("Ιδέες"), element(app, "page.title").label)
        save(app, "el-portrait-journal")
        tapBarButton(app, "nav.journal.pages", label: "Όλες οι σελίδες")
        XCTAssertTrue(cells(app, "journal.pages.cell").firstMatch.waitForExistence(timeout: 10), "The pages grid did not open")
        settle()
        save(app, "el-portrait-journal-pages")
        tap(app, "journal.done")

        tapBarButton(app, "nav.sketches", label: "Σκίτσα")
        XCTAssertTrue(cells(app, "sketches.cell").firstMatch.waitForExistence(timeout: 10), "The sketches did not open")
        settle()
        save(app, "el-portrait-sketches")
        tap(app, "sketches.done")
    }

    // MARK: - Helpers

    /// PencilKit's long-press menu ("Select All", "Insert Space") is on screen.
    @MainActor
    private func pencilKitMenuIsOpen(_ app: XCUIApplication) -> Bool {
        ["Insert Space", "Select All"].contains { label in
            app.buttons[label].exists || app.menuItems[label].exists || app.staticTexts[label].exists
        }
    }

    @MainActor
    private func cells(_ app: XCUIApplication, _ identifier: String) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: identifier)
    }

    @MainActor
    private func waitForCount(_ app: XCUIApplication, _ identifier: String, _ count: Int) {
        let deadline = Date().addingTimeInterval(10)
        while cells(app, identifier).count != count, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
        XCTAssertEqual(cells(app, identifier).count, count, "Expected \(count) × \(identifier)")
    }

    /// Taps the text of a typed item printed on the page, right of its circle or box.
    @MainActor
    private func tapText(_ app: XCUIApplication, _ identifier: String) {
        let marker = element(app, identifier)
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "\(identifier) did not appear")
        marker.coordinate(withNormalizedOffset: CGVector(dx: 5, dy: 0.5)).tap()
    }

    @MainActor
    private func waitUntilGone(_ app: XCUIApplication, _ identifier: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element(app, identifier))
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 10), .completed, "\(identifier) is still on the page")
    }

    /// The labels of the pages grid, in order ("1. Ideas", …).
    @MainActor
    private func pageOrder(_ app: XCUIApplication) -> [String] {
        let grid = cells(app, "journal.pages.cell")
        return (0..<grid.count).map { grid.element(boundBy: $0).label }
    }

    /// A button of a context menu or a menu, by its label.
    @MainActor
    private func tapMenuItem(_ app: XCUIApplication, _ label: String) {
        let item = app.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "No menu item \(label)")
        item.tap()
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
