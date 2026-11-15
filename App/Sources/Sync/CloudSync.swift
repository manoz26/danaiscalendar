import Foundation
import Observation
import PlannerCore
import UIKit

/// "A file of the app was saved here": the sync sends it to iCloud a moment later.
/// Posted from any thread (the savers' queues).
enum LocalChanges {
    static let notification = Notification.Name("DCLocalFileChanged")

    /// `path`: the synced file's path, e.g. `Pages/month-2026-11.dcpage` (see `SyncPath`).
    static func post(_ path: String) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: ["path": path])
    }
}

/// iCloud sync (prompt 7): the same pages, lists and photos on the iPad and the iPhone,
/// through the app's iCloud Documents folder. Local-first: the app keeps writing its own
/// files, and this exchanges them with iCloud (`SyncEngine`) at launch, a moment after
/// every save, and whenever iCloud says something changed (`NSMetadataQuery`). Without
/// iCloud (not signed in, iCloud Drive off for the app), nothing changes: everything stays
/// on the device.
///
/// Everything it does goes to the Diagnostics log (file names and counts, never content).
@MainActor
@Observable
final class CloudSync {
    enum Status: Equatable {
        /// Not signed in to iCloud, or iCloud Drive is off.
        case off
        /// Signed in, but the app's iCloud folder cannot be reached.
        case unavailable
        case starting
        case syncing
        case upToDate
        /// Some files did not sync in the last round (tried again later).
        case problem
    }

    private(set) var status: Status = .starting
    private(set) var lastSync: Date?
    /// Files in iCloud that are not on this device yet.
    private(set) var downloading: Set<String> = []
    /// Counts since launch, for the UI tests ("debug.sync", Debug builds only).
    private(set) var debugSummary = "-"
    @ObservationIgnored private var debugTotal = SyncReport()

    @ObservationIgnored let owner: AppSyncOwner
    @ObservationIgnored private var engine: SyncEngine?
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var queryObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var gathered = false
    @ObservationIgnored private var changed: Set<String> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var running = 0
    @ObservationIgnored private var lastFullSync = Date.distantPast
    @ObservationIgnored private var generation = 0

    /// What this device remembers about the sync (never synced).
    nonisolated static var stateFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Sync", directoryHint: .isDirectory)
    }

    /// The app's folder inside its iCloud container.
    nonisolated static let folderName = "Planner"

    init(owner: AppSyncOwner) {
        self.owner = owner
        let center = NotificationCenter.default
        _ = center.addObserver(forName: LocalChanges.notification, object: nil, queue: .main) { [weak self] note in
            let path = note.userInfo?["path"] as? String
            MainActor.assumeIsolated {
                if let path { self?.localChanged(path) }
            }
        }
        _ = center.addObserver(forName: .NSUbiquityIdentityDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLog.info("iCloud: the iCloud account changed")
                self?.restart()
            }
        }
    }

    // MARK: - Starting

    /// At launch: looks for iCloud, and if it is there starts syncing.
    func start() {
        generation += 1
        #if DEBUG
        if LaunchOptions.fakeCloud {
            startFakeCloud()
            return
        }
        #endif
        guard let token = FileManager.default.ubiquityIdentityToken else {
            status = .off
            AppLog.info("iCloud: not signed in, or iCloud Drive is off; everything stays on this device")
            return
        }
        let account = Self.accountID(token)
        status = .starting
        let container = AppInfo.iCloudContainer
        let started = generation
        Task {
            // Can take a while the first time: never on the main thread.
            let url = await Task.detached(priority: .utility) {
                FileManager.default.url(forUbiquityContainerIdentifier: container)
            }.value
            guard started == self.generation else { return }
            guard let url else {
                self.status = .unavailable
                AppLog.error("iCloud: the app's iCloud folder is unavailable (\(container)); everything stays on this device")
                return
            }
            self.connect(cloud: CloudFolder(root: url.appending(path: Self.folderName, directoryHint: .isDirectory)), account: account)
            self.watchICloud()
        }
    }

    private func restart() {
        stopWatching()
        engine = nil
        downloading = []
        start()
    }

    private func connect(cloud: any SyncStorage, account: String) {
        engine = SyncEngine(
            local: FolderStorage(root: .applicationSupportDirectory), cloud: cloud, owner: owner,
            stateStore: JSONFileStore(folder: Self.stateFolder, fileName: SyncState.fileName),
            account: account, log: Self.log
        )
        AppLog.info("iCloud: connected")
    }

    private nonisolated static let log: SyncEngine.Log = { isError, message in
        if isError {
            AppLog.error(message)
        } else {
            AppLog.info(message)
        }
    }

    /// A short, stable name for the iCloud account (a hash of its token; the account itself is never known).
    private static func accountID(_ token: any NSCoding & NSCopying & NSObjectProtocol) -> String {
        let data = (try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true))
            ?? (try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false))
            ?? Data(String(describing: token).utf8)
        return String(ContentHash.of(data).prefix(16))
    }

    // MARK: - Watching iCloud

    /// iCloud's list of the app's files: when it is ready the first full sync runs, and every
    /// change in it (a file from another device, a download that finished) syncs that file.
    private func watchICloud() {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K LIKE %@", NSMetadataItemFSNameKey, "*")
        let center = NotificationCenter.default
        queryObservers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.queryGathered() }
        })
        queryObservers.append(center.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let paths = CloudSync.paths(in: note)
            MainActor.assumeIsolated { self?.remoteChanged(paths) }
        })
        self.query = query
        if !query.start() {
            AppLog.error("iCloud: could not watch iCloud for changes")
        }
        // If iCloud's list never comes (e.g. offline), sync what is here anyway.
        let started = generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard let self, started == self.generation, !self.gathered else { return }
            AppLog.warning("iCloud: no list of files from iCloud after 20 s; syncing anyway")
            self.gathered = true
            self.syncAll()
        }
    }

    private func stopWatching() {
        query?.stop()
        query = nil
        for observer in queryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        queryObservers = []
        gathered = false
    }

    private func queryGathered() {
        guard !gathered else { return }
        gathered = true
        AppLog.info("iCloud: \(query?.resultCount ?? 0) files in iCloud")
        syncAll()
    }

    /// The synced files a change of iCloud's list is about.
    nonisolated static func paths(in note: Notification) -> Set<String> {
        var paths: Set<String> = []
        let keys = [NSMetadataQueryUpdateAddedItemsKey, NSMetadataQueryUpdateChangedItemsKey, NSMetadataQueryUpdateRemovedItemsKey]
        for key in keys {
            for item in note.userInfo?[key] as? [NSMetadataItem] ?? [] {
                if let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL, let path = Self.path(of: url) {
                    paths.insert(path)
                }
            }
        }
        return paths
    }

    /// `…/Planner/Pages/month-2026-11.dcpage` (or its `.month-2026-11.dcpage.icloud`) → `Pages/month-2026-11.dcpage`.
    nonisolated static func path(of url: URL) -> String? {
        let components = url.pathComponents
        guard components.count >= 2 else { return nil }
        var name = components[components.count - 1]
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            name = String(name.dropFirst().dropLast(".icloud".count))
        }
        let path = "\(components[components.count - 2])/\(name)"
        return SyncPath(path) == nil ? nil : path
    }

    // MARK: - Syncing

    /// Everything, now.
    func syncAll() {
        guard let engine else { return }
        lastFullSync = Date()
        run { await engine.syncAll() }
    }

    /// The app is active again: a full sync if the last one is a while ago, and iCloud is
    /// looked for again if it was off (she may have signed in meanwhile).
    func becameActive() {
        if engine == nil {
            if status == .off || status == .unavailable {
                start()
            }
            return
        }
        if Date().timeIntervalSince(lastFullSync) > 5 * 60 {
            syncAll()
        }
    }

    /// Whether a page is in iCloud but not on this device yet (the page shows it).
    func isDownloading(_ page: PlannerPage) -> Bool {
        downloading.contains(SyncPath(page: page).path)
    }

    private func localChanged(_ path: String) {
        guard engine != nil else { return }
        changed.insert(path)
        scheduleFlush(after: 2)
    }

    private func remoteChanged(_ paths: Set<String>) {
        guard engine != nil, gathered, !paths.isEmpty else { return }
        changed.formUnion(paths)
        scheduleFlush(after: 1)
    }

    private func scheduleFlush(after seconds: Double) {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.flush()
        }
    }

    private func flush() {
        flushTask = nil
        let paths = changed
        changed = []
        guard !paths.isEmpty, let engine else { return }
        run { await engine.sync(paths) }
    }

    private func run(_ work: @escaping @Sendable () async -> SyncReport) {
        running += 1
        if status != .syncing {
            status = .syncing
        }
        Task { [weak self] in
            let report = await work()
            self?.finished(report)
        }
    }

    private func finished(_ report: SyncReport) {
        running -= 1
        let pending = downloading.subtracting(report.inSync).union(report.downloading)
        if pending != downloading {
            downloading = pending
        }
        lastSync = Date()
        if report.changes > 0 || report.failed > 0 || !report.downloading.isEmpty {
            AppLog.info("iCloud: \(report.summary)")
        }
        let next: Status = running > 0 ? .syncing : (report.failed > 0 ? .problem : .upToDate)
        if status != next {
            status = next
        }
        #if DEBUG
        debugTotal.add(report)
        debugSummary = "received \(debugTotal.pulled) sent \(debugTotal.pushed) merged \(debugTotal.merged) failed \(debugTotal.failed)"
        #endif
        // Files still on their way, or a failure: looked at again a little later (iCloud
        // also says when a download finishes).
        if (!downloading.isEmpty || report.failed > 0), retryTask == nil {
            retryTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.retryTask = nil
                if report.failed > 0 {
                    self.syncAll()
                } else {
                    self.remoteChanged(self.downloading)
                }
            }
        }
    }

    // MARK: - Backup

    /// Settings → Backup → Export: everything saved first, then one file with all the data.
    func exportBackup() async throws -> URL {
        owner.saveEverything()
        let writtenBy = AppInfo.versionAndBuild
        return try await Task.detached(priority: .userInitiated) {
            let archive = try BackupArchive.collect(from: .applicationSupportDirectory, writtenBy: writtenBy)
            let data = try archive.encoded()
            let folder = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: folder)
            let unique = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: unique, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            let url = unique.appending(path: "Danai's Calendar \(formatter.string(from: Date())).\(BackupArchive.fileExtension)")
            try data.write(to: url, options: .atomic)
            AppLog.info("Backup made: \(archive.entries.count) files, \(data.count / 1024) KB")
            return url
        }.value
    }

    /// Settings → Backup → Restore: what the backup has comes back; nothing here is deleted.
    /// Returns how many files it had.
    func restoreBackup(from url: URL) async throws -> Int {
        let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            return try Data(contentsOf: url)
        }.value
        let archive = try BackupArchive(decoding: data)
        AppLog.info("Restoring a backup of \(archive.entries.count) files (made by \(archive.writtenBy))")
        let failed = await owner.restore(archive)
        AppLog.info("Backup restored (\(failed) files could not be read)")
        return archive.entries.count
    }

    // MARK: - Fake iCloud for the UI tests

    #if DEBUG
    /// `-DCFakeCloud YES`: a plain folder plays iCloud (`LaunchOptions.fakeCloudFolder`);
    /// `-DCSampleCloud YES` puts another device's files there first.
    private func startFakeCloud() {
        let root = LaunchOptions.fakeCloudFolder
        if LaunchOptions.sampleCloud {
            SampleCloud.seed(root)
        }
        connect(cloud: FolderStorage(root: root), account: "fake")
        AppLog.info("iCloud: a folder plays iCloud (UI tests)")
        gathered = true
        syncAll()
    }
    #endif
}

// MARK: - The app's side of the sync

enum SyncOwnerError: Error {
    case unknownFile(String)
}

/// What owns each synced file on this device: the writing engine (pages), the books of
/// the lists, the wishlist. The sync hands them the other devices' versions.
struct AppSyncOwner: SyncOwner {
    let ink: InkController
    let birthdays: BirthdayBook
    let journal: JournalBook
    let sketches: SketchBook
    let lists: ListBook
    let wishlist: WishlistBook

    func receive(_ data: Data, for path: SyncPath, replacing: String?) async throws -> Data {
        try await receiveOnMain(data, path, replacing)
    }

    func deletedPaths() async -> Set<String> {
        await deletedOnMain()
    }

    func removeLocal(_ path: SyncPath) async -> Bool {
        await removeOnMain(path)
    }

    @MainActor
    private func receiveOnMain(_ data: Data, _ path: SyncPath, _ replacing: String?) async throws -> Data {
        switch path.kind {
        case .page(let page):
            return try await ink.receivePage(data, for: page, replacing: replacing)
        case .photo(let id):
            return try wishlist.receivePhoto(data, id: id)
        case .list(let name):
            switch name {
            case JournalFile.fileName: return try journal.receive(data)
            case SketchFile.fileName: return try sketches.receive(data)
            case ListFile.todoFileName, ListFile.toBuyFileName: return try lists.receive(data, fileName: name)
            case WishlistFile.fileName: return try wishlist.receive(data)
            case LocalBirthdayStore.fileName: return try birthdays.receive(data)
            default: throw SyncOwnerError.unknownFile(name)
            }
        }
    }

    @MainActor
    private func deletedOnMain() -> Set<String> {
        var paths: Set<String> = []
        for id in journal.deletedPageIDs {
            paths.insert(SyncPath(page: .journal(id)).path)
        }
        for id in sketches.deletedSketchIDs {
            paths.insert(SyncPath(page: .sketch(id)).path)
        }
        for id in wishlist.deletedPhotoIDs {
            paths.insert(SyncPath(photo: id).path)
        }
        return paths
    }

    @MainActor
    private func removeOnMain(_ path: SyncPath) -> Bool {
        switch path.kind {
        case .page(let page):
            return ink.forgetIfNotOpen(page)
        case .photo(let id):
            wishlist.removeLocalPhoto(id)
            return true
        case .list:
            return false
        }
    }

    /// Everything not saved yet goes to disk now (before a backup).
    @MainActor
    func saveEverything() {
        ink.saveEverything()
        birthdays.waitUntilSaved()
        journal.waitUntilSaved()
        sketches.waitUntilSaved()
        lists.waitUntilSaved()
        wishlist.waitUntilSaved()
    }

    /// A backup brought back: photos first (so that their list shows them), then the lists
    /// (what is missing here comes back), then the pages (strokes of both kept). Returns how
    /// many files could not be read.
    @MainActor
    func restore(_ archive: BackupArchive) async -> Int {
        let entries = archive.entries.compactMap { entry in SyncPath(entry.path).map { ($0, entry.data) } }
            .sorted { a, b in
                // Photos, lists, pages.
                let rank = { (path: SyncPath) -> Int in path.rank == 2 ? 0 : path.rank + 1 }
                return rank(a.0) != rank(b.0) ? rank(a.0) < rank(b.0) : a.0.path < b.0.path
            }
        var failed = 0
        for (path, data) in entries {
            do {
                switch path.kind {
                case .photo(let id):
                    _ = try wishlist.receivePhoto(data, id: id)
                    LocalChanges.post(path.path)
                case .list(let name):
                    switch name {
                    case JournalFile.fileName: try journal.restore(data)
                    case SketchFile.fileName: try sketches.restore(data)
                    case ListFile.todoFileName, ListFile.toBuyFileName: try lists.restore(data, fileName: name)
                    case WishlistFile.fileName: try wishlist.restore(data)
                    case LocalBirthdayStore.fileName: try birthdays.restore(data)
                    default: throw SyncOwnerError.unknownFile(name)
                    }
                case .page(let page):
                    _ = try await ink.receivePage(data, for: page, replacing: nil)
                    LocalChanges.post(path.path)
                }
            } catch {
                failed += 1
                AppLog.error("Backup: could not restore \(path.path)", error)
            }
        }
        return failed
    }
}
