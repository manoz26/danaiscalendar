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

    public init(
        id: UUID = UUID(), title: String = "", date: PlannerDate?, paper: PaperStyle = .defaultStyle,
        created: Date = Date(), modified: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.paper = paper
        self.created = created
        self.modified = modified ?? created
    }

    public var page: PlannerPage { .journal(id) }

    /// The title without spaces or new lines at the ends, on one line.
    public var trimmedTitle: String {
        title.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// The journal's pages in their order: `Lists/journal.json`,
/// `{"version": 1, "pages": [{"id", "title", "date", "paper", "created", "modified"}]}`.
public struct JournalFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "journal.json"

    public var version: Int
    public var pages: [JournalPage]

    public init(pages: [JournalPage]) {
        version = Self.currentVersion
        self.pages = pages
    }
}

/// The journal: pages in the order she keeps them (new pages go at the end, a duplicate
/// right after its original; she can move them).
public struct Journal: Sendable, Equatable {
    public private(set) var pages: [JournalPage]

    public init(pages: [JournalPage] = []) {
        // One entry per page, even if a file was edited by hand.
        var seen: Set<UUID> = []
        self.pages = pages.filter { seen.insert($0.id).inserted }
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
    public mutating func insert(_ page: JournalPage, after id: UUID? = nil) {
        guard index(of: page.id) == nil else { return }
        if let id, let index = index(of: id) {
            pages.insert(page, at: index + 1)
        } else {
            pages.append(page)
        }
    }

    /// Replaces a page's details (title, date, paper), keeping its place.
    public mutating func update(_ page: JournalPage) {
        guard let index = index(of: page.id) else { return }
        pages[index] = page
    }

    /// A copy of a page right after it, with a new id. Returns the copy.
    @discardableResult
    public mutating func duplicate(_ id: UUID, as newID: UUID = UUID(), now: Date = Date()) -> JournalPage? {
        guard let original = page(id) else { return nil }
        let copy = JournalPage(id: newID, title: original.title, date: original.date, paper: original.paper, created: now)
        insert(copy, after: id)
        return copy
    }

    /// Moves a page to a place in the order (clamped to the ends).
    public mutating func move(_ id: UUID, to newIndex: Int) {
        guard let index = index(of: id) else { return }
        let page = pages.remove(at: index)
        pages.insert(page, at: min(max(0, newIndex), pages.count))
    }

    /// Moves a page `offset` places (-1 earlier, 1 later).
    public mutating func move(_ id: UUID, by offset: Int) {
        guard let index = index(of: id) else { return }
        move(id, to: index + offset)
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

/// `Lists/sketches.json`: `{"version": 1, "sketches": [{"id", "created", "modified", "day"}]}`.
public struct SketchFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "sketches.json"

    public var version: Int
    public var sketches: [Sketch]

    public init(sketches: [Sketch]) {
        version = Self.currentVersion
        self.sketches = sketches
    }
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
