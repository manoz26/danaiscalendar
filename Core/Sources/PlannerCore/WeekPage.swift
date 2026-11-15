import CoreGraphics
import Foundation

/// Where everything sits on a week page, in canvas units (1000 x 1400).
///
/// At the top, like the month page: the year small, the days of the week big
/// ("9 – 15 NOVEMBER") and the week's number on the right. Under them 8 boxes in 2
/// columns of 4: the seven days down the left column and on down the right one, and NOTES
/// last (bottom right). Each box has a header (the day's number and name, or NOTES) over
/// a strong rule, and faint ruled lines to write on, with the same step as the lists of
/// the month page. (Layout `week-v1`.)
public struct WeekPageLayout: Sendable {
    /// A day, or the notes.
    public struct Box: Sendable, Equatable {
        /// The day, or `nil` for the notes.
        public let date: PlannerDate?
        /// The whole box, header and lines: the region its ink belongs to.
        public let frame: CGRect
        /// The header above the rule: the day's number and name, or NOTES.
        public let header: CGRect
        /// The lines to write on, under the rule.
        public let lines: [CGRect]

        /// The strong rule between the header and the lines.
        public var ruleY: CGFloat { header.maxY }
        /// Height on which the header's texts and marks are centred.
        public var headerMiddle: CGFloat { header.maxY - WeekPageLayout.headerTextLift }
    }

    // MARK: Metrics

    public static let margin: CGFloat = 50
    public static let contentWidth: CGFloat = PageCanvas.size.width - 2 * margin
    public static let yearSize: CGFloat = MonthPageLayout.yearSize
    public static let titleSize: CGFloat = MonthPageLayout.titleSize
    public static let labelSize: CGFloat = MonthPageLayout.labelSize
    public static let dayNumberSize: CGFloat = 17
    public static let dayNameSize: CGFloat = 11
    static let yearBaseline: CGFloat = 58
    static let titleBaseline: CGFloat = 102
    /// The rule under the header of the boxes of the top row.
    static let firstRule: CGFloat = 162
    /// From one row of boxes to the next.
    static let rowStride: CGFloat = 310
    static let headerHeight: CGFloat = 34
    /// Height of the header's middle above the rule.
    static let headerTextLift: CGFloat = 16
    public static let lineHeight: CGFloat = 33
    public static let lineCount = 8
    static let columnGutter: CGFloat = 24
    public static let rows = 4
    public static let columns = 2
    /// Centre of the day number from the left edge of its box (today's circle starts at the edge).
    public static let dayNumberCenterX: CGFloat = 14
    /// Where the day's name starts, from the left edge of its box.
    public static let dayNameX: CGFloat = 36

    // MARK: Layout

    public let week: PlannerWeek
    public let yearAnchor: CGPoint
    public let titleAnchor: CGPoint
    public let title: CGRect
    /// Right end of the baseline of the week's number ("WEEK 46").
    public let weekNumberAnchor: CGPoint
    /// The seven days, in order.
    public let days: [Box]
    public let notes: Box

    /// The days, then the notes.
    public var boxes: [Box] { days + [notes] }

    public init(week: PlannerWeek) {
        self.week = week
        let margin = Self.margin
        yearAnchor = CGPoint(x: margin, y: Self.yearBaseline)
        titleAnchor = CGPoint(x: margin, y: Self.titleBaseline)
        title = CGRect(x: margin, y: Self.titleBaseline - 42, width: Self.contentWidth, height: 54)
        let titleMiddle = Self.titleBaseline - Self.titleSize * PlannerFont.capHeight / 2
        weekNumberAnchor = CGPoint(
            x: PageCanvas.size.width - margin,
            y: TemplateText.baseline(centeredOn: titleMiddle, size: Self.labelSize)
        )

        let columnWidth = (Self.contentWidth - Self.columnGutter * CGFloat(Self.columns - 1)) / CGFloat(Self.columns)
        func box(_ index: Int, date: PlannerDate?) -> Box {
            // Down the left column, then down the right one.
            let column = index / Self.rows, row = index % Self.rows
            let x = margin + (columnWidth + Self.columnGutter) * CGFloat(column)
            let rule = Self.firstRule + Self.rowStride * CGFloat(row)
            let header = CGRect(x: x, y: rule - Self.headerHeight, width: columnWidth, height: Self.headerHeight)
            let lines = (0..<Self.lineCount).map { line in
                CGRect(x: x, y: rule + Self.lineHeight * CGFloat(line), width: columnWidth, height: Self.lineHeight)
            }
            let frame = CGRect(
                x: x, y: header.minY, width: columnWidth,
                height: Self.headerHeight + Self.lineHeight * CGFloat(Self.lineCount)
            )
            return Box(date: date, frame: frame, header: header, lines: lines)
        }
        days = week.days.enumerated().map { box($0.offset, date: $0.element) }
        notes = box(7, date: nil)
    }

    /// The box of a day of this week.
    public func box(for date: PlannerDate) -> Box? {
        days.first { $0.date == date }
    }

    /// Every named area of the page.
    public var regions: [PageRegion] {
        var regions = [PageRegion(.title, title)]
        regions += days.compactMap { box in box.date.map { PageRegion(.weekDay($0), box.frame) } }
        regions.append(PageRegion(.section(.weekNotes), notes.frame))
        return regions
    }
}

/// Labels printed on the week page, in the app's language (from the String Catalog).
/// Any case; they are printed in capitals.
public struct WeekPageLabels: Sendable, Equatable {
    /// Before the week's number: "WEEK 46".
    public var week: String
    /// The eighth box.
    public var notes: String

    public init(week: String, notes: String) {
        self.week = week
        self.notes = notes
    }

    public static let english = WeekPageLabels(week: "Week", notes: "Notes")
}

public enum WeekPageTemplate {
    /// The printed week page. Days outside `month` (the month she came from) are grey, as
    /// on the month page; `today` gets the black mark of the month page. Days in
    /// `journalDays` get a small dot after their name, days in `birthdayDays` a small gift
    /// at the right end of their header. A finger on a day's header opens its journal page
    /// (control `day-page:<day>`).
    public static func make(
        week: PlannerWeek,
        locale: Locale,
        labels: WeekPageLabels,
        month: YearMonth? = nil,
        today: PlannerDate? = nil,
        journalDays: Set<PlannerDate> = [],
        birthdayDays: Set<PlannerDate> = []
    ) -> PageTemplate {
        let layout = WeekPageLayout(week: week)
        let caps = { (text: String) in PlannerText.uppercased(text, locale: locale) }
        var shapes: [TemplateShape] = []
        var controls: [PageRegion] = []

        // Year(s), the week's number on the right, and the days as the title.
        shapes.append(.text(TemplateText(
            WeekTitle.years(of: week), font: .semibold, size: WeekPageLayout.yearSize,
            tracking: Tracking.year, tone: .label, anchor: layout.yearAnchor
        )))
        let number = TemplateText(
            caps("\(labels.week) \(week.number)"), font: .semibold, size: WeekPageLayout.labelSize,
            tracking: Tracking.label, tone: .label, anchor: layout.weekNumberAnchor, alignment: .right
        )
        shapes.append(.text(number))
        let title = TemplateText(
            WeekTitle.text(for: week, locale: locale), font: .bold, size: WeekPageLayout.titleSize,
            tone: .ink, anchor: layout.titleAnchor
        )
        let room = layout.title.width - TemplateRenderer.width(of: number) - 24
        shapes.append(.text(shrunk(title, toFit: room)))

        // The boxes: header, strong rule, faint lines.
        let names = CalendarNames.weekdays(week.days.map(\.weekday), locale: locale)
        for (box, name) in zip(layout.days, names) {
            guard let date = box.date else { continue }
            shapes += dayHeader(
                box, date: date, name: name,
                isToday: date == today,
                isOtherMonth: month.map { date.yearMonth != $0 } ?? false,
                hasJournalPage: journalDays.contains(date),
                hasBirthday: birthdayDays.contains(date)
            )
            shapes += lines(of: box)
            controls.append(PageRegion(.dayPage(date), box.header))
        }
        shapes.append(.text(TemplateText(
            caps(labels.notes), font: .semibold, size: WeekPageLayout.labelSize, tracking: Tracking.label,
            tone: .label, anchor: CGPoint(
                x: layout.notes.header.minX,
                y: TemplateText.baseline(centeredOn: layout.notes.headerMiddle, size: WeekPageLayout.labelSize)
            )
        )))
        shapes += lines(of: layout.notes)

        return PageTemplate(shapes: shapes, regions: layout.regions, controls: controls)
    }

    /// The day's number (white on a black circle for today) and its name, in the month
    /// page's tones: Sundays grey, days of another month faint.
    static func dayHeader(
        _ box: WeekPageLayout.Box, date: PlannerDate, name: String,
        isToday: Bool, isOtherMonth: Bool, hasJournalPage: Bool, hasBirthday: Bool
    ) -> [TemplateShape] {
        var shapes: [TemplateShape] = []
        let middle = box.headerMiddle
        let tone: Tone = isOtherMonth ? .faint : date.weekday == .sunday ? .secondary : .text
        let center = CGPoint(x: box.header.minX + WeekPageLayout.dayNumberCenterX, y: middle)
        if isToday {
            shapes.append(.circle(center: center, radius: 14, fill: .ink, stroke: nil, lineWidth: 0))
        }
        let size = WeekPageLayout.dayNumberSize
        shapes.append(.text(TemplateText(
            String(date.day), font: isToday ? .bold : .semibold, size: size, tone: isToday ? .paper : tone,
            anchor: CGPoint(x: center.x, y: TemplateText.baseline(centeredOn: middle, size: size)),
            alignment: .center
        )))
        let nameText = TemplateText(
            name, font: .semibold, size: WeekPageLayout.dayNameSize, tracking: Tracking.label,
            tone: isOtherMonth ? .faint : date.weekday == .sunday ? .secondary : .label,
            anchor: CGPoint(
                x: box.header.minX + WeekPageLayout.dayNameX,
                y: TemplateText.baseline(centeredOn: middle, size: WeekPageLayout.dayNameSize)
            )
        )
        shapes.append(.text(nameText))
        if hasJournalPage {
            let end = nameText.anchor.x + TemplateRenderer.width(of: nameText)
            shapes.append(.circle(center: CGPoint(x: end + 8, y: middle), radius: 2.6, fill: .text, stroke: nil, lineWidth: 0))
        }
        if hasBirthday {
            shapes += GiftMark.shapes(center: CGPoint(x: box.header.maxX - 10, y: middle), size: 14, tone: .text)
        }
        return shapes
    }

    /// The strong rule under the header and a faint rule under each line.
    static func lines(of box: WeekPageLayout.Box) -> [TemplateShape] {
        let frame = box.frame
        var shapes: [TemplateShape] = [.line(
            from: CGPoint(x: frame.minX, y: box.ruleY), to: CGPoint(x: frame.maxX, y: box.ruleY),
            width: Stroke.listTop, tone: .border
        )]
        for line in box.lines {
            shapes.append(.line(
                from: CGPoint(x: line.minX, y: line.maxY), to: CGPoint(x: line.maxX, y: line.maxY),
                width: Stroke.hairline, tone: .rule
            ))
        }
        return shapes
    }

    /// The text at a smaller size when it is wider than `maxWidth` (never below 22).
    static func shrunk(_ text: TemplateText, toFit maxWidth: CGFloat) -> TemplateText {
        var fitted = text
        while fitted.size > 22, TemplateRenderer.width(of: fitted) > maxWidth {
            fitted.size -= 1
        }
        return fitted
    }
}

extension CalendarNames {
    /// Full day names, as printed in the headers of the week page: "MONDAY", "ΔΕΥΤΕΡΑ".
    public static func weekdays(_ days: [Weekday], locale: Locale) -> [String] {
        let symbols = PlannerLocale.calendar(locale: locale).standaloneWeekdaySymbols
        return days.map { PlannerText.uppercased(symbols[$0.rawValue - 1], locale: locale) }
    }
}
