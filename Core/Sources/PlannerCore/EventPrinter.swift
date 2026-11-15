import CoreGraphics
import Foundation

/// Events of the Apple Calendar printed on the pages, under the ink like the rest of the
/// template, in greys only:
/// - in a day cell of the month page, small lines under the day's number: long events
///   (all-day, or 24 hours or more) as thin grey bars that join from day to day, then timed
///   ones as "9:30 Dentist"; "+N" on the last line when they don't all fit;
/// - in a day box of the week page, one per line from the top: bars, then "9:30 – 10:30 Dentist";
/// - on the year page, a dot under each day with an event (see `YearPageTemplate`).
public enum EventPrinter {
    // MARK: Month page metrics

    /// Top of the first event line, from the top of the cell (under the number and the
    /// journal dot).
    public static let monthTop: CGFloat = 47
    public static let monthLineHeight: CGFloat = 13.5
    public static let monthTextSize: CGFloat = 9.5
    static let monthInset: CGFloat = 5
    static let monthBarHeight: CGFloat = 11
    static let monthBarTextSize: CGFloat = 8.5
    static let monthBottomPadding: CGFloat = 3
    /// Room kept on the right of the lowest lines for the sketch mark.
    static let sketchMarkRoom: CGFloat = 27

    // MARK: Week page metrics

    public static let weekTextSize: CGFloat = 12
    static let weekBarHeight: CGFloat = 19
    static let weekBarTextSize: CGFloat = 11.5

    /// Event lines in a cell of the month page (6 with 5 weeks, 4 with 6 weeks).
    public static func monthLineCount(cellHeight: CGFloat) -> Int {
        max(1, Int((cellHeight - monthTop - monthBottomPadding) / monthLineHeight))
    }

    /// Line `index` (from 0) of a cell of the month page.
    public static func monthLine(_ index: Int, in cell: CGRect) -> CGRect {
        CGRect(
            x: cell.minX, y: cell.minY + monthTop + monthLineHeight * CGFloat(index),
            width: cell.width, height: monthLineHeight
        )
    }

    /// What one cell shows: bars in lanes up to `lanes`, the first `timed` timed events, and
    /// "+`hidden`" on line `plusLine` when they don't all fit.
    struct CellPlan {
        var lanes: Int
        var timed: Int
        var hidden: Int
        var plusLine: Int?

        init(_ day: DayEvents, lineCount: Int) {
            if day.laneCount + day.timed.count <= lineCount {
                lanes = day.laneCount
                timed = day.timed.count
                hidden = 0
                plusLine = nil
            } else {
                let room = lineCount - 1
                lanes = min(day.laneCount, room)
                timed = max(0, room - day.laneCount)
                let shownBars = day.bars.filter { $0.lane < room }.count
                hidden = day.count - shownBars - timed
                plusLine = room
            }
        }
    }

    /// The events of one row of the month grid. `cells` are the row's days of this month,
    /// in order, with their frames; `sketchDays` have the sketch mark in their corner.
    static func monthRow(
        _ cells: [(date: PlannerDate, frame: CGRect)], events: [PlannerDate: DayEvents],
        clock: EventClock, sketchDays: Set<PlannerDate>
    ) -> [TemplateShape] {
        var bars: [TemplateShape] = []
        var texts: [TemplateShape] = []
        let plans = cells.map { cell in
            CellPlan(events[cell.date] ?? DayEvents(), lineCount: monthLineCount(cellHeight: cell.frame.height))
        }

        for (position, cell) in cells.enumerated() {
            guard let day = events[cell.date], !day.isEmpty else { continue }
            let plan = plans[position]
            let frame = cell.frame

            for bar in day.bars where bar.lane < plan.lanes {
                let line = monthLine(bar.lane, in: frame)
                let left = bar.continuesBefore ? frame.minX : frame.minX + monthInset
                let right = bar.continuesAfter ? frame.maxX : frame.maxX - monthInset
                bars.append(.rect(
                    CGRect(x: left, y: line.midY - monthBarHeight / 2, width: right - left, height: monthBarHeight),
                    fill: .button, stroke: nil, lineWidth: 0,
                    cornerRadius: bar.continuesBefore || bar.continuesAfter ? 0 : 2.5
                ))
                guard bar.showsTitle else { continue }
                // The title runs along the bar over the next days of the row, while it shows there.
                var end = right
                var next = position + 1
                while next < cells.count, next - position < bar.daysInRow, plans[next].lanes > bar.lane {
                    let there = events[cells[next].date]?.bars.first { $0.event.id == bar.event.id }
                    end = there?.continuesAfter == true ? cells[next].frame.maxX : cells[next].frame.maxX - monthInset
                    next += 1
                }
                let x = left + 4
                let title = TemplateText(
                    bar.event.trimmedTitle, font: .semibold, size: monthBarTextSize, tone: .text,
                    anchor: CGPoint(x: x, y: TemplateText.baseline(centeredOn: line.midY, size: monthBarTextSize))
                )
                if let fitted = fitted(title, maxWidth: end - x - 3) {
                    texts.append(.text(fitted))
                }
            }

            for (index, event) in day.timed.prefix(plan.timed).enumerated() {
                let line = monthLine(day.laneCount + index, in: frame)
                let x = frame.minX + monthInset
                let narrow = sketchDays.contains(cell.date) && line.maxY > frame.maxY - sketchMarkRoom
                let limit = frame.maxX - monthInset - (narrow ? sketchMarkRoom - monthInset : 0)
                let baseline = TemplateText.baseline(centeredOn: line.midY, size: monthTextSize)
                let time = TemplateText(
                    clock.time(event.start), font: .semibold, size: monthTextSize, tone: .label,
                    anchor: CGPoint(x: x, y: baseline)
                )
                guard let shownTime = fitted(time, maxWidth: limit - x) else { continue }
                texts.append(.text(shownTime))
                let titleX = x + TemplateRenderer.width(of: shownTime) + 3
                let title = TemplateText(
                    event.trimmedTitle, font: .medium, size: monthTextSize, tone: .text,
                    anchor: CGPoint(x: titleX, y: baseline)
                )
                if let fitted = fitted(title, maxWidth: limit - titleX) {
                    texts.append(.text(fitted))
                }
            }

            if let plusLine = plan.plusLine, plan.hidden > 0 {
                let line = monthLine(plusLine, in: frame)
                texts.append(.text(TemplateText(
                    "+\(plan.hidden)", font: .semibold, size: monthTextSize, tone: .label,
                    anchor: CGPoint(x: frame.minX + monthInset, y: TemplateText.baseline(centeredOn: line.midY, size: monthTextSize))
                )))
            }
        }
        return bars + texts
    }

    /// The events of one day box of the week page, one per line from the top: bars, then
    /// timed events with their start and end. "+N" on the last line when they don't all fit.
    static func weekBox(_ day: DayEvents, box: WeekPageLayout.Box, clock: EventClock) -> [TemplateShape] {
        guard !day.isEmpty else { return [] }
        var bars: [TemplateShape] = []
        var texts: [TemplateShape] = []
        let lines = box.lines
        let all = day.all
        let shown = all.count <= lines.count ? all.count : lines.count - 1
        let barIDs = Set(day.bars.map(\.event.id))

        for (event, line) in zip(all.prefix(shown), lines) {
            let baseline = TemplateText.baseline(centeredOn: line.midY, size: weekTextSize)
            if barIDs.contains(event.id) {
                let rect = CGRect(x: line.minX + 2, y: line.midY - weekBarHeight / 2, width: line.width - 4, height: weekBarHeight)
                bars.append(.rect(rect, fill: .button, stroke: nil, lineWidth: 0, cornerRadius: 3))
                let title = TemplateText(
                    event.trimmedTitle, font: .semibold, size: weekBarTextSize, tone: .text,
                    anchor: CGPoint(x: rect.minX + 8, y: TemplateText.baseline(centeredOn: line.midY, size: weekBarTextSize))
                )
                if let fitted = fitted(title, maxWidth: rect.width - 16) {
                    texts.append(.text(fitted))
                }
            } else {
                let x = line.minX + 2
                let time = TemplateText(
                    clock.range(event.start, event.end), font: .medium, size: weekTextSize, tone: .label,
                    anchor: CGPoint(x: x, y: baseline)
                )
                texts.append(.text(time))
                let titleX = x + TemplateRenderer.width(of: time) + 8
                let title = TemplateText(
                    event.trimmedTitle, font: .medium, size: weekTextSize, tone: .text,
                    anchor: CGPoint(x: titleX, y: baseline)
                )
                if let fitted = fitted(title, maxWidth: line.maxX - 4 - titleX) {
                    texts.append(.text(fitted))
                }
            }
        }
        if shown < all.count, let line = lines.last {
            texts.append(.text(TemplateText(
                "+\(all.count - shown)", font: .semibold, size: weekTextSize, tone: .label,
                anchor: CGPoint(x: line.minX + 2, y: TemplateText.baseline(centeredOn: line.midY, size: weekTextSize))
            )))
        }
        return bars + texts
    }

    /// The text, cut with "…" when it is wider than `maxWidth`; `nil` when not even one
    /// letter fits.
    public static func fitted(_ text: TemplateText, maxWidth: CGFloat) -> TemplateText? {
        guard maxWidth > 2, !text.string.isEmpty else { return nil }
        let width = TemplateRenderer.width(of: text)
        if width <= maxWidth { return text }
        let characters = Array(text.string)
        // A first guess from the widths, then one letter less at a time.
        var keep = min(characters.count - 1, Int((CGFloat(characters.count) * maxWidth / width).rounded(.down)))
        var cut = text
        while keep > 0 {
            cut.string = String(characters.prefix(keep)).trimmingCharacters(in: .whitespaces) + "…"
            if TemplateRenderer.width(of: cut) <= maxWidth { return cut }
            keep -= 1
        }
        return nil
    }
}
