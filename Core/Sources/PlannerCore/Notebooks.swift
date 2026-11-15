import Foundation

// MARK: - Journal

/// The paper of a journal page. It can be changed after writing: the ink stays where it is.
public enum PaperStyle: String, Codable, CaseIterable, Sendable {
    case blank, lined, grid, dotted

    /// New pages start lined.
    public static let defaultStyle: PaperStyle = .lined
}

/// One page of the journal ("Τετράδιο"). Its ink is in the page file `journal-<id>.dcpage`.
public struct JournalPage: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Optional; printed big at the top.
    public var title: String
    /// The day the page belongs to. A day with a page gets a small dot on the month page,
    /// and a long press on the day opens its page. `nil`: a page without a date.
    public var date: PlannerDate?
    public var paper: PaperStyle
    public var created: Date
    public var modified: Date
    /// Its place in the journal: pages are in the order of their positions. A moved page
    /// gets a position between its new neighbours, so that the move reaches the other
    /// devices as a change of that page only. Files from before prompt 7 have none (their
    /// order is the order of the file).
    public var position: Double?

    public init(
        id: UUID = UUID(), title: String = "", date: PlannerDate?, paper: PaperStyle = .defaultStyle,
        created: Date = Date(), modified: Date? = nil, position: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.paper = paper
        self.created = created
        self.modified = modified ?? created
        self.position = position
    }

    public var page: PlannerPage { .journal(id) }

    /// The title without spaces or new lines at the ends, on one line.
    public var trimmedTitle: String {
        title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// The journal's pages in their order: `Lists/journal.json`,
/// `{"version": 1, "pages": [{"id", "title", "date", "paper", "created", "modified", "position"}],
/// "deleted": [{"id", "deleted"}]}`.
public struct JournalFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "journal.json"

    public var version: Int
    public var pages: [JournalPage]
    public var deleted: [Tombstone]?

    public init(pages: [JournalPage], deleted: [Tombstone] = []) {
        version = Self.currentVersion
        self.pages = pages
        self.deleted = deleted.isEmpty ? nil : deleted
    }

    public var tombstones: [Tombstone] { deleted ?? [] }
}

/// The journal: pages in the order she keeps them (new pages go at the end, a duplicate
/// right after its original; she can move them). The order is the pages' positions.
public struct Journal: Sendable, Equatable {
    public private(set) var pages: [JournalPage]

    public init(pages: [JournalPage] = []) {
        // One entry per page, even if a file was edited by hand.
        var seen: Set<UUID> = []
        self.pages = Self.sorted(Self.positioned(pages.filter { seen.insert($0.id).inserted }))
    }

    /// Pages without a position (files from before prompt 7) get their place in the list.
    public static func positioned(_ pages: [JournalPage]) -> [JournalPage] {
        pages.enumerated().map { index, page in
            guard page.position == nil else { return page }
            var placed = page
            placed.position = Double(index)
            return placed
        }
    }

    /// By position (then id, so that every device has the same order).
    public static func sorted(_ pages: [JournalPage]) -> [JournalPage] {
        pages.sorted { a, b in
            let x = a.position ?? 0
            let y = b.position ?? 0
            return x != y ? x < y : a.id.uuidString < b.id.uuidString
        }
    }

    /// A position for a page put at `index` (between the pages now at `index - 1` and
    /// `index`), or `nil` if they are too close (then the pages are numbered again).
    private func slot(at index: Int) -> Double? {
        let before = index > 0 ? pages[index - 1].position ?? Double(index - 1) : nil
        let after = index < pages.count ? pages[index].position ?? Double(index) : nil
        switch (before, after) {
        case (nil, nil): return 0
        case (let before?, nil): return before + 1
        case (nil, let after?): return after - 1
        case (let before?, let after?):
            let middle = before + (after - before) / 2
            return middle > before && middle < after ? middle : nil
        }
    }

    /// Positions 0, 1, 2… in the current order (pages whose position changes are changed now).
    private mutating func renumber(now: Date) {
        for index in pages.indices where pages[index].position != Double(index) {
            pages[index].position = Double(index)
            pages[index].modified = now
        }
    }

    public var isEmpty: Bool { pages.isEmpty }

    public func index(of id: UUID) -> Int? {
        pages.firstIndex { $0.id == id }
    }

    public func page(_ id: UUID) -> JournalPage? {
        pages.first { $0.id == id }
    }

    /// The first page (in the journal's order) of a day.
    public func page(on date: PlannerDate) -> JournalPage? {
        pages.first { $0.date == date }
    }

    /// Every day that has a page.
    public var datedDays: Set<PlannerDate> {
        Set(pages.compactMap(\.date))
    }

    /// The page `offset` places away (-1 the one before, 1 the one after), if there is one.
    public func neighbor(of id: UUID, offset: Int) -> JournalPage? {
        guard let index = index(of: id), pages.indices.contains(index + offset) else { return nil }
        return pages[index + offset]
    }

    /// Adds a page at the end, or right after the page `after`.
    public mutating func insert(_ page: JournalPage, after id: UUID? = nil, now: Date = Date()) {
        guard index(of: page.id) == nil else { return }
        let at = id.flatMap { index(of: $0) }.map { $0 + 1 } ?? pages.count
        var placed = page
        let slot = slot(at: at)
        placed.position = slot ?? 0
        pages.insert(placed, at: at)
        if slot == nil {
            renumber(now: now)
        }
    }

    /// Replaces a page's details (title, date, paper), keeping its place.
    public mutating func update(_ page: JournalPage) {
        guard let index = index(of: page.id) else { return }
        var changed = page
        changed.position = pages[index].position
        pages[index] = changed
    }

    /// A copy of a page right after it, with a new id. Returns the copy.
    @discardableResult
    public mutating func duplicate(_ id: UUID, as newID: UUID = UUID(), now: Date = Date()) -> JournalPage? {
        guard let original = page(id) else { return nil }
        let copy = JournalPage(id: newID, title: original.title, date: original.date, paper: original.paper, created: now)
        insert(copy, after: id)
        return copy
    }

    /// Moves a page to a place in the order (clamped to the ends). The moved page gets a
    /// position between its new neighbours (and is changed now).
    public mutating func move(_ id: UUID, to newIndex: Int, now: Date = Date()) {
        guard let index = index(of: id) else { return }
        var page = pages.remove(at: index)
        let at = min(max(0, newIndex), pages.count)
        guard at != index else {
            pages.insert(page, at: index)
            return
        }
        let slot = slot(at: at)
        page.position = slot ?? 0
        page.modified = now
        pages.insert(page, at: at)
        if slot == nil {
            renumber(now: now)
        }
    }

    /// Moves a page `offset` places (-1 earlier, 1 later).
    public mutating func move(_ id: UUID, by offset: Int, now: Date = Date()) {
        guard let index = index(of: id) else { return }
        move(id, to: index + offset, now: now)
    }

    public mutating func remove(_ id: UUID) {
        pages.removeAll { $0.id == id }
    }
}

// MARK: - Sketches

/// A sketch from the sketch button. Its ink is in `sketch-<id>.dcpage`. It can be pinned
/// to a day: the day then shows a small sketch mark on the month page that opens it.
public struct Sketch: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var created: Date
    public var modified: Date
    /// The day it is pinned to, if any.
    public var day: PlannerDate?

    public init(id: UUID = UUID(), created: Date = Date(), modified: Date? = nil, day: PlannerDate? = nil) {
        self.id = id
        self.created = created
        self.modified = modified ?? created
        self.day = day
    }

    public var page: PlannerPage { .sketch(id) }
}

/// `Lists/sketches.json`: `{"version": 1, "sketches": [{"id", "created", "modified", "day"}],
/// "deleted": [{"id", "deleted"}]}`.
public struct SketchFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "sketches.json"

    public var version: Int
    public var sketches: [Sketch]
    public var deleted: [Tombstone]?

    public init(sketches: [Sketch], deleted: [Tombstone] = []) {
        version = Self.currentVersion
        self.sketches = sketches
        self.deleted = deleted.isEmpty ? nil : deleted
    }

    public var tombstones: [Tombstone] { deleted ?? [] }
}

extension Sketch {
    /// Newest first, the order of the sketches' grid.
    public static func newestFirst(_ sketches: [Sketch]) -> [Sketch] {
        sketches.sorted { a, b in
            a.created != b.created ? a.created > b.created : a.id.uuidString < b.id.uuidString
        }
    }

    /// The sketches pinned to each day, newest first.
    public static func pinned(_ sketches: [Sketch]) -> [PlannerDate: [Sketch]] {
        var result: [PlannerDate: [Sketch]] = [:]
        for sketch in newestFirst(sketches) {
            guard let day = sketch.day else { continue }
            result[day, default: []].append(sketch)
        }
        return result
    }
}
