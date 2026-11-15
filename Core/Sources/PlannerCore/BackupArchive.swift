import Foundation

/// All the user's data in one file (Settings → Backup): every page, list and wishlist photo,
/// as they are in the data folder. Restoring adds back what the backup has and deletes nothing.
///
/// File layout (`Danai's Calendar 2026-11-15.dcbackup`):
/// - 4 bytes: `DCBK`
/// - 1 byte: format version (`formatVersion`)
/// - 4 bytes: length of the JSON manifest, big-endian
/// - the manifest: `{"created", "writtenBy", "entries": [{"path", "size"}]}`
/// - the files, one after another, in the manifest's order.
public struct BackupArchive: Sendable, Equatable {
    public static let fileExtension = "dcbackup"
    public static let formatVersion: UInt8 = 1
    static let signature: [UInt8] = Array("DCBK".utf8)
    static let headerSize = 9

    public struct Entry: Sendable, Equatable {
        /// A synced file's path, e.g. `Pages/month-2026-11.dcpage` (see `SyncPath`).
        public var path: String
        public var data: Data

        public init(path: String, data: Data) {
            self.path = path
            self.data = data
        }
    }

    struct Manifest: Codable {
        struct Item: Codable {
            var path: String
            var size: Int
        }

        var created: Date
        var writtenBy: String
        var entries: [Item]
    }

    public var created: Date
    /// The app that made it, e.g. "0.1.0 (7)".
    public var writtenBy: String
    public var entries: [Entry]

    public init(created: Date, writtenBy: String, entries: [Entry]) {
        self.created = created
        self.writtenBy = writtenBy
        self.entries = entries
    }

    /// Every synced file of a data folder (`Application Support`): lists, pages, photos.
    public static func collect(from root: URL, created: Date = Date(), writtenBy: String) throws -> BackupArchive {
        let folder = FolderStorage(root: root)
        var entries: [Entry] = []
        for item in folder.listNow().keys.compactMap({ SyncPath($0) }).sorted() {
            if let data = try folder.readNow(item.path) {
                entries.append(Entry(path: item.path, data: data))
            }
        }
        return BackupArchive(created: created, writtenBy: writtenBy, entries: entries)
    }

    public func encoded() throws -> Data {
        let manifest = Manifest(
            created: created, writtenBy: writtenBy,
            entries: entries.map { Manifest.Item(path: $0.path, size: $0.data.count) }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let json = try encoder.encode(manifest)
        var data = Data(capacity: Self.headerSize + json.count + entries.reduce(0) { $0 + $1.data.count })
        data.append(contentsOf: Self.signature)
        data.append(Self.formatVersion)
        let length = UInt32(json.count)
        data.append(contentsOf: [
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ])
        data.append(json)
        for entry in entries {
            data.append(entry.data)
        }
        return data
    }

    public init(decoding data: Data) throws {
        let header = [UInt8](data.prefix(Self.headerSize))
        guard header.count >= 4, Array(header[0..<4]) == Self.signature else { throw BackupError.notABackup }
        guard header.count == Self.headerSize else { throw BackupError.truncated }
        guard header[4] == Self.formatVersion else { throw BackupError.unsupportedVersion(Int(header[4])) }
        let length = Int(header[5]) << 24 | Int(header[6]) << 16 | Int(header[7]) << 8 | Int(header[8])
        let jsonStart = data.startIndex + Self.headerSize
        guard data.count - Self.headerSize >= length else { throw BackupError.truncated }
        let manifest: Manifest
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(Manifest.self, from: data.subdata(in: jsonStart..<(jsonStart + length)))
        } catch {
            throw BackupError.badManifest
        }
        var offset = jsonStart + length
        var entries: [Entry] = []
        for item in manifest.entries {
            guard SyncPath(item.path) != nil else { throw BackupError.badPath(item.path) }
            guard item.size >= 0, data.endIndex - offset >= item.size else { throw BackupError.truncated }
            entries.append(Entry(path: item.path, data: data.subdata(in: offset..<(offset + item.size))))
            offset += item.size
        }
        created = manifest.created
        writtenBy = manifest.writtenBy
        self.entries = entries
    }
}

public enum BackupError: Error, Equatable, Sendable {
    /// The file does not start with `DCBK`.
    case notABackup
    case truncated
    /// Made by a newer version of the app.
    case unsupportedVersion(Int)
    case badManifest
    /// A file the app does not know (never written anywhere).
    case badPath(String)
}
