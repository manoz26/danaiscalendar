import CoreGraphics
import Foundation
import PencilKit
import PlannerCore
import Testing
import UIKit
@testable import DanaisCalendar

/// The journal, sketches and typed lists through the app's own classes and files, and
/// exporting a page.
@Suite("Notebooks and typed lists")
@MainActor
struct NotebookStorageTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "NotebookStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func sampleDrawing() -> PKDrawing {
        PKDrawing(strokes: [SampleInk.rectangle(CGRect(x: 100, y: 200, width: 300, height: 80))])
    }

    @Test func journalPagesAreSavedInOrder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = JournalBook(folder: folder)
        let first = book.addPage(date: PlannerDate(year: 2029, month: 3, day: 5))
        let second = book.addPage(date: nil, paper: .grid)
        let middle = book.addPage(date: nil, after: first.id)
        var titled = first
        titled.title = "Ideas"
        book.update(titled)
        book.waitUntilSaved()

        let reopened = JournalBook(folder: folder)
        #expect(reopened.pages.map(\.id) == [first.id, middle.id, second.id])
        #expect(reopened.pages.first?.title == "Ideas")
        #expect(reopened.pages.last?.paper == .grid)
        #expect(reopened.journal.page(on: PlannerDate(year: 2029, month: 3, day: 5))?.id == first.id)

        reopened.delete(middle.id)
        reopened.move(second.id, to: 0)
        reopened.waitUntilSaved()
        #expect(JournalBook(folder: folder).pages.map(\.id) == [second.id, first.id])
    }

    @Test func sketchesArePinnedAndDeleted() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = SketchBook(folder: folder)
        let sketch = book.add()
        let day = PlannerDate(year: 2029, month: 3, day: 21)
        book.pin(sketch.id, to: day)
        book.waitUntilSaved()
        let reopened = SketchBook(folder: folder)
        #expect(reopened.pinned[day]?.map(\.id) == [sketch.id])
        reopened.delete(sketch.id)
        reopened.waitUntilSaved()
        #expect(SketchBook(folder: folder).sketches.isEmpty)
    }

    @Test func typedItemsTakeFreeLinesAndAreSaved() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let book = ListBook(folder: folder)
        let march = TypedListKind.todo(YearMonth(year: 2029, month: 3))
        // Lines 1 and 2 have handwriting.
        let call = try #require(book.add("  Call the bank ", to: march, inkedLines: [1, 2]))
        #expect(call.line == 3)
        #expect(call.text == "Call the bank")
        #expect(book.add("   ", to: march, inkedLines: []) == nil)
        let milk = try #require(book.add("Milk", to: .toBuy, inkedLines: []))
        #expect(milk.line == 1)
        #expect(book.add("Flowers", to: march, inkedLines: [1, 2])?.line == 4)

        book.toggle(line: 3, in: march)
        #expect(book.items(march).first?.done == true)
        book.setText(milk.id, "", in: .toBuy)
        book.removeEmptyItems(in: .toBuy)
        #expect(book.items(.toBuy).isEmpty)
        book.waitUntilSaved()

        let reopened = ListBook(folder: folder)
        #expect(reopened.items(march).map(\.text) == ["Call the bank", "Flowers"])
        #expect(reopened.items(march).first?.done == true)
        #expect(reopened.items(.todo(YearMonth(year: 2029, month: 4))).isEmpty)
        #expect(reopened.toBuy.isEmpty)
    }

    @Test func pageInkIsCopiedAndDeleted() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = InkLibrary(folder: folder)
        let original = PlannerPage.journal(UUID())
        let copy = PlannerPage.journal(UUID())
        let layout = PageLayoutStamp.current(for: original)
        library.update(sampleDrawing(), for: original, layout: layout)

        // The copy has the ink even though it was not saved yet.
        library.copy(original, to: copy)
        library.files.waitUntilSaved()
        #expect(library.peekDrawing(for: copy).strokes.count == 1)
        #expect(try library.files.store.load(copy)?.metadata.page == copy.description)

        library.forget(original)
        library.files.waitUntilSaved()
        #expect(try library.files.store.load(original) == nil)
        #expect(library.peekDrawing(for: original).strokes.isEmpty)
        #expect(library.peekDrawing(for: copy).strokes.count == 1)
    }

    @Test func pdfAndImageExports() throws {
        let template = JournalPageTemplate.make(paper: .lined, label: "2029", heading: "Ideas")
        let drawing = PKDrawing(strokes: [SampleInk.rectangle(CGRect(x: 400, y: 600, width: 200, height: 200), width: 12)])

        let pdf = PageExporter.pdf(template: template, drawing: drawing, title: "Ideas")
        let provider = try #require(CGDataProvider(data: pdf as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
        let box = try #require(document.page(at: 1)).getBoxRect(.mediaBox)
        #expect(abs(box.width - PageExporter.pdfWidth) < 0.5)
        #expect(abs(box.height - PageExporter.pdfWidth * 1.4) < 0.5)

        let image = PageExporter.image(template: template, drawing: drawing, scale: 1)
        #expect(image.size == PageCanvas.size)
        // Red ink on the left side of the rectangle, white paper in its middle.
        #expect(isRed(image, at: CGPoint(x: 400, y: 700)))
        #expect(!isRed(image, at: CGPoint(x: 500, y: 700)))

        #expect(PageExporter.fileName("a/b: c?") == "a b  c")
        #expect(PageExporter.fileName("  ") == "Danai's Calendar")
    }

    private func isRed(_ image: UIImage, at point: CGPoint) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        var pixel = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        let scale = CGFloat(cgImage.width) / image.size.width
        // Draw the image so that the wanted pixel lands on the single pixel of the context.
        context.draw(cgImage, in: CGRect(
            x: -point.x * scale, y: -(CGFloat(cgImage.height) - point.y * scale),
            width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)
        ))
        return pixel[0] > 170 && pixel[1] < 100 && pixel[2] < 100
    }
}
