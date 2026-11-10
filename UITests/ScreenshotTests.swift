import XCTest

/// Launches the app in each language, walks through the planner pages, and saves screenshots.
///
/// CI passes `TEST_RUNNER_SCREENSHOT_DIR` and `TEST_RUNNER_DEVICE_LABEL`; xcodebuild hands
/// them to this process without the `TEST_RUNNER_` prefix. Files are named
/// `<device>-<language>-<orientation>-<screen>.png`.
final class ScreenshotTests: XCTestCase {
    private static let englishTitle = "^[A-Z]+$"
    // Greek capitals only, no accented capitals (Ά, Έ, ...); Ϊ and Ϋ are allowed.
    private static let greekTitle = "^[Α-ΩΪΫ]+$"

    // MARK: - Tests

    @MainActor
    func testPlannerEnglish() throws {
        try capturePlanner(language: "en", region: "US", titlePattern: Self.englishTitle)
    }

    @MainActor
    func testPlannerGreek() throws {
        try capturePlanner(language: "el", region: "GR", titlePattern: Self.greekTitle)
    }

    @MainActor
    func testFebruariesEnglish() throws {
        try captureFebruaries(language: "en", region: "US", february: "FEBRUARY", zoom: true)
    }

    @MainActor
    func testFebruariesGreek() throws {
        try captureFebruaries(language: "el", region: "GR", february: "ΦΕΒΡΟΥΑΡΙΟΣ", zoom: false)
    }

    @MainActor
    func testSettingsAndDiagnosticsEnglish() throws {
        try captureSettingsAndDiagnostics(language: "en", region: "US")
    }

    @MainActor
    func testSettingsAndDiagnosticsGreek() throws {
        try captureSettingsAndDiagnostics(language: "el", region: "GR")
    }

    // MARK: - Flows

    /// Current month (portrait and landscape) → year page (portrait and landscape) →
    /// a month tab → Today.
    @MainActor
    private func capturePlanner(language: String, region: String, titlePattern: String) throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait
        let app = launch(language: language, region: region)
        let (year, month) = Self.currentYearAndMonth()
        let currentMonth = String(format: "%04d-%02d", year, month)

        waitForPage(app, currentMonth)
        let title = element(app, "page.title")
        XCTAssertNotNil(
            title.label.range(of: titlePattern, options: .regularExpression),
            "Unexpected title '\(title.label)' for language \(language)"
        )
        waitForOrientation(app, landscape: false)
        save(app, "\(language)-portrait-month")

        if isPad {
            device.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, currentMonth)
            save(app, "\(language)-landscape-month")
            device.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // Back to the year.
        tap(app, "nav.year")
        waitForPage(app, String(year))
        save(app, "\(language)-portrait-year")

        if isPad {
            device.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            waitForPage(app, String(year))
            save(app, "\(language)-landscape-year")
            device.orientation = .portrait
            waitForOrientation(app, landscape: false)
        }

        // The January tab, then Today.
        tap(app, "tab.month.1")
        waitForPage(app, String(format: "%04d-01", year))
        tap(app, "nav.today")
        waitForPage(app, currentMonth)
        // No app.terminate(): it can hang on the simulator right after a rotation, and the
        // next launch() (or the end of the run) closes the app anyway.
    }

    /// February 2028 (leap year, opened by tapping it on the year page) and February 2027
    /// (only 4 weeks, reached with the year arrows).
    @MainActor
    private func captureFebruaries(language: String, region: String, february: String, zoom: Bool) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: language, region: region, extraArguments: ["-DCOpenPage", "year:2028"])
        waitForOrientation(app, landscape: false)
        waitForPage(app, "2028")

        tapOnPage(app, "year.month.2028-02")
        waitForPage(app, "2028-02")
        XCTAssertEqual(element(app, "page.title").label, february)
        save(app, "\(language)-portrait-month-2028-02")

        tap(app, "nav.year")
        waitForPage(app, "2028")
        tap(app, "nav.previous")
        waitForPage(app, "2027")
        tapOnPage(app, "year.month.2027-02")
        waitForPage(app, "2027-02")
        save(app, "\(language)-portrait-month-2027-02")

        if zoom {
            let page = element(app, "page.month")
            XCTAssertTrue(page.waitForExistence(timeout: 5), "The month page view was not found")
            page.pinch(withScale: 2.5, velocity: 2)
            settle()
            save(app, "\(language)-portrait-month-2027-02-zoom")
        }
    }

    /// Opens Settings, taps the version 5 times and checks that Diagnostics shows the log.
    @MainActor
    private func captureSettingsAndDiagnostics(language: String, region: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: language, region: region)
        waitForOrientation(app, landscape: false)

        let settingsButton = app.buttons["settings.button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 15), "Settings button did not appear")
        settingsButton.tap()

        let version = app.buttons["settings.version"]
        XCTAssertTrue(version.waitForExistence(timeout: 10), "Settings did not open")
        settle()
        save(app, "\(language)-portrait-settings")

        for _ in 0..<5 {
            version.tap()
        }

        let log = app.staticTexts["diagnostics.log"]
        XCTAssertTrue(log.waitForExistence(timeout: 10), "Diagnostics did not open after 5 taps")
        let launchLine = NSPredicate(format: "label CONTAINS %@", "Launch: Danai's Calendar")
        let logged = XCTNSPredicateExpectation(predicate: launchLine, object: log)
        XCTAssertEqual(XCTWaiter().wait(for: [logged], timeout: 15), .completed, "The launch was not in the log: \(log.label.prefix(500))")
        settle()
        save(app, "\(language)-portrait-diagnostics")
    }

    // MARK: - Helpers

    @MainActor
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    @MainActor
    private func launch(language: String, region: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_\(region)"] + extraArguments
        app.launch()
        return app
    }

    /// Any element with this accessibility identifier (page items are not plain buttons or texts).
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func tap(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(identifier) did not appear")
        target.tap()
    }

    /// Taps the middle of something printed on the page, like a finger would.
    @MainActor
    private func tapOnPage(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(identifier) did not appear")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Waits until the open page is `id` ("2026" for a year, "2026-11" for a month), then
    /// lets the page finish drawing.
    @MainActor
    private func waitForPage(_ app: XCUIApplication, _ id: String) {
        let title = element(app, "page.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20), "No page title appeared")
        let isPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", id), object: title)
        XCTAssertEqual(
            XCTWaiter().wait(for: [isPage], timeout: 10), .completed,
            "Expected page \(id), found \(String(describing: title.value))"
        )
        settle()
    }

    private static func currentYearAndMonth() -> (Int, Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month], from: Date())
        return (parts.year!, parts.month!)
    }

    /// Lets animations and drawing finish before a screenshot.
    @MainActor
    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    /// Waits until the app window has the requested shape, then lets the rotation animation settle.
    @MainActor
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let window = app.windows.firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let frame = window.frame
            if frame.width > 0, (frame.width > frame.height) == landscape { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    @MainActor
    private func save(_ app: XCUIApplication, _ name: String) {
        let environment = ProcessInfo.processInfo.environment
        let deviceLabel = environment["DEVICE_LABEL"] ?? (isPad ? "ipad" : "iphone")
        let fullName = "\(deviceLabel)-\(name)"

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fullName
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = environment["SCREENSHOT_DIR"], !directory.isEmpty else { return }
        // Redraw so the PNG is upright even if the capture carries an orientation flag.
        let image = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let png = UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("\(fullName).png"))
        } catch {
            XCTFail("Could not save screenshot \(fullName): \(error)")
        }
    }
}
