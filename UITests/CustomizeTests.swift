import XCTest

/// Prompt 9: the app made hers. Pens and colours (a palette of eight, favourite pens under
/// the colours, a tool hidden), the paper (dark paper, stronger lines), and the lock.
/// `-DCSampleSettings YES` sets the palette and favourites as if she had; `-DCUnlock`
/// stands in for Face ID, which the simulator cannot do.
final class CustomizeTests: XCTestCase {
    @MainActor
    func testPensAndColoursGreek() throws {
        guard isPad else { throw XCTSkip("There is no drawing on the iPhone.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "el", region: "GR", extraArguments: [
            "-DCOpenPage", "month:2029-03", "-DCToday", "2029-03-21", "-DCSampleSettings", "YES",
        ])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")

        // Eight colours in two columns, two favourites under them, no lasso.
        XCTAssertTrue(element(app, "toolbar.favorite.1").waitForExistence(timeout: 10), "No favourite pens in the toolbar")
        XCTAssertTrue(element(app, "toolbar.favorite.2").exists)
        XCTAssertTrue(element(app, "toolbar.color.custom-teal").exists, "The added colours are not in the toolbar")
        XCTAssertTrue(element(app, "toolbar.color.custom-orange").exists)
        XCTAssertFalse(element(app, "toolbar.tool.lasso").exists, "The lasso was hidden")
        save(app, "el-portrait-toolbar-favorites")

        // A favourite takes its tool; the star adds the pen in use.
        tap(app, "toolbar.favorite.2")
        XCTAssertTrue(wait(for: app.buttons["toolbar.tool.highlighter"], selected: true), "The favourite highlighter was not taken")
        XCTAssertTrue(app.buttons["toolbar.favorite.2"].isSelected)
        tap(app, "toolbar.tool.pencil")
        tap(app, "toolbar.color.custom-orange")
        tap(app, "toolbar.favorite.add")
        XCTAssertTrue(element(app, "toolbar.favorite.3").waitForExistence(timeout: 5), "The star did not add a favourite")
        XCTAssertTrue(app.buttons["toolbar.favorite.3"].isSelected)

        // Settings → Pens and colours.
        tapBarButton(app, "settings.button", label: "Ρυθμίσεις")
        tap(app, "settings.pens")
        XCTAssertTrue(element(app, "pens.color.8").waitForExistence(timeout: 10), "The palette has not eight colours")
        settle()
        save(app, "el-portrait-settings-pens")
        let pencil = app.switches["pens.show.pencil"]
        scroll(app, to: pencil)
        settle()
        save(app, "el-portrait-settings-pens-toolbar")
        pencil.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(wait(for: pencil, value: "0"), "The pencil did not turn off")

        // Settings → Paper: dark paper.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app, "settings.paper")
        XCTAssertTrue(element(app, "paper.preview").waitForExistence(timeout: 10), "No preview of the paper")
        settle()
        save(app, "el-portrait-settings-paper")
        let dark = app.switches["paper.dark"]
        scroll(app, to: dark)
        dark.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertTrue(wait(for: dark, value: "1"), "Dark paper did not turn on")
        scroll(app, to: element(app, "paper.preview"), up: true)
        settle()
        save(app, "el-portrait-settings-paper-dark")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Settings → Month page, with its preview.
        tap(app, "settings.month")
        XCTAssertTrue(element(app, "month.preview").waitForExistence(timeout: 10), "No preview of the month page")
        settle()
        save(app, "el-portrait-settings-month")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app, "settings.done")

        // The month page is dark now, and the toolbar has no pencil.
        waitForPage(app, "2029-03")
        settle(1.5)
        XCTAssertFalse(element(app, "toolbar.tool.pencil").exists, "The pencil was hidden")
        let page = element(app, "page.month")
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        let corner = CGRect(x: page.frame.minX + 4, y: page.frame.minY + 4, width: 16, height: 16)
        let color = ScreenPixels(XCUIScreen.main.screenshot()).averageColor(in: corner)
        XCTAssertLessThan(color.red + color.green + color.blue, 3 * 60, "The paper is not dark: \(color)")
        save(app, "el-portrait-month-dark")
    }

    @MainActor
    func testDarkPaperAndStrongLinesEnglish() throws {
        guard isPad else { throw XCTSkip("The iPhone's pages are checked in PhoneTests.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var app = launch(language: "en", region: "US", extraArguments: [
            "-DCOpenPage", "year:2029", "-DCToday", "2029-03-21", "-DCDarkPaper", "YES",
        ])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029")
        save(app, "en-portrait-year-dark")
        app.terminate()

        app = launch(language: "en", region: "US", extraArguments: [
            "-DCOpenPage", "month:2029-03", "-DCToday", "2029-03-21", "-DCLineStrength", "strong",
        ])
        waitForPage(app, "2029-03")
        save(app, "en-portrait-month-strong")
        app.terminate()

        // Ink on dark paper: the sample's red rectangles are still where they belong (PencilKit
        // shows the ink in its dark-mode colours; red stays red).
        app = launch(language: "en", region: "US", extraArguments: [
            "-DCOpenPage", "month:2029-03", "-DCToday", "2029-03-21", "-DCDarkPaper", "YES", "-DCSampleInk", "YES",
        ])
        waitForPage(app, "2029-03")
        settle(1.5)
        checkInk(app, page: "page.month", targets: ["section.goals", "day.2029-03-03", "day.2029-03-15", "section.todo"], minimum: 3)
        save(app, "en-portrait-month-dark-ink")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        waitForPage(app, "2029-03")
        save(app, "en-landscape-month-dark-ink")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
    }

    /// Her month page: the ink moves with its boxes, and a hidden box gets its ink back.
    @MainActor
    func testMonthLayoutMovesTheInkEnglish() throws {
        guard isPad else { throw XCTSkip("Ink is written on the iPad.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let page = ["-DCOpenPage", "month:2029-03", "-DCToday", "2029-03-21"]
        var app = launch(language: "en", region: "US", extraArguments: page + ["-DCSampleInk", "YES"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        settle(1.5)
        checkInk(app, page: "page.month", targets: ["section.goals", "day.2029-03-03", "day.2029-03-15", "section.todo", "section.memo"], minimum: 4)
        save(app, "en-portrait-month-layout-before")
        settle(1.5)
        app.terminate()

        // The notes above the days ("Ideas"), the to-do list alone under them with 12 lines, no goals.
        app = launch(language: "en", region: "US", extraArguments: page + ["-DCMonthLayout", "test"], reset: false)
        waitForPage(app, "2029-03")
        settle(1.5)
        XCTAssertFalse(element(app, "section.goals").exists, "The goals were hidden")
        for target in ["section.memo", "section.todo", "day.2029-03-03", "day.2029-03-15"] {
            let box = element(app, target)
            XCTAssertTrue(box.waitForExistence(timeout: 5), "\(target) is not on the page")
            XCTAssertNotNil(redBounds(app, in: box.frame.insetBy(dx: 1, dy: 1)), "The ink did not move into \(target)")
        }
        save(app, "en-portrait-month-layout-after")
        settle(1.5)
        app.terminate()

        // Back to the usual page: the goals' ink is back exactly where it was.
        app = launch(language: "en", region: "US", extraArguments: page + ["-DCMonthLayout", "standard"], reset: false)
        waitForPage(app, "2029-03")
        settle(1.5)
        checkInk(app, page: "page.month", targets: ["section.goals"], minimum: 1)
        save(app, "en-portrait-month-layout-back")
    }

    @MainActor
    func testLockEnglish() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        // Locked, and Face ID does not work: only the lock screen.
        var app = launch(language: "en", region: "US", extraArguments: [
            "-DCToday", "2029-03-21", "-DCLock", "app", "-DCUnlock", "no",
        ])
        let lockScreen = element(app, "lock.screen")
        XCTAssertTrue(lockScreen.waitForExistence(timeout: 15), "The app is not locked")
        XCTAssertTrue(app.buttons["lock.unlock"].waitForExistence(timeout: 5))
        settle()
        save(app, "en-portrait-lock")
        app.buttons["lock.unlock"].tap()
        XCTAssertTrue(lockScreen.exists, "Unlocked without Face ID")
        app.terminate()

        // Face ID works: asked at once, and the app opens.
        app = launch(language: "en", region: "US", extraArguments: [
            "-DCToday", "2029-03-21", "-DCLock", "app", "-DCUnlock", "yes",
        ])
        XCTAssertTrue(waitUntilGone(element(app, "lock.screen"), timeout: 15), "The app did not unlock")
        XCTAssertTrue(element(app, "page.title").waitForExistence(timeout: 10))
        app.terminate()

        // Only the journal and sketches: the month is open, the journal waits.
        let journal = isPad ? ["-DCOpenPage", "journal"] : ["-DCOpenPage", "journal", "-DCPhoneTab", "journal"]
        app = launch(language: "en", region: "US", extraArguments: [
            "-DCToday", "2029-03-21", "-DCLock", "journal", "-DCUnlock", "no", "-DCSampleNotebooks", "YES",
        ] + journal)
        XCTAssertTrue(element(app, "lock.screen").waitForExistence(timeout: 15), "The journal is not locked")
        settle()
        save(app, "en-portrait-lock-journal")
        app.terminate()

        app = launch(language: "en", region: "US", extraArguments: [
            "-DCToday", "2029-03-21", "-DCLock", "journal", "-DCUnlock", "no", "-DCOpenPage", "month:2029-03",
        ] + (isPad ? [] : ["-DCPhoneTab", "month"]))
        waitForPage(app, "2029-03")
        XCTAssertFalse(element(app, "lock.screen").exists, "The month page is locked too")
    }

    // MARK: - Helpers

    @MainActor
    private func wait(for element: XCUIElement, selected: Bool, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == %@", NSNumber(value: selected)), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func wait(for element: XCUIElement, value: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Swipes the settings list until the element can be tapped.
    @MainActor
    private func scroll(_ app: XCUIApplication, to element: XCUIElement, up: Bool = false) {
        let list = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        for _ in 0..<8 {
            if element.exists, element.isHittable { return }
            if up { list.swipeDown() } else { list.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) could not be reached")
    }
}
