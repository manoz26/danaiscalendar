import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

private func day(_ year: Int, _ month: Int, _ day: Int) -> PlannerDate {
    PlannerDate(year: year, month: month, day: day)
}

private func week(_ year: Int, _ month: Int, _ start: Int) -> PlannerWeek {
    PlannerWeek(start: day(year, month, start))
}

@Suite("Weeks")
struct WeekTests {
    @Test func aWeekStartsOnTheFirstWeekday() {
        // Saturday 14 November 2026.
        let saturday = day(2026, 11, 14)
        #expect(PlannerWeek(containing: saturday).start == day(2026, 11, 9))
        #expect(PlannerWeek(containing: saturday, firstWeekday: .sunday).start == day(2026, 11, 8))
        #expect(PlannerWeek(containing: day(2026, 11, 9)).start == day(2026, 11, 9))
        #expect(PlannerWeek(containing: day(2026, 11, 15)).start == day(2026, 11, 9))
        #expect(PlannerWeek(containing: day(2026, 11, 15), firstWeekday: .sunday).start == day(2026, 11, 15))

        let november = week(2026, 11, 9)
        #expect(november.days.count == 7)
        #expect(november.days.first == day(2026, 11, 9))
        #expect(november.end == day(2026, 11, 15))
        #expect(november.days.map(\.weekday) == Weekday.week(startingOn: .monday))
        #expect(november.contains(saturday))
        #expect(!november.contains(day(2026, 11, 16)))
    }

    @Test func monthWeeksAreTheRowsOfItsGrid() {
        for (month, count) in [
            (YearMonth(year: 2027, month: 2), 4), // 1 February 2027 is a Monday
            (YearMonth(year: 2026, month: 11), 6), // starts on a Sunday
            (YearMonth(year: 2028, month: 2), 5),
            (YearMonth(year: 2026, month: 8), 6),
        ] {
            let weeks = PlannerWeek.weeks(of: month)
            let grid = MonthGrid(month: month)
            #expect(weeks.count == count, "\(month)")
            #expect(weeks.map(\.start) == grid.weeks.map { $0[0].date }, "\(month)")
            #expect(weeks.allSatisfy { $0.firstWeekday == .monday })
        }
        // With Sunday first, February 2026 (1st is a Sunday) has exactly 4 rows.
        let sundays = PlannerWeek.weeks(of: YearMonth(year: 2026, month: 2), firstWeekday: .sunday)
        #expect(sundays.count == 4)
        #expect(sundays.first?.start == day(2026, 2, 1))
        #expect(sundays.allSatisfy { $0.firstWeekday == .sunday })
        #expect(PlannerWeek.weeks(of: YearMonth(year: 2026, month: 2)).count == 5)
    }

    @Test func aWeekAcrossTwoMonthsIsOnePage() {
        let march = YearMonth(year: 2026, month: 3)
        let april = YearMonth(year: 2026, month: 4)
        let shared = week(2026, 3, 30)
        #expect(PlannerWeek.weeks(of: march).last == shared)
        #expect(PlannerWeek.weeks(of: april).first == shared)
        #expect(PlannerPage.week(PlannerWeek.weeks(of: march).last!) == PlannerPage.week(PlannerWeek.weeks(of: april).first!))
        #expect(shared.months == [march, april])
        #expect(shared.touches(march) && shared.touches(april))
        #expect(!shared.touches(YearMonth(year: 2026, month: 5)))
        // 30, 31 March and 1-5 April: most days are in April.
        #expect(shared.month == april)
        #expect(week(2026, 11, 9).months == [YearMonth(year: 2026, month: 11)])
    }

    @Test func aWeekAcrossTwoYearsIsOnePage() {
        let december = YearMonth(year: 2026, month: 12)
        let january = YearMonth(year: 2027, month: 1)
        let shared = week(2026, 12, 28)
        #expect(PlannerWeek.weeks(of: december).last == shared)
        #expect(PlannerWeek.weeks(of: january).first == shared)
        #expect(shared.months == [december, january])
        // 28-31 December, 1-3 January: the middle day is 31 December.
        #expect(shared.month == december)
        #expect(PlannerPage.week(shared).year == 2026)
        #expect(shared.next == week(2027, 1, 4))
        #expect(shared.previous == week(2026, 12, 21))

        // With Sunday first: 27 December 2026 – 2 January 2027, in both months as well.
        let sunday = PlannerWeek(containing: day(2027, 1, 1), firstWeekday: .sunday)
        #expect(sunday.start == day(2026, 12, 27))
        #expect(PlannerWeek.weeks(of: december, firstWeekday: .sunday).last == sunday)
        #expect(PlannerWeek.weeks(of: january, firstWeekday: .sunday).first == sunday)
    }

    @Test func weekNumbersFollowISO8601() {
        #expect(week(2026, 11, 9).number == 46)
        // 1 January 2026 is a Thursday: its week is week 1, and 2026 has 53 weeks.
        #expect(week(2025, 12, 29).number == 1)
        #expect(week(2026, 12, 28).number == 53)
        #expect(week(2027, 1, 4).number == 1)
        // 3 January 2021 (a Sunday) is still in week 53 of 2020.
        #expect(PlannerWeek(containing: day(2021, 1, 3)).number == 53)
        #expect(PlannerWeek(containing: day(2021, 1, 4)).number == 1)
        // 2027 starts on a Friday: 1-3 January are in week 53 of 2026.
        #expect(PlannerWeek(containing: day(2027, 1, 3)).number == 53)
        // Weeks from Sunday take the ISO week of their Monday to Saturday.
        #expect(PlannerWeek(containing: day(2026, 11, 14), firstWeekday: .sunday).number == 46)
        #expect(PlannerWeek(containing: day(2026, 11, 15), firstWeekday: .sunday).number == 47)
        // Leap year: 29 February 2028 (Tuesday) is in week 9.
        #expect(PlannerWeek(containing: day(2028, 2, 29)).number == 9)
    }

    @Test func weekPagesHaveStableNamesAndNeighbours() throws {
        let november = week(2026, 11, 9)
        let page = PlannerPage.week(november)
        #expect(november.description == "2026-11-09")
        #expect(page.description == "week:2026-11-09")
        #expect(PlannerPage("week:2026-11-09") == page)
        #expect(PlannerPage("week:2026-11-31") == nil)
        #expect(PlannerWeek("2026-11-09") == november)
        #expect(page.fileStem == "week-2026-11-09")
        #expect(PlannerPage(fileStem: "week-2026-11-09") == page)
        #expect(page.year == 2026)
        #expect(page.week == november)
        #expect(!page.isCalendarPage)
        #expect(!page.isNotebookPage)
        #expect(page.previous == .week(week(2026, 11, 2)))
        #expect(page.next == .week(week(2026, 11, 16)))
        #expect(Set(page.neighbors) == [.week(week(2026, 11, 2)), .week(week(2026, 11, 16)), .month(YearMonth(year: 2026, month: 11))])
        #expect(PageLayoutStamp.current(for: page).name == "week-v1")
        #expect(PlannerPage.month(YearMonth(year: 2026, month: 11)).week == nil)
        // The first and last weeks the app can show stay inside its years.
        #expect(PlannerPage.week(week(9999, 12, 27)).next == .week(week(9999, 12, 27)))
        #expect(PlannerPage.week(week(1, 1, 1)).previous == .week(week(1, 1, 1)))
    }

    @Test func weekTitles() {
        let english = Locale(identifier: "en_US")
        let greek = Locale(identifier: "el_GR")
        #expect(WeekTitle.text(for: week(2026, 11, 9), locale: english) == "9 – 15 NOVEMBER")
        #expect(WeekTitle.text(for: week(2026, 3, 30), locale: english) == "30 MARCH – 5 APRIL")
        #expect(WeekTitle.text(for: week(2026, 12, 28), locale: english) == "28 DECEMBER – 3 JANUARY")
        #expect(WeekTitle.days(of: week(2026, 11, 9), locale: english) == "9 – 15 November")
        // Greek: the month after a day is in the genitive, capitals without accents.
        #expect(WeekTitle.text(for: week(2026, 11, 9), locale: greek) == "9 – 15 ΝΟΕΜΒΡΙΟΥ")
        #expect(WeekTitle.text(for: week(2026, 3, 30), locale: greek) == "30 ΜΑΡΤΙΟΥ – 5 ΑΠΡΙΛΙΟΥ")
        #expect(WeekTitle.text(for: week(2026, 5, 4), locale: greek) == "4 – 10 ΜΑΪΟΥ")
        #expect(WeekTitle.years(of: week(2026, 11, 9)) == "2026")
        #expect(WeekTitle.years(of: week(2026, 12, 28)) == "2026 – 2027")
        #expect(CalendarNames.weekdays([.monday, .sunday], locale: english) == ["MONDAY", "SUNDAY"])
        #expect(CalendarNames.weekdays([.monday, .sunday], locale: greek) == ["ΔΕΥΤΕΡΑ", "ΚΥΡΙΑΚΗ"])
    }
}

@Suite("Week page")
struct WeekPageTests {
    init() {
        _ = TestFonts.registered
    }

    private let english = Locale(identifier: "en_US")
    private let greek = Locale(identifier: "el_GR")

    @Test func eightBoxesInTwoColumnsOfFour() throws {
        let layout = WeekPageLayout(week: week(2026, 11, 9))
        #expect(layout.days.count == 7)
        #expect(layout.boxes.count == 8)
        #expect(layout.days.map(\.date) == week(2026, 11, 9).days)
        #expect(layout.notes.date == nil)

        let page = CGRect(origin: .zero, size: PageCanvas.size)
        for box in layout.boxes {
            #expect(page.insetBy(dx: 40, dy: 40).contains(box.frame), "\(box.frame)")
            #expect(box.lines.count == WeekPageLayout.lineCount)
            #expect(box.header.minY == box.frame.minY)
            #expect(abs(box.lines.last!.maxY - box.frame.maxY) < 0.001)
            #expect(box.frame.minY > layout.title.maxY)
            for other in layout.boxes where other != box {
                #expect(!box.frame.intersects(other.frame), "\(box.frame) and \(other.frame)")
            }
        }
        // Monday to Thursday down the left column, Friday to Sunday and the notes down the right.
        let left = layout.boxes[0].frame.minX, right = layout.boxes[4].frame.minX
        #expect(layout.boxes.prefix(4).allSatisfy { $0.frame.minX == left })
        #expect(layout.boxes.suffix(4).allSatisfy { $0.frame.minX == right })
        #expect(left == WeekPageLayout.margin)
        #expect(abs(layout.boxes[4].frame.maxX - (PageCanvas.size.width - WeekPageLayout.margin)) < 0.001)
        for column in [0, 4] {
            let rows = layout.boxes[column..<(column + 4)].map(\.frame.minY)
            #expect(rows == rows.sorted())
        }
        #expect(layout.notes.frame.minY > layout.days[6].frame.maxY)
        #expect(layout.notes.frame.minX == layout.days[6].frame.minX)
        // Lines have the step of the month page's lists, for the same handwriting.
        #expect(layout.notes.lines.allSatisfy { abs($0.height - 33) < 0.001 })
    }

    @Test func regionsHaveStableNames() throws {
        let layout = WeekPageLayout(week: week(2026, 3, 30))
        let names = layout.regions.map(\.id.description)
        #expect(names == [
            "title",
            "week-day:2026-03-30", "week-day:2026-03-31", "week-day:2026-04-01", "week-day:2026-04-02",
            "week-day:2026-04-03", "week-day:2026-04-04", "week-day:2026-04-05",
            "section:week-notes",
        ])
        for name in names + ["day-page:2026-04-01"] {
            #expect(RegionID(name)?.description == name)
        }
        #expect(RegionID("week-day:2026-02-30") == nil)

        // Ink in a day's box belongs to that day, even on its header; ink in the notes to the notes.
        let template = WeekPageTemplate.make(week: week(2026, 3, 30), locale: english, labels: .english)
        let thursday = try #require(layout.box(for: day(2026, 4, 2)))
        #expect(InkAnchor.region(at: CGPoint(x: thursday.frame.midX, y: thursday.lines[3].midY), in: template) == .weekDay(day(2026, 4, 2)))
        #expect(InkAnchor.region(at: CGPoint(x: thursday.header.midX, y: thursday.header.midY), in: template) == .weekDay(day(2026, 4, 2)))
        #expect(InkAnchor.region(at: CGPoint(x: layout.notes.frame.midX, y: layout.notes.frame.midY), in: template) == .section(.weekNotes))
        #expect(InkAnchor.region(at: CGPoint(x: 500, y: 1390), in: template) == nil)
        // The header of a day is a control that opens its journal page; the notes have none.
        #expect(template.control(at: CGPoint(x: thursday.header.midX, y: thursday.header.midY))?.id == .dayPage(day(2026, 4, 2)))
        #expect(template.control(at: CGPoint(x: thursday.frame.midX, y: thursday.lines[3].midY)) == nil)
        #expect(template.control(at: CGPoint(x: layout.notes.header.midX, y: layout.notes.header.midY)) == nil)
        #expect(template.controls.count == 7)
    }

    @Test func titleNumberAndHeaders() throws {
        let template = WeekPageTemplate.make(
            week: week(2026, 3, 30), locale: greek,
            labels: WeekPageLabels(week: "Εβδομάδα", notes: "Σημειώσεις"),
            month: YearMonth(year: 2026, month: 3), today: day(2026, 4, 1)
        )
        let texts = template.texts.map(\.string)
        #expect(texts.contains("2026"))
        #expect(texts.contains("30 ΜΑΡΤΙΟΥ – 5 ΑΠΡΙΛΙΟΥ"))
        #expect(texts.contains("ΕΒΔΟΜΑΔΑ 14"))
        #expect(texts.contains("ΣΗΜΕΙΩΣΕΙΣ"))
        #expect(texts.contains("ΤΕΤΑΡΤΗ"))

        // March days are dark; April days (another month here) faint; today white on black.
        let byText = Dictionary(template.texts.map { ($0.string, $0) }, uniquingKeysWith: { first, _ in first })
        #expect(byText["30"]?.tone == .text)
        #expect(byText["31"]?.tone == .text)
        #expect(byText["2"]?.tone == .faint)
        #expect(byText["5"]?.tone == .faint)
        #expect(byText["1"]?.tone == .paper)
        let layout = WeekPageLayout(week: week(2026, 3, 30))
        let todayBox = try #require(layout.box(for: day(2026, 4, 1)))
        #expect(template.shapes.contains { shape in
            if case let .circle(center, _, fill, _, _) = shape {
                return fill == .ink && abs(center.x - (todayBox.header.minX + WeekPageLayout.dayNumberCenterX)) < 0.01
            }
            return false
        })

        // Opened from April instead, the March days are the faint ones.
        let fromApril = WeekPageTemplate.make(
            week: week(2026, 3, 30), locale: greek, labels: .english, month: YearMonth(year: 2026, month: 4)
        )
        let tones = Dictionary(fromApril.texts.map { ($0.string, $0.tone) }, uniquingKeysWith: { first, _ in first })
        #expect(tones["30"] == .faint)
        #expect(tones["2"] == .text)
        #expect(tones["5"] == .secondary) // Sunday
    }

    @Test func longTitlesStayClearOfTheWeekNumber() throws {
        _ = TestFonts.registered
        let labels = WeekPageLabels(week: "Εβδομάδα", notes: "Σημειώσεις")
        for start in [day(2026, 9, 28), day(2026, 11, 30), day(2026, 12, 28), day(2027, 2, 22)] {
            let template = WeekPageTemplate.make(week: PlannerWeek(start: start), locale: greek, labels: labels)
            let title = try #require(template.texts.first { $0.font == .bold })
            let number = try #require(template.texts.first { $0.alignment == .right })
            let titleEnd = title.anchor.x + TemplateRenderer.width(of: title)
            let numberStart = number.anchor.x - TemplateRenderer.width(of: number)
            #expect(titleEnd + 20 <= numberStart, "\(title.string) at \(title.size)")
        }
    }

    @Test func journalDotsAndBirthdayGifts() {
        let plain = WeekPageTemplate.make(week: week(2026, 11, 9), locale: english, labels: .english)
        let marked = WeekPageTemplate.make(
            week: week(2026, 11, 9), locale: english, labels: .english,
            journalDays: [day(2026, 11, 10)], birthdayDays: [day(2026, 11, 13), day(2026, 12, 1)]
        )
        func circles(_ template: PageTemplate) -> Int {
            template.shapes.filter { if case .circle = $0 { true } else { false } }.count
        }
        // One dot, and a gift (two circles for its bow); the birthday of another week shows nothing.
        #expect(circles(marked) - circles(plain) == 3)
    }

    @Test func weekPageIsDrawnInGreysOnly() throws {
        let template = WeekPageTemplate.make(
            week: week(2026, 11, 9), locale: english, labels: .english,
            month: YearMonth(year: 2026, month: 11), today: day(2026, 11, 14)
        )
        let bitmap = try PageBitmap(template, scale: 1)
        let layout = WeekPageLayout(week: week(2026, 11, 9))
        #expect(bitmap.isGreyscale)
        // The title is printed at the top-left, the rules under each header.
        #expect(bitmap.darkPixels(in: CGRect(x: 50, y: 75, width: 200, height: 27)) > 400)
        for box in layout.boxes {
            #expect(bitmap.white(at: CGPoint(x: box.frame.midX, y: box.ruleY)) < 0.8)
            #expect(bitmap.white(at: CGPoint(x: box.frame.midX, y: box.lines[3].midY)) == 1)
        }
    }

    @Test func weeklyButtonsWithInkGetADot() {
        let month = YearMonth(year: 2026, month: 11)
        let plain = MonthPageTemplate.make(month: month, locale: english, labels: .english)
        let inked = MonthPageTemplate.make(month: month, locale: english, labels: .english, inkedWeeks: [2, 6])
        let layout = MonthPageLayout(month: month)
        func dots(_ template: PageTemplate) -> [CGPoint] {
            template.shapes.compactMap { shape in
                if case let .circle(center, _, _, _, _) = shape, center.y < layout.goals.minY { return center }
                return nil
            }
        }
        #expect(dots(plain).isEmpty)
        #expect(dots(inked).map(\.x) == [layout.weeklyButtons[1].midX, layout.weeklyButtons[5].midX])
        // The WEEKLY buttons are still regions of the page, numbered from 1.
        #expect(inked.region(.weekly(6))?.rect == layout.weeklyButtons[5])
    }
}

@Suite("Page metadata")
struct PageMetadataTests {
    @Test func metadataIsReadWithoutTheDrawing() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "PlannerCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalPageStore(folder: folder)
        let page = PlannerPage.week(week(2026, 12, 28))
        #expect(try store.metadata(of: page) == nil)

        let metadata = PageMetadata(
            page: page, layout: .current(for: page), strokeCount: 4,
            modified: Date(timeIntervalSince1970: 1_800_000_000), writtenBy: "tests"
        )
        try store.save(PageFile(metadata: metadata, drawing: Data(repeating: 7, count: 50_000)), for: page)
        #expect(try store.metadata(of: page) == metadata)
        #expect(try store.savedPages() == [page])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "week-2026-12-28.dcpage").path(percentEncoded: false)))

        try Data("DCPG".utf8).write(to: store.url(for: page))
        #expect(throws: PageFileError.truncated) { try store.metadata(of: page) }
        try Data("nope, not a page".utf8).write(to: store.url(for: page))
        #expect(throws: PageFileError.notAPageFile) { try store.metadata(of: page) }
    }
}
