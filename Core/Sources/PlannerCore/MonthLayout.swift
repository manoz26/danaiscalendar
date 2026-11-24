import CoreGraphics
import Foundation

// MARK: - Her month page

/// A box of the month page besides the day grid.
public enum MonthBoxKind: String, Codable, CaseIterable, Sendable {
    case goals, todo, memo
    /// A box of her own, with her own title (e.g. "EXPENSES").
    case custom

    public var section: RegionID.Section {
        switch self {
        case .goals: .goals
        case .todo: .todo
        case .memo: .memo
        case .custom: .custom
        }
    }
}

/// Where a box sits: above the grid (a grey box, like GOALS) or under it (ruled lines, on
/// the left under three columns and on the right under four; alone, across the page).
public enum MonthSlot: String, Codable, CaseIterable, Sendable {
    case top, left, right
}

/// What a month page has besides the grid (Settings → Month page, prompt 9): which box is
/// above the grid and which two are under it (or none), her titles, and the number of
/// ruled lines under the grid. The to-do list is always under the grid (its lines have
/// circles and typed to-dos).
public struct MonthLayout: Codable, Sendable, Hashable {
    public var top: MonthBoxKind?
    public var left: MonthBoxKind?
    public var right: MonthBoxKind?
    /// Ruled lines of the lists under the grid.
    public var rows: Int
    /// Her titles, by `MonthBoxKind.rawValue` (none: the usual label; the own box: "NOTES").
    public var titles: [String: String]

    public init(
        top: MonthBoxKind? = .goals, left: MonthBoxKind? = .todo, right: MonthBoxKind? = .memo,
        rows: Int = MonthLayout.standardRows, titles: [String: String] = [:]
    ) {
        self.top = top
        self.left = left
        self.right = right
        self.rows = rows
        self.titles = titles
    }

    /// GOALS above, TO DO LIST and MEMO under the grid with 9 lines: the page as it always was.
    public static let standard = MonthLayout()
    public static let standardRows = 9
    public static let rowRange = 5...12
    public static let maxTitleLength = 30

    private enum CodingKeys: String, CodingKey {
        case top, left, right, rows, titles
    }

    /// Anything missing or unknown is the standard page's.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func box(_ key: CodingKeys, _ standard: MonthBoxKind) -> MonthBoxKind? {
            guard container.contains(key) else { return standard }
            if (try? container.decodeNil(forKey: key)) == true { return nil }
            return (try? container.decode(MonthBoxKind.self, forKey: key)) ?? standard
        }
        top = box(.top, .goals)
        left = box(.left, .todo)
        right = box(.right, .memo)
        rows = (try? container.decodeIfPresent(Int.self, forKey: .rows)) ?? Self.standardRows
        titles = (try? container.decodeIfPresent([String: String].self, forKey: .titles)) ?? [:]
        self = validated
    }

    /// Empty slots are written as `null`, so that "nothing here" is not read as the standard box.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(top, forKey: .top)
        try container.encode(left, forKey: .left)
        try container.encode(right, forKey: .right)
        try container.encode(rows, forKey: .rows)
        try container.encode(titles, forKey: .titles)
    }

    public func kind(in slot: MonthSlot) -> MonthBoxKind? {
        switch slot {
        case .top: top
        case .left: left
        case .right: right
        }
    }

    public mutating func set(_ kind: MonthBoxKind?, in slot: MonthSlot) {
        // The to-do list stays under the grid.
        guard !(kind == .todo && slot == .top) else { return }
        // A box is in one place only: taken from where it was.
        if let kind {
            for other in MonthSlot.allCases where other != slot && self.kind(in: other) == kind {
                assign(nil, to: other)
            }
        }
        assign(kind, to: slot)
        self = validated
    }

    private mutating func assign(_ kind: MonthBoxKind?, to slot: MonthSlot) {
        switch slot {
        case .top: top = kind
        case .left: left = kind
        case .right: right = kind
        }
    }

    public func slot(of kind: MonthBoxKind) -> MonthSlot? {
        MonthSlot.allCases.first { self.kind(in: $0) == kind }
    }

    /// Her title for a box, or `nil` for the usual label.
    public func title(of kind: MonthBoxKind) -> String? {
        let text = (titles[kind.rawValue] ?? "")
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : String(text.prefix(Self.maxTitleLength))
    }

    public mutating func setTitle(_ title: String, of kind: MonthBoxKind) {
        titles[kind.rawValue] = title
        self = validated
    }

    /// Each box once, the to-do list never above the grid, 5–12 lines, titles trimmed (empty ones dropped).
    public var validated: MonthLayout {
        var result = self
        if result.top == .todo { result.top = nil }
        if result.left != nil, result.left == result.top { result.left = nil }
        if result.right != nil, result.right == result.top || result.right == result.left { result.right = nil }
        result.rows = min(max(rows, Self.rowRange.lowerBound), Self.rowRange.upperBound)
        var titles: [String: String] = [:]
        for kind in MonthBoxKind.allCases {
            if let title = title(of: kind) { titles[kind.rawValue] = title }
        }
        result.titles = titles
        return result
    }

    public var isStandard: Bool { validated == Self.standard }
}

/// Her month layouts: one for all months, or one from a month on ("from this month on").
/// JSON: `{"entries": [{"from": "2027-01", "layout": {…}, "changed": …}]}`; no `from`: all months.
public struct MonthLayouts: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        /// The first month it is for (`nil`: every month before the next entry).
        public var from: YearMonth?
        public var layout: MonthLayout
        /// When she chose it: of two versions of a page written on different layouts, the
        /// one on the later layout wins (see `PageLayoutStamp`).
        public var changed: Date

        public init(from: YearMonth?, layout: MonthLayout, changed: Date) {
            self.from = from
            self.layout = layout
            self.changed = changed
        }
    }

    public private(set) var entries: [Entry]

    public init(entries: [Entry] = []) {
        self.entries = Self.sorted(entries)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = Self.sorted((try? container.decode([Entry].self, forKey: .entries)) ?? [])
    }

    private enum CodingKeys: String, CodingKey {
        case entries
    }

    private static func sorted(_ entries: [Entry]) -> [Entry] {
        // One per first month (the later choice), all months first.
        var latest: [String: Entry] = [:]
        for entry in entries {
            let key = entry.from?.description ?? ""
            if let known = latest[key], known.changed > entry.changed { continue }
            latest[key] = entry
        }
        return latest.values.sorted { ($0.from?.description ?? "") < ($1.from?.description ?? "") }
    }

    /// The entry a month uses: the last one that starts at or before it.
    public func entry(for month: YearMonth) -> Entry? {
        entries.last { $0.from.map { $0 <= month } ?? true }
    }

    public func layout(for month: YearMonth) -> MonthLayout {
        entry(for: month)?.layout ?? .standard
    }

    /// A layout for every month (`from: nil`), or from a month on (later choices for later
    /// months are replaced).
    public mutating func set(_ layout: MonthLayout, from month: YearMonth?, at date: Date = Date()) {
        var kept = entries
        if let month {
            kept.removeAll { entry in entry.from.map { $0 >= month } ?? false }
        } else {
            kept = []
        }
        kept.append(Entry(from: month, layout: layout.validated, changed: date))
        entries = Self.sorted(kept)
    }

    public var isStandard: Bool {
        entries.allSatisfy { $0.layout.isStandard }
    }
}

// MARK: - Moving ink with its region

/// When a page's layout changes, each stroke moves (and shrinks, never grows) with the
/// region it belongs to (`InkAnchor`): from its place in the old region to the same place
/// in the region of the same name in the new layout. Regions of boxes that are not shown
/// are parked off the page (`MonthPageLayout.anchorRegions`), so a hidden box keeps its ink
/// and gets it back when it is shown again. A stroke whose region is in neither stays.
public enum LayoutMigration {
    /// The transform (in canvas units) for a stroke with these bounds, or `nil` to leave it.
    public static func transform(forStrokeBounds bounds: CGRect, from old: [PageRegion], to new: [PageRegion]) -> CGAffineTransform? {
        guard !bounds.isNull, !bounds.isInfinite, bounds.width.isFinite, bounds.height.isFinite else { return nil }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        guard let source = old.filter({ $0.rect.contains(center) })
                .min(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }),
              let target = new.first(where: { $0.id == source.id }),
              source.rect != target.rect,
              source.rect.width > 0, source.rect.height > 0 else { return nil }
        let kx = target.rect.width / source.rect.width
        let ky = target.rect.height / source.rect.height
        let scale = min(1, kx, ky)
        let minX = target.rect.minX + (bounds.minX - source.rect.minX) * kx
        let minY = target.rect.minY + (bounds.minY - source.rect.minY) * ky
        return CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: minX - scale * bounds.minX, ty: minY - scale * bounds.minY)
    }
}
