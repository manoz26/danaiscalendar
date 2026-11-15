import CryptoKit
import Foundation

// MARK: - Deletions

/// A deleted item of a synced list: which one, and when. Lists keep these so that another
/// device that still has the item deletes it too, instead of bringing it back (prompt 7).
public struct Tombstone: Codable, Sendable, Hashable {
    public var id: UUID
    public var deleted: Date

    public init(id: UUID, deleted: Date) {
        self.id = id
        self.deleted = deleted
    }

    /// Kept this long, then forgotten (a device offline for longer may bring an item back).
    public static let keptFor: TimeInterval = 400 * 24 * 3600

    /// One per id (the latest deletion), without the ones older than `keptFor`, in a fixed order.
    public static func merged(_ a: [Tombstone], _ b: [Tombstone], now: Date = Date()) -> [Tombstone] {
        var latest: [UUID: Date] = [:]
        for tombstone in a + b {
            if let known = latest[tombstone.id], known >= tombstone.deleted { continue }
            latest[tombstone.id] = tombstone.deleted
        }
        let oldest = now.addingTimeInterval(-keptFor)
        return latest
            .filter { $0.value >= oldest }
            .map { Tombstone(id: $0.key, deleted: $0.value) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// `tombstones`, plus one (at `date`) for each id of `before` that is not in `after`.
    public static func recording(
        deletionsFrom before: [UUID], to after: [UUID], in tombstones: [Tombstone], at date: Date = Date()
    ) -> [Tombstone] {
        let remaining = Set(after)
        let gone = before.filter { !remaining.contains($0) }
        guard !gone.isEmpty else { return tombstones }
        return merged(tombstones, gone.map { Tombstone(id: $0, deleted: date) }, now: date)
    }
}

// MARK: - Lists

/// Something in a synced list: an id, and when it last changed.
public protocol MergeableItem: Codable, Sendable, Equatable, Identifiable where ID == UUID {
    /// When it was last changed: of two versions of an item, the newer one wins.
    var lastChange: Date { get }
    /// The same item, changed at `date` (an item brought back from a backup).
    func touched(at date: Date) -> Self
}

/// Merging two versions of a list (from two devices, or a backup), item by item.
///
/// The result does not depend on which version is "mine": both devices get the same list,
/// so after one exchange they agree and nothing more is sent.
public enum ListMerge {
    /// Whole seconds: list files keep dates to the second, so both devices compare the same values.
    public static func seconds(_ date: Date) -> Int64 {
        let value = date.timeIntervalSince1970.rounded(.down)
        guard value.isFinite else { return value < 0 ? .min : .max }
        return Int64(max(-9e18, min(9e18, value)))
    }

    /// One entry per id: the newer version of each item (on a tie, the same one on every
    /// device), without the deleted ones (a tombstone at or after the item's last change).
    /// Order: `mine`, then what only `theirs` has; callers sort the result.
    public static func merge<Item: MergeableItem>(mine: [Item], theirs: [Item], tombstones: [Tombstone]) -> [Item] {
        var deletedAt: [UUID: Int64] = [:]
        for tombstone in tombstones {
            deletedAt[tombstone.id] = max(deletedAt[tombstone.id] ?? .min, seconds(tombstone.deleted))
        }
        var theirsByID: [UUID: Item] = [:]
        for item in theirs where theirsByID[item.id] == nil {
            theirsByID[item.id] = item
        }
        var result: [Item] = []
        var seen: Set<UUID> = []
        for item in mine where seen.insert(item.id).inserted {
            result.append(theirsByID[item.id].map { newer(item, $0) } ?? item)
        }
        for item in theirs where seen.insert(item.id).inserted {
            result.append(item)
        }
        return result.filter { item in
            guard let at = deletedAt[item.id] else { return true }
            return seconds(item.lastChange) > at
        }
    }

    static func newer<Item: MergeableItem>(_ a: Item, _ b: Item) -> Item {
        let x = seconds(a.lastChange)
        let y = seconds(b.lastChange)
        if x != y { return x > y ? a : b }
        if a == b { return a }
        return tieKey(a) >= tieKey(b) ? a : b
    }

    /// The item as the list files write it (dates to the second), to break ties the same way everywhere.
    static func tieKey<Item: Encodable>(_ item: Item) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(item) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A backup brought back: its items that are missing here (deleted, or never here) come
    /// back, changed now, so that the other devices bring them back too; the others are
    /// merged as usual (a newer change here stays). Returns the items and the tombstones left.
    public static func restore<Item: MergeableItem>(
        mine: [Item], tombstones: [Tombstone], backup: [Item], now: Date = Date()
    ) -> (items: [Item], tombstones: [Tombstone]) {
        let saved = Dictionary(backup.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let here = Set(mine.map(\.id))
        // Items here keep their version, unless the backup's is newer.
        var items = mine.map { item in
            guard let old = saved[item.id], seconds(old.lastChange) > seconds(item.lastChange) else { return item }
            return old
        }
        var seen = here
        for item in backup where seen.insert(item.id).inserted {
            items.append(item.touched(at: now))
        }
        let revived = seen.subtracting(here)
        return (items, tombstones.filter { !revived.contains($0.id) })
    }
}

extension ListItem: MergeableItem {
    public var lastChange: Date { modified }

    public func touched(at date: Date) -> ListItem {
        var copy = self
        copy.modified = date
        return copy
    }

    /// The order of the list files: oldest first.
    public static func canonical(_ items: [ListItem]) -> [ListItem] {
        items.sorted { a, b in
            a.created != b.created ? a.created < b.created : a.id.uuidString < b.id.uuidString
        }
    }
}

extension JournalPage: MergeableItem {
    public var lastChange: Date { modified }

    public func touched(at date: Date) -> JournalPage {
        var copy = self
        copy.modified = date
        return copy
    }
}

extension Sketch: MergeableItem {
    public var lastChange: Date { modified }

    public func touched(at date: Date) -> Sketch {
        var copy = self
        copy.modified = date
        return copy
    }

    /// The order of the sketches file: oldest first.
    public static func canonical(_ sketches: [Sketch]) -> [Sketch] {
        sketches.sorted { a, b in
            a.created != b.created ? a.created < b.created : a.id.uuidString < b.id.uuidString
        }
    }
}

extension WishlistPhoto: MergeableItem {
    public var lastChange: Date { modified ?? created }

    public func touched(at date: Date) -> WishlistPhoto {
        var copy = self
        copy.modified = date
        return copy
    }
}

extension Birthday: MergeableItem {
    /// Birthdays saved before prompt 7 have no date: any change wins over them.
    public var lastChange: Date { modified ?? .distantPast }

    public func touched(at date: Date) -> Birthday {
        var copy = self
        copy.modified = date
        return copy
    }

    /// The order of the birthdays file (the list shows them by date anyway).
    public static func canonical(_ birthdays: [Birthday]) -> [Birthday] {
        birthdays.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

extension ListFile {
    /// Two versions of a typed list: each item once, the newer version, without deleted ones.
    public static func merged(_ mine: ListFile, _ theirs: ListFile, now: Date = Date()) -> ListFile {
        let tombstones = Tombstone.merged(mine.tombstones, theirs.tombstones, now: now)
        let items = ListMerge.merge(mine: mine.items, theirs: theirs.items, tombstones: tombstones)
        return ListFile(items: ListItem.canonical(items), deleted: tombstones)
    }

    /// A backup's items brought back (see `ListMerge.restore`).
    public static func restored(_ mine: ListFile, from backup: ListFile, now: Date = Date()) -> ListFile {
        let result = ListMerge.restore(mine: mine.items, tombstones: mine.tombstones, backup: backup.items, now: now)
        return ListFile(items: ListItem.canonical(result.items), deleted: result.tombstones)
    }
}

extension SketchFile {
    public static func merged(_ mine: SketchFile, _ theirs: SketchFile, now: Date = Date()) -> SketchFile {
        let tombstones = Tombstone.merged(mine.tombstones, theirs.tombstones, now: now)
        let sketches = ListMerge.merge(mine: mine.sketches, theirs: theirs.sketches, tombstones: tombstones)
        return SketchFile(sketches: Sketch.canonical(sketches), deleted: tombstones)
    }

    public static func restored(_ mine: SketchFile, from backup: SketchFile, now: Date = Date()) -> SketchFile {
        let result = ListMerge.restore(mine: mine.sketches, tombstones: mine.tombstones, backup: backup.sketches, now: now)
        return SketchFile(sketches: Sketch.canonical(result.items), deleted: result.tombstones)
    }
}

extension WishlistFile {
    public static func merged(_ mine: WishlistFile, _ theirs: WishlistFile, now: Date = Date()) -> WishlistFile {
        let tombstones = Tombstone.merged(mine.tombstones, theirs.tombstones, now: now)
        let photos = ListMerge.merge(mine: mine.photos, theirs: theirs.photos, tombstones: tombstones)
        return WishlistFile(photos: WishlistPhoto.newestFirst(photos), deleted: tombstones)
    }

    public static func restored(_ mine: WishlistFile, from backup: WishlistFile, now: Date = Date()) -> WishlistFile {
        let result = ListMerge.restore(mine: mine.photos, tombstones: mine.tombstones, backup: backup.photos, now: now)
        return WishlistFile(photos: WishlistPhoto.newestFirst(result.items), deleted: result.tombstones)
    }
}

extension BirthdayFile {
    public static func merged(_ mine: BirthdayFile, _ theirs: BirthdayFile, now: Date = Date()) -> BirthdayFile {
        let tombstones = Tombstone.merged(mine.tombstones, theirs.tombstones, now: now)
        let birthdays = ListMerge.merge(mine: mine.birthdays, theirs: theirs.birthdays, tombstones: tombstones)
        return BirthdayFile(birthdays: Birthday.canonical(birthdays), deleted: tombstones)
    }

    public static func restored(_ mine: BirthdayFile, from backup: BirthdayFile, now: Date = Date()) -> BirthdayFile {
        let result = ListMerge.restore(mine: mine.birthdays, tombstones: mine.tombstones, backup: backup.birthdays, now: now)
        return BirthdayFile(birthdays: Birthday.canonical(result.items), deleted: result.tombstones)
    }
}

extension JournalFile {
    /// The journal's pages of both versions, in the order of their positions (a page moved
    /// on one device takes its new place on the other).
    public static func merged(_ mine: JournalFile, _ theirs: JournalFile, now: Date = Date()) -> JournalFile {
        let tombstones = Tombstone.merged(mine.tombstones, theirs.tombstones, now: now)
        let pages = ListMerge.merge(
            mine: Journal.positioned(mine.pages), theirs: Journal.positioned(theirs.pages), tombstones: tombstones
        )
        return JournalFile(pages: Journal.sorted(pages), deleted: tombstones)
    }

    /// A backup's pages brought back: the missing ones go after the last page.
    public static func restored(_ mine: JournalFile, from backup: JournalFile, now: Date = Date()) -> JournalFile {
        let pages = Journal.positioned(mine.pages)
        let last = pages.compactMap(\.position).max() ?? -1
        let missing = Set(backup.pages.map(\.id)).subtracting(pages.map(\.id))
        var next = last + 1
        let backupPages = Journal.positioned(backup.pages).map { page -> JournalPage in
            guard missing.contains(page.id) else { return page }
            var moved = page
            moved.position = next
            next += 1
            return moved
        }
        let result = ListMerge.restore(mine: pages, tombstones: mine.tombstones, backup: backupPages, now: now)
        return JournalFile(pages: Journal.sorted(result.items), deleted: result.tombstones)
    }
}

// MARK: - Ordered things (the strokes of a page)

/// Merging two orders of things that have keys but no ids, such as the strokes of a page:
/// the result is a list of which element to take from which side, in order.
public enum OrderedMerge {
    public enum Source: Equatable, Sendable {
        case mine(Int)
        case theirs(Int)
    }

    /// Everything either side has, nothing twice: `mine` in its order, then what only
    /// `theirs` has. A key that appears n times on one side and m on the other appears
    /// max(n, m) times.
    public static func union<Key: Hashable>(mine: [Key], theirs: [Key]) -> [Source] {
        threeWay(base: [], mine: mine, theirs: theirs)
    }

    /// What each side changed since `base` (added or removed) is kept. Where both changed
    /// the count of a key, the larger count is kept: nothing both sides have is lost.
    /// Order: `mine`, then what only `theirs` adds.
    public static func threeWay<Key: Hashable>(base: [Key], mine: [Key], theirs: [Key]) -> [Source] {
        let b = counts(base)
        let m = counts(mine)
        let t = counts(theirs)
        func target(_ key: Key) -> Int {
            let inBase = b[key] ?? 0
            let inMine = m[key] ?? 0
            let inTheirs = t[key] ?? 0
            if inMine == inBase { return inTheirs }
            if inTheirs == inBase { return inMine }
            return max(inMine, inTheirs)
        }
        var emitted: [Key: Int] = [:]
        var result: [Source] = []
        for (index, key) in mine.enumerated() where (emitted[key] ?? 0) < target(key) {
            emitted[key, default: 0] += 1
            result.append(.mine(index))
        }
        for (index, key) in theirs.enumerated() where (emitted[key] ?? 0) < target(key) {
            emitted[key, default: 0] += 1
            result.append(.theirs(index))
        }
        return result
    }

    private static func counts<Key: Hashable>(_ keys: [Key]) -> [Key: Int] {
        var result: [Key: Int] = [:]
        for key in keys {
            result[key, default: 0] += 1
        }
        return result
    }
}

// MARK: - Hashes

/// A fingerprint of a file's content (SHA-256, hex), to tell whether two copies differ.
public enum ContentHash {
    public static func of(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
