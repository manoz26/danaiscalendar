import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import PlannerCore

/// The wishlist's photos: the app's copy of a picked photo (shrunk, upright, without its
/// location), and the photo files with their list.
@Suite("Wishlist")
struct WishlistTests {
    // MARK: - Making test photos

    /// Blue on the left half, red on the right one (or transparent there, with `alpha`).
    static func picture(width: Int, height: Int, alpha: Bool = false) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space,
            bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        if !alpha {
            context.setFillColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.setFillColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }

    /// The picture as a file, the way a camera would save it: with an orientation, a
    /// location and camera details.
    static func file(_ image: CGImage, type: String = "public.jpeg", orientation: Int? = nil, location: Bool = false) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, 1, nil))
        var properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifLensModel: "Test lens"],
        ]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        if location {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 37.97, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 23.72, kCGImagePropertyGPSLongitudeRef: "E",
            ]
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func properties(of data: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    /// The colour (0–255) at a point of an image file, measured from its top-left corner.
    static func color(of data: Data, atX x: Int, y: Int) throws -> (red: Int, green: Int, blue: Int) {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // Row 0 of the buffer is the top of the image.
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        #expect(drawn)
        let index = (y * image.width + x) * 4
        return (Int(pixels[index]), Int(pixels[index + 1]), Int(pixels[index + 2]))
    }

    static func temporaryStore() -> WishlistStore {
        let root = FileManager.default.temporaryDirectory.appending(path: "wishlist-tests-\(UUID().uuidString)")
        return WishlistStore(folder: root.appending(path: "Wishlist"), thumbnailFolder: root.appending(path: "Thumbnails"))
    }

    // MARK: - The app's copy of a photo

    @Test func aBigPhotoIsShrunkTurnedUprightAndLosesItsLocation() throws {
        // 3000 × 1500 as stored, shown turned a quarter clockwise (EXIF orientation 6).
        let original = try Self.file(Self.picture(width: 3000, height: 1500), orientation: 6, location: true)
        #expect(try Self.properties(of: original)[kCGImagePropertyGPSDictionary] != nil)

        let photo = try WishlistImages.prepare(original)
        #expect(photo.width == 1024)
        #expect(photo.height == 2048)

        let saved = try Self.properties(of: photo.data)
        #expect(saved[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(saved[kCGImagePropertyPixelHeight] as? Int == 2048)
        #expect(saved[kCGImagePropertyGPSDictionary] == nil, "The location must be removed")
        #expect((saved[kCGImagePropertyOrientation] as? Int ?? 1) == 1, "The copy is upright and needs no orientation")
        let exif = saved[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        #expect(exif[kCGImagePropertyExifLensModel] == nil, "Camera details must be removed")

        // Upright: the stored left half (blue) is now the top half.
        let top = try Self.color(of: photo.data, atX: 512, y: 400)
        let bottom = try Self.color(of: photo.data, atX: 512, y: 1650)
        #expect(top.blue > 180 && top.red < 80, "Top: \(top)")
        #expect(bottom.red > 180 && bottom.blue < 80, "Bottom: \(bottom)")
    }

    @Test func aSmallPhotoKeepsItsSize() throws {
        let photo = try WishlistImages.prepare(Self.file(Self.picture(width: 300, height: 200), type: "public.png"))
        #expect(photo.width == 300)
        #expect(photo.height == 200)
        #expect(try Self.properties(of: photo.data)[kCGImagePropertyPixelWidth] as? Int == 300)
    }

    @Test func transparentPartsBecomeWhite() throws {
        let photo = try WishlistImages.prepare(Self.file(Self.picture(width: 400, height: 300, alpha: true), type: "public.png"))
        let clear = try Self.color(of: photo.data, atX: 300, y: 150)
        #expect(clear.red > 245 && clear.green > 245 && clear.blue > 245, "Was transparent: \(clear)")
        let blue = try Self.color(of: photo.data, atX: 100, y: 150)
        #expect(blue.blue > 180 && blue.red < 80, "Blue half: \(blue)")
    }

    @Test func somethingThatIsNotAPhotoIsRefused() {
        #expect(throws: WishlistImageError.notAnImage) {
            try WishlistImages.prepare(Data("not a photo".utf8))
        }
        #expect(throws: WishlistImageError.notAnImage) {
            try WishlistImages.prepare(Data())
        }
    }

    // MARK: - Files

    @Test func addingSavesTheCopyAndDeletingRemovesItsFiles() throws {
        let store = Self.temporaryStore()
        let created = Date(timeIntervalSince1970: 1_900_000_000)
        let photo = try store.add(Self.file(Self.picture(width: 2500, height: 2500), location: true), created: created)
        #expect(photo.created == created)
        #expect(photo.width == 2048 && photo.height == 2048)
        let saved = try Data(contentsOf: store.url(of: photo))
        #expect(try Self.properties(of: saved)[kCGImagePropertyGPSDictionary] == nil)

        // The small copy for the grid is made once and kept in the cache.
        let thumbnail = try store.thumbnail(of: photo)
        #expect(try Self.properties(of: thumbnail)[kCGImagePropertyPixelWidth] as? Int == WishlistImages.thumbnailPixelSize)
        #expect(FileManager.default.fileExists(atPath: store.thumbnailURL(of: photo).path(percentEncoded: false)))
        #expect(try store.thumbnail(of: photo) == thumbnail)

        try store.delete(photo)
        #expect(!FileManager.default.fileExists(atPath: store.url(of: photo).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: store.thumbnailURL(of: photo).path(percentEncoded: false)))
        // Deleting again is fine.
        try store.delete(photo)
    }

    @Test func theListIsCheckedAgainstTheFilesAtLaunch() throws {
        let store = Self.temporaryStore()
        let jpeg = try Self.file(Self.picture(width: 640, height: 480))
        let old = try store.add(jpeg, created: Date(timeIntervalSince1970: 1_800_000_000))
        let new = try store.add(jpeg, created: Date(timeIntervalSince1970: 1_800_000_100))
        // Saved, but the app stopped before the list was: not in the list.
        let unlisted = try store.add(jpeg, created: Date(timeIntervalSince1970: 1_700_000_000))
        // In the list, but its file is gone.
        let gone = WishlistPhoto(created: Date(timeIntervalSince1970: 1_800_000_200), width: 10, height: 10)

        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let result = store.reconcile([old, new, gone, old], now: now)
        #expect(result.missing == 1)
        #expect(result.adopted == 1)
        #expect(result.photos.map(\.id) == [unlisted.id, new.id, old.id])
        let adopted = try #require(result.photos.first)
        #expect(adopted.created == now)
        #expect(adopted.width == 640 && adopted.height == 480)
    }

    @Test func theListFileRoundTrips() throws {
        let store = Self.temporaryStore()
        let lists = JSONFileStore<WishlistFile>(folder: store.folder.deletingLastPathComponent().appending(path: "Lists"), fileName: WishlistFile.fileName)
        #expect(try lists.load() == nil)
        let photos = [
            WishlistPhoto(created: Date(timeIntervalSince1970: 1_800_000_000), width: 2048, height: 1536),
            WishlistPhoto(created: Date(timeIntervalSince1970: 1_800_000_100), width: 1024, height: 2048),
        ]
        try lists.save(WishlistFile(photos: photos))
        let loaded = try #require(try lists.load())
        #expect(loaded.version == 1)
        #expect(loaded.photos == photos)
    }

    @Test func theNewestComeFirst() {
        let a = WishlistPhoto(created: Date(timeIntervalSince1970: 100), width: 1, height: 1)
        let b = WishlistPhoto(created: Date(timeIntervalSince1970: 300), width: 1, height: 1)
        let c = WishlistPhoto(created: Date(timeIntervalSince1970: 200), width: 1, height: 1)
        #expect(WishlistPhoto.newestFirst([a, b, c]).map(\.id) == [b.id, c.id, a.id])
    }
}
