import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
@testable import PlannerCore

/// Registers the app's Inter fonts for this test process (the app does it via UIAppFonts).
enum TestFonts {
    static let fontsFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PlannerCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Core
        .deletingLastPathComponent() // repo root
        .appending(path: "App/Resources/Fonts")

    static let registered: Bool = {
        for font in PlannerFont.allCases {
            let url = fontsFolder.appending(path: "\(font.postScriptName).ttf")
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return true
    }()
}

/// An RGBA bitmap of a page, with canvas y going down like on iOS.
struct PageBitmap {
    let width: Int
    let height: Int
    let scale: CGFloat
    let pixels: [UInt8]
    let image: CGImage

    init(_ template: PageTemplate, scale: CGFloat) throws {
        _ = TestFonts.registered
        width = Int(PageCanvas.size.width * scale)
        height = Int(PageCanvas.size.height * scale)
        self.scale = scale
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        // Bitmap contexts have y going up; flip so the template is drawn as on iOS.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        TemplateRenderer.drawPage(template, in: context, scale: scale)
        image = try #require(context.makeImage())
        let data = try #require(context.data)
        pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height * 4))
    }

    /// Brightness 0...1 at a canvas point. Row 0 of the bitmap is the top of the page.
    func white(at point: CGPoint) -> CGFloat {
        let x = min(width - 1, max(0, Int(point.x * scale)))
        let y = min(height - 1, max(0, Int(point.y * scale)))
        let index = (y * width + x) * 4
        return CGFloat(Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])) / (3 * 255)
    }

    /// Pixels darker than 50% grey inside a canvas rectangle.
    func darkPixels(in rect: CGRect) -> Int {
        var count = 0
        for y in Int(rect.minY * scale)..<Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale)..<Int(rect.maxX * scale) {
                let index = (y * width + x) * 4
                if Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2]) < 3 * 128 { count += 1 }
            }
        }
        return count
    }

    /// True if no pixel has colour (red, green and blue always equal, give or take rounding).
    var isGreyscale: Bool {
        stride(from: 0, to: pixels.count, by: 4).allSatisfy { index in
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            return abs(r - g) <= 2 && abs(g - b) <= 2
        }
    }

    func writePNG(to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

@Suite("Template renderer")
struct TemplateRendererTests {
    private let english = Locale(identifier: "en_US")
    private let greek = Locale(identifier: "el_GR")
    private let greekLabels = MonthPageLabels(
        goals: "Στόχοι", todo: "Να κάνω", memo: "Σημειώσεις", weekly: "Εβδομάδες"
    )

    @Test func interIsAvailableToTheRenderer() {
        _ = TestFonts.registered
        for font in PlannerFont.allCases {
            let ctFont = CTFontCreateWithName(font.postScriptName as CFString, 12, nil)
            #expect(CTFontCopyPostScriptName(ctFont) as String == font.postScriptName)
        }
    }

    @Test func monthPageIsDrawnUprightWhereTheLayoutSays() throws {
        let november = YearMonth(year: 2026, month: 11)
        let today = PlannerDate(year: 2026, month: 11, day: 10)
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english, today: today)
        let bitmap = try PageBitmap(template, scale: 1)
        let layout = MonthPageLayout(month: november)

        // The title's capitals sit just above its baseline, at the top-left.
        let capHeight = MonthPageLayout.titleSize * PlannerFont.capHeight
        let titleInk = bitmap.darkPixels(in: CGRect(x: 50, y: 102 - capHeight, width: 150, height: capHeight))
        #expect(titleInk > 800)
        // Nothing below the baseline (no descenders in "NOVEMBER") or mirrored at the bottom.
        #expect(bitmap.darkPixels(in: CGRect(x: 50, y: 104, width: 150, height: 10)) == 0)
        #expect(bitmap.darkPixels(in: CGRect(x: 50, y: 1360, width: 150, height: 30)) == 0)

        // The goals box is light grey, the paper white.
        #expect(abs(bitmap.white(at: CGPoint(x: layout.goals.midX, y: layout.goals.midY)) - Tone.fill.white) < 0.02)
        let cell = try #require(layout.cell(for: PlannerDate(year: 2026, month: 11, day: 18)))
        #expect(bitmap.white(at: CGPoint(x: cell.frame.midX, y: cell.frame.maxY - 15)) == 1)

        // Today's mark is black, with the number in white on it.
        let todayCell = try #require(layout.cell(for: today))
        let mark = CGPoint(x: todayCell.frame.minX + MonthPageLayout.dayNumberOffset.x, y: todayCell.frame.minY + MonthPageLayout.dayNumberOffset.y)
        #expect(bitmap.white(at: CGPoint(x: mark.x - 11, y: mark.y)) < 0.1)
        #expect(bitmap.darkPixels(in: CGRect(x: mark.x - 13, y: mark.y - 13, width: 26, height: 26)) > 300)

        // The strong top rule of the grid.
        #expect(bitmap.white(at: CGPoint(x: 500, y: layout.gridFrame.minY)) < 0.6)
        #expect(bitmap.isGreyscale)
    }

    @Test func yearPageDrawsTwelveNotesBoxes() throws {
        let template = YearPageTemplate.make(year: 2026, locale: greek, today: PlannerDate(year: 2026, month: 11, day: 10))
        let bitmap = try PageBitmap(template, scale: 1)
        let layout = YearPageLayout(year: 2026)
        for mini in layout.months {
            #expect(abs(bitmap.white(at: CGPoint(x: mini.notes.midX, y: mini.notes.midY)) - Tone.fill.white) < 0.02)
            #expect(bitmap.darkPixels(in: mini.title) > 100, "title of \(mini.month)")
        }
        #expect(bitmap.isGreyscale)
    }

    /// With PLANNER_RENDER_DIR set (the CI does), saves PNGs of sample pages to look at.
    @Test func savesSamplePagesForReview() throws {
        guard let folder = ProcessInfo.processInfo.environment["PLANNER_RENDER_DIR"], !folder.isEmpty else { return }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let today = PlannerDate(year: 2026, month: 11, day: 10)
        var samples: [(String, PageTemplate)] = [
            ("month-2026-11-en", MonthPageTemplate.make(month: YearMonth(year: 2026, month: 11), locale: english, labels: .english, today: today)),
            ("month-2028-02-el", MonthPageTemplate.make(month: YearMonth(year: 2028, month: 2), locale: greek, labels: greekLabels)),
            ("month-2027-02-en", MonthPageTemplate.make(month: YearMonth(year: 2027, month: 2), locale: english, labels: .english)),
            ("month-2026-09-el", MonthPageTemplate.make(month: YearMonth(year: 2026, month: 9), locale: greek, labels: greekLabels)),
            ("month-2026-11-el-birthdays", MonthPageTemplate.make(
                month: YearMonth(year: 2026, month: 11), locale: greek, labels: greekLabels, today: today,
                birthdays: [
                    BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 13), text: "Μάνος — γενέθλια"),
                    BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 21), text: "Ελένη — γενέθλια"),
                    BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 21), text: "Αλεξάνδρα-Μαρία Παπαδοπούλου — γενέθλια"),
                ]
            )),
            ("year-2026-en", YearPageTemplate.make(year: 2026, locale: english, today: today)),
            ("year-2028-el", YearPageTemplate.make(year: 2028, locale: greek)),
            ("tobuy-en", ToBuyPageTemplate.make(locale: english, title: "To buy")),
            ("tobuy-el", ToBuyPageTemplate.make(locale: greek, title: "Να αγοράσω")),
            ("tobuy-el-typed", ToBuyPageTemplate.make(
                locale: greek, title: "Να αγοράσω",
                items: [
                    PrintedItem(line: 1, text: "Γάλα", done: false),
                    PrintedItem(line: 2, text: "Ψωμί ολικής άλεσης", done: true),
                    PrintedItem(line: 4, text: "Μπαταρίες AA για το τηλεχειριστήριο της τηλεόρασης του σαλονιού", done: false),
                    PrintedItem(line: 37, text: "Δώρο για τη Μαρία", done: false),
                ]
            )),
            ("month-2026-11-en-notebooks", MonthPageTemplate.make(
                month: YearMonth(year: 2026, month: 11), locale: english, labels: .english, today: today,
                journalDays: [PlannerDate(year: 2026, month: 11, day: 5), PlannerDate(year: 2026, month: 11, day: 10), PlannerDate(year: 2026, month: 11, day: 21)],
                sketchDays: [PlannerDate(year: 2026, month: 11, day: 21), PlannerDate(year: 2026, month: 11, day: 27)],
                todos: [
                    PrintedItem(line: 1, text: "Call the bank", done: false),
                    PrintedItem(line: 2, text: "Book the dentist", done: true),
                    PrintedItem(line: 5, text: "A very long to-do that will not fit on its line at all", done: false),
                ],
                todoOverflow: 1
            )),
        ]
        let heading = JournalHeading.texts(title: "", date: today, locale: greek)
        let titled = JournalHeading.texts(title: "Ideas for the summer", date: today, locale: english)
        for style in PaperStyle.allCases {
            samples.append(("journal-\(style.rawValue)-el", JournalPageTemplate.make(paper: style, label: heading.label, heading: heading.heading)))
        }
        samples.append(("journal-lined-en-title", JournalPageTemplate.make(paper: .lined, label: titled.label, heading: titled.heading)))
        for (name, template) in samples {
            try PageBitmap(template, scale: 1.5).writePNG(to: directory.appending(path: "\(name).png"))
        }
    }
}
