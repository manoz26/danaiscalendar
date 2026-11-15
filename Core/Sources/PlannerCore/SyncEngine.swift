import Foundation

// MARK: - Synced files

/// A file the app keeps the same on every device (prompt 7): a page, a list, or a photo of
/// the wishlist, by its path inside the data folder (`Pages/month-2026-11.dcpage`,
/// `Lists/todo.json`, `Wishlist/<id>.jpg`). The same paths are used on this device
/// (`Application Support`) and in iCloud.
public struct SyncPath: Hashable, Sendable, Comparable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        case page(PlannerPage)
        /// One of `listNames`.
        case list(String)
        case photo(UUID)
    }

    public static let pagesFolder = "Pages"
    public static let listsFolder = "Lists"
    public static let photosFolder = "Wishlist"
    public static let folders = [listsFolder, pagesFolder, photosFolder]
    public static let listNames: Set<String> = [
        JournalFile.fileName, SketchFile.fileName, ListFile.todoFileName, ListFile.toBuyFileName,
        WishlistFile.fileName, LocalBirthdayStore.fileName,
    ]

    public let path: String
    public let kind: Kind

    /// Only the app's own file names (e.g. a page's name with a lowercase uuid), so a file has one path.
    public init?(_ path: String) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let folder = String(parts[0])
        let name = String(parts[1])
        switch folder {
        case Self.pagesFolder:
            let suffix = ".\(PageFile.fileExtension)"
            guard name.hasSuffix(suffix),
                  let page = PlannerPage(fileStem: String(name.dropLast(suffix.count))),
                  page.fileStem + suffix == name else { return nil }
            kind = .page(page)
        case Self.listsFolder:
            guard Self.listNames.contains(name) else { return nil }
            kind = .list(name)
        case Self.photosFolder:
            guard name.hasSuffix(".jpg"), let id = UUID(uuidString: String(name.dropLast(4))),
                  Self.photoName(id) == name else { return nil }
            kind = .photo(id)
        default:
            return nil
        }
        self.path = path
    }

    public init(page: PlannerPage) {
        path = "\(Self.pagesFolder)/\(page.fileStem).\(PageFile.fileExtension)"
        kind = .page(page)
    }

    public init(photo id: UUID) {
        path = "\(Self.photosFolder)/\(Self.photoName(id))"
        kind = .photo(id)
    }

    /// `name` must be one of `listNames`.
    public init(list name: String) {
        path = "\(Self.listsFolder)/\(name)"
        kind = .list(name)
    }

    private static func photoName(_ id: UUID) -> String {
        WishlistPhoto(id: id, created: Date(timeIntervalSince1970: 0), width: 0, height: 0).fileName
    }

    /// Files that are only ever removed on purpose (a journal page, a sketch, a photo): when
    /// one is missing on one side, its list says whether it was deleted. Other files missing
    /// on one side are copied there again.
    public var isDeletable: Bool {
        switch kind {
        case .page(.journal), .page(.sketch), .photo: true
        case .page, .list: false
        }
    }

    /// Photos never change: two files with the same name are the same photo.
    public var isImmutable: Bool {
        if case .photo = kind { return true }
        return false
    }

    /// Lists first (their deletions decide which pages and photos go), then pages, then photos.
    public var rank: Int {
        switch kind {
        case .list: 0
        case .page: 1
        case .photo: 2
        }
    }

    public static func < (a: SyncPath, b: SyncPath) -> Bool {
        a.rank != b.rank ? a.rank < b.rank : a.path < b.path
    }

    public var description: String { path }
}

// MARK: - The two sides

/// How a file is in a folder.
public enum StoredItem: Sendable, Equatable {
    case present
    /// In iCloud, not on this device yet.
    case notDownloaded
    /// Two devices wrote it at the same time: iCloud kept the other versions too.
    case conflicted
}

/// A folder with the synced files: iCloud (`CloudFolder` in the app), or a plain folder.
public protocol SyncStorage: Sendable {
    /// The synced files there and their state (missing files are not listed).
    func list() async throws -> [String: StoredItem]
    /// `nil` if the file is not there.
    func read(_ path: String) async throws -> Data?
    func write(_ data: Data, to path: String) async throws
    /// Nothing happens if the file is not there.
    func delete(_ path: String) async throws
    /// Asks for a file that is not on this device yet.
    func startDownloading(_ path: String) async throws
    /// The other versions of a conflicted file.
    func conflictVersions(of path: String) async throws -> [Data]
    /// Forgets those versions (after they were merged).
    func resolveConflicts(of path: String) async throws
}

/// The synced files in a plain folder: this device's own data folder (read by the sync;
/// the app writes it), the tests' "iCloud", and the debug fake iCloud of the UI tests.
public final class FolderStorage: SyncStorage {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(of path: String) -> URL {
        root.appending(path: path)
    }

    public func list() async throws -> [String: StoredItem] {
        listNow()
    }

    /// Only the app's own file names (no `.unreadable-…` copies, no temporary files).
    public func listNow() -> [String: StoredItem] {
        var result: [String: StoredItem] = [:]
        for folder in SyncPath.folders {
            let directory = root.appending(path: folder, directoryHint: .isDirectory)
            let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))) ?? []
            for name in names {
                let path = "\(folder)/\(name)"
                if SyncPath(path) != nil {
                    result[path] = .present
                }
            }
        }
        return result
    }

    public func read(_ path: String) async throws -> Data? {
        try readNow(path)
    }

    public func readNow(_ path: String) throws -> Data? {
        do {
            return try Data(contentsOf: url(of: path))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    public func write(_ data: Data, to path: String) async throws {
        let target = url(of: path)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    public func delete(_ path: String) async throws {
        do {
            try FileManager.default.removeItem(at: url(of: path))
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
    }

    public func startDownloading(_ path: String) async throws {}

    public func conflictVersions(of path: String) async throws -> [Data] { [] }

    public func resolveConflicts(of path: String) async throws {}
}

/// The app's side of the sync: what owns each file on this device (the ink of the pages,
/// the books of the lists, the wishlist). The sync never writes this device's files itself.
public protocol SyncOwner: Sendable {
    /// Another version of a file arrives (from another device, an iCloud conflict, or a
    /// backup): the owner takes it into this device's file and returns that file's content
    /// afterwards. `replacing`: the hash of this device's file if nothing changed here since
    /// the last sync; if the file (and anything not saved yet) is still that, the other
    /// version replaces it, so that deletions on the other device happen here too. Otherwise
    /// (and when it is `nil`) both are kept: strokes of both pages, items of both lists.
    func receive(_ data: Data, for path: SyncPath, replacing: String?) async throws -> Data
    /// Files that must go: pages of journal pages and sketches deleted here or on another
    /// device (their lists say so), photos deleted from the wishlist.
    func deletedPaths() async -> Set<String>
    /// Deletes this device's copy of such a file. `false`: not now (e.g. the page is open).
    func removeLocal(_ path: SyncPath) async -> Bool
}

// MARK: - Deciding

/// How a file is in iCloud, for deciding.
public enum RemoteState: Sendable, Equatable {
    case missing
    case notDownloaded
    case conflicted
    /// There, with this hash.
    case present(String)
}

public enum SyncAction: Sendable, Equatable {
    case nothing
    /// Both sides are the same: remember it.
    case record(String)
    /// Gone from both sides: forget it.
    case forget
    /// Only this device changed it: send it.
    case push
    /// Only the other side changed it: take it (replacing this device's file).
    case pull
    /// Both changed it: keep both (the owner merges), and send the result.
    case merge
    case download
    case resolveConflicts
}

public enum SyncPlanner {
    /// What to do with a file, from its hash here (`nil`: not here), its state in iCloud, and
    /// the hash both sides had at the last sync (`nil`: never synced). Nothing is ever lost:
    /// a file missing on one side is only left alone when its list will say it was deleted.
    public static func action(for path: SyncPath, local: String?, remote: RemoteState, synced: String?) -> SyncAction {
        switch remote {
        case .notDownloaded:
            return .download
        case .conflicted:
            return .resolveConflicts
        case .missing:
            guard let local else { return synced == nil ? .nothing : .forget }
            // Deleted on purpose on the other device (its list will say so), and not changed here since.
            if let synced, path.isDeletable, local == synced { return .nothing }
            return .push
        case .present(let remote):
            guard let local else {
                // Deleted on purpose here; the other device's copy goes too (when its list says so).
                if let synced, path.isDeletable, remote == synced { return .nothing }
                return .pull
            }
            if local == remote { return synced == remote ? .nothing : .record(remote) }
            if synced == remote { return .push }
            if synced == local { return .pull }
            return .merge
        }
    }
}

// MARK: - State

/// What this device remembers about the sync (`Application Support/Sync/state.json`, never synced).
public struct SyncState: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "state.json"

    public var version: Int
    /// Which iCloud account it belongs to (a hash of the account's token).
    public var account: String?
    /// For each file, the hash both sides had at the last sync.
    public var synced: [String: String]

    public init(account: String?, synced: [String: String] = [:]) {
        version = Self.currentVersion
        self.account = account
        self.synced = synced
    }
}

/// What one round of syncing did.
public struct SyncReport: Sendable, Equatable {
    public var pushed = 0
    public var pulled = 0
    public var merged = 0
    public var conflicts = 0
    public var deleted = 0
    public var failed = 0
    /// Files in iCloud that are not on this device yet.
    public var downloading: Set<String> = []
    /// Files that are the same on both sides now.
    public var inSync: Set<String> = []

    public init() {}

    public var changes: Int { pushed + pulled + merged + conflicts + deleted }

    public mutating func add(_ other: SyncReport) {
        pushed += other.pushed
        pulled += other.pulled
        merged += other.merged
        conflicts += other.conflicts
        deleted += other.deleted
        failed += other.failed
        downloading = downloading.subtracting(other.inSync).union(other.downloading)
        inSync = inSync.subtracting(other.downloading).union(other.inSync)
    }

    /// For the log: counts only.
    public var summary: String {
        "sent \(pushed), received \(pulled), merged \(merged), conflicts \(conflicts), deleted \(deleted), "
            + "failed \(failed), downloading \(downloading.count)"
    }
}

// MARK: - The engine

/// Keeps this device's files and iCloud's the same (prompt 7). Local-first: the app always
/// reads and writes its own folder, and this exchanges the files with iCloud afterwards, so
/// writing never waits for the network and without iCloud nothing changes.
///
/// For each file it compares this device's copy, iCloud's copy, and what both had at the
/// last sync (`SyncPlanner`): a file changed on one side is copied to the other; a file
/// changed on both is merged by its owner (strokes of both pages, items of both lists).
/// Lists go first: their deletions decide which journal pages, sketches and photos go.
/// One round at a time; changes asked for meanwhile wait for the next round.
public actor SyncEngine {
    public typealias Log = @Sendable (_ isError: Bool, _ message: String) -> Void

    /// Stands for a photo's content: photos never change, so they are never read to compare.
    static let photoHash = "photo"

    let local: FolderStorage
    let cloud: any SyncStorage
    let owner: any SyncOwner
    let stateStore: JSONFileStore<SyncState>
    let account: String
    let log: Log

    private var state: SyncState?
    private var report = SyncReport()
    private var running = false
    private var wantsAll = false
    private var wanted: Set<String> = []
    private var waiting: [CheckedContinuation<SyncReport, Never>] = []

    public init(
        local: FolderStorage, cloud: any SyncStorage, owner: any SyncOwner,
        stateStore: JSONFileStore<SyncState>, account: String, log: @escaping Log
    ) {
        self.local = local
        self.cloud = cloud
        self.owner = owner
        self.stateStore = stateStore
        self.account = account
        self.log = log
    }

    /// Every file (at launch, and when iCloud says it has news).
    public func syncAll() async -> SyncReport {
        wantsAll = true
        return await drain()
    }

    /// Only these files (changed here, or in iCloud).
    public func sync(_ paths: Set<String>) async -> SyncReport {
        wanted.formUnion(paths)
        return await drain()
    }

    /// How many files are known to be the same on both sides.
    public func syncedCount() -> Int {
        loadedState().synced.count
    }

    private func drain() async -> SyncReport {
        if running {
            return await withCheckedContinuation { waiting.append($0) }
        }
        running = true
        var total = SyncReport()
        while wantsAll || !wanted.isEmpty {
            let all = wantsAll
            let paths = wanted
            wantsAll = false
            wanted = []
            total.add(await run(all: all, paths: paths))
        }
        running = false
        let waiters = waiting
        waiting = []
        for waiter in waiters {
            waiter.resume(returning: total)
        }
        return total
    }

    private func loadedState() -> SyncState {
        if let state { return state }
        var loaded: SyncState
        do {
            loaded = try stateStore.load() ?? SyncState(account: nil)
        } catch {
            log(true, "iCloud: could not read the sync state; starting again: \(String(reflecting: error))")
            _ = try? stateStore.setAside()
            loaded = SyncState(account: nil)
        }
        if loaded.account != account {
            log(false, "iCloud: first sync with this iCloud account: this device's files and iCloud's are merged")
            loaded = SyncState(account: account)
        }
        state = loaded
        return loaded
    }

    private func saveState() {
        guard let state else { return }
        do {
            try stateStore.save(state)
        } catch {
            log(true, "iCloud: could not save the sync state: \(String(reflecting: error))")
        }
    }

    private func setSynced(_ path: String, _ hash: String?) {
        var current = loadedState()
        current.synced[path] = hash
        state = current
    }

    private func run(all: Bool, paths: Set<String>) async -> SyncReport {
        report = SyncReport()
        var current = loadedState()
        let localItems = local.listNow()
        let remoteItems: [String: StoredItem]
        do {
            remoteItems = try await cloud.list()
        } catch {
            log(true, "iCloud: could not list the files: \(String(reflecting: error))")
            report.failed += 1
            return report
        }
        if all, !current.synced.isEmpty, remoteItems.isEmpty, !localItems.isEmpty {
            log(false, "iCloud: the iCloud folder is empty; this device's files are sent again")
            current.synced = [:]
            state = current
        }
        let names = all ? Set(localItems.keys).union(remoteItems.keys).union(current.synced.keys) : paths
        let items = names.compactMap { SyncPath($0) }.sorted()

        for item in items where item.rank == 0 {
            await process(item, localItems: localItems, remoteItems: remoteItems)
        }
        let gone = await owner.deletedPaths()
        for path in gone.sorted() {
            let known = loadedState().synced[path] != nil
            if remoteItems[path] != nil || localItems[path] != nil || known {
                await remove(path, here: localItems[path] != nil, there: remoteItems[path] != nil)
            }
        }
        for item in items where item.rank > 0 && !gone.contains(item.path) {
            await process(item, localItems: localItems, remoteItems: remoteItems)
        }
        saveState()
        return report
    }

    private func remove(_ path: String, here: Bool, there: Bool) async {
        do {
            if there {
                try await cloud.delete(path)
            }
            if here, let item = SyncPath(path), await !owner.removeLocal(item) {
                return
            }
            setSynced(path, nil)
            if here || there {
                report.deleted += 1
                log(false, "iCloud: deleted \(path)")
            }
        } catch {
            report.failed += 1
            log(true, "iCloud: could not delete \(path): \(String(reflecting: error))")
        }
    }

    private func process(_ item: SyncPath, localItems: [String: StoredItem], remoteItems: [String: StoredItem]) async {
        let path = item.path
        do {
            let isHere = localItems[path] != nil
            let localData = try (isHere && !item.isImmutable ? local.readNow(path) : nil)
            let localHash: String? = item.isImmutable ? (isHere ? Self.photoHash : nil) : localData.map(ContentHash.of)
            var remoteData: Data?
            let remote: RemoteState
            switch remoteItems[path] {
            case nil:
                remote = .missing
            case .notDownloaded:
                remote = .notDownloaded
            case .conflicted:
                remote = .conflicted
            case .present:
                if item.isImmutable {
                    remote = .present(Self.photoHash)
                } else if let data = try await cloud.read(path) {
                    remoteData = data
                    remote = .present(ContentHash.of(data))
                } else {
                    remote = .missing
                }
            }
            let action = SyncPlanner.action(for: item, local: localHash, remote: remote, synced: loadedState().synced[path])
            switch action {
            case .nothing:
                if let localHash, remote == .present(localHash) {
                    report.inSync.insert(path)
                }
            case .record(let hash):
                setSynced(path, hash)
                report.inSync.insert(path)
            case .forget:
                setSynced(path, nil)
            case .push:
                guard let data = try (item.isImmutable ? local.readNow(path) : localData) else { return }
                try await cloud.write(data, to: path)
                setSynced(path, localHash)
                report.pushed += 1
                report.inSync.insert(path)
                log(false, "iCloud: sent \(path)")
            case .pull, .merge:
                guard let data = try await (item.isImmutable ? cloud.read(path) : remoteData) else { return }
                let result = try await owner.receive(data, for: item, replacing: action == .pull ? localHash : nil)
                let resultHash = item.isImmutable ? Self.photoHash : ContentHash.of(result)
                let remoteHash = item.isImmutable ? Self.photoHash : ContentHash.of(data)
                if resultHash != remoteHash {
                    try await cloud.write(result, to: path)
                    report.pushed += 1
                }
                setSynced(path, resultHash)
                if action == .pull {
                    report.pulled += 1
                } else {
                    report.merged += 1
                }
                report.inSync.insert(path)
                log(false, "iCloud: \(action == .pull ? "received" : "merged") \(path)")
            case .download:
                try await cloud.startDownloading(path)
                report.downloading.insert(path)
            case .resolveConflicts:
                let versions = try await cloud.conflictVersions(of: path)
                if let current = try await cloud.read(path) {
                    var result = try await owner.receive(current, for: item, replacing: nil)
                    for version in versions where !item.isImmutable {
                        result = try await owner.receive(version, for: item, replacing: nil)
                    }
                    if !item.isImmutable {
                        try await cloud.write(result, to: path)
                    }
                    setSynced(path, item.isImmutable ? Self.photoHash : ContentHash.of(result))
                }
                try await cloud.resolveConflicts(of: path)
                report.conflicts += 1
                report.inSync.insert(path)
                log(false, "iCloud: \(versions.count + 1) versions of \(path) merged")
            }
        } catch {
            report.failed += 1
            log(true, "iCloud: could not sync \(path): \(String(reflecting: error))")
        }
    }
}
