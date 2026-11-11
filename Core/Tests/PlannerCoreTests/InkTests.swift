import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

@Suite("Ink belongs to the region under its centre")
struct InkAnchorTests {
    private let november = YearMonth(year: 2026, month: 11)
    private var monthTemplate: PageTemplate {
        MonthPageTemplate.make(month: november, locale: Locale(identifier: "en_US"), labels: .english)
    }
    private var yearTemplate: PageTemplate {
        YearPageTemplate.make(year: 2026, locale: Locale(identifier: "en_US"))
    }

    /// A small stroke-sized box centred on a point.
    private func box(around point: CGPoint, width: CGFloat = 40, height: CGFloat = 12) -> CGRect {
        CGRect(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }

    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    @Test func strokeInADayCell() throws {
        let layout = MonthPageLayout(month: november)
        let cell = try #require(layout.cell(for: PlannerDate(year: 2026, month: 11, day: 14)))
        let id = InkAnchor.region(forStrokeBounds: box(around: center(cell.frame)), in: monthTemplate)
        #expect(id == .day(PlannerDate(year: 2026, month: 11, day: 14)))
        #expect(id?.description == "day:2026-11-14")
    }

    @Test func strokeOverTwoCellsGoesWhereItsCentreIs() throws {
        let layout = MonthPageLayout(month: november)
        let fourteenth = try #require(layout.cell(for: PlannerDate(year: 2026, month: 11, day: 14)))
        // From the middle of the 14th to three quarters into the 15th: the centre is in the 15th.
        let bounds = CGRect(
            x: fourteenth.frame.midX, y: fourteenth.frame.midY,
            width: fourteenth.frame.width * 1.25, height: 10
        )
        #expect(InkAnchor.region(forStrokeBounds: bounds, in: monthTemplate) == .day(PlannerDate(year: 2026, month: 11, day: 15)))
    }

    @Test func dayOfAnotherMonthOnThePage() throws {
        // November 2026 starts on a Sunday, so the first row shows 26-31 October.
        let layout = MonthPageLayout(month: november)
        let cell = try #require(layout.cell(for: PlannerDate(year: 2026, month: 10, day: 27)))
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(cell.frame)), in: monthTemplate) == .day(PlannerDate(year: 2026, month: 10, day: 27)))
    }

    @Test func listLinesWinOverTheirList() {
        let layout = MonthPageLayout(month: november)
        let third = layout.todo.rows[2]
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(third), width: 120), in: monthTemplate) == .todoLine(3))
        let firstToBuy = layout.toBuy.rows[0]
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(firstToBuy)), in: monthTemplate) == .toBuyLine(1))
    }

    @Test func boxes() {
        let layout = MonthPageLayout(month: november)
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(layout.goals), width: 300), in: monthTemplate) == .section(.goals))
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(layout.memo)), in: monthTemplate) == .section(.memo))
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(layout.title)), in: monthTemplate) == .title)
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(layout.weeklyButtons[1]), width: 10, height: 10), in: monthTemplate) == .weekly(2))
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(layout.weekdays[0].frame)), in: monthTemplate) == .weekday(.monday))
    }

    @Test func marginsBelongToNoRegion() {
        #expect(InkAnchor.region(forStrokeBounds: box(around: CGPoint(x: 20, y: 700)), in: monthTemplate) == nil)
        #expect(InkAnchor.region(forStrokeBounds: box(around: CGPoint(x: 500, y: 1390)), in: monthTemplate) == nil)
        #expect(InkAnchor.region(forStrokeBounds: .null, in: monthTemplate) == nil)
    }

    @Test func yearPage() {
        let layout = YearPageLayout(year: 2026)
        let march = layout.miniMonth(3)
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(march.notes)), in: yearTemplate) == .monthNotes(YearMonth(year: 2026, month: 3)))
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(march.title), width: 20), in: yearTemplate) == .monthTitle(YearMonth(year: 2026, month: 3)))
        // A day number of a small month wins over the small month around it.
        let fourteenth = march.weeks.joined().first { $0.day.date == PlannerDate(year: 2026, month: 3, day: 14) }!
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(fourteenth.frame), width: 8, height: 8), in: yearTemplate) == .day(PlannerDate(year: 2026, month: 3, day: 14)))
        // Weekday letters are inside the small month but not on a day.
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(march.weekdays[2].frame), width: 6, height: 6), in: yearTemplate) == .month(YearMonth(year: 2026, month: 3)))
        #expect(InkAnchor.region(forStrokeBounds: box(around: center(layout.title)), in: yearTemplate) == .title)
    }

    @Test func fromStrokePoints() throws {
        let layout = MonthPageLayout(month: november)
        let cell = try #require(layout.cell(for: PlannerDate(year: 2026, month: 11, day: 3)))
        let points = [
            CGPoint(x: cell.frame.minX + 10, y: cell.frame.midY),
            CGPoint(x: cell.frame.midX, y: cell.frame.midY - 20),
            CGPoint(x: cell.frame.maxX - 10, y: cell.frame.midY + 15),
        ]
        #expect(InkAnchor.region(forStrokePoints: points, in: monthTemplate) == .day(PlannerDate(year: 2026, month: 11, day: 3)))
        #expect(InkAnchor.region(forStrokePoints: [], in: monthTemplate) == nil)
        // A single dot.
        #expect(InkAnchor.region(forStrokePoints: [center(layout.memo)], in: monthTemplate) == .section(.memo))
    }
}

@Suite("Toolbar state")
struct InkToolStateTests {
    @Test func startsWithABlackMediumPen() {
        let state = InkToolState()
        #expect(state.tool == .pen)
        #expect(state.color.key == "black")
        #expect(state.widthIndex == 1)
        #expect(state.width == 3)
        #expect(state.eraserMode == .partial)
    }

    @Test func eachToolKeepsItsWidth() {
        var state = InkToolState()
        state.selectWidth(2)
        state.select(.highlighter)
        #expect(state.widthIndex == 1)
        state.selectWidth(0)
        state.select(.pen)
        #expect(state.widthIndex == 2)
        #expect(state.widthIndex(for: .highlighter) == 0)
        state.selectWidth(7)
        #expect(state.widthIndex == 2)
    }

    @Test func lassoHasNoWidth() {
        var state = InkToolState()
        state.select(.lasso)
        state.selectWidth(0)
        #expect(state.width == nil)
        state.select(.pen)
        #expect(state.widthIndex == 1)
    }

    @Test func pickingAColourLeavesTheEraser() {
        var state = InkToolState()
        state.select(.pencil)
        state.select(.eraser)
        state.selectColor(2)
        #expect(state.tool == .pencil)
        #expect(state.color.key == "red")
        state.select(.lasso)
        state.selectColor(0)
        #expect(state.tool == .pencil)
        state.selectColor(99)
        #expect(state.color.key == "purple")
    }

    @Test func pencilDoubleTapTogglesTheEraser() {
        var state = InkToolState()
        state.select(.highlighter)
        state.toggleEraser()
        #expect(state.tool == .eraser)
        state.toggleEraser()
        #expect(state.tool == .highlighter)
        // Straight from launch: the eraser and back to the pen.
        var fresh = InkToolState()
        fresh.toggleEraser()
        fresh.toggleEraser()
        #expect(fresh.tool == .pen)
    }

    @Test func pencilDoubleTapSwitchesToThePreviousTool() {
        var state = InkToolState()
        state.switchToPrevious()
        #expect(state.tool == .eraser)
        state.switchToPrevious()
        #expect(state.tool == .pen)
        state.select(.lasso)
        state.switchToPrevious()
        #expect(state.tool == .pen)
    }

    @Test func survivesSavingAndLoading() throws {
        var state = InkToolState()
        state.select(.pencil)
        state.selectWidth(2)
        state.selectColor(3)
        state.eraserMode = .wholeStroke
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(InkToolState.self, from: data) == state)
    }

    @Test func widthsGrow() {
        for tool in InkTool.allCases where tool.hasWidths {
            let values = InkWidths.values(for: tool)
            #expect(values.count == InkToolState.widthCount)
            #expect(values == values.sorted())
        }
        #expect(InkWidths.values(for: .lasso).isEmpty)
    }

    @Test func paletteHasSixDistinctColours() {
        #expect(InkPalette.colors.count == 6)
        #expect(Set(InkPalette.colors.map(\.key)).count == 6)
        #expect(InkPalette.colors[InkPalette.defaultIndex].key == "black")
        let red = InkPalette.colors[2]
        #expect(red.key == "red" && red.red > 0.8 && red.green < 0.2 && red.blue < 0.2)
    }
}
