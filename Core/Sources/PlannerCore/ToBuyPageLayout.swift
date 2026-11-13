import CoreGraphics
import Foundation

/// Where everything sits on the shopping list page, in canvas units (1000 x 1400): the
/// title ("TO BUY"), and two columns of ruled lines with a small box at the start of each,
/// for writing by hand and ticking. One page for everything to buy, not tied to a month.
public struct ToBuyPageLayout: Sendable {
    // MARK: Metrics

    public static let margin: CGFloat = 50
    public static let titleSize: CGFloat = MonthPageLayout.titleSize
    static let titleBaseline: CGFloat = 102
    static let listTop: CGFloat = 150
    public static let rowHeight: CGFloat = 33
    public static let rowsPerColumn = 36
    public static let columnCount = 2
    static let columnGutter: CGFloat = 40

    // MARK: Layout

    public let titleAnchor: CGPoint
    public let title: CGRect
    /// Both columns of lines.
    public let frame: CGRect
    /// Each column of lines, left to right.
    public let columns: [CGRect]
    /// Every line: down the left column, then down the right one.
    public let rows: [CGRect]

    public init() {
        let margin = Self.margin
        titleAnchor = CGPoint(x: margin, y: Self.titleBaseline)
        title = CGRect(x: margin, y: Self.titleBaseline - 42, width: 560, height: 54)

        let contentWidth = PageCanvas.size.width - 2 * margin
        let count = CGFloat(Self.columnCount)
        let columnWidth = (contentWidth - Self.columnGutter * (count - 1)) / count
        let height = Self.rowHeight * CGFloat(Self.rowsPerColumn)
        columns = (0..<Self.columnCount).map { index in
            CGRect(
                x: margin + (columnWidth + Self.columnGutter) * CGFloat(index), y: Self.listTop,
                width: columnWidth, height: height
            )
        }
        rows = columns.flatMap { column in
            (0..<Self.rowsPerColumn).map { index in
                CGRect(x: column.minX, y: column.minY + Self.rowHeight * CGFloat(index), width: column.width, height: Self.rowHeight)
            }
        }
        frame = CGRect(x: margin, y: Self.listTop, width: contentWidth, height: height)
    }

    /// Every named area of the page.
    public var regions: [PageRegion] {
        var regions = [PageRegion(.title, title), PageRegion(.section(.tobuy), frame)]
        regions += rows.enumerated().map { PageRegion(.toBuyLine($0.offset + 1), $0.element) }
        return regions
    }
}
