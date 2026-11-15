import Foundation
import Observation
import PhotosUI
import PlannerCore
import SwiftUI
import UIKit

/// The wishlist ("Λίστα επιθυμιών"): photos of things she would like to buy, newest first.
/// Each photo is the app's own copy (`Application Support/Wishlist/<id>.jpg`, see
/// `WishlistStore`), listed in `Lists/wishlist.json`. Photos are prepared off the main
/// thread; the list is saved after each change like the other lists.
///
/// The photos are the user's content: nothing about them but counts goes to the log.
@MainActor
@Observable
final class WishlistBook {
    private(set) var photos: [WishlistPhoto]
    /// Photos picked and still being prepared.
    private(set) var adding = 0
    /// Picked photos that could not be added since the last time this was cleared.
    var failedToAdd = 0

    @ObservationIgnored let store: WishlistStore
    @ObservationIgnored private let saver: JSONSaver<WishlistFile>
    @ObservationIgnored private let thumbnails = NSCache<NSUUID, UIImage>()

    nonisolated static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Wishlist", directoryHint: .isDirectory)
    }

    nonisolated static var thumbnailFolder: URL {
        URL.cachesDirectory.appending(path: "WishlistThumbnails", directoryHint: .isDirectory)
    }

    init(listsFolder: URL = ListsFolder.url, folder: URL = WishlistBook.defaultFolder, thumbnailFolder: URL = WishlistBook.thumbnailFolder) {
        store = WishlistStore(folder: folder, thumbnailFolder: thumbnailFolder)
        saver = JSONSaver(folder: listsFolder, fileName: WishlistFile.fileName)
        let listed = saver.read()?.photos ?? []
        let checked = store.reconcile(listed)
        photos = checked.photos
        if checked.missing > 0 {
            AppLog.warning("Wishlist: \(checked.missing) listed photos have no file; left out")
        }
        if checked.adopted > 0 {
            AppLog.warning("Wishlist: \(checked.adopted) photo files were not in the list; kept")
        }
        if checked.missing > 0 || checked.adopted > 0 {
            persist()
        }
        AppLog.info("Wishlist photos: \(photos.count)")
    }

    func photo(_ id: UUID) -> WishlistPhoto? {
        photos.first { $0.id == id }
    }

    func url(of photo: WishlistPhoto) -> URL {
        store.url(of: photo)
    }

    /// Adds photos picked in the system's photo picker, one after another, each at the top
    /// of the grid as soon as it is ready. The picker hands over the original files; the
    /// app never reads the photo library itself.
    func add(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        adding += items.count
        var added = 0
        for item in items {
            defer { adding -= 1 }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw WishlistImageError.notAnImage
                }
                let store = store
                let photo = try await Task.detached(priority: .userInitiated) {
                    try store.add(data)
                }.value
                photos.insert(photo, at: 0)
                persist()
                added += 1
            } catch {
                failedToAdd += 1
                AppLog.error("Could not add a photo to the wishlist", error)
            }
        }
        AppLog.info("Wishlist: \(added) photos added (\(photos.count) in all)")
    }

    /// Deletes the app's copy (never anything in the photo library).
    func delete(_ id: UUID) {
        guard let photo = photo(id) else { return }
        photos.removeAll { $0.id == id }
        thumbnails.removeObject(forKey: id as NSUUID)
        persist()
        let store = store
        Task.detached(priority: .utility) {
            do {
                try store.delete(photo)
            } catch {
                AppLog.error("Could not delete a wishlist photo's file", error)
            }
        }
        AppLog.info("Wishlist photo deleted (\(photos.count) left)")
    }

    /// The grid's small picture: from memory, else from the cache folder (made if missing).
    func thumbnail(of photo: WishlistPhoto) async -> UIImage? {
        if let cached = thumbnails.object(forKey: photo.id as NSUUID) {
            return cached
        }
        let store = store
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? store.thumbnail(of: photo) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value
        if let image {
            thumbnails.setObject(image, forKey: photo.id as NSUUID)
        } else {
            AppLog.warning("Could not make a wishlist thumbnail")
        }
        return image
    }

    /// The whole photo, ready to draw.
    func image(of photo: WishlistPhoto) async -> UIImage? {
        let url = store.url(of: photo)
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path(percentEncoded: false))?.preparingForDisplay()
        }.value
    }

    func waitUntilSaved() {
        saver.waitUntilSaved()
    }

    private func persist() {
        saver.save(WishlistFile(photos: photos))
    }

    #if DEBUG
    /// `-DCSampleWishlist YES`: five made-up photos (drawn by the code, not real ones), if
    /// there are none. They go through the same preparing as picked photos.
    func addSamplesIfRequested() {
        guard LaunchOptions.sampleWishlist, photos.isEmpty else { return }
        let start = Date(timeIntervalSince1970: 1_850_000_000)
        for index in 0..<5 {
            do {
                var photo = try store.add(Self.samplePhoto(index))
                photo.created = start.addingTimeInterval(TimeInterval(index * 60))
                photos.append(photo)
            } catch {
                AppLog.error("Could not make a sample wishlist photo", error)
            }
        }
        photos = WishlistPhoto.newestFirst(photos)
        persist()
        AppLog.info("Sample wishlist photos added")
    }

    /// A colourful picture: a background, a big shape and a number. Some are portrait, some
    /// landscape, some square, like real photos.
    private static func samplePhoto(_ index: Int) -> Data {
        let sizes = [CGSize(width: 1600, height: 1200), CGSize(width: 1200, height: 1600), CGSize(width: 1400, height: 1400),
                     CGSize(width: 3000, height: 2000), CGSize(width: 1000, height: 1500)]
        let colors: [(UIColor, UIColor)] = [
            (UIColor(red: 0.98, green: 0.80, blue: 0.82, alpha: 1), UIColor(red: 0.85, green: 0.20, blue: 0.40, alpha: 1)),
            (UIColor(red: 0.80, green: 0.90, blue: 0.98, alpha: 1), UIColor(red: 0.15, green: 0.40, blue: 0.80, alpha: 1)),
            (UIColor(red: 0.86, green: 0.95, blue: 0.84, alpha: 1), UIColor(red: 0.20, green: 0.60, blue: 0.30, alpha: 1)),
            (UIColor(red: 0.99, green: 0.93, blue: 0.78, alpha: 1), UIColor(red: 0.90, green: 0.55, blue: 0.10, alpha: 1)),
            (UIColor(red: 0.90, green: 0.85, blue: 0.97, alpha: 1), UIColor(red: 0.50, green: 0.30, blue: 0.75, alpha: 1)),
        ]
        let size = sizes[index % sizes.count]
        let (background, shape) = colors[index % colors.count]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            shape.setFill()
            let side = min(size.width, size.height) * 0.55
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            switch index % 3 {
            case 0: UIBezierPath(ovalIn: rect).fill()
            case 1: UIBezierPath(roundedRect: rect, cornerRadius: side * 0.12).fill()
            default:
                let path = UIBezierPath()
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.close()
                path.fill()
            }
            let number = NSAttributedString(string: "\(index + 1)", attributes: [
                .font: UIFont.systemFont(ofSize: side * 0.4, weight: .bold),
                .foregroundColor: UIColor.white,
            ])
            let textSize = number.size()
            number.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 + side * 0.08))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
    #endif
}
