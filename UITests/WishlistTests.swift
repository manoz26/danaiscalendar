import XCTest

/// The wishlist (the heart on the To Buy page). The tests cannot tap inside the system's
/// photo picker, so `-DCSampleWishlist YES` puts five pictures drawn by the code in it,
/// prepared the same way as picked photos.
///
/// In English: the empty wishlist with its + , the grid, a photo on the whole screen,
/// swiping to the next one, deleting it there, and the photos still there after the app is
/// closed. In Greek: the grid and a photo in both orientations (iPad), and deleting from a
/// photo's menu.
final class WishlistTests: XCTestCase {
    @MainActor
    func testWishlistEnglish() throws {
        guard isPad else { throw XCTSkip("The iPhone has its own screens (PhoneTests).") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "tobuy"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")

        // Empty: a big + and a line of text, and the + of the bar.
        tapBarButton(app, "nav.wishlist", label: "Wishlist")
        XCTAssertTrue(element(app, "wishlist.empty").waitForExistence(timeout: 10), "The empty wishlist did not appear")
        XCTAssertTrue(app.buttons["wishlist.empty.add"].isHittable, "No big + in the empty wishlist")
        XCTAssertTrue(app.buttons["wishlist.add"].isHittable, "No + in the bar")
        settle()
        save(app, "en-portrait-wishlist-empty")
        tap(app, "wishlist.done")
        waitForPage(app, "tobuy")

        // Five sample photos.
        app.terminate()
        app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "tobuy", "-DCSampleWishlist", "YES"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")
        tapBarButton(app, "nav.wishlist", label: "Wishlist")
        let cells = app.buttons.matching(identifier: "wishlist.cell")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "The photos did not appear")
        XCTAssertEqual(cells.count, 5)
        XCTAssertTrue(app.buttons["wishlist.add"].isHittable, "No + over the photos")
        settle(2)
        save(app, "en-portrait-wishlist-grid")

        // The newest on the whole screen, then the next one with a swipe.
        cells.element(boundBy: 0).tap()
        let position = element(app, "wishlist.viewer.position")
        XCTAssertTrue(position.waitForExistence(timeout: 10), "The photo did not open")
        XCTAssertTrue(wait(position, value: "1/5"), "Expected the first photo, found \(String(describing: position.value))")
        settle(1.5)
        save(app, "en-portrait-wishlist-photo")
        app.windows.firstMatch.swipeLeft()
        XCTAssertTrue(wait(position, value: "2/5"), "The swipe did not show the next photo: \(String(describing: position.value))")

        // Delete it there, after a confirmation: the next one takes its place.
        tap(app, "wishlist.viewer.delete")
        confirmDelete(app, label: "Delete")
        XCTAssertTrue(wait(position, value: "2/4"), "After deleting: \(String(describing: position.value))")
        tap(app, "wishlist.viewer.close")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(cells.count, 4)
        tap(app, "wishlist.done")
        waitForPage(app, "tobuy")

        // Saved: still four after the app is closed and opened again.
        XCUIDevice.shared.press(.home)
        settle(2)
        app.terminate()
        app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "tobuy"], reset: false)
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")
        tapBarButton(app, "nav.wishlist", label: "Wishlist")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "The photos were not kept")
        XCTAssertEqual(cells.count, 4)
    }

    @MainActor
    func testWishlistGreek() throws {
        guard isPad else { throw XCTSkip("The iPhone has its own screens (PhoneTests).") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "el", region: "GR", extraArguments: ["-DCOpenPage", "tobuy", "-DCSampleWishlist", "YES"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")
        save(app, "el-portrait-tobuy-wishlist")
        tapBarButton(app, "nav.wishlist", label: "Λίστα επιθυμιών")
        let cells = app.buttons.matching(identifier: "wishlist.cell")
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10), "The photos did not appear")
        XCTAssertEqual(cells.count, 5)
        settle(2)
        save(app, "el-portrait-wishlist-grid")

        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            settle(1.5)
            save(app, "el-landscape-wishlist-grid")
            cells.element(boundBy: 1).tap()
            let position = element(app, "wishlist.viewer.position")
            XCTAssertTrue(position.waitForExistence(timeout: 10), "The photo did not open")
            XCTAssertTrue(wait(position, value: "2/5"))
            settle(1.5)
            save(app, "el-landscape-wishlist-photo")
            tap(app, "wishlist.viewer.close")
            XCUIDevice.shared.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // Hold a photo: its menu deletes it, after a confirmation.
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 10))
        cells.element(boundBy: 0).press(forDuration: 1.2)
        let menuItem = app.buttons["Διαγραφή φωτογραφίας"]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "No menu on the photo")
        menuItem.tap()
        confirmDelete(app, label: "Διαγραφή")
        let four = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 4"), object: cells)
        XCTAssertEqual(XCTWaiter().wait(for: [four], timeout: 10), .completed, "Still \(cells.count) photos")
        tap(app, "wishlist.done")
        waitForPage(app, "tobuy")
    }

    // MARK: - Helpers

    @MainActor
    private func wait(_ element: XCUIElement, value: String, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Taps Delete in the confirmation (by identifier, else by its label).
    @MainActor
    private func confirmDelete(_ app: XCUIApplication, label: String) {
        var confirm = app.buttons.matching(identifier: "wishlist.confirmDelete").firstMatch
        if !confirm.waitForExistence(timeout: 3) {
            confirm = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation before deleting")
        confirm.tap()
    }
}
