import CoreGraphics
import Foundation

/// Labels printed on the month page, in the app's language (from the String Catalog).
/// Any case; they are printed in capitals.
public struct MonthPageLabels: Sendable, Equatable {
    public var goals: String
    public var todo: String
    public var memo: String
    public var toBuy: String
    public var weekly: String

    public init(goals: String, todo: String, memo: String, toBuy: String, weekly: String) {
        self.goals = goals
        self.todo = todo
        self.memo = memo
        self.toBuy = toBuy
        self.weekly = weekly
    }

    public static let english = MonthPageLabels(
        goals: "Goals", todo: "To do list", memo: "Memo", toBuy: "To buy", weekly: "Weekly"
    )
}

/// Line widths of the printed pages, in canvas units.
enum Stroke {
    static let hairline: CGFloat = 0.8
    static let strong: CGFloat = 1.5
    static let listTop: CGFloat = 1.1
    static let mark: CGFloat = 0.9
}

/// Letter-spacing of small capitalised labels.
enum Tracking {
    static let label: CGFloat = 1.6
    static let weekday: CGFloat = 1.2
    static let year: CGFloat = 2
}

public enum MonthPageTemplate {
    /// The printed month page. `today` gets a discreet black mark when it is a day of this month.
    public static func make(
        month: YearMonth,
        firstWeekday: Weekday = .defaultFirst,
        locale: Locale,
        labels: MonthPageLabels,
        today: PlannerDate? = nil
    ) -> PageTemplate {
        let layout = MonthPageLayout(month: month, firstWeekday: firstWeekday)
        let caps = { (text: String) in PlannerText.uppercased(text, locale: locale) }
        var shapes: [TemplateShape] = []

        // Year and title.
        shapes.append(.text(TemplateText(
            String(month.year), font: .semibold, size: MonthPageLayout.yearSize,
            tracking: Tracking.year, tone: .label, anchor: layout.yearAnchor
        )))
        shapes.append(.text(TemplateText(
            MonthTitle.text(for: month, locale: locale), font: .bold, size: MonthPageLayout.titleSize,
            tone: .ink, anchor: layout.titleAnchor
        )))

        // WEEKLY 1…n.
        shapes.append(.text(TemplateText(
            caps(labels.weekly), font: .semibold, size: MonthPageLayout.labelSize,
            tracking: Tracking.label, tone: .label, anchor: layout.weeklyLabelAnchor, alignment: .right
        )))
        for (index, button) in layout.weeklyButtons.enumerated() {
            shapes.append(.rect(button, fill: .button, stroke: nil, lineWidth: 0, cornerRadius: 4))
            shapes.append(.text(TemplateText(
                String(index + 1), font: .medium, size: 12, tone: .label,
                anchor: CGPoint(x: button.midX, y: TemplateText.baseline(centeredOn: button.midY, size: 12)),
                alignment: .center
            )))
        }

        // GOALS.
        shapes.append(label(caps(labels.goals), at: layout.goalsLabelAnchor))
        shapes.append(.rect(layout.goals, fill: .fill, stroke: nil, lineWidth: 0, cornerRadius: 0))

        // Weekday headers.
        let names = CalendarNames.shortWeekdays(layout.grid.columns, locale: locale)
        for (column, name) in zip(layout.weekdays, names) {
            let size = MonthPageLayout.weekdaySize
            shapes.append(.text(TemplateText(
                name, font: .semibold, size: size, tracking: Tracking.weekday,
                tone: column.weekday == .sunday ? .secondary : .label,
                anchor: CGPoint(x: column.frame.midX + Tracking.weekday / 2,
                                y: TemplateText.baseline(centeredOn: column.frame.midY, size: size)),
                alignment: .center
            )))
        }

        // Day grid: thin inner rules, strong top and bottom.
        let grid = layout.gridFrame
        for row in 1..<layout.grid.weekCount {
            let y = grid.minY + layout.rowHeight * CGFloat(row)
            shapes.append(.line(from: CGPoint(x: grid.minX, y: y), to: CGPoint(x: grid.maxX, y: y), width: Stroke.hairline, tone: .rule))
        }
        for column in 1..<7 {
            let x = layout.weekdays[column].frame.minX
            shapes.append(.line(from: CGPoint(x: x, y: grid.minY), to: CGPoint(x: x, y: grid.maxY), width: Stroke.hairline, tone: .rule))
        }
        for y in [grid.minY, grid.maxY] {
            shapes.append(.line(from: CGPoint(x: grid.minX, y: y), to: CGPoint(x: grid.maxX, y: y), width: Stroke.strong, tone: .border))
        }

        // Day numbers.
        for cell in layout.weeks.joined() {
            let center = CGPoint(
                x: cell.frame.minX + MonthPageLayout.dayNumberOffset.x,
                y: cell.frame.minY + MonthPageLayout.dayNumberOffset.y
            )
            let day = cell.day
            let isToday = day.isInMonth && day.date == today
            if isToday {
                shapes.append(.circle(center: center, radius: 14, fill: .ink, stroke: nil, lineWidth: 0))
            }
            let tone: Tone = isToday ? .paper : !day.isInMonth ? .faint : day.date.weekday == .sunday ? .secondary : .text
            let size = MonthPageLayout.dayNumberSize
            shapes.append(.text(TemplateText(
                String(day.date.day), font: isToday ? .semibold : .medium, size: size, tone: tone,
                anchor: CGPoint(x: center.x, y: TemplateText.baseline(centeredOn: center.y, size: size)),
                alignment: .center
            )))
        }

        // TO DO LIST (circles) and TO BUY (boxes).
        shapes += list(layout.todo, label: caps(labels.todo), marker: .circle)
        shapes += list(layout.toBuy, label: caps(labels.toBuy), marker: .box)

        // MEMO: an open box.
        shapes.append(label(caps(labels.memo), at: layout.memoLabelAnchor))
        shapes.append(.rect(layout.memo, fill: nil, stroke: .rule, lineWidth: Stroke.hairline, cornerRadius: 0))
        shapes.append(.line(
            from: CGPoint(x: layout.memo.minX, y: layout.memo.minY),
            to: CGPoint(x: layout.memo.maxX, y: layout.memo.minY),
            width: Stroke.listTop, tone: .border
        ))

        return PageTemplate(shapes: shapes, regions: layout.regions)
    }

    private enum Marker { case circle, box }

    private static func list(_ section: MonthPageLayout.ListSection, label text: String, marker: Marker) -> [TemplateShape] {
        var shapes = [label(text, at: section.labelAnchor)]
        let frame = section.frame
        shapes.append(.line(
            from: CGPoint(x: frame.minX, y: frame.minY), to: CGPoint(x: frame.maxX, y: frame.minY),
            width: Stroke.listTop, tone: .border
        ))
        for row in section.rows {
            shapes.append(.line(
                from: CGPoint(x: row.minX, y: row.maxY), to: CGPoint(x: row.maxX, y: row.maxY),
                width: Stroke.hairline, tone: .rule
            ))
            switch marker {
            case .circle:
                shapes.append(.circle(center: CGPoint(x: row.minX + 9, y: row.midY), radius: 4.5, fill: nil, stroke: .label, lineWidth: Stroke.mark))
            case .box:
                shapes.append(.rect(CGRect(x: row.minX + 4.5, y: row.midY - 4.5, width: 9, height: 9), fill: nil, stroke: .label, lineWidth: Stroke.mark, cornerRadius: 1.5))
            }
        }
        return shapes
    }

    static func label(_ text: String, at anchor: CGPoint) -> TemplateShape {
        .text(TemplateText(
            text, font: .semibold, size: MonthPageLayout.labelSize,
            tracking: Tracking.label, tone: .label, anchor: anchor
        ))
    }
}

public enum YearPageTemplate {
    /// The printed year page. `today` gets a discreet black mark when it falls in this year.
    public static func make(
        year: Int,
        firstWeekday: Weekday = .defaultFirst,
        locale: Locale,
        today: PlannerDate? = nil
    ) -> PageTemplate {
        let layout = YearPageLayout(year: year, firstWeekday: firstWeekday)
        var shapes: [TemplateShape] = []

        shapes.append(.text(TemplateText(
            String(year), font: .bold, size: YearPageLayout.titleSize, tone: .ink, anchor: layout.titleAnchor
        )))

        // Separators: a strong rule under the title, thin rules between rows and columns.
        let grid = layout.gridFrame
        for row in 0..<YearPageLayout.rows {
            let y = grid.minY + layout.slotSize.height * CGFloat(row)
            shapes.append(.line(
                from: CGPoint(x: grid.minX, y: y), to: CGPoint(x: grid.maxX, y: y),
                width: row == 0 ? Stroke.strong : Stroke.hairline, tone: row == 0 ? .border : .rule
            ))
        }
        for column in 1..<YearPageLayout.columns {
            let x = grid.minX + layout.slotSize.width * CGFloat(column)
            shapes.append(.line(from: CGPoint(x: x, y: grid.minY), to: CGPoint(x: x, y: grid.maxY), width: Stroke.hairline, tone: .rule))
        }

        let firstColumns = layout.months.first?.grid.columns ?? Weekday.week(startingOn: firstWeekday)
        let names = CalendarNames.narrowWeekdays(firstColumns, locale: locale)
        for mini in layout.months {
            shapes.append(.text(TemplateText(
                MonthTitle.numbered(for: mini.month, locale: locale), font: .bold,
                size: YearPageLayout.miniTitleSize, tone: .ink, anchor: mini.titleAnchor
            )))
            for (column, name) in zip(mini.weekdays, names) {
                let size = YearPageLayout.weekdaySize
                shapes.append(.text(TemplateText(
                    name, font: .semibold, size: size,
                    tone: column.weekday == .sunday ? .secondary : .label,
                    anchor: CGPoint(x: column.frame.midX, y: TemplateText.baseline(centeredOn: column.frame.midY, size: size)),
                    alignment: .center
                )))
            }
            for cell in mini.weeks.joined() where cell.day.isInMonth {
                let date = cell.day.date
                let center = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
                let isToday = date == today
                if isToday {
                    shapes.append(.circle(center: center, radius: 9.5, fill: .ink, stroke: nil, lineWidth: 0))
                }
                let size = YearPageLayout.dayNumberSize
                shapes.append(.text(TemplateText(
                    String(date.day), font: isToday ? .semibold : .medium, size: size,
                    tone: isToday ? .paper : date.weekday == .sunday ? .secondary : .text,
                    anchor: CGPoint(x: center.x, y: TemplateText.baseline(centeredOn: center.y, size: size)),
                    alignment: .center
                )))
            }
            shapes.append(.rect(mini.notes, fill: .fill, stroke: nil, lineWidth: 0, cornerRadius: 0))
        }

        return PageTemplate(shapes: shapes, regions: layout.regions)
    }
}
