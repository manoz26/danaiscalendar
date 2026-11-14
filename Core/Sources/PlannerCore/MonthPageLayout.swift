import CoreGraphics
import Foundation

/// Where everything sits on a month page, in canvas units (1000 x 1400).
///
/// Top to bottom: year and title (WEEKLY buttons on the right), GOALS box, weekday
/// headers, the day grid, and at the bottom TO DO LIST (under 3 columns of the grid) and
/// MEMO (ruled lines under the other 4). The grid always fills the same area; 4, 5 or 6
/// weeks share it. (Layout `month-v2`; v1 also had a TO BUY list where MEMO's lines now
/// start: the shopping list has its own page.)
public struct MonthPageLayout: Sendable {
    public struct Column: Sendable, Equatable {
        public let weekday: Weekday
        public let frame: CGRect
    }

    public struct Cell: Sendable, Equatable {
        public let day: MonthGrid.Day
        public let frame: CGRect
    }

    /// A list at the bottom of the page: its label and ruled rows.
    public struct ListSection: Sendable, Equatable {
        public let labelAnchor: CGPoint
        public let frame: CGRect
        public let rows: [CGRect]
    }

    // MARK: Metrics

    public static let margin: CGFloat = 50
    public static let contentWidth: CGFloat = PageCanvas.size.width - 2 * margin

    public static let yearSize: CGFloat = 12
    public static let titleSize: CGFloat = 34
    public static let labelSize: CGFloat = 10.5
    public static let weekdaySize: CGFloat = 11
    public static let dayNumberSize: CGFloat = 13

    static let yearBaseline: CGFloat = 58
    static let titleBaseline: CGFloat = 102
    static let weeklyButtonSize: CGFloat = 26
    static let weeklyButtonGap: CGFloat = 8
    static let weeklyLabelGap: CGFloat = 12
    static let goalsLabelBaseline: CGFloat = 152
    static let goalsFrame = CGRect(x: margin, y: 162, width: contentWidth, height: 84)
    static let weekdayRow = CGRect(x: margin, y: 262, width: contentWidth, height: 38)
    static let gridFrame = CGRect(x: margin, y: 300, width: contentWidth, height: 690)
    static let listLabelBaseline: CGFloat = 1032
    static let listTop: CGFloat = 1044
    static let listRowHeight: CGFloat = 33
    public static let listRowCount = 9
    static let columnGutter: CGFloat = 24

    /// Centre of a day number, from the top-left corner of its cell.
    public static let dayNumberOffset = CGPoint(x: 21, y: 21)
    /// Height of the dot of a day with a journal page, from the top of its cell (under the number).
    public static let journalDotY: CGFloat = 41

    // MARK: Layout

    public let grid: MonthGrid
    public let yearAnchor: CGPoint
    public let titleAnchor: CGPoint
    public let title: CGRect
    /// Right end of the WEEKLY label's baseline.
    public let weeklyLabelAnchor: CGPoint
    /// One button per week, left to right.
    public let weeklyButtons: [CGRect]
    public let goalsLabelAnchor: CGPoint
    public let goals: CGRect
    public let weekdays: [Column]
    public let gridFrame: CGRect
    public let columnWidth: CGFloat
    public let rowHeight: CGFloat
    /// One row of 7 cells per week.
    public let weeks: [[Cell]]
    public let todo: ListSection
    /// The notes: ruled lines that run across the rest of the width.
    public let memo: ListSection

    public var month: YearMonth { grid.month }

    public init(month: YearMonth, firstWeekday: Weekday = .defaultFirst) {
        let grid = MonthGrid(month: month, firstWeekday: firstWeekday)
        self.grid = grid
        let margin = Self.margin
        let right = PageCanvas.size.width - margin

        yearAnchor = CGPoint(x: margin, y: Self.yearBaseline)
        titleAnchor = CGPoint(x: margin, y: Self.titleBaseline)
        title = CGRect(x: margin, y: Self.titleBaseline - 42, width: 560, height: 54)

        // WEEKLY buttons sit on the middle of the title's capitals, flush right.
        let titleMiddle = Self.titleBaseline - Self.titleSize * PlannerFont.capHeight / 2
        let size = Self.weeklyButtonSize
        let gap = Self.weeklyButtonGap
        let count = grid.weekCount
        let buttonsLeft = right - CGFloat(count) * size - CGFloat(count - 1) * gap
        weeklyButtons = (0..<count).map { index in
            CGRect(x: buttonsLeft + CGFloat(index) * (size + gap), y: titleMiddle - size / 2, width: size, height: size)
        }
        weeklyLabelAnchor = CGPoint(
            x: buttonsLeft - Self.weeklyLabelGap,
            y: TemplateText.baseline(centeredOn: titleMiddle, size: Self.labelSize)
        )

        goalsLabelAnchor = CGPoint(x: margin, y: Self.goalsLabelBaseline)
        goals = Self.goalsFrame

        // Columns share the content width exactly; edges are computed per column so they line up.
        let columnWidth = Self.contentWidth / 7
        self.columnWidth = columnWidth
        func columnEdge(_ index: Int) -> CGFloat { margin + columnWidth * CGFloat(index) }

        weekdays = grid.columns.enumerated().map { index, weekday in
            Column(weekday: weekday, frame: CGRect(
                x: columnEdge(index), y: Self.weekdayRow.minY,
                width: columnEdge(index + 1) - columnEdge(index), height: Self.weekdayRow.height
            ))
        }

        let gridFrame = Self.gridFrame
        self.gridFrame = gridFrame
        let rowHeight = gridFrame.height / CGFloat(grid.weekCount)
        self.rowHeight = rowHeight
        weeks = grid.weeks.enumerated().map { row, days in
            days.enumerated().map { column, day in
                let top = gridFrame.minY + rowHeight * CGFloat(row)
                let bottom = gridFrame.minY + rowHeight * CGFloat(row + 1)
                return Cell(day: day, frame: CGRect(
                    x: columnEdge(column), y: top,
                    width: columnEdge(column + 1) - columnEdge(column), height: bottom - top
                ))
            }
        }

        // Bottom lists line up with the grid columns: TO DO over 3, MEMO over the other 4.
        let halfGutter = Self.columnGutter / 2
        let listHeight = Self.listRowHeight * CGFloat(Self.listRowCount)
        func list(from firstColumn: Int, to endColumn: Int) -> ListSection {
            let leftEdge = firstColumn == 0 ? margin : columnEdge(firstColumn) + halfGutter
            let rightEdge = endColumn == 7 ? right : columnEdge(endColumn) - halfGutter
            let width = rightEdge - leftEdge
            let frame = CGRect(x: leftEdge, y: Self.listTop, width: width, height: listHeight)
            let rows = (0..<Self.listRowCount).map { index in
                CGRect(x: leftEdge, y: Self.listTop + Self.listRowHeight * CGFloat(index), width: width, height: Self.listRowHeight)
            }
            return ListSection(labelAnchor: CGPoint(x: leftEdge, y: Self.listLabelBaseline), frame: frame, rows: rows)
        }
        todo = list(from: 0, to: 3)
        memo = list(from: 3, to: 7)
    }

    /// The cell of a day shown on this page (including days of the next/previous month).
    public func cell(for date: PlannerDate) -> Cell? {
        guard let position = grid.position(of: date) else { return nil }
        return weeks[position.week][position.column]
    }

    /// Every named area of the page.
    public var regions: [PageRegion] {
        var regions = [PageRegion(.title, title)]
        regions += weeklyButtons.enumerated().map { PageRegion(.weekly($0.offset + 1), $0.element) }
        regions.append(PageRegion(.section(.goals), goals))
        regions += weekdays.map { PageRegion(.weekday($0.weekday), $0.frame) }
        regions += weeks.joined().map { PageRegion(.day($0.day.date), $0.frame) }
        regions.append(PageRegion(.section(.todo), todo.frame))
        regions += todo.rows.enumerated().map { PageRegion(.todoLine($0.offset + 1), $0.element) }
        regions.append(PageRegion(.section(.memo), memo.frame))
        return regions
    }
}
