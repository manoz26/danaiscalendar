import XCTest

/// Temporary: which part of the page makes the app crash when a finger touches it in the
/// simulator? Each test switches one part off (`TouchDiagnosis` in the app), taps a small
/// month on the year page, and checks that the app is still running.
final class DiagnosticTouchTests: XCTestCase {
    @MainActor func testTouchBaseline() throws { try touchPage() }
    @MainActor func testTouchWithoutTap() throws { try touchPage("-DCDiagNoTap") }
    @MainActor func testTouchWithoutToolbar() throws { try touchPage("-DCDiagNoToolbar") }
    @MainActor func testTouchWithoutContentDelay() throws { try touchPage("-DCDiagNoDelay") }
    @MainActor func testTouchWithoutDrawing() throws { try touchPage("-DCDiagNoDrawing") }
    @MainActor func testTouchWithoutOverrides() throws { try touchPage("-DCDiagNoOverrides") }
    @MainActor func testTouchWithoutPencilInteraction() throws { try touchPage("-DCDiagNoPencil") }
    @MainActor func testTouchWithoutTemplateView() throws { try touchPage("-DCDiagNoTemplate") }

    @MainActor
    private func touchPage(_ flag: String? = nil) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(
            language: "en", region: "US",
            extraArguments: ["-DCOpenPage", "year:2030"] + (flag.map { [$0, "YES"] } ?? [])
        )
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2030")
        let page = element(app, "page.year")
        XCTAssertTrue(page.waitForExistence(timeout: 5), "The year page view was not found")
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        settle(2)
        XCTAssertEqual(app.state, .runningForeground, "The app stopped after a finger touched the page (\(flag ?? "baseline"))")
        XCTAssertTrue(element(app, "page.title").exists, "The page is gone after a touch (\(flag ?? "baseline"))")
    }
}
