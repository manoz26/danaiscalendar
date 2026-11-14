import CoreGraphics
import Foundation

/// Labels printed on the month page, in the app's language (from the String Catalog).
/// Any case; they are printed in capitals.
public struct MonthPageLabels: Sendable, Equatable {
    public var goals: String
    public var todo: String
    public var memo: String
    public var weekly: String

    public init(goals: String, todo: String, memo: String, weekly: String) {
        self.goals = goals
        self.todo = todo
        self.memo = memo
        self.weekly = weekly
    }

    public static let english = MonthPageLabels(goals: "Goals", todo: "To do list", memo: "Memo", weekly: "Weekly")
}

/// Line widths of the printed pages, in canvas units.
enum Stroke {
    static let hairline: CGFloat = 0.8
    static let strong: CGFloat = 1.5
    static let listTop: CGFloat = 1.1
    static let mark: CGFloat = 0.9
    /// Grid paper: thinner than the rules, or the page turns grey.
    static let grid: CGFloat = 0.55
}

/// Letter-spacing of small capitalised labels.
enum Tracking {
    static let label: CGFloat = 1.6
    static let weekday: CGFloat = 1.2
    static let year: CGFloat = 2
}

public enum MonthPageTemplate {
    /// The printed month page. `today` gets a discreet black mark when it is a day of this
    /// month. Each of `birthdays` (see `Birthday.notes`) puts a small gift in its day's cell
    /// and a line in the notes, printed under the ink like everything else. Days in
    /// `journalDays` (a journal page) get a small dot under their number, days in
    /// `sketchDays` (pinned sketches) a small sketch mark in their corner that opens them.
    /// `todos` are the typed to-dos (see `TypedLists.printed`), on the lines of the to-do
    /// list, with a + to add more.
    public static func make(
        month: YearMonth,
        firstWeekday: Weekday = .defaultFirst,
        locale: Locale,
        labels: MonthPageLabels,
        today: PlannerDate? = nil,
        birthdays: [BirthdayNote] = [],
        journalDays: Set<PlannerDate> = [],
        sketchDays: Set<PlannerDate> = [],
        todos: [PrintedItem] = [],
        todoOverflow: Int = 0
    ) -> PageTemplate {
        let layout = MonthPageLayout(month: month, firstWeekday: firstWeekday)
        let caps = { (text: String) in PlannerText.uppercased(text, locale: locale) }
        var shapes: [TemplateShape] = []
        var controls: [PageRegion] = []

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

        // Day numbers, and a small gift on days of this month with a birthday.
        let birthdayDates = Set(birthdays.map(\.date))
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
            if day.isInMonth, birthdayDates.contains(day.date) {
                shapes += GiftMark.shapes(
                    center: CGPoint(x: cell.frame.maxX - MonthPageLayout.dayNumberOffset.x + 3, y: center.y),
                    size: 14, tone: .text
                )
            }
            if day.isInMonth, journalDays.contains(day.date) {
                shapes.append(.circle(
                    center: CGPoint(x: center.x, y: cell.frame.minY + MonthPageLayout.journalDotY),
                    radius: 2.6, fill: .text, stroke: nil, lineWidth: 0
                ))
            }
            if day.isInMonth, sketchDays.contains(day.date) {
                let mark = CGPoint(x: cell.frame.maxX - 16, y: cell.frame.maxY - 14)
                shapes += SketchMark.shapes(center: mark, size: 15, tone: .text)
                controls.append(PageRegion(
                    .sketchMark(day.date),
                    CGRect(x: mark.x - 17, y: mark.y - 17, width: 34, height: 34).intersection(cell.frame)
                ))
            }
        }

        // TO DO LIST (circles) and MEMO (plain lines across the rest of the width).
        shapes += list(layout.todo, label: caps(labels.todo), marker: .circle)
        shapes += list(layout.memo, label: caps(labels.memo), marker: nil)
        shapes += birthdayLines(birthdays.filter { $0.date.yearMonth == month }, in: layout.memo)

        // Typed to-dos on their lines, and the + that adds one (right end of the label row).
        let typed = TypedItemPrinter.shapes(todos, overflow: todoOverflow, rows: layout.todo.rows, section: .todo)
        shapes += typed.shapes
        controls += typed.controls
        let add = addButtonRect(rightEdge: layout.todo.frame.maxX, labelBaseline: layout.todo.labelAnchor.y)
        shapes += TypedItemPrinter.addButton(add)
        controls.append(PageRegion(.addItem(.todo), add.insetBy(dx: -10, dy: -10)))

        return PageTemplate(shapes: shapes, regions: layout.regions, controls: controls)
    }

    /// The + of a list: 20 units square, on the middle of the label's capitals, flush right.
    static func addButtonRect(rightEdge: CGFloat, labelBaseline: CGFloat) -> CGRect {
        let middle = labelBaseline - MonthPageLayout.labelSize * PlannerFont.capHeight / 2
        return CGRect(x: rightEdge - 20, y: middle - 10, width: 20, height: 20)
    }

    enum Marker { case circle, box }

    /// Size of the printed birthday lines in the notes.
    public static let birthdaySize: CGFloat = 12.5

    /// One birthday per line of the notes, from the top: a small gift, the day, the text.
    /// When there are more than lines, each line holds two; beyond that the last place
    /// says "+N".
    static func birthdayLines(_ notes: [BirthdayNote], in memo: MonthPageLayout.ListSection) -> [TemplateShape] {
        guard !notes.isEmpty else { return [] }
        let (slots, shownCount) = birthdaySlots(count: notes.count, in: memo)
        let shown = notes.prefix(shownCount)
        let more = notes.count - shownCount

        let size = birthdaySize
        var shapes: [TemplateShape] = []
        for (note, slot) in zip(shown, slots) {
            let baseline = TemplateText.baseline(centeredOn: slot.midY, size: size)
            shapes += GiftMark.shapes(center: CGPoint(x: slot.minX + 9, y: slot.midY), size: 11, tone: .text)
            shapes.append(.text(TemplateText(
                String(note.date.day), font: .semibold, size: size, tone: .text,
                anchor: CGPoint(x: slot.minX + 24, y: baseline)
            )))
            // Inter at this size is under 7 units per letter on average.
            let room = max(4, Int((slot.width - 56) / 7))
            shapes.append(.text(TemplateText(
                Birthday.shortened(note.text, to: room), font: .medium, size: size, tone: .text,
                anchor: CGPoint(x: slot.minX + 48, y: baseline)
            )))
        }
        if more > 0, let slot = slots.last {
            shapes.append(.text(TemplateText(
                "+\(more)", font: .semibold, size: size, tone: .label,
                anchor: CGPoint(x: slot.minX + 24, y: TemplateText.baseline(centeredOn: slot.midY, size: size))
            )))
        }
        return shapes
    }

    /// Where the printed birthdays go in the notes, in order, and how many are printed: when
    /// they don't all fit two per line, the last place holds "+N" instead.
    public static func birthdaySlots(count: Int, in memo: MonthPageLayout.ListSection) -> (slots: [CGRect], shown: Int) {
        let rows = memo.rows
        let columns = count > rows.count ? 2 : 1
        let slots: [CGRect] = (0..<columns).flatMap { column in
            rows.map { row in
                let width = row.width / CGFloat(columns)
                return CGRect(x: row.minX + width * CGFloat(column), y: row.minY, width: width, height: row.height)
            }
        }
        let shown = count > slots.count ? slots.count - 1 : count
        return (slots, shown)
    }

    static func list(_ section: MonthPageLayout.ListSection, label text: String, marker: Marker?) -> [TemplateShape] {
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
            shapes += markerShapes(marker, in: row)
        }
        return shapes
    }

    static func markerShapes(_ marker: Marker?, in row: CGRect) -> [TemplateShape] {
        switch marker {
        case .circle:
            [.circle(center: CGPoint(x: row.minX + 9, y: row.midY), radius: 4.5, fill: nil, stroke: .label, lineWidth: Stroke.mark)]
        case .box:
            [.rect(CGRect(x: row.minX + 4.5, y: row.midY - 4.5, width: 9, height: 9), fill: nil, stroke: .label, lineWidth: Stroke.mark, cornerRadius: 1.5)]
        case nil:
            []
        }
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

public enum ToBuyPageTemplate {
    /// The printed shopping list page: its title, a + that adds a typed item, and two
    /// columns of lines with boxes. `items` are the typed things to buy on their lines
    /// (see `TypedLists.printed`).
    public static func make(locale: Locale, title: String, items: [PrintedItem] = [], overflow: Int = 0) -> PageTemplate {
        let layout = ToBuyPageLayout()
        var shapes: [TemplateShape] = [.text(TemplateText(
            PlannerText.uppercased(title, locale: locale), font: .bold, size: ToBuyPageLayout.titleSize,
            tone: .ink, anchor: layout.titleAnchor
        ))]
        for column in layout.columns {
            shapes.append(.line(
                from: CGPoint(x: column.minX, y: column.minY), to: CGPoint(x: column.maxX, y: column.minY),
                width: Stroke.listTop, tone: .border
            ))
        }
        for row in layout.rows {
            shapes.append(.line(
                from: CGPoint(x: row.minX, y: row.maxY), to: CGPoint(x: row.maxX, y: row.maxY),
                width: Stroke.hairline, tone: .rule
            ))
            shapes += MonthPageTemplate.markerShapes(.box, in: row)
        }

        let typed = TypedItemPrinter.shapes(items, overflow: overflow, rows: layout.rows, section: .tobuy)
        shapes += typed.shapes
        // The + sits on the middle of the title's capitals, flush right, like the WEEKLY buttons.
        let middle = layout.titleAnchor.y - ToBuyPageLayout.titleSize * PlannerFont.capHeight / 2
        let add = CGRect(x: layout.frame.maxX - 26, y: middle - 13, width: 26, height: 26)
        shapes += TypedItemPrinter.addButton(add)
        let controls = typed.controls + [PageRegion(.addItem(.tobuy), add.insetBy(dx: -9, dy: -9))]
        return PageTemplate(shapes: shapes, regions: layout.regions, controls: controls)
    }
}

/// A small gift drawn with lines (box, lid, ribbon and bow): the birthday mark of the
/// month page, like the gift button that opens the birthdays.
public enum GiftMark {
    /// The gift centred on `center`, about `size` units wide and tall.
    public static func shapes(center c: CGPoint, size s: CGFloat, tone: Tone) -> [TemplateShape] {
        let width = max(0.8, s * 0.075)
        return [
            // Lid, then the box under it.
            .rect(CGRect(x: c.x - s / 2, y: c.y - s * 0.28, width: s, height: s * 0.22), fill: nil, stroke: tone, lineWidth: width, cornerRadius: 0),
            .rect(CGRect(x: c.x - s * 0.41, y: c.y - s * 0.06, width: s * 0.82, height: s * 0.5), fill: nil, stroke: tone, lineWidth: width, cornerRadius: 0),
            // Ribbon down the middle, and the bow on top.
            .line(from: CGPoint(x: c.x, y: c.y - s * 0.28), to: CGPoint(x: c.x, y: c.y + s * 0.44), width: width, tone: tone),
            .circle(center: CGPoint(x: c.x - s * 0.14, y: c.y - s * 0.4), radius: s * 0.12, fill: nil, stroke: tone, lineWidth: width),
            .circle(center: CGPoint(x: c.x + s * 0.14, y: c.y - s * 0.4), radius: s * 0.12, fill: nil, stroke: tone, lineWidth: width),
        ]
    }
}
