import Foundation
import PencilKit
import PlannerCore

/// A drawing handed between threads. `PKDrawing` is a value type: every copy is independent.
struct DrawingBox: @unchecked Sendable {
    let drawing: PKDrawing
}

/// A page's file after another version of it was taken in (`PageFiles.apply`).
struct AppliedPage: Sendable {
    /// The ink of the file now.
    let drawing: DrawingBox
    /// The file's bytes now.
    let data: Data
    /// The file is now exactly the other version (nothing here was missing from it).
    let replaced: Bool
    /// The layout the file's ink is on now.
    let stamp: PageLayoutStamp?
}

/// A page read from its file: the ink, and the layout it was written on (`nil`: no file).
struct LoadedPage: @unchecked Sendable {
    let drawing: PKDrawing
    let stamp: PageLayoutStamp?
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
        loadPageNow(page).drawing
    }

    /// Like `loadNow`, with the layout the ink was written on.
    func loadPageNow(_ page: PlannerPage) -> LoadedPage {
        let store = store
        return queue.sync { Self.readPage(page, from: store) }
    }

    /// Reads a page in the background and hands it to the main thread.
    func load(_ page: PlannerPage, then completion: @escaping @MainActor @Sendable (LoadedPage) -> Void) {
        let store = store
        queue.async {
            let loaded = Self.readPage(page, from: store)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(loaded) }
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

    /// The weeks whose page file has strokes, from the files' headers (their drawings are not
    /// read). Waits for any save still in flight.
    func weeksWithInk() -> Set<PlannerWeek> {
        let store = store
        return queue.sync {
            let pages: [PlannerPage]
            do {
                pages = try store.savedPages()
            } catch {
                AppLog.error("Could not list the page files", error)
                return []
            }
            var weeks: Set<PlannerWeek> = []
            for page in pages {
                guard case .week(let week) = page else { continue }
                do {
                    if let metadata = try store.metadata(of: page), metadata.strokeCount > 0 {
                        weeks.insert(week)
                    }
                } catch {
                    AppLog.warning("Could not read the header of page \(page.fileStem)")
                }
            }
            return weeks
        }
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
                if try store.copy(source, to: target) {
                    LocalChanges.post(SyncPath(page: target).path)
                }
            } catch {
                AppLog.error("Could not copy page \(source.fileStem)", error)
            }
        }
    }

    /// Takes another version of a page (from another device, or a backup) into its file,
    /// after any save still in flight. If the file still has the hash `expected` (nothing
    /// changed here since the last sync), or has nothing the other version lacks, the file
    /// becomes the other version; otherwise the file keeps the strokes of both.
    func apply(_ data: Data, theirs: DrawingBox, to page: PlannerPage, replacing expected: String?, writtenBy: String) async throws -> AppliedPage {
        let store = store
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try Self.applyNow(data, theirs: theirs, to: page, replacing: expected, writtenBy: writtenBy, store: store)
                })
            }
        }
    }

    private static func applyNow(
        _ data: Data, theirs: DrawingBox, to page: PlannerPage, replacing expected: String?, writtenBy: String, store: LocalPageStore
    ) throws -> AppliedPage {
        let theirStamp = (try? PageFile(decoding: data))?.metadata.stamp
        guard let local = try store.data(of: page) else {
            try store.save(data: data, for: page)
            return AppliedPage(drawing: theirs, data: data, replaced: true, stamp: theirStamp)
        }
        if let expected, ContentHash.of(local) == expected {
            try store.save(data: data, for: page)
            return AppliedPage(drawing: theirs, data: data, replaced: true, stamp: theirStamp)
        }
        var mine: PKDrawing
        var theirs = theirs
        var layout: PageLayoutStamp
        do {
            let file = try PageFile(decoding: local)
            mine = try PKDrawing(data: file.drawing)
            layout = file.metadata.stamp
        } catch {
            // Unreadable here: kept aside (never deleted), and the other version is taken.
            AppLog.error("Could not read page \(page.fileStem) to merge it", error)
            if let kept = try store.setAside(page) {
                AppLog.warning("Kept the unreadable file as \(kept.lastPathComponent)")
            }
            try store.save(data: data, for: page)
            return AppliedPage(drawing: theirs, data: data, replaced: true, stamp: theirStamp)
        }
        // Written on two layouts of her month page: both on the one chosen later, then joined.
        if let theirStamp, theirStamp != layout {
            let later = PageLayoutStamp.later(layout, theirStamp)
            if later == theirStamp {
                mine = InkLibrary.migrated(mine, page: page, from: layout, to: theirStamp) ?? mine
            } else {
                theirs = DrawingBox(drawing: InkLibrary.migrated(theirs.drawing, page: page, from: theirStamp, to: layout) ?? theirs.drawing)
            }
            layout = later
        }
        let merged = InkMerge.union(mine, theirs.drawing)
        if InkMerge.sameStrokes(merged, theirs.drawing), layout == theirStamp ?? layout {
            try store.save(data: data, for: page)
            return AppliedPage(drawing: theirs, data: data, replaced: true, stamp: theirStamp)
        }
        if InkMerge.sameStrokes(merged, mine), let localStamp = try? PageFile(decoding: local).metadata.stamp, localStamp == layout {
            return AppliedPage(drawing: DrawingBox(drawing: mine), data: local, replaced: false, stamp: layout)
        }
        let metadata = PageMetadata(page: page, layout: layout, strokeCount: merged.strokes.count, modified: Date(), writtenBy: writtenBy)
        let encoded = try PageFile(metadata: metadata, drawing: merged.dataRepresentation()).encoded()
        try store.save(data: encoded, for: page)
        AppLog.info("Page \(page.fileStem): strokes of both versions kept (\(mine.strokes.count) here, \(theirs.drawing.strokes.count) there, \(merged.strokes.count) now)")
        return AppliedPage(drawing: DrawingBox(drawing: merged), data: encoded, replaced: false, stamp: layout)
    }

    private static func readPage(_ page: PlannerPage, from store: LocalPageStore) -> LoadedPage {
        do {
            guard let file = try store.load(page) else { return LoadedPage(drawing: PKDrawing(), stamp: nil) }
            return LoadedPage(drawing: try PKDrawing(data: file.drawing), stamp: file.metadata.stamp)
        } catch {
            AppLog.error("Could not read page \(page.fileStem)", error)
            do {
                if let kept = try store.setAside(page) {
                    AppLog.warning("Kept the unreadable file as \(kept.lastPathComponent); the page starts empty")
                }
            } catch {
                AppLog.error("Could not set aside the unreadable page \(page.fileStem)", error)
            }
            return LoadedPage(drawing: PKDrawing(), stamp: nil)
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
            LocalChanges.post(SyncPath(page: page).path)
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
    /// Called when the user changes a page's ink, with whether the page has strokes now
    /// (`false` when a page is forgotten).
    var onInkChange: ((PlannerPage, Bool) -> Void)?
    /// Called when ink from another device changed a page in memory: the ink before and
    /// after (in canvas units), so that the open page can show it.
    var onRemoteInk: ((PlannerPage, PKDrawing, PKDrawing) -> Void)?
    private var entries: [PlannerPage: Entry] = [:]
    /// Saves started for each page (to notice one that happened while another version came in).
    private var saveCount: [PlannerPage: Int] = [:]
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
            let loaded = files.loadPageNow(page)
            entries[page] = Entry(drawing: loaded.drawing, layout: loaded.stamp ?? layout)
        }
        moveInk(of: page, to: layout)
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
        onInkChange?(page, !drawing.strokes.isEmpty)
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
        onInkChange?(page, false)
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
            files.load(page) { [weak self] loaded in
                guard let self else { return }
                self.loading.remove(page)
                // Opened (or written on) in the meantime: that version is newer.
                guard self.entries[page] == nil else { return }
                // On the layout it was written on; it moves to hers when it opens.
                let layout = loaded.stamp ?? PageLayoutStamp.current(for: page)
                self.entries[page] = Entry(drawing: loaded.drawing, layout: layout, lastUse: self.useCounter)
                self.trimCache()
            }
        }
    }

    /// Another version of a page arrives (another device, an iCloud conflict, a backup):
    /// its file takes it in (`PageFiles.apply`), and so does the ink in memory, keeping
    /// anything written here meanwhile. Returns the file's bytes afterwards.
    func receive(_ data: Data, for page: PlannerPage, replacing expected: String?) async throws -> Data {
        let file = try PageFile(decoding: data)
        let theirs = DrawingBox(drawing: try PKDrawing(data: file.drawing))
        let start = entries[page]
        let before = start.map { Self.rescaled($0.drawing, from: $0.scale, to: 1) }
        let wasClean = !(start?.isDirty ?? false)
        let savesBefore = saveCount[page] ?? 0
        let appliedFile = try await files.apply(
            data, theirs: theirs, to: page, replacing: wasClean ? expected : nil, writtenBy: writtenBy
        )
        let savedMeanwhile = (saveCount[page] ?? 0) != savesBefore
        guard var entry = entries[page] else {
            onInkChange?(page, !appliedFile.drawing.drawing.strokes.isEmpty)
            return appliedFile.data
        }
        let now = Self.rescaled(entry.drawing, from: entry.scale, to: 1)
        // The other version on the layout in use here (her month page as this device has it).
        var applied = appliedFile
        if let stamp = applied.stamp, stamp != entry.layout,
           let moved = Self.migrated(applied.drawing.drawing, page: page, from: stamp, to: entry.layout) {
            applied = AppliedPage(drawing: DrawingBox(drawing: moved), data: applied.data, replaced: applied.replaced, stamp: entry.layout)
        }
        let merged: PKDrawing
        if let before {
            // Nothing unsaved here and the file became the other version: what was erased
            // there is erased here too. Otherwise both are kept.
            merged = wasClean && applied.replaced
                ? InkMerge.threeWay(base: before, mine: now, theirs: applied.drawing.drawing)
                : InkMerge.union(now, applied.drawing.drawing)
        } else {
            // Read from the file while this was on its way: the file's version, unless written on.
            merged = entry.isDirty ? InkMerge.union(now, applied.drawing.drawing) : applied.drawing.drawing
        }
        entry.drawing = merged
        entry.scale = 1
        let needsSave = savedMeanwhile || !InkMerge.sameStrokes(merged, applied.drawing.drawing)
        if needsSave, entry.dirtySince == nil {
            entry.dirtySince = Date()
        }
        entries[page] = entry
        if needsSave {
            save(page)
        }
        if !InkMerge.sameStrokes(merged, now) {
            onRemoteInk?(page, now, merged)
        }
        onInkChange?(page, !merged.strokes.isEmpty)
        return applied.data
    }

    /// Her month page changed (or the page was written on another layout): every stroke
    /// moves with its box, day or line (`LayoutMigration`), and the page is saved on the new
    /// layout. Hidden boxes keep their ink off the page until they come back.
    private func moveInk(of page: PlannerPage, to layout: PageLayoutStamp) {
        guard var entry = entries[page], entry.layout != layout else { return }
        let canvasUnits = Self.rescaled(entry.drawing, from: entry.scale, to: 1)
        if let moved = Self.migrated(canvasUnits, page: page, from: entry.layout, to: layout) {
            entry.drawing = moved
            entry.scale = 1
            if entry.dirtySince == nil {
                entry.dirtySince = Date()
            }
            entries[page] = entry
            scheduleSave(page)
        }
        entries[page]?.layout = layout
    }

    /// The ink of a page moved from one layout to another (canvas units), or `nil` when no
    /// stroke moves.
    nonisolated static func migrated(_ drawing: PKDrawing, page: PlannerPage, from old: PageLayoutStamp, to new: PageLayoutStamp) -> PKDrawing? {
        guard !drawing.strokes.isEmpty,
              let transforms = old.migration(to: new, page: page, strokeBounds: drawing.strokes.map(\.renderBounds)) else { return nil }
        var strokes = drawing.strokes
        var count = 0
        for (index, transform) in transforms.enumerated() {
            guard let transform else { continue }
            strokes[index].transform = strokes[index].transform.concatenating(transform)
            count += 1
        }
        AppLog.info("Page \(page.fileStem): \(count) of \(strokes.count) strokes moved to the new layout")
        return PKDrawing(strokes: strokes)
    }

    /// Whether a page's ink is in memory and not saved yet.
    func hasUnsavedInk(_ page: PlannerPage) -> Bool {
        entries[page]?.isDirty ?? false
    }

    /// Saves a page now if it has unsaved ink. The writing happens off the main thread.
    func save(_ page: PlannerPage) {
        saveTasks[page]?.cancel()
        saveTasks[page] = nil
        guard var entry = entries[page], entry.isDirty else { return }
        saveCount[page, default: 0] += 1
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
