import XCTest

/// Launches the app in each language, checks the main screens, and saves screenshots.
///
/// CI passes `TEST_RUNNER_SCREENSHOT_DIR` and `TEST_RUNNER_DEVICE_LABEL`; xcodebuild hands
/// them to this process without the `TEST_RUNNER_` prefix. Files are named
/// `<device>-<language>-<orientation>-<screen>.png`.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testMonthPageEnglish() throws {
        try captureMonthPage(language: "en", region: "US", titlePattern: "^[A-Z]+$")
    }

    @MainActor
    func testMonthPageGreek() throws {
        // Greek capitals only, no accented capitals (Ά, Έ, ...); Ϊ and Ϋ are allowed.
        try captureMonthPage(language: "el", region: "GR", titlePattern: "^[Α-ΩΪΫ]+$")
    }

    @MainActor
    func testSettingsAndDiagnosticsEnglish() throws {
        try captureSettingsAndDiagnostics(language: "en", region: "US")
    }

    @MainActor
    func testSettingsAndDiagnosticsGreek() throws {
        try captureSettingsAndDiagnostics(language: "el", region: "GR")
    }

    // MARK: - Helpers

    @MainActor
    private func launch(language: String, region: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_\(region)"]
        app.launch()
        return app
    }

    @MainActor
    private func captureMonthPage(language: String, region: String, titlePattern: String) throws {
        continueAfterFailure = false
        let device = XCUIDevice.shared
        device.orientation = .portrait

        let app = launch(language: language, region: region)

        let title = app.staticTexts["page.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 15), "Month title did not appear")
        XCTAssertNotNil(
            title.label.range(of: titlePattern, options: .regularExpression),
            "Unexpected title '\(title.label)' for language \(language)"
        )

        waitForOrientation(app, landscape: false)
        save(app, "\(language)-portrait-month")

        if UIDevice.current.userInterfaceIdiom == .pad {
            device.orientation = .landscapeLeft
            waitForOrientation(app, landscape: true)
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            save(app, "\(language)-landscape-month")
            device.orientation = .portrait
        }
        // No app.terminate(): it can hang on the simulator right after a rotation, and the
        // next launch() (or the end of the run) closes the app anyway.
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

    /// Lets animations finish before a screenshot.
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
        let deviceLabel = environment["DEVICE_LABEL"] ?? (UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone")
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
