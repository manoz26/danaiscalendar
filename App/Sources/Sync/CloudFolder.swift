import Foundation
import PlannerCore

/// The app's folder in its iCloud container (`<container>/Planner`), with the same paths
/// as on the device (`Pages/…`, `Lists/…`, `Wishlist/…`). iCloud Documents, so no CloudKit
/// schema and no server of ours.
///
/// Every read and write is coordinated with iCloud (`NSFileCoordinator`), on a queue of its
/// own (never the main thread). Files that are not on this device yet are listed as such and
/// only asked for (`startDownloadingUbiquitousItem`), never read: a coordinated read would
/// wait for the download.
final class CloudFolder: SyncStorage {
    let root: URL
    private let queue = DispatchQueue(label: "DanaisCalendar.iCloud", qos: .utility)

    init(root: URL) {
        self.root = root
    }

    func list() async throws -> [String: StoredItem] {
        try await run { [root] in
            var result: [String: StoredItem] = [:]
            let keys: [URLResourceKey] = [.ubiquitousItemDownloadingStatusKey, .ubiquitousItemHasUnresolvedConflictsKey]
            for folder in SyncPath.folders {
                let directory = root.appending(path: folder, directoryHint: .isDirectory)
                guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else {
                    continue
                }
                for url in urls {
                    var name = url.lastPathComponent
                    // A file that is not downloaded can show as a hidden ".name.icloud".
                    let placeholder = name.hasPrefix(".") && name.hasSuffix(".icloud")
                    if placeholder {
                        name = String(name.dropFirst().dropLast(".icloud".count))
                    }
                    let path = "\(folder)/\(name)"
                    guard SyncPath(path) != nil else { continue }
                    if placeholder {
                        if result[path] == nil {
                            result[path] = .notDownloaded
                        }
                        continue
                    }
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    if values?.ubiquitousItemHasUnresolvedConflicts == true {
                        result[path] = .conflicted
                    } else if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                        result[path] = .notDownloaded
                    } else {
                        result[path] = .present
                    }
                }
            }
            return result
        }
    }

    func read(_ path: String) async throws -> Data? {
        try await run { [root] in
            try Self.coordinatedRead(root.appending(path: path))
        }
    }

    func write(_ data: Data, to path: String) async throws {
        try await run { [root] in
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.coordinate(writing: url, options: .forReplacing) { target in
                try data.write(to: target, options: .atomic)
            }
        }
    }

    func delete(_ path: String) async throws {
        try await run { [root] in
            let url = root.appending(path: path)
            try Self.coordinate(writing: url, options: .forDeleting) { target in
                do {
                    try FileManager.default.removeItem(at: target)
                } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                    return
                }
            }
        }
    }

    func startDownloading(_ path: String) async throws {
        try await run { [root] in
            try FileManager.default.startDownloadingUbiquitousItem(at: root.appending(path: path))
        }
    }

    func conflictVersions(of path: String) async throws -> [Data] {
        try await run { [root] in
            let url = root.appending(path: path)
            return try (NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []).map { version in
                try Data(contentsOf: version.url)
            }
        }
    }

    func resolveConflicts(of path: String) async throws {
        try await run { [root] in
            let url = root.appending(path: path)
            try Self.coordinate(writing: url, options: []) { target in
                for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: target) ?? [] {
                    version.isResolved = true
                }
                try NSFileVersion.removeOtherVersionsOfItem(at: target)
            }
        }
    }

    // MARK: - Helpers

    private func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private static func coordinatedRead(_ url: URL) throws -> Data? {
        var coordinationError: NSError?
        var result: Result<Data?, any Error> = .success(nil)
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { target in
            do {
                result = .success(try Data(contentsOf: target))
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                result = .success(nil)
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError {
            if coordinationError.domain == NSCocoaErrorDomain,
               coordinationError.code == CocoaError.fileReadNoSuchFile.rawValue || coordinationError.code == CocoaError.fileNoSuchFile.rawValue {
                return nil
            }
            throw coordinationError
        }
        return try result.get()
    }

    private static func coordinate(
        writing url: URL, options: NSFileCoordinator.WritingOptions, _ work: (URL) throws -> Void
    ) throws {
        var coordinationError: NSError?
        var workError: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &coordinationError) { target in
            do {
                try work(target)
            } catch {
                workError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let workError { throw workError }
    }
}
