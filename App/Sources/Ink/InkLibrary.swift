import Foundation
import PencilKit
import PlannerCore

/// A drawing handed between threads. `PKDrawing` is a value type: every copy is independent.
struct DrawingBox: @unchecked Sendable {
    let drawing: PKDrawing
}

/// Reads and writes page files one at a time, off the main thread.
///
/// One serial queue keeps saves in order (the newest version of a page always lands
/// last) and makes a read wait for any save still in flight. Each save replaces the file
/// in one step (`LocalPageStore`), so a crash never leaves half a page.
final class PageFiles: Sendable {
    let store: LocalPageStore
    private let queue = DispatchQueue(label: "DanaisCalendar.PageFiles", qos: .userInitiated)

    init(folder: URL) {
        store = LocalPageStore(folder: folder)
    }

    /// Reads a page now, after any pending save. Never fails: an unreadable file is
    /// logged and set aside (kept, not deleted), and the page starts empty.
    func loadNow(_ page: PlannerPage) -> PKDrawing {
        let store = store
        return queue.sync { Self.read(page, from: store) }.drawing
    }

    /// Reads a page in the background and hands it to the main thread.
    func load(_ page: PlannerPage, then completion: @escaping @MainActor @Sendable (DrawingBox) -> Void) {
        let store = store
        queue.async {
            let box = Self.read(page, from: store)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(box) }
            }
        }
    }

    /// Saves a page in the background. `scale` is the drawing's PencilKit units per canvas
    /// unit (files are always in canvas units). `completion` (on the main thread) gets
    /// `false` if it failed.
    func save(
        _ box: DrawingBox, scale: CGFloat = 1, page: PlannerPage, layout: PageLayoutStamp, writtenBy: String,
        then completion: (@MainActor @Sendable (Bool) -> Void)? = nil
    ) {
        let store = store
        queue.async {
            let canvasUnits = DrawingBox(drawing: InkLibrary.rescaled(box.drawing, from: scale, to: 1))
            let saved = Self.write(canvasUnits, page: page, layout: layout, writtenBy: writtenBy, to: store)
            guard let completion else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(saved) }
            }
        }
    }

    /// Waits until every save requested so far is on disk.
    func waitUntilSaved() {
        queue.sync {}
    }

    /// Deletes a page's file, after any save still in flight (a deleted journal page or sketch).
    func delete(_ page: PlannerPage) {
        let store = store
        queue.async {
            do {
                try store.delete(page)
            } catch {
                AppLog.error("Could not delete page \(page.fileStem)", error)
            }
        }
    }

    /// Copies a page's file to another page, after any save still in flight (a duplicated journal page).
    func copy(_ source: PlannerPage, to target: PlannerPage) {
        let store = store
        queue.async {
            do {
                try store.copy(source, to: target)
            } catch {
                AppLog.error("Could not copy page \(source.fileStem)", error)
            }
        }
    }

    private static func read(_ page: PlannerPage, from store: LocalPageStore) -> DrawingBox {
        do {
            guard let file = try store.load(page) else { return DrawingBox(drawing: PKDrawing()) }
            return DrawingBox(drawing: try PKDrawing(data: file.drawing))
        } catch {
            AppLog.error("Could not read page \(page.fileStem)", error)
            do {
                if let kept = try store.setAside(page) {
                    AppLog.warning("Kept the unreadable file as \(kept.lastPathComponent); the page starts empty")
                }
            } catch {
                AppLog.error("Could not set aside the unreadable page \(page.fileStem)", error)
            }
            return DrawingBox(drawing: PKDrawing())
        }
    }

    private static func write(
        _ box: DrawingBox, page: PlannerPage, layout: PageLayoutStamp, writtenBy: String, to store: LocalPageStore
    ) -> Bool {
        let drawing = box.drawing
        let metadata = PageMetadata(
            page: page, layout: layout, strokeCount: drawing.strokes.count,
            modified: Date(), writtenBy: writtenBy
        )
        do {
            try store.save(PageFile(metadata: metadata, drawing: drawing.dataRepresentation()), for: page)
            return true
        } catch {
            AppLog.error("Could not save page \(page.fileStem)", error)
            return false
        }
    }
}

/// The ink of the pages opened recently, kept in memory, saved a moment after each change,
/// and right away when another page opens or the app goes to the background. The pages
/// next to the open one are read in advance, so turning to them is instant.
@MainActor
final class InkLibrary {
    /// Pause after the last change before a page is saved.
    static let saveDelay: Duration = .seconds(1)
    /// Even while writing without pause, unsaved ink is never older than this.
    static let longestUnsavedTime: TimeInterval = 8
    /// Pages kept in memory (the open page and its neighbours always stay).
    static let cacheSize = 8

    nonisolated static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Pages", directoryHint: .isDirectory)
    }

    private struct Entry {
        var drawing: PKDrawing
        /// PencilKit units per canvas unit of `drawing` (1 when read from disk).
        var scale: CGFloat = 1
        var layout: PageLayoutStamp
        var dirtySince: Date?
        var lastUse = 0

        var isDirty: Bool { dirtySince != nil }
    }

    let files: PageFiles
    private var entries: [PlannerPage: Entry] = [:]
    private var loading: Set<PlannerPage> = []
    private var saveTasks: [PlannerPage: Task<Void, Never>] = [:]
    private var useCounter = 0
    private var current: PlannerPage?
    private let writtenBy = AppInfo.versionAndBuild

    init(folder: URL = InkLibrary.defaultFolder) {
        files = PageFiles(folder: folder)
    }

    /// The ink of a page at `scale` PencilKit units per canvas unit, from memory or (the
    /// first time) from disk.
    func drawing(for page: PlannerPage, scale: CGFloat = 1, layout: PageLayoutStamp) -> PKDrawing {
        current = page
        if entries[page] == nil {
            entries[page] = Entry(drawing: files.loadNow(page), layout: layout)
        }
        touch(page)
        trimCache()
        guard let entry = entries[page] else { return PKDrawing() }
        return Self.rescaled(entry.drawing, from: entry.scale, to: scale)
    }

    /// The user changed a page's ink (at `scale` PencilKit units per canvas unit): keep it
    /// and save it shortly.
    func update(_ drawing: PKDrawing, scale: CGFloat = 1, for page: PlannerPage, layout: PageLayoutStamp) {
        var entry = entries[page] ?? Entry(drawing: drawing, layout: layout)
        entry.drawing = drawing
        entry.scale = scale
        entry.layout = layout
        if entry.dirtySince == nil {
            entry.dirtySince = Date()
        }
        entries[page] = entry
        touch(page)
        scheduleSave(page)
    }

    /// The ink of a page in canvas units, without making it the open page or keeping it in
    /// memory (thumbnails, exports, the lines taken by handwriting).
    func peekDrawing(for page: PlannerPage) -> PKDrawing {
        if let entry = entries[page] {
            return Self.rescaled(entry.drawing, from: entry.scale, to: 1)
        }
        return files.loadNow(page)
    }

    /// Forgets a deleted page: its ink in memory, any pending save, and its file.
    func forget(_ page: PlannerPage) {
        saveTasks[page]?.cancel()
        saveTasks[page] = nil
        entries[page] = nil
        files.delete(page)
    }

    /// Copies a page's ink (saved first) to a new page.
    func copy(_ source: PlannerPage, to target: PlannerPage) {
        save(source)
        entries[target] = nil
        files.copy(source, to: target)
    }

    /// Reads pages in the background so they open instantly.
    func preload(_ pages: [PlannerPage]) {
        for page in pages where entries[page] == nil && !loading.contains(page) {
            loading.insert(page)
            let layout = PageLayoutStamp.current(for: page)
            files.load(page) { [weak self] box in
                guard let self else { return }
                self.loading.remove(page)
                // Opened (or written on) in the meantime: that version is newer.
                guard self.entries[page] == nil else { return }
                self.entries[page] = Entry(drawing: box.drawing, layout: layout, lastUse: self.useCounter)
                self.trimCache()
            }
        }
    }

    /// Saves a page now if it has unsaved ink. The writing happens off the main thread.
    func save(_ page: PlannerPage) {
        saveTasks[page]?.cancel()
        saveTasks[page] = nil
        guard var entry = entries[page], entry.isDirty else { return }
        entry.dirtySince = nil
        entries[page] = entry
        files.save(DrawingBox(drawing: entry.drawing), scale: entry.scale, page: page, layout: entry.layout, writtenBy: writtenBy) { [weak self] saved in
            guard !saved else { return }
            self?.markUnsaved(page)
        }
    }

    /// Saves every page with unsaved ink. With `wait`, returns only once it is on disk.
    func saveAll(wait: Bool) {
        let dirty = entries.filter { $0.value.isDirty }.map(\.key)
        for page in dirty {
            save(page)
        }
        if wait {
            files.waitUntilSaved()
        }
        if !dirty.isEmpty {
            AppLog.info("Saved \(dirty.count) page(s)\(wait ? " before going to the background" : "")")
        }
    }

    /// Low memory: keep only unsaved pages and the open page.
    func releaseMemory() {
        entries = entries.filter { $0.value.isDirty || $0.key == current }
    }

    /// The same ink at another scale (strokes keep their points; PencilKit stores the
    /// scaling as each stroke's transform, so nothing is lost).
    nonisolated static func rescaled(_ drawing: PKDrawing, from: CGFloat, to: CGFloat) -> PKDrawing {
        guard from > 0, to > 0, abs(from - to) > 0.000_001 else { return drawing }
        let ratio = to / from
        return drawing.transformed(using: CGAffineTransform(scaleX: ratio, y: ratio))
    }

    private func scheduleSave(_ page: PlannerPage) {
        saveTasks[page]?.cancel()
        if let since = entries[page]?.dirtySince, Date().timeIntervalSince(since) > Self.longestUnsavedTime {
            save(page)
            return
        }
        saveTasks[page] = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.save(page)
        }
    }

    /// A save failed (e.g. the disk is full): keep the ink as unsaved so it is tried again.
    private func markUnsaved(_ page: PlannerPage) {
        guard var entry = entries[page], !entry.isDirty else { return }
        entry.dirtySince = Date()
        entries[page] = entry
    }

    private func touch(_ page: PlannerPage) {
        useCounter += 1
        entries[page]?.lastUse = useCounter
    }

    private func trimCache() {
        guard entries.count > Self.cacheSize else { return }
        var kept: Set<PlannerPage> = []
        if let current {
            kept.insert(current)
            kept.formUnion(current.neighbors)
        }
        let removable = entries
            .filter { !$0.value.isDirty && !kept.contains($0.key) }
            .sorted { $0.value.lastUse < $1.value.lastUse }
        for (page, _) in removable.prefix(entries.count - Self.cacheSize) {
            entries[page] = nil
        }
    }
}
