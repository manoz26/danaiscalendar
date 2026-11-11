import XCTest

/// Temporary: why does the app crash when a finger touches the PencilKit page in the
/// simulator? The first test prints every gesture recognizer around the canvas; the
/// others try a fix each, tap the year page and check that the app is still running.
final class DiagnosticTouchTests: XCTestCase {
    @MainActor
    func testARecognizerReport() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "en", region: "US", extraArguments: ["-DCOpenPage", "year:2030", "-DCDiagReport", "YES"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2030")
        settle(2)
        let report = element(app, "diag.recognizers")
        XCTAssertTrue(report.waitForExistence(timeout: 5), "No recognizer report")
        print("RECOGNIZERS BEGIN\n\(report.label)\nRECOGNIZERS END")
        let attachment = XCTAttachment(string: report.label)
        attachment.name = "recognizers"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testTouchBaseline() throws { try touchPage(nil) }
    @MainActor func testTouchWithoutDelays() throws { try touchPage("-DCDiagNoDelays") }
    @MainActor func testTouchWithoutKitGestures() throws { try touchPage("-DCDiagNoKitGestures") }

    @MainActor
    private func touchPage(_ flag: String?) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(
            language: "en", region: "US",
            extraArguments: ["-DCOpenPage", "year:2030"] + (flag.map { [$0, "YES"] } ?? [])
        )
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2030")
        settle(2)
        let page = element(app, "page.year")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "The year page view was not found")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        settle(2)
        XCTAssertEqual(app.state, .runningForeground, "The app stopped after a finger touched the page (\(flag ?? "baseline"))")
    }
}
