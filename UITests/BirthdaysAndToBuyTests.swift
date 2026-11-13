import XCTest

/// The gift (birthdays) and bag (To Buy) buttons of the top bar.
///
/// In English a birthday is added through the form like a person would (name typed, day
/// and month on the wheels), shows up on its month page (a mark on the day, a line in
/// the notes), and is still there after the app is closed. In Greek, made-up birthdays
/// (`-DCSampleBirthdays YES`) are shown, one is deleted, and the To Buy page opens and
/// goes back.
final class BirthdaysAndToBuyTests: XCTestCase {
    @MainActor
    func testAddABirthdayAndOpenToBuyEnglish() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        XCTAssertFalse(element(app, "memo.birthday.1").exists, "A birthday line before any birthday")

        tap(app, "nav.birthdays")
        XCTAssertTrue(element(app, "birthdays.empty").waitForExistence(timeout: 10), "The empty birthdays list did not appear")
        settle()
        save(app, "en-portrait-birthdays-empty")

        tap(app, "birthdays.add")
        let name = app.textFields["birthday.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "The birthday form did not open")
        name.tap()
        name.typeText("Manos\n")
        pick(app, "birthday.month", wheel: 1, value: "March")
        pick(app, "birthday.day", wheel: 0, value: "21")
        settle()
        save(app, "en-portrait-birthday-form")
        tap(app, "birthday.save")

        XCTAssertTrue(row(app, containing: "Manos").waitForExistence(timeout: 10), "The new birthday is not in the list")
        settle()
        save(app, "en-portrait-birthdays-list")
        tap(app, "birthdays.done")

        // The month page marks the 21st and writes it in the notes.
        let line = element(app, "memo.birthday.1")
        XCTAssertTrue(line.waitForExistence(timeout: 10), "No birthday line in the notes")
        XCTAssertTrue(line.label.contains("Manos's birthday"), "Notes line: \(line.label)")
        XCTAssertEqual(element(app, "day.2029-03-21").value as? String, "Manos's birthday")
        settle()
        save(app, "en-portrait-month-birthday")

        // The bag opens the To Buy page; back returns to the month.
        tap(app, "nav.tobuy")
        waitForPage(app, "tobuy")
        XCTAssertFalse(element(app, "nav.previous").exists, "The To Buy page has no previous page")
        save(app, "en-portrait-tobuy")
        if isPad {
            XCUIDevice.shared.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, "tobuy")
            save(app, "en-landscape-tobuy")
            XCUIDevice.shared.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }
        tap(app, "nav.back")
        waitForPage(app, "2029-03")

        // Saved: still there after the app is closed and opened again.
        XCUIDevice.shared.press(.home)
        settle(2)
        app.terminate()
        app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "month:2029-03"], reset: false)
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        XCTAssertTrue(element(app, "memo.birthday.1").waitForExistence(timeout: 10), "The birthday was not saved")
    }

    @MainActor
    func testBirthdaysAndToBuyGreek() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "el", region: "GR", extraArguments: ["-DCSampleBirthdays", "YES", "-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")

        // Sample birthdays in March: Ελένη on the 7th, Μαρία and Νίκος on the 21st.
        XCTAssertTrue(element(app, "memo.birthday.3").waitForExistence(timeout: 10), "Expected three birthday lines")
        XCTAssertTrue(element(app, "memo.birthday.1").label.contains("Ελένη — γενέθλια"), element(app, "memo.birthday.1").label)
        XCTAssertTrue(element(app, "memo.birthday.2").label.contains("Μαρία — γενέθλια"), element(app, "memo.birthday.2").label)
        XCTAssertTrue(element(app, "memo.birthday.3").label.contains("Νίκος — γενέθλια"), element(app, "memo.birthday.3").label)
        XCTAssertEqual(element(app, "day.2029-03-21").value as? String, "Μαρία — γενέθλια, Νίκος — γενέθλια")
        save(app, "el-portrait-month-birthdays")

        tap(app, "nav.birthdays")
        let eleni = row(app, containing: "Ελένη")
        XCTAssertTrue(eleni.waitForExistence(timeout: 10), "The birthdays list did not open")
        settle()
        save(app, "el-portrait-birthdays")

        // Delete Ελένη: open her birthday, Delete, confirm.
        eleni.tap()
        XCTAssertTrue(app.textFields["birthday.name"].waitForExistence(timeout: 10), "The birthday form did not open")
        settle()
        save(app, "el-portrait-birthday-edit")
        tap(app, "birthday.delete")
        var confirm = app.buttons["birthday.confirmDelete"]
        if !confirm.waitForExistence(timeout: 3) {
            confirm = app.buttons["Διαγραφή"]
        }
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No confirmation before deleting")
        confirm.tap()
        XCTAssertTrue(row(app, containing: "Μαρία").waitForExistence(timeout: 10), "The list did not come back")
        XCTAssertFalse(row(app, containing: "Ελένη").exists, "Ελένη was not deleted")
        tap(app, "birthdays.done")

        let first = element(app, "memo.birthday.1")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "No birthday lines after deleting one")
        XCTAssertTrue(first.label.contains("Μαρία"), "First line after deleting Ελένη: \(first.label)")
        XCTAssertFalse(element(app, "memo.birthday.3").exists, "Still three birthday lines")

        tap(app, "nav.tobuy")
        waitForPage(app, "tobuy")
        XCTAssertEqual(element(app, "page.title").label, "ΝΑ ΑΓΟΡΑΣΩ")
        save(app, "el-portrait-tobuy")
        // The bag again goes back too.
        tap(app, "nav.tobuy")
        waitForPage(app, "2029-03")
    }

    // MARK: - Helpers

    /// Turns a wheel of a picker to a value. Falls back to the wheel's position on screen
    /// if the identifier is not on the picker itself.
    @MainActor
    private func pick(_ app: XCUIApplication, _ identifier: String, wheel index: Int, value: String) {
        var wheel = app.pickers[identifier].pickerWheels.firstMatch
        if !wheel.waitForExistence(timeout: 2) {
            wheel = app.pickerWheels.element(boundBy: index)
        }
        XCTAssertTrue(wheel.waitForExistence(timeout: 5), "The \(identifier) wheel was not found")
        wheel.adjust(toPickerWheelValue: value)
        XCTAssertEqual(wheel.value as? String, value, "\(identifier) did not turn to \(value)")
    }

    /// The row of the birthdays list whose label contains a text (a row joins its texts).
    @MainActor
    private func row(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "birthday.row", text))
            .firstMatch
    }
}
