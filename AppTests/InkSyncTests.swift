import Foundation
import PencilKit
import PlannerCore
import Testing
import UIKit
@testable import DanaisCalendar

/// Real PencilKit strokes merged the way iCloud sync merges two versions of a page (prompt 7).
@Suite("Ink from another device")
@MainActor
struct InkSyncTests {
    private let page = PlannerPage.month(YearMonth(year: 2029, month: 3))

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "InkSyncTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func stroke(_ x: CGFloat, color: UIColor = .black) -> PKStroke {
        SampleInk.rectangle(CGRect(x: x, y: 200, width: 40, height: 40), color: color)
    }

    /// A page file's bytes, as another device would send them.
    private func file(_ drawing: PKDrawing, writtenBy: String = "another device") throws -> Data {
        try PageFile(
            metadata: PageMetadata(page: page, layout: .current(for: page), strokeCount: drawing.strokes.count, modified: Date(), writtenBy: writtenBy),
            drawing: drawing.dataRepresentation()
        ).encoded()
    }

    @Test func aStrokeHasTheSameKeyInMemoryAndFromAFile() throws {
        let drawing = PKDrawing(strokes: [stroke(100), stroke(300, color: .red)])
        let fromFile = try PKDrawing(data: drawing.dataRepresentation())
        #expect(InkMerge.keys(InkMerge.normalized(drawing)) == InkMerge.keys(InkMerge.normalized(fromFile)))
        #expect(InkMerge.sameStrokes(drawing, fromFile))
        // Two different strokes never share a key.
        #expect(Set(InkMerge.keys(drawing)).count == 2)
        // Rescaled to the canvas and back (rotation, zoom), still the same strokes.
        let there = InkLibrary.rescaled(drawing, from: 1, to: 1.37)
        #expect(InkMerge.sameStrokes(InkLibrary.rescaled(there, from: 1.37, to: 1), drawing))
    }

    @Test func unionKeepsTheStrokesOfBothOnce() throws {
        let shared = stroke(100)
        let mine = PKDrawing(strokes: [shared, stroke(200)])
        let theirs = try PKDrawing(data: PKDrawing(strokes: [shared, stroke(400, color: .blue)]).dataRepresentation())
        let merged = InkMerge.union(mine, theirs)
        #expect(merged.strokes.count == 3)
        #expect(InkMerge.sameStrokes(InkMerge.union(merged, theirs), merged), "merging again adds nothing")
    }

    @Test func threeWayKeepsErasingOnBothSides() {
        let a = stroke(100), b = stroke(200), c = stroke(300)
        let base = PKDrawing(strokes: [a, b, c])
        let mine = PKDrawing(strokes: [a, c, stroke(500)]) // erased b, wrote one more
        let theirs = PKDrawing(strokes: [a, b]) // erased c
        let merged = InkMerge.threeWay(base: base, mine: mine, theirs: theirs)
        #expect(merged.strokes.count == 2)
        #expect(InkMerge.keys(InkMerge.normalized(merged)) == InkMerge.keys(InkMerge.normalized(PKDrawing(strokes: [a, mine.strokes[2]]))))
    }

    @Test func aPageUnchangedHereTakesTheOtherVersionWithItsErasing() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = InkLibrary(folder: folder)
        let layout = PageLayoutStamp.current(for: page)
        let a = stroke(100), b = stroke(200)
        library.update(PKDrawing(strokes: [a, b]), for: page, layout: layout)
        library.saveAll(wait: true)
        let synced = try #require(try library.files.store.data(of: page))

        // The other device erased b and wrote c.
        let theirs = try file(PKDrawing(strokes: [a, stroke(300)]))
        let result = try await library.receive(theirs, for: page, replacing: ContentHash.of(synced))
        #expect(result == theirs, "the file is the other version, byte for byte")
        #expect(library.peekDrawing(for: page).strokes.count == 2)
        #expect(!library.hasUnsavedInk(page))
        #expect(PageFiles(folder: folder).loadNow(page).strokes.count == 2)
    }

    @Test func aPageChangedHereKeepsTheStrokesOfBoth() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = InkLibrary(folder: folder)
        let layout = PageLayoutStamp.current(for: page)
        let a = stroke(100)
        library.update(PKDrawing(strokes: [a]), for: page, layout: layout)
        library.saveAll(wait: true)
        let synced = try #require(try library.files.store.data(of: page))

        // Written here (not saved yet) while the other device wrote too.
        library.update(PKDrawing(strokes: [a, stroke(200)]), for: page, layout: layout)
        let theirs = try file(PKDrawing(strokes: [a, stroke(300)]))
        let result = try await library.receive(theirs, for: page, replacing: ContentHash.of(synced))
        #expect(library.peekDrawing(for: page).strokes.count == 3)
        library.saveAll(wait: true)
        #expect(PageFiles(folder: folder).loadNow(page).strokes.count == 3)
        #expect(try PageFile(decoding: result).metadata.page == page.description)
    }

    @Test func aPageNotOpenedYetIsWrittenAsItCame() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = InkLibrary(folder: folder)
        let theirs = try file(PKDrawing(strokes: [stroke(100), stroke(200)]))
        let result = try await library.receive(theirs, for: page, replacing: nil)
        #expect(result == theirs)
        #expect(try library.files.store.data(of: page) == theirs)
        #expect(library.peekDrawing(for: page).strokes.count == 2)
    }

    @Test func listsOfTwoDevicesMergeInTheBooks() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = ListBook(folder: folder)
        let milk = try #require(book.add("Milk", to: .toBuy, inkedLines: []))
        let other = ListItem(text: "Coffee", line: 5, created: Date(timeIntervalSince1970: 1_850_000_000))
        let data = try JSONFileStore<ListFile>.encode(ListFile(items: [other]))
        let result = try book.receive(data, fileName: ListFile.toBuyFileName)
        #expect(Set(book.toBuy.map(\.text)) == ["Milk", "Coffee"])
        #expect(try JSONFileStore<ListFile>.decode(result).items.count == 2)

        // Deleted here: the deletion is in the file for the other device.
        book.delete(milk.id, from: .toBuy)
        book.waitUntilSaved()
        let saved = try #require(try JSONFileStore<ListFile>(folder: folder, fileName: ListFile.toBuyFileName).load())
        #expect(saved.items.map(\.text) == ["Coffee"])
        #expect(saved.tombstones.map(\.id) == [milk.id])
        // The other device still has it: it does not come back.
        _ = try book.receive(try JSONFileStore<ListFile>.encode(ListFile(items: [other, milk])), fileName: ListFile.toBuyFileName)
        #expect(book.toBuy.map(\.text) == ["Coffee"])
    }
}
