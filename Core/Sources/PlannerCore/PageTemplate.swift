import CoreGraphics
import Foundation

/// The printed part of a page (lines, boxes, numbers, labels) as a list of simple shapes
/// in canvas units, plus the named regions of the page.
///
/// One renderer (`TemplateRenderer`) turns it into pixels, so the same page looks the
/// same on screen, in an image and in a PDF.
public struct PageTemplate: Sendable, Equatable {
    public var shapes: [TemplateShape]
    /// The fixed areas of the layout. The ink is anchored to them (`InkAnchor`).
    public var regions: [PageRegion]
    /// Printed things a finger taps that come and go with her data (the + buttons, the
    /// boxes of typed items, sketch marks). Never used to anchor ink.
    public var controls: [PageRegion]

    public init(shapes: [TemplateShape] = [], regions: [PageRegion] = [], controls: [PageRegion] = []) {
        self.shapes = shapes
        self.regions = regions
        self.controls = controls
    }

    /// The control under a point, if any (the smallest one first).
    public func control(at point: CGPoint) -> PageRegion? {
        controls
            .filter { $0.rect.contains(point) }
            .min { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    public func control(_ id: RegionID) -> PageRegion? {
        controls.first { $0.id == id }
    }

    public func region(_ id: RegionID) -> PageRegion? {
        regions.first { $0.id == id }
    }

    /// Every region under a point, the most specific (smallest) first.
    public func regions(at point: CGPoint) -> [PageRegion] {
        regions
            .filter { $0.rect.contains(point) }
            .sorted { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }
    }

    /// All printed text, in drawing order.
    public var texts: [TemplateText] {
        shapes.compactMap { shape in
            if case .text(let text) = shape { return text }
            return nil
        }
    }
}

/// A named area of a page, in canvas units.
public struct PageRegion: Sendable, Equatable {
    public let id: RegionID
    public let rect: CGRect

    public init(_ id: RegionID, _ rect: CGRect) {
        self.id = id
        self.rect = rect
    }
}

/// Stable name of a page area, e.g. `day:2026-11-14` or `section:memo`.
public enum RegionID: Hashable, Sendable, CustomStringConvertible {
    public enum Section: String, Sendable, CaseIterable {
        case goals, todo, memo, tobuy
        /// The writing area of a journal page or a sketch.
        case body
    }

    /// The page title ("NOVEMBER", "2026", "TO BUY").
    case title
    /// Month page: the WEEKLY buttons, numbered from 1.
    case weekly(Int)
    /// Month page: a column header.
    case weekday(Weekday)
    /// A day cell (month page) or day number (small month on the year page).
    case day(PlannerDate)
    /// Month page: goals box, to-do list, memo. To-buy page: the whole list.
    case section(Section)
    /// Month page: a to-do line, numbered from 1.
    case todoLine(Int)
    /// To-buy page: a line, numbered from 1 (down the left column, then the right one).
    case toBuyLine(Int)
    /// Year page: a small month (title and days); tapping it opens the month.
    case month(YearMonth)
    /// Year page: the title of a small month.
    case monthTitle(YearMonth)
    /// Year page: the grey notes box under a small month.
    case monthNotes(YearMonth)
    /// Control: the printed + that adds a typed item to the to-do list or the To Buy page.
    case addItem(Section)
    /// Control: the circle or box of a typed item on a line, numbered from 1.
    case itemMarker(Section, Int)
    /// Control: the small mark of the sketches pinned to a day (month page).
    case sketchMark(PlannerDate)

    public var description: String {
        switch self {
        case .title: "title"
        case .weekly(let number): "weekly:\(number)"
        case .weekday(let day): "weekday:\(day.key)"
        case .day(let date): "day:\(date)"
        case .section(let section): "section:\(section.rawValue)"
        case .todoLine(let number): "todo:\(number)"
        case .toBuyLine(let number): "tobuy:\(number)"
        case .month(let month): "month:\(month)"
        case .monthTitle(let month): "month-title:\(month)"
        case .monthNotes(let month): "notes:\(month)"
        case .addItem(let section): "add:\(section.rawValue)"
        case .itemMarker(let section, let line): "check:\(section.rawValue):\(line)"
        case .sketchMark(let date): "sketches:\(date)"
        }
    }

    /// Parses `description`.
    public init?(_ text: String) {
        if text == "title" {
            self = .title
            return
        }
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let kind = text[..<colon]
        let value = String(text[text.index(after: colon)...])
        switch kind {
        case "weekly": guard let n = Int(value), n > 0 else { return nil }; self = .weekly(n)
        case "weekday": guard let day = Weekday(key: value) else { return nil }; self = .weekday(day)
        case "day": guard let date = PlannerDate(value) else { return nil }; self = .day(date)
        case "section": guard let section = Section(rawValue: value) else { return nil }; self = .section(section)
        case "todo": guard let n = Int(value), n > 0 else { return nil }; self = .todoLine(n)
        case "tobuy": guard let n = Int(value), n > 0 else { return nil }; self = .toBuyLine(n)
        case "month": guard let month = YearMonth(value) else { return nil }; self = .month(month)
        case "month-title": guard let month = YearMonth(value) else { return nil }; self = .monthTitle(month)
        case "notes": guard let month = YearMonth(value) else { return nil }; self = .monthNotes(month)
        case "add": guard let section = Section(rawValue: value) else { return nil }; self = .addItem(section)
        case "check":
            let parts = value.split(separator: ":")
            guard parts.count == 2, let section = Section(rawValue: String(parts[0])),
                  let line = Int(parts[1]), line > 0 else { return nil }
            self = .itemMarker(section, line)
        case "sketches": guard let date = PlannerDate(value) else { return nil }; self = .sketchMark(date)
        default: return nil
        }
    }
}

/// Greys of the printed page. There is no other colour: colour belongs to the user's ink.
public enum Tone: Sendable, Equatable, CaseIterable {
    /// Titles and the "today" mark.
    case ink
    /// Day numbers.
    case text
    /// Small capitalised labels and column headers.
    case label
    /// Strong rules: top and bottom of the day grid and of the lists.
    case border
    /// Sundays.
    case secondary
    /// Days of another month.
    case faint
    /// Thin rules.
    case rule
    /// Inactive buttons.
    case button
    /// Box fills, like the goals and notes boxes.
    case fill
    /// White paper.
    case paper

    /// 0 = black, 1 = white.
    public var white: CGFloat {
        switch self {
        case .ink: 0
        case .text: 0.13
        case .label: 0.36
        case .border: 0.3
        case .secondary: 0.6
        case .faint: 0.8
        case .rule: 0.8
        case .button: 0.93
        case .fill: 0.95
        case .paper: 1
        }
    }
}

/// Inter, bundled with the app.
public enum PlannerFont: String, Sendable, CaseIterable {
    case regular = "Inter-Regular"
    case medium = "Inter-Medium"
    case semibold = "Inter-SemiBold"
    case bold = "Inter-Bold"

    public var postScriptName: String { rawValue }

    /// Height of Inter's capitals as a fraction of the font size.
    public static let capHeight: CGFloat = 0.727
}

/// One line of printed text.
public struct TemplateText: Sendable, Equatable {
    public enum Alignment: Sendable, Equatable {
        /// `anchor` is the left end of the baseline.
        case left
        /// `anchor` is the middle of the baseline.
        case center
        /// `anchor` is the right end of the baseline.
        case right
    }

    public var string: String
    public var font: PlannerFont
    public var size: CGFloat
    /// Extra space after each letter, in canvas units.
    public var tracking: CGFloat
    public var tone: Tone
    public var anchor: CGPoint
    public var alignment: Alignment

    public init(
        _ string: String, font: PlannerFont, size: CGFloat, tracking: CGFloat = 0,
        tone: Tone, anchor: CGPoint, alignment: Alignment = .left
    ) {
        self.string = string
        self.font = font
        self.size = size
        self.tracking = tracking
        self.tone = tone
        self.anchor = anchor
        self.alignment = alignment
    }

    /// Baseline that centres capitals and digits vertically on `y`.
    public static func baseline(centeredOn y: CGFloat, size: CGFloat) -> CGFloat {
        y + size * PlannerFont.capHeight / 2
    }
}

/// A simple shape of the printed page.
public enum TemplateShape: Sendable, Equatable {
    case line(from: CGPoint, to: CGPoint, width: CGFloat, tone: Tone)
    case rect(CGRect, fill: Tone?, stroke: Tone?, lineWidth: CGFloat, cornerRadius: CGFloat)
    case circle(center: CGPoint, radius: CGFloat, fill: Tone?, stroke: Tone?, lineWidth: CGFloat)
    case text(TemplateText)
}
