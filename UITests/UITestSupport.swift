import XCTest

/// Helpers shared by the UI tests.
///
/// CI passes `TEST_RUNNER_SCREENSHOT_DIR` and `TEST_RUNNER_DEVICE_LABEL`; xcodebuild hands
/// them to this process without the `TEST_RUNNER_` prefix. Screenshots are named
/// `<device>-<language>-<orientation>-<screen>.png`.
extension XCTestCase {
    @MainActor
    var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// Launches the app in a language. With `reset` (the default) it starts without saved
    /// pages and with the default tools, so one test never sees another's ink.
    @MainActor
    func launch(language: String, region: String, extraArguments: [String] = [], reset: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_\(region)"]
            + (reset ? ["-DCResetData", "YES"] : [])
            + extraArguments
        app.launch()
        return app
    }

    /// Any element with this accessibility identifier (page items are not plain buttons or texts).
    @MainActor
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func tap(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(identifier) did not appear")
        target.tap()
    }

    /// Taps the middle of something printed on the page, like a finger would.
    @MainActor
    func tapOnPage(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(identifier) did not appear")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    /// Waits until the open page is `id` ("2026" for a year, "2026-11" for a month), then
    /// lets the page finish drawing.
    @MainActor
    func waitForPage(_ app: XCUIApplication, _ id: String) {
        let title = element(app, "page.title")
        XCTAssertTrue(title.waitForExistence(timeout: 20), "No page title appeared")
        let isPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", id), object: title)
        XCTAssertEqual(
            XCTWaiter().wait(for: [isPage], timeout: 10), .completed,
            "Expected page \(id), found \(String(describing: title.value))"
        )
        settle()
    }

    /// Lets animations and drawing finish before a screenshot.
    @MainActor
    func settle(_ seconds: TimeInterval = 1.0) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    /// Waits until the app window has the requested shape, then lets the rotation animation settle.
    @MainActor
    func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
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
    func save(_ app: XCUIApplication, _ name: String) {
        let environment = ProcessInfo.processInfo.environment
        let deviceLabel = environment["DEVICE_LABEL"] ?? (isPad ? "ipad" : "iphone")
        let fullName = "\(deviceLabel)-\(name)"

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = fullName
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = environment["SCREENSHOT_DIR"], !directory.isEmpty else { return }
        let png = ScreenPixels.upright(screenshot.image).pngData() ?? Data()
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appendingPathComponent("\(fullName).png"))
        } catch {
            XCTFail("Could not save screenshot \(fullName): \(error)")
        }
    }
}

/// Ink on screen (helpers shared by the ink and notebook tests).
extension XCTestCase {
    // MARK: - Checking ink on screen

    /// Checks every target that is fully on screen: the red rectangle the app drew 20% inside
    /// it must be found there, edge for edge.
    @MainActor
    func checkInk(_ app: XCUIApplication, page pageID: String, targets: [String], minimum: Int) {
        let page = element(app, pageID)
        XCTAssertTrue(page.waitForExistence(timeout: 5), "\(pageID) was not found")
        let visible = page.frame.intersection(app.windows.firstMatch.frame)
        let pixels = ScreenPixels(XCUIScreen.main.screenshot())
        XCTAssertEqual(pixels.size.width, app.windows.firstMatch.frame.width, accuracy: 1, "Screenshot and window differ: \(pixels.size)")
        let toolbar = element(app, "toolbar")
        let excluded = toolbar.exists ? [toolbar.frame.insetBy(dx: -4, dy: -4)] : []

        var checked: [String] = []
        for id in targets {
            let target = element(app, id)
            XCTAssertTrue(target.exists, "\(id) was not found")
            let frame = target.frame
            let expected = frame.insetBy(dx: frame.width * 0.2, dy: frame.height * 0.2)
            guard visible.insetBy(dx: -1, dy: -1).contains(frame),
                  !excluded.contains(where: { $0.intersects(expected.insetBy(dx: -8, dy: -8)) }) else { continue }
            guard let found = pixels.redBounds(in: frame.insetBy(dx: -12, dy: -12), excluding: excluded) else {
                XCTFail("No ink found in \(id) (\(frame))")
                continue
            }
            // The stroke's own width, plus a little: a misplaced stroke is off by much more.
            let tolerance = 4 + 0.05 * min(frame.width, frame.height)
            let off = [
                abs(found.minX - expected.minX), abs(found.maxX - expected.maxX),
                abs(found.minY - expected.minY), abs(found.maxY - expected.maxY),
            ].max() ?? 0
            XCTAssertLessThanOrEqual(
                off, tolerance,
                "Ink in \(id) at \(found), expected \(expected) (off by \(off), allowed \(tolerance)). \(element(app, "debug.inkGeometry").label)"
            )
            checked.append(id)
        }
        XCTAssertGreaterThanOrEqual(checked.count, minimum, "Too few boxes on screen to check: \(checked)")
    }

    /// No red ink on the page outside the boxes that have their own sample ink (ink of the
    /// previous page left on screen would be).
    @MainActor
    func checkNoInkOutside(_ app: XCUIApplication, page pageID: String, targets: [String]) {
        let page = element(app, pageID)
        XCTAssertTrue(page.waitForExistence(timeout: 5), "\(pageID) was not found")
        let visible = page.frame.intersection(app.windows.firstMatch.frame)
        let toolbar = element(app, "toolbar")
        var excluded = targets.map { element(app, $0).frame.insetBy(dx: -14, dy: -14) }
        if toolbar.exists {
            excluded.append(toolbar.frame.insetBy(dx: -4, dy: -4))
        }
        let stray = ScreenPixels(XCUIScreen.main.screenshot()).redBounds(in: visible, excluding: excluded)
        XCTAssertNil(stray, "Ink of another page left on screen at \(String(describing: stray)). \(element(app, "debug.inkGeometry").label)")
    }

    @MainActor
    func redBounds(_ app: XCUIApplication, in rect: CGRect) -> CGRect? {
        let toolbar = element(app, "toolbar")
        let excluded = toolbar.exists ? [toolbar.frame.insetBy(dx: -4, dy: -4)] : []
        return ScreenPixels(XCUIScreen.main.screenshot()).redBounds(in: rect, excluding: excluded)
    }

    /// Taps a button of the top bar, or the same button in the "…" menu when the bar is
    /// too narrow for it (iPhone). Menu items are found by identifier, else by label.
    @MainActor
    func tapBarButton(_ app: XCUIApplication, _ identifier: String, label: String) {
        let direct = app.buttons[identifier]
        if direct.waitForExistence(timeout: 4), direct.isHittable {
            direct.tap()
            return
        }
        let more = app.buttons["nav.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "\(identifier) is not in the bar and there is no … menu")
        more.tap()
        var item = app.buttons[identifier]
        if !item.waitForExistence(timeout: 3) || !item.isHittable {
            item = app.buttons[label]
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(label) is not in the … menu")
        item.tap()
    }

    /// Holds a finger on something printed on the page.
    @MainActor
    func longPressOnPage(_ app: XCUIApplication, _ identifier: String) {
        let target = element(app, identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 10), "\(identifier) did not appear")
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 1.0)
    }

    /// The accessibility value of a page item, or "" when it has none.
    @MainActor
    func value(_ app: XCUIApplication, _ identifier: String) -> String {
        element(app, identifier).value as? String ?? ""
    }
}

/// The pixels of a screenshot, upright, in sRGB, addressed in points like element frames.
struct ScreenPixels {
    let size: CGSize
    private let scale: CGFloat
    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    @MainActor
    init(_ screenshot: XCUIScreenshot) {
        self.init(image: screenshot.image)
    }

    @MainActor
    init(image: UIImage) {
        let upright = Self.upright(image)
        size = upright.size
        scale = upright.scale
        let cgImage = upright.cgImage
        let pixelWidth = cgImage?.width ?? 0
        let pixelHeight = cgImage?.height ?? 0
        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        if let cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) {
            buffer.withUnsafeMutableBytes { raw in
                let context = CGContext(
                    data: raw.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                    bytesPerRow: pixelWidth * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                // Row 0 of the buffer is the top of the image.
                context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            }
        }
        width = pixelWidth
        height = pixelHeight
        bytes = buffer
    }

    /// Redraws a screenshot so its pixels are upright even if it carries an orientation flag.
    @MainActor
    static func upright(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Strongly red: the sample ink and the red pen. The printed page is grey only, and the
    /// toolbar's pink and purple dots are not counted.
    func isRed(x: Int, y: Int) -> Bool {
        let index = (y * width + x) * 4
        let red = Int(bytes[index]), green = Int(bytes[index + 1]), blue = Int(bytes[index + 2])
        return red > 170 && green < 100 && blue < 100
    }

    /// Bounding box (in points) of the red pixels inside `rect`, skipping `excluded` areas.
    func redBounds(in rect: CGRect, excluding excluded: [CGRect] = []) -> CGRect? {
        let area = rect.intersection(CGRect(origin: .zero, size: size))
        guard !area.isNull, width > 0 else { return nil }
        let x0 = max(0, Int((area.minX * scale).rounded(.down)))
        let x1 = min(width, Int((area.maxX * scale).rounded(.up)))
        let y0 = max(0, Int((area.minY * scale).rounded(.down)))
        let y1 = min(height, Int((area.maxY * scale).rounded(.up)))
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        for y in y0..<y1 {
            for x in x0..<x1 where isRed(x: x, y: y) {
                let point = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                if excluded.contains(where: { $0.contains(point) }) { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale
        )
    }
}
