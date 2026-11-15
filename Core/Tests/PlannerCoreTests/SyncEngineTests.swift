import Foundation
import Testing
@testable import PlannerCore

// MARK: - Test devices

/// A device's owner for the tests: lists are merged with the app's real merges; a "page" is
/// a few lines of text, one stroke per line, merged as a union of lines (the app merges
/// PencilKit strokes the same way). It writes the device's folder like the app does.
final class TestOwner: SyncOwner {
    let root: URL

    init(root: URL) {
        self.root = root
    }

    var lists: URL { root.appending(path: SyncPath.listsFolder) }

    func receive(_ data: Data, for path: SyncPath, replacing: String?) async throws -> Data {
        let url = root.appending(path: path.path)
        let local = try? Data(contentsOf: url)
        let result: Data
        switch path.kind {
        case .page:
            if let replacing, let local, ContentHash.of(local) == replacing {
                result = data
            } else {
                let mine = Self.lines(local ?? Data())
                let theirs = Self.lines(data)
                var merged = mine
                for line in theirs where !merged.contains(line) {
                    merged.append(line)
                }
                result = merged == theirs ? data : Data(merged.joined(separator: "\n").utf8)
            }
        case .photo:
            result = local ?? data
        case .list(let name):
            switch name {
            case ListFile.todoFileName, ListFile.toBuyFileName:
                result = try Self.merge(ListFile.self, data, local, ListFile.merged)
            case JournalFile.fileName:
                result = try Self.merge(JournalFile.self, data, local, JournalFile.merged)
            case SketchFile.fileName:
                result = try Self.merge(SketchFile.self, data, local, SketchFile.merged)
            case WishlistFile.fileName:
                result = try Self.merge(WishlistFile.self, data, local, WishlistFile.merged)
            default:
                let theirs = try BirthdayFile(decoding: data)
                let mine = try local.map { try BirthdayFile(decoding: $0) }
                result = try (mine.map { BirthdayFile.merged($0, theirs) } ?? theirs).encoded()
            }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try result.write(to: url, options: .atomic)
        return result
    }

    func deletedPaths() async -> Set<String> {
        var paths: Set<String> = []
        if let journal = try? JSONFileStore<JournalFile>(folder: lists, fileName: JournalFile.fileName).load() {
            let present = Set(journal.pages.map(\.id))
            for tombstone in journal.tombstones where !present.contains(tombstone.id) {
                paths.insert(SyncPath(page: .journal(tombstone.id)).path)
            }
        }
        if let wishlist = try? JSONFileStore<WishlistFile>(folder: lists, fileName: WishlistFile.fileName).load() {
            let present = Set(wishlist.photos.map(\.id))
            for tombstone in wishlist.tombstones where !present.contains(tombstone.id) {
                paths.insert(SyncPath(photo: tombstone.id).path)
            }
        }
        return paths
    }

    func removeLocal(_ path: SyncPath) async -> Bool {
        try? FileManager.default.removeItem(at: root.appending(path: path.path))
        return true
    }

    static func lines(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    static func merge<File: VersionedFile>(_ type: File.Type, _ data: Data, _ local: Data?, _ merged: (File, File, Date) -> File) throws -> Data {
        let theirs = try JSONFileStore<File>.decode(data)
        guard let local else { return data }
        return try JSONFileStore<File>.encode(merged(try JSONFileStore<File>.decode(local), theirs, Date()))
    }
}

/// A device: its data folder, its owner and its sync engine, all sharing one "iCloud".
struct TestDevice {
    let root: URL
    let engine: SyncEngine

    init(cloud: any SyncStorage, base: URL, name: String) {
        root = base.appending(path: name, directoryHint: .isDirectory)
        engine = SyncEngine(
            local: FolderStorage(root: root), cloud: cloud, owner: TestOwner(root: root),
            stateStore: JSONFileStore(folder: base.appending(path: "\(name)-sync"), fileName: SyncState.fileName),
            account: "test-account", log: { _, _ in }
        )
    }

    func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    func write(_ data: Data, to path: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func text(_ path: String) -> String? {
        (try? Data(contentsOf: root.appending(path: path))).map { String(decoding: $0, as: UTF8.self) }
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false))
    }

    var lists: URL { root.appending(path: SyncPath.listsFolder) }

    func save(toBuy items: [ListItem], deleted: [Tombstone] = []) throws {
        try JSONFileStore<ListFile>(folder: lists, fileName: ListFile.toBuyFileName).save(ListFile(items: items, deleted: deleted))
    }

    func toBuy() throws -> ListFile? {
        try JSONFileStore<ListFile>(folder: lists, fileName: ListFile.toBuyFileName).load()
    }

    func save(journal pages: [JournalPage], deleted: [Tombstone] = []) throws {
        try JSONFileStore<JournalFile>(folder: lists, fileName: JournalFile.fileName).save(JournalFile(pages: pages, deleted: deleted))
    }

    func journal() throws -> JournalFile? {
        try JSONFileStore<JournalFile>(folder: lists, fileName: JournalFile.fileName).load()
    }

    /// Every synced file and its content.
    func contents() -> [String: Data] {
        Self.contents(of: FolderStorage(root: root))
    }

    static func contents(of folder: FolderStorage) -> [String: Data] {
        var result: [String: Data] = [:]
        for path in folder.listNow().keys {
            result[path] = try? folder.readNow(path)
        }
        return result
    }
}

/// An "iCloud" whose files can be not downloaded yet, or have conflict versions.
final class TestCloud: SyncStorage, @unchecked Sendable {
    let folder: FolderStorage
    private let lock = NSLock()
    private var notDownloaded: Set<String> = []
    private var conflicts: [String: [Data]] = [:]
    private(set) var downloadRequests: Set<String> = []
    private(set) var resolved: Set<String> = []

    init(root: URL) {
        folder = FolderStorage(root: root)
    }

    func hide(_ path: String) { lock.withLock { _ = notDownloaded.insert(path) } }
    func arrive(_ path: String) { lock.withLock { _ = notDownloaded.remove(path) } }
    func addConflict(_ data: Data, for path: String) { lock.withLock { conflicts[path, default: []].append(data) } }

    func list() async throws -> [String: StoredItem] {
        var items = folder.listNow()
        lock.withLock {
            for path in notDownloaded where items[path] != nil {
                items[path] = .notDownloaded
            }
            for path in conflicts.keys where items[path] != nil {
                items[path] = .conflicted
            }
        }
        return items
    }

    func read(_ path: String) async throws -> Data? { try folder.readNow(path) }
    func write(_ data: Data, to path: String) async throws { try await folder.write(data, to: path) }
    func delete(_ path: String) async throws { try await folder.delete(path) }

    func startDownloading(_ path: String) async throws {
        lock.withLock { _ = downloadRequests.insert(path) }
    }

    func conflictVersions(of path: String) async throws -> [Data] {
        lock.withLock { conflicts[path] ?? [] }
    }

    func resolveConflicts(of path: String) async throws {
        lock.withLock {
            conflicts[path] = nil
            _ = resolved.insert(path)
        }
    }
}

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "SyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private let month = "Pages/month-2026-11.dcpage"
private let year = "Pages/year-2026.dcpage"
private let toBuy = "Lists/tobuy.json"

// MARK: - Tests

@Suite("Syncing two devices through iCloud")
struct SyncEngineTests {
    @Test func theFirstSyncMergesBothDevicesWithoutLossOrDuplicates() async throws {
        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let cloud = FolderStorage(root: base.appending(path: "cloud"))
        let ipad = TestDevice(cloud: cloud, base: base, name: "ipad")
        let iphone = TestDevice(cloud: cloud, base: base, name: "iphone")

        // Both used the app before iCloud: each has its own pages and lists.
        try ipad.write("a1\na2", to: month)
        try ipad.write("y1", to: year)
        let milk = ListItem(text: "Milk", line: 1, created: Date(timeIntervalSince1970: 1_900_000_000))
        try ipad.save(toBuy: [milk])
        try ipad.write(BirthdayFile(birthdays: [Birthday(name: "Manos", month: 11, day: 13)]).encoded(), to: "Lists/birthdays.json")

        try iphone.write("b1\na1", to: month)
        let bread = ListItem(text: "Bread", line: 2, created: Date(timeIntervalSince1970: 1_900_000_100))
        try iphone.save(toBuy: [bread])
        let photo = WishlistPhoto(width: 4, height: 3)
        try iphone.write(Data([0xFF, 0xD8, 1, 2, 3]), to: "Wishlist/\(photo.fileName)")
        try JSONFileStore<WishlistFile>(folder: iphone.lists, fileName: WishlistFile.fileName).save(WishlistFile(photos: [photo]))

        let first = await ipad.engine.syncAll()
        #expect(first.pushed == 4)
        #expect(first.failed == 0)
        let second = await iphone.engine.syncAll()
        #expect(second.failed == 0)
        let third = await ipad.engine.syncAll()
        #expect(third.failed == 0)

        // Everything is everywhere, the same.
        let cloudFiles = TestDevice.contents(of: cloud)
        #expect(ipad.contents() == cloudFiles)
        #expect(iphone.contents() == cloudFiles)
        #expect(Set(cloudFiles.keys) == [month, year, toBuy, "Lists/birthdays.json", "Lists/wishlist.json", "Wishlist/\(photo.fileName)"])
        // Strokes of both pages, each once; items of both lists, each once.
        #expect(TestOwner.lines(cloudFiles[month] ?? Data()).sorted() == ["a1", "a2", "b1"])
        #expect(try ipad.toBuy()?.items.map(\.text) == ["Milk", "Bread"])

        // Nothing more to do on either device.
        #expect(await ipad.engine.syncAll().changes == 0)
        #expect(await iphone.engine.syncAll().changes == 0)
    }

    @Test func changesAndDeletionsTravel() async throws {
        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let cloud = FolderStorage(root: base.appending(path: "cloud"))
        let ipad = TestDevice(cloud: cloud, base: base, name: "ipad")
        let iphone = TestDevice(cloud: cloud, base: base, name: "iphone")
        let milk = ListItem(text: "Milk", line: 1, created: Date(timeIntervalSince1970: 1_900_000_000))
        let bread = ListItem(text: "Bread", line: 2, created: Date(timeIntervalSince1970: 1_900_000_001))
        try ipad.write("a1\na2\na3", to: month)
        try ipad.save(toBuy: [milk, bread])
        _ = await ipad.engine.syncAll()
        _ = await iphone.engine.syncAll()
        #expect(iphone.text(month) == "a1\na2\na3")

        // Erasing on the iPad: the stroke goes on the iPhone too (not merged back).
        try ipad.write("a1\na3", to: month)
        let sent = await ipad.engine.sync([month])
        #expect(sent.pushed == 1)
        let received = await iphone.engine.sync([month])
        #expect(received.pulled == 1)
        #expect(iphone.text(month) == "a1\na3")

        // Deleting an item on the iPhone: it goes on the iPad too.
        try iphone.save(toBuy: [milk], deleted: [Tombstone(id: bread.id, deleted: Date(timeIntervalSince1970: 1_900_000_500))])
        _ = await iphone.engine.sync([toBuy])
        _ = await ipad.engine.syncAll()
        #expect(try ipad.toBuy()?.items.map(\.text) == ["Milk"])

        // A journal page from the iPad, deleted on the iPhone: its ink goes from iCloud and the iPad.
        let page = JournalPage(title: "Ideas", date: nil, created: Date(timeIntervalSince1970: 1_900_000_000))
        let pagePath = SyncPath(page: .journal(page.id)).path
        try ipad.save(journal: [page])
        try ipad.write("j1", to: pagePath)
        _ = await ipad.engine.syncAll()
        _ = await iphone.engine.syncAll()
        #expect(iphone.text(pagePath) == "j1")
        try iphone.save(journal: [], deleted: [Tombstone(id: page.id, deleted: Date(timeIntervalSince1970: 1_900_000_600))])
        try FileManager.default.removeItem(at: iphone.root.appending(path: pagePath))
        let deleted = await iphone.engine.syncAll()
        #expect(deleted.deleted == 1)
        #expect(!FileManager.default.fileExists(atPath: cloud.url(of: pagePath).path(percentEncoded: false)))
        _ = await ipad.engine.syncAll()
        #expect(!ipad.exists(pagePath))
        #expect(try ipad.journal()?.pages.isEmpty == true)
        #expect(await ipad.engine.syncAll().changes == 0)
        #expect(await iphone.engine.syncAll().changes == 0)
    }

    @Test func changesOnBothDevicesAreBothKept() async throws {
        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let cloud = FolderStorage(root: base.appending(path: "cloud"))
        let ipad = TestDevice(cloud: cloud, base: base, name: "ipad")
        let mac = TestDevice(cloud: cloud, base: base, name: "mac")
        try ipad.write("a1", to: month)
        _ = await ipad.engine.syncAll()
        _ = await mac.engine.syncAll()

        // Both write on the same page while apart.
        try ipad.write("a1\nipad", to: month)
        try mac.write("a1\nmac", to: month)
        _ = await ipad.engine.syncAll()
        let merged = await mac.engine.syncAll()
        #expect(merged.merged == 1)
        _ = await ipad.engine.syncAll()
        #expect(TestOwner.lines(Data((ipad.text(month) ?? "").utf8)).sorted() == ["a1", "ipad", "mac"])
        #expect(ipad.text(month) == mac.text(month))
    }

    @Test func filesNotOnThisDeviceYetAreAskedForThenTaken() async throws {
        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let cloud = TestCloud(root: base.appending(path: "cloud"))
        let ipad = TestDevice(cloud: cloud, base: base, name: "ipad")
        let iphone = TestDevice(cloud: cloud, base: base, name: "iphone")
        try ipad.write("a1", to: month)
        _ = await ipad.engine.syncAll()

        cloud.hide(month)
        let waiting = await iphone.engine.syncAll()
        #expect(waiting.downloading == [month])
        #expect(cloud.downloadRequests == [month])
        #expect(!iphone.exists(month))

        cloud.arrive(month)
        let arrived = await iphone.engine.sync([month])
        #expect(arrived.pulled == 1)
        #expect(arrived.inSync.contains(month))
        #expect(iphone.text(month) == "a1")
    }

    @Test func conflictVersionsAreMergedAndResolved() async throws {
        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let cloud = TestCloud(root: base.appending(path: "cloud"))
        let ipad = TestDevice(cloud: cloud, base: base, name: "ipad")
        let milk = ListItem(text: "Milk", line: 1, created: Date(timeIntervalSince1970: 1_900_000_000))
        try ipad.save(toBuy: [milk])
        _ = await ipad.engine.syncAll()

        // Two other devices wrote the list at the same time: iCloud kept both.
        let eggs = ListItem(text: "Eggs", line: 2, created: Date(timeIntervalSince1970: 1_900_000_010))
        let tea = ListItem(text: "Tea", line: 3, created: Date(timeIntervalSince1970: 1_900_000_020))
        try await cloud.write(JSONFileStore<ListFile>.encode(ListFile(items: [milk, eggs])), to: toBuy)
        cloud.addConflict(try JSONFileStore<ListFile>.encode(ListFile(items: [milk, tea])), for: toBuy)

        let report = await ipad.engine.syncAll()
        #expect(report.conflicts == 1)
        #expect(cloud.resolved == [toBuy])
        #expect(try ipad.toBuy()?.items.map(\.text) == ["Milk", "Eggs", "Tea"])
        #expect(try cloud.folder.readNow(toBuy) == ipad.contents()[toBuy])
    }

    @Test func anotherAccountStartsAFirstSyncAgain() async throws {
        let base = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: base) }
        let cloud = FolderStorage(root: base.appending(path: "cloud"))
        let ipad = TestDevice(cloud: cloud, base: base, name: "ipad")
        try ipad.write("a1", to: month)
        _ = await ipad.engine.syncAll()
        #expect(await ipad.engine.syncedCount() == 1)

        // Another account's iCloud is empty: this device's files are sent there, nothing is deleted here.
        let other = FolderStorage(root: base.appending(path: "other-cloud"))
        let engine = SyncEngine(
            local: FolderStorage(root: ipad.root), cloud: other, owner: TestOwner(root: ipad.root),
            stateStore: JSONFileStore(folder: base.appending(path: "ipad-sync"), fileName: SyncState.fileName),
            account: "another-account", log: { _, _ in }
        )
        let report = await engine.syncAll()
        #expect(report.pushed == 1)
        #expect(ipad.text(month) == "a1")
        #expect(try other.readNow(month) == Data("a1".utf8))
    }
}

@Suite("Sync decisions")
struct SyncPlannerTests {
    private let page = SyncPath(page: .month(YearMonth(year: 2026, month: 11)))
    private let journalPage = SyncPath(page: .journal(UUID()))

    @Test func oneSideChanged() {
        #expect(SyncPlanner.action(for: page, local: "new", remote: .present("old"), synced: "old") == .push)
        #expect(SyncPlanner.action(for: page, local: "old", remote: .present("new"), synced: "old") == .pull)
        #expect(SyncPlanner.action(for: page, local: "a", remote: .present("b"), synced: "old") == .merge)
        #expect(SyncPlanner.action(for: page, local: "a", remote: .present("b"), synced: nil) == .merge)
        #expect(SyncPlanner.action(for: page, local: "same", remote: .present("same"), synced: "same") == .nothing)
        #expect(SyncPlanner.action(for: page, local: "same", remote: .present("same"), synced: nil) == .record("same"))
    }

    @Test func missingOnOneSide() {
        #expect(SyncPlanner.action(for: page, local: "a", remote: .missing, synced: nil) == .push)
        #expect(SyncPlanner.action(for: page, local: nil, remote: .present("a"), synced: nil) == .pull)
        // A month page is never deleted on purpose: copied back.
        #expect(SyncPlanner.action(for: page, local: "a", remote: .missing, synced: "a") == .push)
        #expect(SyncPlanner.action(for: page, local: nil, remote: .present("a"), synced: "a") == .pull)
        // A journal page deleted on one side waits for its list (then both copies go)…
        #expect(SyncPlanner.action(for: journalPage, local: "a", remote: .missing, synced: "a") == .nothing)
        #expect(SyncPlanner.action(for: journalPage, local: nil, remote: .present("a"), synced: "a") == .nothing)
        // …unless it was written on since: then nothing written is lost.
        #expect(SyncPlanner.action(for: journalPage, local: "b", remote: .missing, synced: "a") == .push)
        #expect(SyncPlanner.action(for: journalPage, local: nil, remote: .present("b"), synced: "a") == .pull)
        #expect(SyncPlanner.action(for: page, local: nil, remote: .missing, synced: "a") == .forget)
        #expect(SyncPlanner.action(for: page, local: nil, remote: .missing, synced: nil) == .nothing)
    }

    @Test func iCloudStates() {
        #expect(SyncPlanner.action(for: page, local: "a", remote: .notDownloaded, synced: "a") == .download)
        #expect(SyncPlanner.action(for: page, local: nil, remote: .conflicted, synced: nil) == .resolveConflicts)
    }

    @Test func paths() throws {
        let id = try #require(UUID(uuidString: "1E2D3C4B-5A69-4788-9900-AABBCCDDEEFF"))
        #expect(SyncPath("Pages/month-2026-11.dcpage")?.kind == .page(.month(YearMonth(year: 2026, month: 11))))
        #expect(SyncPath("Pages/journal-1e2d3c4b-5a69-4788-9900-aabbccddeeff.dcpage")?.kind == .page(.journal(id)))
        #expect(SyncPath("Pages/journal-1E2D3C4B-5A69-4788-9900-AABBCCDDEEFF.dcpage") == nil, "one name per page")
        #expect(SyncPath("Pages/month-2026-11.dcpage.unreadable-1800000000") == nil)
        #expect(SyncPath("Lists/todo.json")?.kind == .list("todo.json"))
        #expect(SyncPath("Lists/state.json") == nil)
        #expect(SyncPath("Wishlist/1E2D3C4B-5A69-4788-9900-AABBCCDDEEFF.jpg")?.kind == .photo(id))
        #expect(SyncPath(photo: id).path == "Wishlist/1E2D3C4B-5A69-4788-9900-AABBCCDDEEFF.jpg")
        #expect(SyncPath("Diagnostics/DanaisCalendar-log.txt") == nil)
        #expect(SyncPath("../Pages/year-2026.dcpage") == nil)
        #expect(SyncPath("Pages/x/year-2026.dcpage") == nil)
        let sorted = [SyncPath(photo: id), SyncPath(page: .year(2026)), SyncPath(list: "todo.json")].sorted().map(\.rank)
        #expect(sorted == [0, 1, 2])
    }
}

@Suite("Backup file")
struct BackupArchiveTests {
    @Test func collectsEverySyncedFileAndRoundTrips() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = FolderStorage(root: root)
        let files: [String: Data] = [
            month: Data("ink".utf8),
            toBuy: Data(#"{"version": 1, "items": []}"#.utf8),
            "Wishlist/1E2D3C4B-5A69-4788-9900-AABBCCDDEEFF.jpg": Data((0..<5000).map { UInt8(truncatingIfNeeded: $0) }),
        ]
        for (path, data) in files {
            let url = folder.url(of: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        // Not part of a backup: the log, the sync state, set-aside files.
        for other in ["Diagnostics/DanaisCalendar-log.txt", "Sync/state.json", "Pages/month-2026-11.dcpage.unreadable-1"] {
            let url = root.appending(path: other)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }

        let archive = try BackupArchive.collect(from: root, created: Date(timeIntervalSince1970: 1_900_000_000), writtenBy: "0.1.0 (7)")
        #expect(Set(archive.entries.map(\.path)) == Set(files.keys))
        let data = try archive.encoded()
        #expect(Array(data.prefix(4)) == Array("DCBK".utf8))
        let decoded = try BackupArchive(decoding: data)
        #expect(decoded == archive)
        for entry in decoded.entries {
            #expect(entry.data == files[entry.path])
        }
    }

    @Test func refusesOtherFiles() throws {
        #expect(throws: BackupError.notABackup) { try BackupArchive(decoding: Data("hello".utf8)) }
        let archive = BackupArchive(created: Date(timeIntervalSince1970: 0), writtenBy: "x", entries: [BackupArchive.Entry(path: month, data: Data("abc".utf8))])
        var data = try archive.encoded()
        #expect(throws: BackupError.truncated) { try BackupArchive(decoding: data.dropLast(1)) }
        data[4] = 9
        #expect(throws: BackupError.unsupportedVersion(9)) { try BackupArchive(decoding: data) }
        let bad = BackupArchive(created: Date(timeIntervalSince1970: 0), writtenBy: "x", entries: [BackupArchive.Entry(path: "../secret", data: Data())])
        #expect(throws: BackupError.badPath("../secret")) { try BackupArchive(decoding: try bad.encoded()) }
    }
}
