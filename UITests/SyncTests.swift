import XCTest

/// iCloud sync (prompt 7) without iCloud: `-DCFakeCloud YES` makes a plain folder play
/// iCloud, and `-DCSampleCloud YES` puts another device's files there (two typed things to
/// buy on lines 5 and 6, a birthday on 12 March, red rectangles on March 2029).
///
/// A device with its own typed items meets that iCloud: both lists merge, each item once,
/// and the other device's ink lines up with the page. Then a new device (no data of its
/// own, same iCloud) gets everything back.
final class SyncTests: XCTestCase {
    private static let monthTargets = ["section.goals", "day.2029-03-03", "day.2029-03-15", "section.todo", "section.memo"]
    /// The typed things to buy: four of this device's (`-DCSampleLists`), two of the other's.
    private static let toBuyLines = [1, 2, 3, 5, 6, 37]

    @MainActor
    func testFakeICloudMergesAndANewDeviceGetsEverything() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var app = launch(language: "en", region: "US", extraArguments: [
            "-DCSampleLists", "YES", "-DCFakeCloud", "YES", "-DCSampleCloud", "YES", "-DCOpenPage", "tobuy",
        ])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")
        let coffee = element(app, "tobuy.item.5")
        XCTAssertTrue(coffee.waitForExistence(timeout: 20), "The other device's items did not arrive")
        XCTAssertTrue(coffee.label.contains("Coffee"), "Line 5: \(coffee.label)")
        XCTAssertTrue(element(app, "tobuy.item.1").label.contains("Milk"))
        checkToBuyLines(app)
        waitForSync(app, sent: 1)
        settle()
        save(app, "en-portrait-sync-tobuy")

        // The other device's ink and birthday on March 2029 (after a relaunch: they were saved here).
        app.terminate()
        app = launch(language: "en", region: "US", extraArguments: ["-DCFakeCloud", "YES", "-DCOpenPage", "month:2029-03"], reset: false)
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        checkInk(app, page: "page.month", targets: Self.monthTargets, minimum: 3)
        XCTAssertTrue(element(app, "memo.birthday.1").label.contains("Sofia's birthday"))
        save(app, "en-portrait-sync-month")

        // A new device with the same iCloud: everything comes back, each item once.
        app.terminate()
        app = launch(language: "en", region: "US", extraArguments: ["-DCFakeCloud", "YES", "-DCKeepCloud", "YES", "-DCOpenPage", "tobuy"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "tobuy")
        XCTAssertTrue(element(app, "tobuy.item.1").waitForExistence(timeout: 20), "Nothing came back on the new device")
        XCTAssertTrue(element(app, "tobuy.item.1").label.contains("Milk"))
        XCTAssertTrue(element(app, "tobuy.item.6").label.contains("Stamps"))
        checkToBuyLines(app)
        settle()
        save(app, "en-portrait-sync-new-device")
    }

    /// Settings in Greek, with the fake iCloud: the iCloud and backup sections; a backup is made.
    @MainActor
    func testICloudAndBackupSettingsGreek() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "el", region: "GR", extraArguments: [
            "-DCSampleLists", "YES", "-DCFakeCloud", "YES", "-DCOpenPage", "month:2029-03",
        ])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        waitForSync(app, sent: 1)
        openSettings(app)
        // "Συγχρονισμός: Ενημερωμένα" (up to date).
        let upToDate = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Ενημερωμένα", "Ενημερωμένα"))
            .firstMatch
        revealInSettings(app, upToDate)
        XCTAssertTrue(upToDate.waitForExistence(timeout: 15), "The iCloud section does not say up to date")
        let export = element(app, "settings.exportBackup")
        if !export.isHittable {
            app.swipeUp()
        }
        settle()
        save(app, "el-portrait-settings-icloud")

        export.tap()
        let backup = element(app, "debug.lastBackup")
        let made = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "dcbackup "), object: backup)
        XCTAssertEqual(XCTWaiter().wait(for: [made], timeout: 15), .completed, "No backup file: \(backup.label)")
        settle(1.5)
        save(app, "el-portrait-backup-share")
    }

    // MARK: - Helpers

    @MainActor
    private func checkToBuyLines(_ app: XCUIApplication) {
        for line in Self.toBuyLines {
            XCTAssertTrue(element(app, "tobuy.item.\(line)").exists, "No typed item on line \(line)")
        }
        for line in [4, 7, 38] {
            XCTAssertFalse(element(app, "tobuy.item.\(line)").exists, "An item twice? Line \(line) has one")
        }
    }

    /// Waits until the sync has sent at least `sent` files to the (fake) iCloud.
    @MainActor
    private func waitForSync(_ app: XCUIApplication, sent: Int) {
        let summary = element(app, "debug.sync")
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let words = summary.label.split(separator: " ")
            if let index = words.firstIndex(of: "sent"), index + 1 < words.count, let count = Int(words[index + 1]), count >= sent {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        XCTFail("The sync sent nothing: \(summary.label)")
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) {
        tapBarButton(app, "settings.button", label: "Ρυθμίσεις")
    }
}
