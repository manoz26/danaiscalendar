import Foundation

/// Where the birthdays live: one small JSON file. Today a local folder
/// (`LocalBirthdayStore`); later the iCloud Documents container (prompt 7).
public protocol BirthdayStore: Sendable {
    /// Every saved birthday; empty if none was ever saved.
    func load() throws -> [Birthday]
    /// Replaces the file in one step: a crash leaves either the old or the new file.
    func save(_ birthdays: [Birthday]) throws
    /// Moves an unreadable file out of the way (kept, never deleted). Returns where it went.
    @discardableResult
    func setAside() throws -> URL?
}

/// The birthdays file: `{"version": 1, "birthdays": [{"id", "name", "month", "day"}]}`.
public struct BirthdayFile: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var birthdays: [Birthday]

    public init(birthdays: [Birthday]) {
        version = Self.currentVersion
        self.birthdays = birthdays
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return try encoder.encode(self)
    }

    public init(decoding data: Data) throws {
        let file: BirthdayFile
        do {
            file = try JSONDecoder().decode(BirthdayFile.self, from: data)
        } catch {
            throw BirthdayFileError.unreadable(String(describing: error))
        }
        guard file.version <= Self.currentVersion else {
            throw BirthdayFileError.unsupportedVersion(file.version)
        }
        self = file
    }
}

public enum BirthdayFileError: Error, Equatable, Sendable {
    case unreadable(String)
    /// Written by a newer version of the app.
    case unsupportedVersion(Int)
}

/// The birthdays in a folder on this device (`birthdays.json`).
public final class LocalBirthdayStore: BirthdayStore {
    public static let fileName = "birthdays.json"

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public var url: URL {
        folder.appending(path: Self.fileName)
    }

    public func load() throws -> [Birthday] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        return try BirthdayFile(decoding: data).birthdays
    }

    public func save(_ birthdays: [Birthday]) throws {
        let data = try BirthdayFile(birthdays: birthdays).encoded()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Written to a temporary file next to it, then renamed over the old one.
        try data.write(to: url, options: .atomic)
    }

    @discardableResult
    public func setAside() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        var target = folder.appending(path: "\(Self.fileName).unreadable-\(stamp)")
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            target = folder.appending(path: "\(Self.fileName).unreadable-\(stamp)-\(UUID().uuidString)")
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
