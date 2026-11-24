import CoreGraphics
import Foundation

/// Where everything sits on a month page, in canvas units (1000 x 1400).
///
/// Top to bottom on the standard page: year and title (WEEKLY buttons on the right), GOALS
/// box, weekday headers, the day grid, and at the bottom TO DO LIST (under 3 columns of the
/// grid) and MEMO (ruled lines under the other 4). The grid always fills the same area; 4,
/// 5 or 6 weeks share it. (Layout `month-v2`; v1 also had a TO BUY list where MEMO's lines
/// now start: the shopping list has its own page.)
///
/// With her own layout (`MonthLayout`, prompt 9) the box above the grid and the lists under
/// it can be others or none, and the lists have 5 to 12 lines; the grid takes what is left.
/// Boxes that are not shown are parked off the page with their standard size, so that the
/// ink written in them waits there (`anchorRegions`, `LayoutMigration`).
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

    /// A box of the page: where it is (`nil`: not shown, parked off the page) and its area.
    /// Above the grid it has no rows (a grey box); under it, ruled rows.
    public struct Box: Sendable, Equatable {
        public let kind: MonthBoxKind
        public let slot: MonthSlot?
        public let section: ListSection

        public var isShown: Bool { slot != nil }
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
    /// Lines of the lists of the standard page (see `MonthLayout.rows`).
    public static let listRowCount = MonthLayout.standardRows
    static let columnGutter: CGFloat = 24
    /// The bottom of the lists: the standard page's 9 lines end there, whatever their number.
    static let listBottom: CGFloat = listTop + listRowHeight * CGFloat(listRowCount)
    /// Without a box above the grid, the weekday headers come up under the title.
    static let gridTopWithoutBox: CGFloat = 168
    /// From the bottom of the grid to the top of the lists' lines (their labels sit between).
    static let listGap: CGFloat = listTop - gridFrame.maxY
    /// Boxes that are not shown wait this far to the right, off the page.
    static let parkingOffset: CGFloat = 2000

    /// Centre of a day number, from the top-left corner of its cell.
    public static let dayNumberOffset = CGPoint(x: 21, y: 21)
    /// Height of the dot of a day with a journal page, from the top of its cell (under the number).
    public static let journalDotY: CGFloat = 41

    // MARK: Layout

    public let grid: MonthGrid
    /// Her layout (`MonthLayout.standard` unless she changed it).
    public let options: MonthLayout
    public let yearAnchor: CGPoint
    public let titleAnchor: CGPoint
    public let title: CGRect
    /// Right end of the WEEKLY label's baseline.
    public let weeklyLabelAnchor: CGPoint
    /// One button per week, left to right.
    public let weeklyButtons: [CGRect]
    public let weekdays: [Column]
    public let gridFrame: CGRect
    public let columnWidth: CGFloat
    public let rowHeight: CGFloat
    /// One row of 7 cells per week.
    public let weeks: [[Cell]]
    /// Every box, shown or parked, in `MonthBoxKind` order.
    public let boxes: [Box]
    /// To-do lines that are not on the page (beyond `options.rows`, or all of them when the
    /// list is not shown), parked off it so that their ink comes back with them.
    public let parkedTodoLines: [CGRect]

    public var month: YearMonth { grid.month }

    public func box(_ kind: MonthBoxKind) -> Box {
        boxes.first { $0.kind == kind } ?? boxes[0]
    }

    /// The boxes on the page.
    public var shownBoxes: [Box] { boxes.filter(\.isShown) }

    /// The to-do list: under the grid, or parked.
    public var todo: ListSection { box(.todo).section }
    /// The notes (ruled lines under the grid on the standard page), or parked.
    public var memo: ListSection { box(.memo).section }
    /// The goals box (above the grid on the standard page), or parked.
    public var goals: CGRect { box(.goals).section.frame }
    public var goalsLabelAnchor: CGPoint { box(.goals).section.labelAnchor }

    public init(month: YearMonth, firstWeekday: Weekday = .defaultFirst, layout options: MonthLayout = .standard) {
        let options = options.validated
        self.options = options
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

        // Columns share the content width exactly; edges are computed per column so they line up.
        let columnWidth = Self.contentWidth / 7
        self.columnWidth = columnWidth
        func columnEdge(_ index: Int) -> CGFloat { margin + columnWidth * CGFloat(index) }

        // The grid fills what the boxes leave: from under the box above it (or the title) to
        // over the lists under it (or the bottom of the lists' area).
        let hasTop = options.top != nil
        let hasBottom = options.left != nil || options.right != nil
        let rowCount = options.rows
        let listTop = Self.listBottom - Self.listRowHeight * CGFloat(rowCount)
        let gridTop = hasTop ? Self.gridFrame.minY : Self.gridTopWithoutBox
        let gridBottom = hasBottom ? listTop - Self.listGap : Self.listBottom
        let headerHeight = Self.weekdayRow.height

        weekdays = grid.columns.enumerated().map { index, weekday in
            Column(weekday: weekday, frame: CGRect(
                x: columnEdge(index), y: gridTop - headerHeight,
                width: columnEdge(index + 1) - columnEdge(index), height: headerHeight
            ))
        }

        let gridFrame = CGRect(x: margin, y: gridTop, width: Self.contentWidth, height: gridBottom - gridTop)
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

        // Lists under the grid line up with its columns: on the left over 3, on the right
        // over the other 4 (TO DO LIST and MEMO on the standard page); alone, across.
        let halfGutter = Self.columnGutter / 2
        let labelGap = Self.listTop - Self.listLabelBaseline
        func list(from firstColumn: Int, to endColumn: Int, top: CGFloat, rows count: Int, dx: CGFloat = 0) -> ListSection {
            let leftEdge = (firstColumn == 0 ? margin : columnEdge(firstColumn) + halfGutter) + dx
            let rightEdge = (endColumn == 7 ? right : columnEdge(endColumn) - halfGutter) + dx
            let width = rightEdge - leftEdge
            let frame = CGRect(x: leftEdge, y: top, width: width, height: Self.listRowHeight * CGFloat(count))
            let rows = (0..<count).map { index in
                CGRect(x: leftEdge, y: top + Self.listRowHeight * CGFloat(index), width: width, height: Self.listRowHeight)
            }
            return ListSection(labelAnchor: CGPoint(x: leftEdge, y: top - labelGap), frame: frame, rows: rows)
        }
        func topBox(dx: CGFloat = 0) -> ListSection {
            ListSection(
                labelAnchor: CGPoint(x: margin + dx, y: Self.goalsLabelBaseline),
                frame: Self.goalsFrame.offsetBy(dx: dx, dy: 0), rows: []
            )
        }
        // Where a box waits while it is not shown: its place on the standard page, off the page.
        func parked(_ kind: MonthBoxKind) -> ListSection {
            let dx = Self.parkingOffset * (kind == .custom ? 2 : 1)
            switch kind {
            case .goals: return topBox(dx: dx)
            case .todo: return list(from: 0, to: 3, top: Self.listTop, rows: Self.listRowCount, dx: dx)
            case .memo, .custom: return list(from: 3, to: 7, top: Self.listTop, rows: Self.listRowCount, dx: dx)
            }
        }
        let alone = options.left == nil || options.right == nil
        boxes = MonthBoxKind.allCases.map { kind in
            switch options.slot(of: kind) {
            case .top?: Box(kind: kind, slot: .top, section: topBox())
            case .left?: Box(kind: kind, slot: .left, section: list(from: 0, to: alone ? 7 : 3, top: listTop, rows: rowCount))
            case .right?: Box(kind: kind, slot: .right, section: list(from: alone ? 0 : 3, to: 7, top: listTop, rows: rowCount))
            case nil: Box(kind: kind, slot: nil, section: parked(kind))
            }
        }
        // To-do lines off the page continue the standard list, off the page.
        let shownTodoLines = options.slot(of: .todo) == nil ? 0 : rowCount
        let parkedList = list(from: 0, to: 3, top: Self.listTop, rows: MonthLayout.rowRange.upperBound, dx: Self.parkingOffset)
        parkedTodoLines = Array(parkedList.rows.dropFirst(shownTodoLines))
    }

    /// The cell of a day shown on this page (including days of the next/previous month).
    public func cell(for date: PlannerDate) -> Cell? {
        guard let position = grid.position(of: date) else { return nil }
        return weeks[position.week][position.column]
    }

    /// Every named area on the page.
    public var regions: [PageRegion] {
        var regions = [PageRegion(.title, title)]
        regions += weeklyButtons.enumerated().map { PageRegion(.weekly($0.offset + 1), $0.element) }
        if let top = shownBoxes.first(where: { $0.slot == .top }) {
            regions.append(PageRegion(.section(top.kind.section), top.section.frame))
        }
        regions += weekdays.map { PageRegion(.weekday($0.weekday), $0.frame) }
        regions += weeks.joined().map { PageRegion(.day($0.day.date), $0.frame) }
        for box in shownBoxes where box.slot != .top {
            regions.append(PageRegion(.section(box.kind.section), box.section.frame))
            if box.kind == .todo {
                regions += box.section.rows.enumerated().map { PageRegion(.todoLine($0.offset + 1), $0.element) }
            }
        }
        return regions
    }

    /// The regions on the page and those parked off it (boxes not shown, to-do lines beyond
    /// the page's): what ink is anchored to when the layout changes (`LayoutMigration`).
    public var anchorRegions: [PageRegion] {
        var regions = self.regions
        for box in boxes where !box.isShown {
            regions.append(PageRegion(.section(box.kind.section), box.section.frame))
        }
        let firstParked = MonthLayout.rowRange.upperBound - parkedTodoLines.count + 1
        regions += parkedTodoLines.enumerated().map { PageRegion(.todoLine(firstParked + $0.offset), $0.element) }
        return regions
    }
}

extension MonthPageLayout {
    /// The day's number in the top-left corner of its cell: with "Draw with finger too" a
    /// finger there still opens the day's events (anywhere else in the cell it writes).
    public static func isOnDayNumber(_ point: CGPoint, cell: CGRect) -> Bool {
        cell.contains(point) && point.x < cell.minX + 2 * dayNumberOffset.x && point.y < cell.minY + 2 * dayNumberOffset.y
    }
}
