import CoreGraphics
import Foundation

/// Where everything sits on a journal page, in canvas units (1000 x 1400): a small label
/// and a big heading at the top (like the year and title of the month page), a rule under
/// them, and the paper (lines, grid or dots) below. The paper's area never moves, with or
/// without a title, so the ink always stays on the same lines.
public struct JournalPageLayout: Sendable {
    public static let margin: CGFloat = 50
    public static let labelSize: CGFloat = MonthPageLayout.yearSize
    public static let headingSize: CGFloat = MonthPageLayout.titleSize
    static let labelBaseline: CGFloat = 58
    static let headingBaseline: CGFloat = 102
    public static let paperTop: CGFloat = 132
    public static let paperBottom: CGFloat = 1332
    /// Lined paper: the same step as the lists of the month page.
    public static let lineSpacing: CGFloat = 33
    /// Grid and dotted paper.
    public static let gridSpacing: CGFloat = 25

    public let labelAnchor: CGPoint
    public let headingAnchor: CGPoint
    /// The label and heading.
    public let title: CGRect
    /// The paper, where she writes.
    public let paper: CGRect

    public init() {
        let margin = Self.margin
        let width = PageCanvas.size.width - 2 * margin
        labelAnchor = CGPoint(x: margin, y: Self.labelBaseline)
        headingAnchor = CGPoint(x: margin, y: Self.headingBaseline)
        title = CGRect(x: margin, y: 36, width: width, height: Self.paperTop - 36 - 4)
        paper = CGRect(x: margin, y: Self.paperTop, width: width, height: Self.paperBottom - Self.paperTop)
    }

    public var regions: [PageRegion] {
        [PageRegion(.title, title), PageRegion(.section(.body), paper)]
    }
}

/// The two texts at the top of a journal page.
public enum JournalHeading {
    /// - With a title: the full date small ("SATURDAY, NOVEMBER 14, 2026") and the title big.
    /// - Without one: the year small and the day big ("SATURDAY, NOVEMBER 14"), like a
    ///   month page.
    /// - Without a date: only the title, if any.
    public static func texts(title: String, date: PlannerDate?, locale: Locale) -> (label: String, heading: String) {
        let title = title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard let date else { return ("", title) }
        if title.isEmpty {
            return (String(date.year), PlannerText.uppercased(format(date, template: "EEEEdMMMM", locale: locale), locale: locale))
        }
        return (PlannerText.uppercased(format(date, template: "EEEEdMMMMy", locale: locale), locale: locale), title)
    }

    /// A day as words, e.g. "Saturday, November 14, 2026" / "Σάββατο 14 Νοεμβρίου 2026".
    public static func fullDate(_ date: PlannerDate, locale: Locale) -> String {
        format(date, template: "EEEEdMMMMy", locale: locale)
    }

    /// A short day, e.g. "Nov 14, 2026" / "14 Νοε 2026" (captions of the grids).
    public static func shortDate(_ date: PlannerDate, locale: Locale) -> String {
        format(date, template: "dMMMy", locale: locale)
    }

    static func format(_ date: PlannerDate, template: String, locale: Locale) -> String {
        let calendar = PlannerLocale.calendar(locale: locale)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        let components = DateComponents(year: date.year, month: date.month, day: date.day, hour: 12)
        guard let day = calendar.date(from: components) else { return date.description }
        return formatter.string(from: day)
    }
}

public enum JournalPageTemplate {
    /// A journal page: the heading texts (see `JournalHeading`), a rule, and the paper.
    public static func make(paper style: PaperStyle, label: String, heading: String) -> PageTemplate {
        let layout = JournalPageLayout()
        var shapes: [TemplateShape] = []
        if !label.isEmpty {
            shapes.append(.text(TemplateText(
                label, font: .semibold, size: JournalPageLayout.labelSize,
                tracking: Tracking.year, tone: .label, anchor: layout.labelAnchor
            )))
        }
        if !heading.isEmpty {
            let text = TemplateText(
                heading, font: .bold, size: JournalPageLayout.headingSize, tone: .ink, anchor: layout.headingAnchor
            )
            shapes.append(.text(TypedItemPrinter.fitted(text, maxWidth: layout.paper.width)))
        }

        let paper = layout.paper
        shapes.append(.line(
            from: CGPoint(x: paper.minX, y: paper.minY), to: CGPoint(x: paper.maxX, y: paper.minY),
            width: Stroke.listTop, tone: .border
        ))
        switch style {
        case .blank:
            break
        case .lined:
            let step = JournalPageLayout.lineSpacing
            var y = paper.minY + step
            while y <= paper.maxY + 0.5 {
                shapes.append(.line(from: CGPoint(x: paper.minX, y: y), to: CGPoint(x: paper.maxX, y: y), width: Stroke.hairline, tone: .rule))
                y += step
            }
        case .grid:
            let step = JournalPageLayout.gridSpacing
            let rows = Int(paper.height / step)
            let columns = Int(paper.width / step)
            let bottom = paper.minY + CGFloat(rows) * step
            for row in 1...rows {
                let y = paper.minY + CGFloat(row) * step
                shapes.append(.line(from: CGPoint(x: paper.minX, y: y), to: CGPoint(x: paper.maxX, y: y), width: Stroke.grid, tone: .rule))
            }
            for column in 0...columns {
                let x = paper.minX + CGFloat(column) * step
                shapes.append(.line(from: CGPoint(x: x, y: paper.minY), to: CGPoint(x: x, y: bottom), width: Stroke.grid, tone: .rule))
            }
        case .dotted:
            let step = JournalPageLayout.gridSpacing
            let rows = Int(paper.height / step)
            let columns = Int(paper.width / step)
            for row in 1...rows {
                for column in 0...columns {
                    let center = CGPoint(x: paper.minX + CGFloat(column) * step, y: paper.minY + CGFloat(row) * step)
                    shapes.append(.circle(center: center, radius: 1.15, fill: .secondary, stroke: nil, lineWidth: 0))
                }
            }
        }
        return PageTemplate(shapes: shapes, regions: layout.regions)
    }
}

public enum SketchPageTemplate {
    /// The writing area of a sketch, for the sample ink of the tests.
    public static let body = CGRect(x: 50, y: 50, width: 900, height: 1300)

    /// A sketch is a blank page: nothing is printed on it.
    public static func make() -> PageTemplate {
        PageTemplate(shapes: [], regions: [PageRegion(.section(.body), body)])
    }
}

/// The small mark of a day with pinned sketches (month page): a frame with a scribble.
public enum SketchMark {
    public static func shapes(center c: CGPoint, size s: CGFloat, tone: Tone) -> [TemplateShape] {
        let width = max(0.8, s * 0.07)
        let w = s, h = s * 0.8
        let points = [
            CGPoint(x: c.x - w * 0.3, y: c.y + h * 0.16),
            CGPoint(x: c.x - w * 0.1, y: c.y - h * 0.18),
            CGPoint(x: c.x + w * 0.1, y: c.y + h * 0.16),
            CGPoint(x: c.x + w * 0.3, y: c.y - h * 0.18),
        ]
        var shapes: [TemplateShape] = [
            .rect(CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), fill: nil, stroke: tone, lineWidth: width, cornerRadius: s * 0.12),
        ]
        for (from, to) in zip(points, points.dropFirst()) {
            shapes.append(.line(from: from, to: to, width: width, tone: tone))
        }
        return shapes
    }
}

/// Typed items printed on ruled lines (month to-dos, the To Buy page), the printed +
/// buttons, and fitting text into a width.
public enum TypedItemPrinter {
    public static let size: CGFloat = 12.5
    /// Where the text starts, from the left end of its line (after the circle or box).
    static let textOffset: CGFloat = 24
    /// Width of the tap area of a circle or box.
    static let markerTapWidth: CGFloat = 40

    /// The shapes and tap areas of typed items on `rows`, after the markers the page
    /// already prints. Done items get a tick and grey, struck-through text.
    static func shapes(
        _ items: [PrintedItem], overflow: Int, rows: [CGRect], section: RegionID.Section
    ) -> (shapes: [TemplateShape], controls: [PageRegion]) {
        var shapes: [TemplateShape] = []
        var controls: [PageRegion] = []
        for item in items where (1...rows.count).contains(item.line) {
            let row = rows[item.line - 1]
            let marker = CGPoint(x: row.minX + 9, y: row.midY)
            if item.done {
                shapes += tick(center: marker)
            }
            let baseline = TemplateText.baseline(centeredOn: row.midY, size: size)
            let isLast = item.line == rows.count
            let room = row.width - textOffset - 6 - (isLast && overflow > 0 ? 34 : 0)
            let text = fitted(TemplateText(
                item.text, font: .medium, size: size, tone: item.done ? .secondary : .text,
                anchor: CGPoint(x: row.minX + textOffset, y: baseline)
            ), maxWidth: room)
            shapes.append(.text(text))
            if item.done {
                let width = TemplateRenderer.width(of: text)
                let y = baseline - size * 0.29
                shapes.append(.line(
                    from: CGPoint(x: text.anchor.x - 1, y: y), to: CGPoint(x: text.anchor.x + width + 1, y: y),
                    width: 1, tone: .secondary
                ))
            }
            controls.append(PageRegion(
                .itemMarker(section, item.line),
                CGRect(x: row.minX - 6, y: row.minY, width: markerTapWidth, height: row.height)
            ))
        }
        if overflow > 0, let last = rows.last {
            shapes.append(.text(TemplateText(
                "+\(overflow)", font: .semibold, size: size, tone: .label,
                anchor: CGPoint(x: last.maxX - 4, y: TemplateText.baseline(centeredOn: last.midY, size: size)),
                alignment: .right
            )))
        }
        return (shapes, controls)
    }

    /// A tick over a circle or box.
    static func tick(center c: CGPoint) -> [TemplateShape] {
        let corner = CGPoint(x: c.x - 0.9, y: c.y + 2.7)
        return [
            .line(from: CGPoint(x: c.x - 3.4, y: c.y + 0.1), to: corner, width: 1.5, tone: .ink),
            .line(from: corner, to: CGPoint(x: c.x + 3.8, y: c.y - 3.2), width: 1.5, tone: .ink),
        ]
    }

    /// A printed +: a small grey button like the WEEKLY ones.
    static func addButton(_ rect: CGRect) -> [TemplateShape] {
        let arm = rect.width * 0.2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return [
            .rect(rect, fill: .button, stroke: nil, lineWidth: 0, cornerRadius: 4),
            .line(from: CGPoint(x: c.x - arm, y: c.y), to: CGPoint(x: c.x + arm, y: c.y), width: 1.4, tone: .label),
            .line(from: CGPoint(x: c.x, y: c.y - arm), to: CGPoint(x: c.x, y: c.y + arm), width: 1.4, tone: .label),
        ]
    }

    /// The text, shortened with "…" until it is at most `maxWidth` wide.
    public static func fitted(_ text: TemplateText, maxWidth: CGFloat) -> TemplateText {
        guard TemplateRenderer.width(of: text) > maxWidth else { return text }
        let characters = Array(text.string)
        var candidate = text
        func shortened(_ count: Int) -> TemplateText {
            var copy = text
            copy.string = String(characters.prefix(count)).trimmingCharacters(in: .whitespaces) + "…"
            return copy
        }
        // The longest prefix that fits, found by halving.
        var low = 0, high = characters.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if TemplateRenderer.width(of: shortened(middle)) <= maxWidth {
                low = middle
            } else {
                high = middle - 1
            }
        }
        candidate = shortened(low)
        return candidate
    }
}
