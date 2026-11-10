import CoreGraphics
import Foundation

/// Where everything sits on a year page, in canvas units (1000 x 1400).
///
/// The year as title, then 12 small months in 3 columns and 4 rows, each with a grey
/// notes box under it. Every small month reserves 6 week rows, so the notes boxes line up.
public struct YearPageLayout: Sendable {
    public struct MiniMonth: Sendable, Equatable {
        public let grid: MonthGrid
        /// The whole slot, between the separator lines.
        public let slot: CGRect
        /// Title and days. Tapping here opens the month.
        public let block: CGRect
        public let title: CGRect
        public let titleAnchor: CGPoint
        public let weekdays: [MonthPageLayout.Column]
        /// One row of 7 day frames per week of the month.
        public let weeks: [[MonthPageLayout.Cell]]
        public let notes: CGRect

        public var month: YearMonth { grid.month }
    }

    // MARK: Metrics

    public static let margin: CGFloat = MonthPageLayout.margin
    public static let columns = 3
    public static let rows = 4
    public static let titleSize: CGFloat = MonthPageLayout.titleSize
    public static let miniTitleSize: CGFloat = 15
    public static let weekdaySize: CGFloat = 9
    public static let dayNumberSize: CGFloat = 11

    static let titleBaseline: CGFloat = 102
    static let gridTop: CGFloat = 140
    static let gridBottom: CGFloat = 1350
    static let slotInset: CGFloat = 16
    static let miniTitleBaseline: CGFloat = 36
    static let weekdayCenter: CGFloat = 58
    static let daysTop: CGFloat = 70
    static let dayRowHeight: CGFloat = 20
    static let notesTop: CGFloat = 198
    static let notesBottomInset: CGFloat = 16

    // MARK: Layout

    public let year: Int
    public let titleAnchor: CGPoint
    public let title: CGRect
    /// The area of the 12 small months.
    public let gridFrame: CGRect
    public let slotSize: CGSize
    /// January first, row by row.
    public let months: [MiniMonth]

    public init(year: Int, firstWeekday: Weekday = .defaultFirst) {
        self.year = year
        let margin = Self.margin
        titleAnchor = CGPoint(x: margin, y: Self.titleBaseline)
        title = CGRect(x: margin, y: Self.titleBaseline - 42, width: 400, height: 54)

        let gridFrame = CGRect(
            x: margin, y: Self.gridTop,
            width: PageCanvas.size.width - 2 * margin, height: Self.gridBottom - Self.gridTop
        )
        self.gridFrame = gridFrame
        let slotSize = CGSize(
            width: gridFrame.width / CGFloat(Self.columns),
            height: gridFrame.height / CGFloat(Self.rows)
        )
        self.slotSize = slotSize

        months = (1...12).map { number in
            let index = number - 1
            let slot = CGRect(
                x: gridFrame.minX + slotSize.width * CGFloat(index % Self.columns),
                y: gridFrame.minY + slotSize.height * CGFloat(index / Self.columns),
                width: slotSize.width, height: slotSize.height
            )
            return Self.miniMonth(
                MonthGrid(month: YearMonth(year: year, month: number), firstWeekday: firstWeekday),
                in: slot
            )
        }
    }

    private static func miniMonth(_ grid: MonthGrid, in slot: CGRect) -> MiniMonth {
        let content = slot.insetBy(dx: slotInset, dy: 0)
        let columnWidth = content.width / 7
        func columnEdge(_ index: Int) -> CGFloat { content.minX + columnWidth * CGFloat(index) }

        let weekdays = grid.columns.enumerated().map { index, weekday in
            MonthPageLayout.Column(weekday: weekday, frame: CGRect(
                x: columnEdge(index), y: slot.minY + weekdayCenter - dayRowHeight / 2,
                width: columnEdge(index + 1) - columnEdge(index), height: dayRowHeight
            ))
        }
        let weeks = grid.weeks.enumerated().map { row, days in
            days.enumerated().map { column, day in
                MonthPageLayout.Cell(day: day, frame: CGRect(
                    x: columnEdge(column), y: slot.minY + daysTop + dayRowHeight * CGFloat(row),
                    width: columnEdge(column + 1) - columnEdge(column), height: dayRowHeight
                ))
            }
        }
        let daysBottom = slot.minY + daysTop + dayRowHeight * 6
        let titleTop = slot.minY + 10
        return MiniMonth(
            grid: grid,
            slot: slot,
            block: CGRect(x: content.minX, y: titleTop, width: content.width, height: daysBottom - titleTop),
            title: CGRect(x: content.minX, y: titleTop, width: content.width, height: 36),
            titleAnchor: CGPoint(x: content.minX, y: slot.minY + miniTitleBaseline),
            weekdays: weekdays,
            weeks: weeks,
            notes: CGRect(
                x: content.minX, y: slot.minY + notesTop,
                width: content.width, height: slot.height - notesTop - notesBottomInset
            )
        )
    }

    public func miniMonth(_ month: Int) -> MiniMonth {
        months[month - 1]
    }

    /// Every named area of the page.
    public var regions: [PageRegion] {
        var regions = [PageRegion(.title, title)]
        for mini in months {
            regions.append(PageRegion(.month(mini.month), mini.block))
            regions.append(PageRegion(.monthTitle(mini.month), mini.title))
            regions.append(PageRegion(.monthNotes(mini.month), mini.notes))
            regions += mini.weeks.joined()
                .filter(\.day.isInMonth)
                .map { PageRegion(.day($0.day.date), $0.frame) }
        }
        return regions
    }
}
