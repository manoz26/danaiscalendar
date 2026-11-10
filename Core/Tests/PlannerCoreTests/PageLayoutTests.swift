import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

private let canvas = CGRect(origin: .zero, size: PageCanvas.size)

private func expectNoOverlap(_ rects: [CGRect], _ what: String, sourceLocation: SourceLocation = #_sourceLocation) {
    for (i, a) in rects.enumerated() {
        for b in rects[(i + 1)...] {
            let overlap = a.intersection(b)
            #expect(overlap.isNull || overlap.width * overlap.height < 0.01, "\(what) overlap: \(a) \(b)", sourceLocation: sourceLocation)
        }
    }
}

@Suite("Month page layout")
struct MonthPageLayoutTests {
    private let months = [
        YearMonth(year: 2027, month: 2), // 4 weeks
        YearMonth(year: 2028, month: 2), // leap, 5 weeks
        YearMonth(year: 2026, month: 11), // 6 weeks
    ]

    @Test func everythingIsInsideTheCanvas() {
        for month in months {
            for region in MonthPageLayout(month: month).regions {
                #expect(canvas.contains(region.rect), "\(region.id) \(region.rect)")
            }
        }
    }

    @Test func regionIdentifiersAreUniqueAndRoundTrip() {
        for month in months {
            let regions = MonthPageLayout(month: month).regions
            let ids = regions.map(\.id.description)
            #expect(Set(ids).count == ids.count)
            for region in regions {
                #expect(RegionID(region.id.description) == region.id, "\(region.id)")
            }
        }
    }

    @Test func stableIdentifiers() {
        #expect(RegionID.day(PlannerDate(year: 2026, month: 11, day: 14)).description == "day:2026-11-14")
        #expect(RegionID.section(.memo).description == "section:memo")
        #expect(RegionID.section(.tobuy).description == "section:tobuy")
        #expect(RegionID.todoLine(3).description == "todo:3")
        #expect(RegionID.weekly(5).description == "weekly:5")
        #expect(RegionID.weekday(.monday).description == "weekday:monday")
        #expect(RegionID.month(YearMonth(year: 2026, month: 3)).description == "month:2026-03")
        #expect(RegionID.monthNotes(YearMonth(year: 2026, month: 3)).description == "notes:2026-03")
        #expect(RegionID("nonsense:1") == nil)
        #expect(RegionID("todo:0") == nil)
    }

    @Test func dayCellsTileTheSameGridWhateverTheNumberOfWeeks() {
        let frames = months.map { MonthPageLayout(month: $0).gridFrame }
        #expect(Set(frames.map { "\($0)" }).count == 1)

        for month in months {
            let layout = MonthPageLayout(month: month)
            let cells = layout.weeks.joined().map(\.frame)
            #expect(cells.count == layout.grid.weekCount * 7)
            let area = cells.reduce(0) { $0 + $1.width * $1.height }
            #expect(abs(area - layout.gridFrame.width * layout.gridFrame.height) < 0.5)
            expectNoOverlap(cells, "cells of \(month)")
            #expect(cells.allSatisfy { layout.gridFrame.insetBy(dx: -0.01, dy: -0.01).contains($0) })
        }
    }

    @Test func fourWeekMonthsHaveTallerCells() {
        let four = MonthPageLayout(month: YearMonth(year: 2027, month: 2))
        let six = MonthPageLayout(month: YearMonth(year: 2026, month: 11))
        #expect(four.rowHeight == four.gridFrame.height / 4)
        #expect(six.rowHeight == six.gridFrame.height / 6)
        #expect(four.rowHeight > six.rowHeight)
        #expect(four.columnWidth == six.columnWidth)
    }

    @Test func columnsFollowTheFirstWeekday() {
        let monday = MonthPageLayout(month: YearMonth(year: 2026, month: 11))
        #expect(monday.weekdays.first?.weekday == .monday)
        #expect(monday.weekdays.last?.weekday == .sunday)
        let sunday = MonthPageLayout(month: YearMonth(year: 2026, month: 11), firstWeekday: .sunday)
        #expect(sunday.weekdays.first?.weekday == .sunday)
        #expect(sunday.cell(for: PlannerDate(year: 2026, month: 11, day: 1))?.frame.minX == MonthPageLayout.margin)
    }

    @Test func oneWeeklyButtonPerWeek() {
        for month in months {
            let layout = MonthPageLayout(month: month)
            #expect(layout.weeklyButtons.count == layout.grid.weekCount)
            expectNoOverlap(layout.weeklyButtons, "weekly buttons")
            #expect(abs((layout.weeklyButtons.last?.maxX ?? 0) - (PageCanvas.size.width - MonthPageLayout.margin)) < 0.01)
            #expect(layout.weeklyButtons.allSatisfy { !$0.intersects(layout.title) })
        }
    }

    @Test func sectionsStackWithoutOverlapping() {
        let layout = MonthPageLayout(month: YearMonth(year: 2026, month: 11))
        #expect(layout.title.maxY < layout.goals.minY)
        #expect(layout.goals.maxY < layout.weekdays[0].frame.minY)
        #expect(layout.weekdays[0].frame.maxY <= layout.gridFrame.minY)
        #expect(layout.gridFrame.maxY < layout.todo.frame.minY)
        expectNoOverlap([layout.todo.frame, layout.toBuy.frame, layout.memo], "bottom lists")
        #expect(layout.todo.rows.count == MonthPageLayout.listRowCount)
        #expect(layout.toBuy.rows.count == MonthPageLayout.listRowCount)
        #expect(layout.todo.frame.minX == MonthPageLayout.margin)
        #expect(abs(layout.memo.maxX - (PageCanvas.size.width - MonthPageLayout.margin)) < 0.01)
        // The lists line up with the grid's columns.
        #expect(layout.todo.frame.width > layout.toBuy.frame.width)
        #expect(abs(layout.toBuy.frame.midX - layout.weekdays[4].frame.minX) < 0.01)
    }

    @Test func hitTestingFindsTheMostSpecificRegion() throws {
        let template = MonthPageTemplate.make(month: YearMonth(year: 2026, month: 11), locale: Locale(identifier: "en_US"), labels: .english)
        let day = PlannerDate(year: 2026, month: 11, day: 14)
        let cell = try #require(template.region(.day(day)))
        #expect(template.regions(at: CGPoint(x: cell.rect.midX, y: cell.rect.midY)).first?.id == .day(day))

        let line = try #require(template.region(.todoLine(3)))
        let hits = template.regions(at: CGPoint(x: line.rect.midX, y: line.rect.midY)).map(\.id)
        #expect(hits == [.todoLine(3), .section(.todo)])

        #expect(template.regions(at: CGPoint(x: 500, y: 255)).isEmpty)
    }
}

@Suite("Year page layout")
struct YearPageLayoutTests {
    @Test func twelveMonthsInThreeColumnsAndFourRows() {
        let layout = YearPageLayout(year: 2026)
        #expect(layout.months.map(\.month.month) == Array(1...12))
        #expect(layout.months.allSatisfy { $0.month.year == 2026 })
        let jan = layout.miniMonth(1), mar = layout.miniMonth(3), apr = layout.miniMonth(4), dec = layout.miniMonth(12)
        #expect(jan.slot.minX == mar.slot.minX - 2 * layout.slotSize.width)
        #expect(jan.slot.minY == mar.slot.minY)
        #expect(apr.slot.minX == jan.slot.minX)
        #expect(apr.slot.minY == jan.slot.maxY)
        #expect(abs(dec.slot.maxX - (PageCanvas.size.width - YearPageLayout.margin)) < 0.01)
        expectNoOverlap(layout.months.map(\.slot), "slots")
    }

    @Test func notesBoxesLineUpUnderEveryMonth() {
        let layout = YearPageLayout(year: 2026)
        for mini in layout.months {
            #expect(mini.slot.contains(mini.block))
            #expect(mini.slot.contains(mini.notes))
            #expect(mini.block.maxY < mini.notes.minY)
            #expect(mini.title.maxY <= mini.weekdays[0].frame.minY + 0.01)
            for cell in mini.weeks.joined() {
                #expect(mini.block.insetBy(dx: -0.01, dy: -0.01).contains(cell.frame), "\(cell.day.date)")
            }
            #expect(mini.notes.minY - mini.slot.minY == layout.miniMonth(1).notes.minY - layout.miniMonth(1).slot.minY)
        }
    }

    @Test func everythingIsInsideTheCanvasWithUniqueIdentifiers() {
        let regions = YearPageLayout(year: 2028).regions
        for region in regions {
            #expect(canvas.contains(region.rect), "\(region.id)")
            #expect(RegionID(region.id.description) == region.id)
        }
        let ids = regions.map(\.id)
        #expect(Set(ids).count == ids.count)
        // Only the days of each month are named: 366 in a leap year.
        #expect(ids.filter { if case .day = $0 { true } else { false } }.count == 366)
    }

    @Test func tappingASmallMonthFindsIt() throws {
        let template = YearPageTemplate.make(year: 2028, locale: Locale(identifier: "en_US"))
        let february = YearMonth(year: 2028, month: 2)
        let block = try #require(template.region(.month(february)))
        let title = try #require(template.region(.monthTitle(february)))
        #expect(template.regions(at: CGPoint(x: title.rect.midX, y: title.rect.midY)).map(\.id).contains(.month(february)))
        #expect(template.regions(at: CGPoint(x: block.rect.midX, y: block.rect.maxY - 5)).map(\.id).contains(.month(february)))
        let notes = try #require(template.region(.monthNotes(february)))
        #expect(!template.regions(at: CGPoint(x: notes.rect.midX, y: notes.rect.midY)).map(\.id).contains(.month(february)))
    }
}
