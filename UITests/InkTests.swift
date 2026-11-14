import XCTest

/// The ink lines up with the printed page and is saved.
///
/// There is no Apple Pencil in the simulator. The app draws sample strokes instead
/// (`-DCSampleInk YES`: a pure red rectangle 20% inside each of a few known boxes), and
/// these tests find the red pixels in the screenshot and check that they sit exactly
/// where the boxes are: in portrait, in landscape, zoomed in, on the year page, and after
/// the app was killed and opened again. On iPad, a finger (with "Draw with finger too")
/// also draws through the real touch path, with undo and redo from the tool bar.
final class InkTests: XCTestCase {
    private static func monthTargets(_ month: String) -> [String] {
        ["section.goals", "day.\(month)-03", "day.\(month)-15", "section.todo", "section.memo"]
    }

    private static func yearTargets(_ year: String) -> [String] {
        ["year.notes.\(year)-02", "year.notes.\(year)-07", "year.month.\(year)-11"]
    }

    @MainActor
    func testSampleInkLinesUpWithThePage() throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCSampleInk", "YES", "-DCOpenPage", "month:2029-03"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-03")
        settle()
        print("INK GEOMETRY: \(element(app, "debug.inkGeometry").label)")
        save(app, "en-portrait-ink-month")
        checkInk(app, page: "page.month", targets: Self.monthTargets("2029-03"), minimum: 3)

        if isPad {
            device.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, "2029-03")
            save(app, "en-landscape-ink-month")
            checkInk(app, page: "page.month", targets: Self.monthTargets("2029-03"), minimum: 2)

            // The bottom of the page (to-do list and memo), far below the first screen.
            let page = element(app, "page.month")
            page.swipeUp(velocity: .fast)
            page.swipeUp(velocity: .fast)
            settle(1.5)
            checkInk(app, page: "page.month", targets: Self.monthTargets("2029-03"), minimum: 2)
            save(app, "en-landscape-ink-month-bottom")
            page.swipeDown(velocity: .fast)
            page.swipeDown(velocity: .fast)
            settle()
            device.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // Zoomed in around the middle of the page, where the 15th is.
        let page = element(app, "page.month")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "The month page view was not found")
        page.pinch(withScale: 2.5, velocity: 2)
        settle(1.5)
        // On iPhone the middle of the view is low on the page, where no sample box is whole.
        checkInk(app, page: "page.month", targets: Self.monthTargets("2029-03"), minimum: isPad ? 1 : 0)
        save(app, "en-portrait-ink-month-zoom")

        // From the zoomed-in month to the year: nothing of the month's ink may stay on screen.
        tap(app, "nav.year")
        waitForPage(app, "2029")
        checkNoInkOutside(app, page: "page.year", targets: Self.yearTargets("2029"))
        settle()
        checkInk(app, page: "page.year", targets: Self.yearTargets("2029"), minimum: 3)
        checkNoInkOutside(app, page: "page.year", targets: Self.yearTargets("2029"))
        save(app, "en-portrait-ink-year")
    }

    /// The ink is on disk: the app goes to the background, is killed, and opens again.
    @MainActor
    func testInkIsSavedAndComesBack() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        var app = launch(language: "en", region: "US", extraArguments: ["-DCSampleInk", "YES", "-DCOpenPage", "month:2029-05"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-05")
        XCUIDevice.shared.press(.home)
        settle(2)
        app.terminate()

        app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "month:2029-05"], reset: false)
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-05")
        settle()
        checkInk(app, page: "page.month", targets: Self.monthTargets("2029-05"), minimum: 3)
        save(app, "en-portrait-ink-relaunch")
    }

    /// A finger draws (Settings → Draw with finger too) through the real touch path; undo,
    /// redo, moving and folding the tool bar.
    @MainActor
    func testFingerDrawingAndToolbar() throws {
        guard isPad else { throw XCTSkip("There is no drawing on iPhone.") }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCDrawWithFinger", "YES", "-DCOpenPage", "month:2029-06"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2029-06")

        tap(app, "toolbar.tool.pen")
        tap(app, "toolbar.width.3")
        tap(app, "toolbar.color.red")
        let cell = element(app, "day.2029-06-13")
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "Day 13 was not found")
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.6))
        let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        settle()

        let frame = cell.frame
        let search = frame.insetBy(dx: -20, dy: -20)
        let line = try XCTUnwrap(redBounds(app, in: search), "The finger did not draw")
        XCTAssertEqual(line.minX, frame.minX + frame.width * 0.2, accuracy: 12, "Stroke starts at \(line), cell \(frame)")
        XCTAssertEqual(line.maxX, frame.minX + frame.width * 0.8, accuracy: 12, "Stroke ends at \(line), cell \(frame)")
        XCTAssertEqual(line.midY, frame.minY + frame.height * 0.6, accuracy: 8, "Stroke height at \(line), cell \(frame)")
        save(app, "en-portrait-ink-finger")

        tap(app, "toolbar.undo")
        settle()
        XCTAssertNil(redBounds(app, in: search), "Undo did not remove the stroke")
        tap(app, "toolbar.redo")
        settle()
        XCTAssertNotNil(redBounds(app, in: search), "Redo did not bring the stroke back")

        // Drag the tool bar to the right edge, then fold and unfold it.
        let window = app.windows.firstMatch
        let grip = element(app, "toolbar.grip")
        XCTAssertTrue(grip.waitForExistence(timeout: 5), "The tool bar grip was not found")
        grip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 0.2,
            thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        )
        settle()
        XCTAssertGreaterThan(element(app, "toolbar").frame.midX, window.frame.midX, "The tool bar did not move right")
        save(app, "en-portrait-toolbar-right")

        tap(app, "toolbar.collapse")
        settle()
        save(app, "en-portrait-toolbar-folded")
        tap(app, "toolbar.expand")
        settle()
        XCTAssertTrue(element(app, "toolbar.undo").exists, "The tool bar did not unfold")
    }
}
