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

    public init(
        id: UUID = UUID(), text: String, done: Bool = false, line: Int?, month: YearMonth? = nil,
        created: Date = Date(), modified: Date? = nil
    ) {
        self.id = id
        self.text = text
        self.done = done
        self.line = line
        self.month = month
        self.created = created
        self.modified = modified ?? created
    }

    /// On one line, without spaces at the ends.
    public var trimmedText: String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// A list file: `Lists/tobuy.json` (things to buy) or `Lists/todo.json` (the to-dos of
/// every month), `{"version": 1, "items": [{"id", "text", "done", "line", "month", "created", "modified"}]}`.
public struct ListFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let toBuyFileName = "tobuy.json"
    public static let todoFileName = "todo.json"

    public var version: Int
    public var items: [ListItem]

    public init(items: [ListItem]) {
        version = Self.currentVersion
        self.items = items
    }
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
}
