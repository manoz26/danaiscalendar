import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

private let march = YearMonth(year: 2029, month: 3)
private let canvas = CGRect(origin: .zero, size: PageCanvas.size)

private func region(_ id: RegionID, in layout: MonthPageLayout) -> CGRect? {
    layout.anchorRegions.first { $0.id == id }?.rect
}

/// A stroke's bounds moved by a migration.
private func moved(_ bounds: CGRect, from old: MonthLayout, to new: MonthLayout, month: YearMonth = march) -> CGRect {
    let before = MonthPageLayout(month: month, layout: old).anchorRegions
    let after = MonthPageLayout(month: month, layout: new).anchorRegions
    guard let transform = LayoutMigration.transform(forStrokeBounds: bounds, from: before, to: after) else { return bounds }
    return bounds.applying(transform)
}

@Suite("Her month page (prompt 9)")
struct MonthLayoutTests {
    @Test func theStandardLayoutIsThePageAsItWas() {
        let layout = MonthPageLayout(month: march)
        #expect(layout.options == .standard)
        #expect(layout.goals == CGRect(x: 50, y: 162, width: 900, height: 84))
        #expect(layout.gridFrame == CGRect(x: 50, y: 300, width: 900, height: 690))
        #expect(layout.todo.frame.minY == 1044)
        #expect(layout.todo.rows.count == 9)
        #expect(layout.memo.labelAnchor.y == 1032)
        #expect(layout.regions.map(\.id.description).filter { $0.hasPrefix("section:") } == ["section:goals", "section:todo", "section:memo"])
        // Templates of the standard layout are the same as before prompt 9.
        #expect(MonthPageTemplate.make(month: march, layout: .standard, locale: Locale(identifier: "en_US"), labels: .english)
            == MonthPageTemplate.make(month: march, locale: Locale(identifier: "en_US"), labels: .english))
    }

    @Test func withoutTheBoxAboveTheGridTheGridIsTaller() {
        var options = MonthLayout.standard
        options.set(nil, in: .top)
        let layout = MonthPageLayout(month: march, layout: options)
        #expect(layout.gridFrame.minY == 168)
        #expect(layout.gridFrame.maxY == 990)
        #expect(layout.weekdays[0].frame.maxY == 168)
        #expect(!layout.box(.goals).isShown)
        #expect(!canvas.intersects(layout.goals), "Goals are parked off the page")
        #expect(!layout.regions.contains { $0.id == .section(.goals) })
        #expect(layout.anchorRegions.contains { $0.id == .section(.goals) })
    }

    @Test func moreOrFewerLinesUnderTheGrid() {
        var options = MonthLayout.standard
        options.rows = 12
        let twelve = MonthPageLayout(month: march, layout: options)
        #expect(twelve.todo.rows.count == 12)
        #expect(twelve.todo.frame.maxY == 1341)
        #expect(abs(twelve.gridFrame.maxY - (1341 - 12 * 33 - 54)) < 0.001)
        options.rows = 30
        #expect(MonthPageLayout(month: march, layout: options).todo.rows.count == 12)
        options.rows = 5
        let five = MonthPageLayout(month: march, layout: options)
        #expect(five.todo.rows.count == 5)
        #expect(five.gridFrame.height > MonthPageLayout(month: march).gridFrame.height)
        // Lines 6...12 wait off the page.
        #expect(five.parkedTodoLines.count == 7)
        #expect(five.anchorRegions.filter { if case .todoLine = $0.id { return true } else { return false } }.count == 12)
        #expect(!five.regions.contains { $0.id == .todoLine(6) })
    }

    @Test func everythingShownIsOnThePageAndUnique() {
        let layouts: [MonthLayout] = [
            .standard,
            MonthLayout(top: nil, left: .todo, right: .memo, rows: 12),
            MonthLayout(top: .custom, left: .memo, right: .todo, rows: 6, titles: ["custom": "Expenses"]),
            MonthLayout(top: .goals, left: .todo, right: nil),
            MonthLayout(top: nil, left: nil, right: nil),
        ]
        for options in layouts {
            for month in [march, YearMonth(year: 2026, month: 11), YearMonth(year: 2027, month: 2)] {
                let layout = MonthPageLayout(month: month, layout: options)
                for region in layout.regions {
                    #expect(canvas.contains(region.rect), "\(region.id) \(region.rect) with \(options)")
                }
                let ids = layout.anchorRegions.map(\.id.description)
                #expect(Set(ids).count == ids.count, "\(options)")
            }
        }
    }

    @Test func aListAloneRunsAcrossThePage() {
        let layout = MonthPageLayout(month: march, layout: MonthLayout(top: .goals, left: .todo, right: nil))
        #expect(layout.todo.frame.minX == 50)
        #expect(layout.todo.frame.maxX == 950)
        #expect(!layout.box(.memo).isShown)
        let nothing = MonthPageLayout(month: march, layout: MonthLayout(top: nil, left: nil, right: nil))
        #expect(nothing.gridFrame == CGRect(x: 50, y: 168, width: 900, height: 1341 - 168))
    }

    @Test func eachBoxIsInOnePlaceAndTheToDoListUnderTheGrid() {
        var options = MonthLayout.standard
        options.set(.memo, in: .top)
        #expect(options.top == .memo && options.right == nil)
        options.set(.todo, in: .top)
        #expect(options.top == .memo, "The to-do list is never above the grid")
        options.set(.custom, in: .right)
        options.setTitle("  Expenses \n", of: .custom)
        #expect(options.title(of: .custom) == "Expenses")
        options.setTitle(" ", of: .goals)
        #expect(options.title(of: .goals) == nil)
        #expect(MonthLayout(top: .todo, left: .todo, right: .todo).validated == MonthLayout(top: nil, left: .todo, right: nil))
    }

    @Test func layoutsSurviveTheirFile() throws {
        let options = MonthLayout(top: nil, left: .memo, right: .custom, rows: 7, titles: ["custom": "Έξοδα"])
        let data = try JSONEncoder().encode(options)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""top":null"#), Comment(rawValue: text))
        #expect(try JSONDecoder().decode(MonthLayout.self, from: data) == options)
        // Unknown boxes are the standard ones; missing keys too.
        let odd = #"{"top":"calendar","rows":99}"#
        let read = try JSONDecoder().decode(MonthLayout.self, from: Data(odd.utf8))
        #expect(read == MonthLayout(rows: 12))
    }

    @Test func fromThisMonthOnOrForAllMonths() {
        var layouts = MonthLayouts()
        #expect(layouts.layout(for: march) == .standard)
        let custom = MonthLayout(top: nil)
        layouts.set(custom, from: march, at: Date(timeIntervalSince1970: 10))
        #expect(layouts.layout(for: YearMonth(year: 2029, month: 2)) == .standard)
        #expect(layouts.layout(for: march) == custom)
        #expect(layouts.layout(for: YearMonth(year: 2031, month: 7)) == custom)
        let later = MonthLayout(rows: 12)
        layouts.set(later, from: YearMonth(year: 2029, month: 6), at: Date(timeIntervalSince1970: 20))
        #expect(layouts.layout(for: YearMonth(year: 2029, month: 5)) == custom)
        #expect(layouts.layout(for: YearMonth(year: 2029, month: 6)) == later)
        // From an earlier month on: the later choices go.
        layouts.set(.standard, from: YearMonth(year: 2029, month: 1), at: Date(timeIntervalSince1970: 30))
        #expect(layouts.entries.count == 1)
        #expect(layouts.layout(for: YearMonth(year: 2029, month: 6)) == .standard)
        layouts.set(later, from: nil, at: Date(timeIntervalSince1970: 40))
        #expect(layouts.entries.count == 1)
        #expect(layouts.layout(for: YearMonth(year: 1990, month: 1)) == later)
        #expect(layouts.entry(for: march)?.changed == Date(timeIntervalSince1970: 40))
    }

    @Test func inkMovesWithItsDay() {
        // A note in the 21st (a Wednesday) moves into the 21st's taller cell.
        let page = MonthPageLayout(month: march)
        let cell = page.cell(for: PlannerDate(year: 2029, month: 3, day: 21))!.frame
        let note = CGRect(x: cell.minX + 10, y: cell.minY + 50, width: 60, height: 20)
        let taller = MonthLayout(top: nil, left: .todo, right: .memo, rows: 5)
        let newCell = MonthPageLayout(month: march, layout: taller).cell(for: PlannerDate(year: 2029, month: 3, day: 21))!.frame
        let result = moved(note, from: .standard, to: taller)
        #expect(newCell.contains(result))
        // Same width, taller cell: the handwriting keeps its size.
        #expect(abs(result.width - note.width) < 0.001)
        #expect(abs(result.height - note.height) < 0.001)
    }

    @Test func inkShrinksIntoASmallerBoxNeverGrows() {
        let memo = MonthPageLayout(month: march).memo.frame
        let note = CGRect(x: memo.minX + 20, y: memo.minY + 40, width: 300, height: 60)
        // The notes go above the grid: a lower box.
        let top = MonthLayout(top: .memo, left: .todo, right: nil)
        let box = MonthPageLayout(month: march, layout: top).memo.frame
        let shrunk = moved(note, from: .standard, to: top)
        #expect(box.contains(shrunk), "\(shrunk) not in \(box)")
        #expect(shrunk.height < note.height)
        #expect(abs(shrunk.width / note.width - shrunk.height / note.height) < 0.001, "Not stretched")
        // And back under the grid: the same size again at most.
        let back = moved(shrunk, from: top, to: .standard)
        #expect(back.width <= note.width + 0.001)
    }

    @Test func aHiddenBoxKeepsItsInkAndGetsItBack() {
        let goals = MonthPageLayout(month: march).goals
        let note = CGRect(x: goals.minX + 100, y: goals.minY + 20, width: 200, height: 40)
        var hidden = MonthLayout.standard
        hidden.set(nil, in: .top)
        let parked = moved(note, from: .standard, to: hidden)
        #expect(!canvas.intersects(parked), "Hidden goals' ink is off the page: \(parked)")
        let back = moved(parked, from: hidden, to: .standard)
        #expect(abs(back.minX - note.minX) < 0.001 && abs(back.minY - note.minY) < 0.001)
        #expect(abs(back.width - note.width) < 0.001)
    }

    @Test func toDoLinesComeBackWithTheirInk() {
        let standard = MonthPageLayout(month: march)
        let eighth = standard.todo.rows[7]
        let tick = CGRect(x: eighth.minX + 30, y: eighth.minY + 8, width: 80, height: 16)
        let five = MonthLayout(rows: 5)
        let parked = moved(tick, from: .standard, to: five)
        #expect(!canvas.intersects(parked), "Line 8 is not on a page of five lines")
        let twelve = MonthLayout(rows: 12)
        let shown = moved(parked, from: five, to: twelve)
        let line8 = MonthPageLayout(month: march, layout: twelve).todo.rows[7]
        #expect(line8.contains(CGPoint(x: shown.midX, y: shown.midY)), "\(shown) not on \(line8)")
    }

    @Test func inkInTheMarginsStays() {
        let margin = CGRect(x: 5, y: 600, width: 20, height: 30)
        #expect(moved(margin, from: .standard, to: MonthLayout(top: nil, rows: 12)) == margin)
    }

    @Test func pageFilesKeepHerLayout() throws {
        let changed = Date(timeIntervalSince1970: 1_900_000_000)
        let stamp = PageLayoutStamp(name: "month-v2", firstWeekday: .monday, monthLayout: MonthLayout(top: nil), changed: changed)
        let metadata = PageMetadata(page: .month(march), layout: stamp, strokeCount: 3, modified: changed, writtenBy: "test")
        let file = PageFile(metadata: metadata, drawing: Data([1, 2, 3]))
        let read = try PageFile(decoding: try file.encoded())
        #expect(read.metadata.stamp == stamp)
        #expect(read.metadata.stamp.changed == changed)
        // The standard page writes nothing new.
        let plain = PageMetadata(page: .month(march), layout: .current(for: .month(march)), strokeCount: 0, modified: changed, writtenBy: "test")
        let json = String(decoding: try PageMetadata.makeEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("monthLayout") && !json.contains("layoutChanged"), Comment(rawValue: json))
        // v1 and v2 print the same places: nothing moves.
        let v1 = PageLayoutStamp(name: "month-v1", firstWeekday: .monday)
        #expect(v1 == .current(for: .month(march)))
        #expect(v1.migration(to: .current(for: .month(march)), page: .month(march), strokeBounds: [CGRect(x: 100, y: 200, width: 10, height: 10)]) == nil)
    }

    @Test func theLaterLayoutWins() {
        let old = PageLayoutStamp(name: "month-v2", firstWeekday: .monday)
        let new = PageLayoutStamp(name: "month-v2", firstWeekday: .monday, monthLayout: MonthLayout(rows: 6), changed: Date(timeIntervalSince1970: 5))
        #expect(PageLayoutStamp.later(old, new) == new)
        #expect(PageLayoutStamp.later(new, old) == new)
        var layouts = MonthLayouts()
        layouts.set(MonthLayout(rows: 6), from: nil, at: Date(timeIntervalSince1970: 5))
        #expect(PageLayoutStamp.current(for: .month(march), monthLayouts: layouts) == new)
        #expect(PageLayoutStamp.current(for: .year(2029), monthLayouts: layouts) == PageLayoutStamp.current(for: .year(2029)))
        let moves = old.migration(to: new, page: .month(march), strokeBounds: [
            CGRect(x: 100, y: 1100, width: 40, height: 10), CGRect(x: 5, y: 5, width: 5, height: 5),
        ])
        #expect(moves?.count == 2)
        #expect(moves?[1] == nil)
    }

    @Test func herTitlesArePrinted() {
        let options = MonthLayout(top: .custom, left: .todo, right: .memo, titles: ["custom": "Expenses", "memo": "Ideas"])
        let template = MonthPageTemplate.make(month: march, layout: options, locale: Locale(identifier: "en_US"), labels: .english)
        let texts = template.texts.map(\.string)
        #expect(texts.contains("EXPENSES"))
        #expect(texts.contains("IDEAS"))
        #expect(!texts.contains("GOALS"))
        #expect(texts.contains("TO DO LIST"))
        // Without the to-do list there is no + for typed to-dos.
        let noTodo = MonthPageTemplate.make(month: march, layout: MonthLayout(left: .memo, right: nil), locale: Locale(identifier: "en_US"), labels: .english)
        #expect(noTodo.control(.addItem(.todo)) == nil)
        #expect(template.control(.addItem(.todo)) != nil)
    }
}
