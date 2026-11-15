import CoreGraphics
import Foundation
import ImageIO

// MARK: - Photos and their list

/// A photo of the wishlist ("Λίστα επιθυμιών"): something she would like to buy. The photo
/// is a copy inside the app (`Wishlist/<id>.jpg`), not a link to the photo library, so it
/// stays when the original is deleted there. Each file is written once and never changed.
public struct WishlistPhoto: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var created: Date
    /// Size in pixels of the saved photo.
    public var width: Int
    public var height: Int

    public init(id: UUID = UUID(), created: Date = Date(), width: Int, height: Int) {
        self.id = id
        self.created = created
        self.width = width
        self.height = height
    }

    public var fileName: String { "\(id.uuidString).jpg" }

    /// Newest first, the order of the grid.
    public static func newestFirst(_ photos: [WishlistPhoto]) -> [WishlistPhoto] {
        photos.sorted { a, b in
            a.created != b.created ? a.created > b.created : a.id.uuidString < b.id.uuidString
        }
    }
}

/// `Lists/wishlist.json`: `{"version": 1, "photos": [{"id", "created", "width", "height"}]}`.
public struct WishlistFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "wishlist.json"

    public var version: Int
    public var photos: [WishlistPhoto]

    public init(photos: [WishlistPhoto]) {
        version = Self.currentVersion
        self.photos = photos
    }
}

// MARK: - Image processing

public enum WishlistImageError: Error, Equatable, Sendable {
    case notAnImage
    case cannotEncode
}

/// A photo ready to be saved: JPEG data and its size in pixels.
public struct PreparedPhoto: Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
}

/// Turns a picked photo (HEIC, JPEG, PNG…) into the app's copy: upright, its longest side
/// at most 2048 pixels, as JPEG, on white where it was transparent, and without any of the
/// original's metadata (no location, no camera details). Colours keep their colour space
/// (e.g. Display P3).
public enum WishlistImages {
    public static let maxPixelSize = 2048
    /// The grid's small pictures.
    public static let thumbnailPixelSize = 512
    public static let quality: CGFloat = 0.85
    public static let thumbnailQuality: CGFloat = 0.8

    public static func prepare(_ data: Data, maxPixelSize: Int = maxPixelSize, quality: CGFloat = quality) throws -> PreparedPhoto {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let size = pixelSize(source) else {
            throw WishlistImageError.notAnImage
        }
        // Never larger than the original: ImageIO is only ever asked to shrink.
        let longest = min(maxPixelSize, max(size.width, size.height))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies the photo's orientation, so the copy needs none.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longest,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WishlistImageError.notAnImage
        }
        let flat = try opaque(image)
        return PreparedPhoto(data: try jpeg(flat, quality: quality), width: flat.width, height: flat.height)
    }

    /// A small copy for the grid.
    public static func thumbnail(of data: Data) throws -> Data {
        try prepare(data, maxPixelSize: thumbnailPixelSize, quality: thumbnailQuality).data
    }

    /// Width and height in pixels as stored (before the orientation is applied).
    static func pixelSize(_ source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        return (width, height)
    }

    /// The size of a saved photo file, if it is a readable image.
    public static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return pixelSize(source)
    }

    /// The image drawn on white, without transparency (JPEG has none).
    static func opaque(_ image: CGImage) throws -> CGImage {
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        let own = image.colorSpace?.model == .rgb ? image.colorSpace : nil
        for space in [own, sRGB].compactMap({ $0 }) {
            guard let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { continue }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect)
            context.interpolationQuality = .high
            context.draw(image, in: rect)
            if let flat = context.makeImage() { return flat }
        }
        throw WishlistImageError.cannotEncode
    }

    /// JPEG data with no metadata at all: only the pixels (and their colour profile).
    static func jpeg(_ image: CGImage, quality: CGFloat) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            throw WishlistImageError.cannotEncode
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WishlistImageError.cannotEncode }
        return output as Data
    }
}

// MARK: - Files

/// The wishlist's photo files on this device (later the iCloud Documents container,
/// prompt 7): `Wishlist/<id>.jpg`, each written in one step and never changed, and their
/// small copies for the grid in a cache folder (made again whenever they are missing).
public final class WishlistStore: Sendable {
    public let folder: URL
    public let thumbnailFolder: URL

    public init(folder: URL, thumbnailFolder: URL) {
        self.folder = folder
        self.thumbnailFolder = thumbnailFolder
    }

    public func url(of photo: WishlistPhoto) -> URL {
        folder.appending(path: photo.fileName)
    }

    func thumbnailURL(of photo: WishlistPhoto) -> URL {
        thumbnailFolder.appending(path: photo.fileName)
    }

    /// Saves the app's copy of a picked photo. The caller adds it to the list.
    public func add(_ data: Data, id: UUID = UUID(), created: Date = Date()) throws -> WishlistPhoto {
        let prepared = try WishlistImages.prepare(data)
        let photo = WishlistPhoto(id: id, created: created, width: prepared.width, height: prepared.height)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Written to a temporary file, then renamed: never half a photo.
        try prepared.data.write(to: url(of: photo), options: .atomic)
        return photo
    }

    /// The grid's small copy: from the cache, or made from the photo (and kept).
    public func thumbnail(of photo: WishlistPhoto) throws -> Data {
        let cached = thumbnailURL(of: photo)
        if let data = try? Data(contentsOf: cached), !data.isEmpty {
            return data
        }
        let thumbnail = try WishlistImages.thumbnail(of: Data(contentsOf: url(of: photo)))
        try? FileManager.default.createDirectory(at: thumbnailFolder, withIntermediateDirectories: true)
        try? thumbnail.write(to: cached, options: .atomic)
        return thumbnail
    }

    /// Deletes the photo and its small copy (files already gone are fine).
    public func delete(_ photo: WishlistPhoto) throws {
        for url in [url(of: photo), thumbnailURL(of: photo)] {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                continue
            }
        }
    }

    /// Ids of the photo files in the folder.
    func photoFileIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        return Set(names.compactMap { name in
            guard name.hasSuffix(".jpg") else { return nil }
            return UUID(uuidString: String(name.dropLast(4)))
        })
    }

    public struct Reconciled: Sendable, Equatable {
        /// Newest first.
        public var photos: [WishlistPhoto]
        /// Listed photos whose file is gone (left out).
        public var missing: Int
        /// Photo files the list did not know (the app stopped between saving a photo and its
        /// list): kept, as the newest.
        public var adopted: Int
    }

    /// The list as read at launch, checked against the files: one entry per photo, only
    /// photos that have a file, and every photo file in the list. No photo is ever lost.
    public func reconcile(_ listed: [WishlistPhoto], now: Date = Date()) -> Reconciled {
        let files = photoFileIDs()
        var seen: Set<UUID> = []
        var photos: [WishlistPhoto] = []
        var missing = 0
        for photo in listed where seen.insert(photo.id).inserted {
            if files.contains(photo.id) {
                photos.append(photo)
            } else {
                missing += 1
            }
        }
        var adopted = 0
        for id in files.subtracting(seen).sorted(by: { $0.uuidString < $1.uuidString }) {
            var photo = WishlistPhoto(id: id, created: now, width: 0, height: 0)
            guard let size = WishlistImages.pixelSize(of: url(of: photo)) else { continue }
            photo.width = size.width
            photo.height = size.height
            photos.append(photo)
            adopted += 1
        }
        return Reconciled(photos: WishlistPhoto.newestFirst(photos), missing: missing, adopted: adopted)
    }
}
