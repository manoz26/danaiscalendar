import Foundation

/// A small JSON file of the app with a version number, e.g. the journal's page list.
public protocol VersionedFile: Codable, Sendable {
    /// The version this app writes. Files with a higher one come from a newer app.
    static var currentVersion: Int { get }
    var version: Int { get }
}

public enum JSONFileError: Error, Equatable, Sendable {
    case unreadable(String)
    /// Written by a newer version of the app.
    case unsupportedVersion(Int)
}

/// One JSON file in a folder on this device (later the iCloud Documents container,
/// prompt 7). Each save replaces the file in one step: a crash leaves either the old or
/// the new file. A file that cannot be read is moved aside, never deleted.
public final class JSONFileStore<File: VersionedFile>: Sendable {
    public let folder: URL
    public let fileName: String

    public init(folder: URL, fileName: String) {
        self.folder = folder
        self.fileName = fileName
    }

    public var url: URL {
        folder.appending(path: fileName)
    }

    /// The saved file, or `nil` if it was never saved.
    public func load() throws -> File? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        let file: File
        do {
            file = try Self.makeDecoder().decode(File.self, from: data)
        } catch {
            throw JSONFileError.unreadable(String(describing: error))
        }
        guard file.version <= File.currentVersion else {
            throw JSONFileError.unsupportedVersion(file.version)
        }
        return file
    }

    public func save(_ file: File) throws {
        let data = try Self.makeEncoder().encode(file)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Written to a temporary file next to it, then renamed over the old one.
        try data.write(to: url, options: .atomic)
    }

    /// Moves an unreadable file out of the way (kept, never deleted). Returns where it went.
    @discardableResult
    public func setAside() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        var target = folder.appending(path: "\(fileName).unreadable-\(stamp)")
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            target = folder.appending(path: "\(fileName).unreadable-\(stamp)-\(UUID().uuidString)")
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
