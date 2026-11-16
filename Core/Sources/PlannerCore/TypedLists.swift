import Foundation

/// A typed item of a list: a to-do of a month or a thing to buy. It is printed on the
/// page's lines under the ink, with a circle (to-do) or a box (to buy) she can tick with a
/// finger; handwriting and typed items live side by side. Later the iPhone adds them too.
public struct ListItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var text: String
    public var done: Bool
    /// The printed line it sits on, from 1 (`todo:N`, `tobuy:N`), or `nil` when no line
    /// was free. Chosen once, when the item is added, so it never jumps around.
    public var line: Int?
    /// The month of a to-do; `nil` on the To Buy list.
    public var month: YearMonth?
    public var created: Date
    public var modified: Date
    /// Its place in the iPhone's lists, once she has moved it there (`nil`: where it was
    /// added). The printed line never changes with it.
    public var position: Double?

    public init(
        id: UUID = UUID(), text: String, done: Bool = false, line: Int?, month: YearMonth? = nil,
        created: Date = Date(), modified: Date? = nil, position: Double? = nil
    ) {
        self.id = id
        self.text = text
        self.done = done
        self.line = line
        self.month = month
        self.created = created
        self.modified = modified ?? created
        self.position = position
    }

    /// What the iPhone's lists are ordered by: `position`, or else when the item was added.
    public var orderKey: Double {
        position ?? created.timeIntervalSinceReferenceDate
    }

    /// On one line, without spaces at the ends.
    public var trimmedText: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// A list file: `Lists/tobuy.json` (things to buy) or `Lists/todo.json` (the to-dos of
/// every month), `{"version": 1, "items": [{"id", "text", "done", "line", "month", "created", "modified", "position"}],
/// "deleted": [{"id", "deleted"}]}` (the deleted items, for iCloud; left out when there are none).
public struct ListFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let toBuyFileName = "tobuy.json"
    public static let todoFileName = "todo.json"

    public var version: Int
    public var items: [ListItem]
    public var deleted: [Tombstone]?

    public init(items: [ListItem], deleted: [Tombstone] = []) {
        version = Self.currentVersion
        self.items = items
        self.deleted = deleted.isEmpty ? nil : deleted
    }

    public var tombstones: [Tombstone] { deleted ?? [] }
}

/// A typed item as printed on a page.
public struct PrintedItem: Sendable, Equatable {
    /// From 1.
    public var line: Int
    public var text: String
    public var done: Bool

    public init(line: Int, text: String, done: Bool) {
        self.line = line
        self.text = text
        self.done = done
    }
}

public enum TypedLists {
    /// The first line (1...count) with no typed item on it and no ink in it, or `nil`.
    public static func freeLine(count: Int, items: [ListItem], inked: Set<Int>) -> Int? {
        let taken = Set(items.compactMap(\.line)).union(inked)
        return (1...max(1, count)).first { !taken.contains($0) && $0 <= count }
    }

    /// The items printed on a page with `lineCount` lines, by line, and how many have no
    /// line (printed as "+N"). Two items never share a line: the older one keeps it.
    public static func printed(_ items: [ListItem], lineCount: Int) -> (items: [PrintedItem], overflow: Int) {
        var byLine: [Int: ListItem] = [:]
        var overflow = 0
        for item in items.sorted(by: { $0.created < $1.created }) {
            guard let line = item.line, (1...lineCount).contains(line), byLine[line] == nil else {
                overflow += 1
                continue
            }
            byLine[line] = item
        }
        let printed = byLine.keys.sorted().compactMap { line in
            byLine[line].map { PrintedItem(line: line, text: $0.trimmedText, done: $0.done) }
        }
        return (printed, overflow)
    }

    /// The order of the iPhone's lists: as she arranged them (items she never moved: oldest first).
    public static func arranged(_ items: [ListItem]) -> [ListItem] {
        items.sorted { a, b in
            a.orderKey != b.orderKey ? a.orderKey < b.orderKey : a.id.uuidString < b.id.uuidString
        }
    }

    /// The iPhone's lists show what is still open first and the ticked items below, each as arranged.
    public static func openThenTicked(_ items: [ListItem]) -> (open: [ListItem], ticked: [ListItem]) {
        let all = arranged(items)
        return (all.filter { !$0.done }, all.filter(\.done))
    }

    /// The position of an item dropped at `index` of `others` (the arranged items without
    /// it): between its new neighbours, so that the move changes that item only.
    public static func position(at index: Int, among others: [ListItem]) -> Double {
        let at = min(max(0, index), others.count)
        let before = at > 0 ? others[at - 1].orderKey : nil
        let after = at < others.count ? others[at].orderKey : nil
        switch (before, after) {
        case (nil, nil): return 0
        case (let before?, nil): return before + 1
        case (nil, let after?): return after - 1
        case (let before?, let after?): return before + (after - before) / 2
        }
    }
}
