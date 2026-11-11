import Foundation
import PencilKit
import PlannerCore
import Testing
import UIKit
@testable import DanaisCalendar

/// Real PencilKit drawings through the app's page files.
@Suite("Ink storage")
@MainActor
struct InkStorageTests {
    private let page = PlannerPage.month(YearMonth(year: 2029, month: 3))

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "InkStorageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func sampleDrawing() -> PKDrawing {
        PKDrawing(strokes: [
            SampleInk.rectangle(CGRect(x: 100, y: 200, width: 300, height: 80)),
            SampleInk.rectangle(CGRect(x: 600, y: 900, width: 50, height: 50), color: .blue, width: 8),
        ])
    }

    @Test func drawingRoundTripsThroughAPageFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = PageFiles(folder: folder)
        let drawing = sampleDrawing()
        files.save(DrawingBox(drawing: drawing), page: page, layout: .current(for: page), writtenBy: "tests")
        files.waitUntilSaved()

        let loaded = files.loadNow(page)
        #expect(loaded.strokes.count == 2)
        #expect(abs(loaded.bounds.minX - drawing.bounds.minX) < 0.5)
        #expect(abs(loaded.bounds.maxY - drawing.bounds.maxY) < 0.5)
        #expect(loaded.strokes.map(\.ink.inkType) == [.pen, .pen])

        let file = try #require(try files.store.load(page))
        #expect(file.metadata.page == "month:2029-03")
        #expect(file.metadata.layout == "month-v1")
        #expect(file.metadata.firstWeekday == "monday")
        #expect(file.metadata.strokeCount == 2)
        #expect(file.metadata.writtenBy == "tests")
    }

    @Test func missingPageIsEmpty() {
        #expect(PageFiles(folder: temporaryFolder()).loadNow(page).strokes.isEmpty)
    }

    @Test func unreadablePageIsKeptAsideAndStartsEmpty() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = PageFiles(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a page".utf8).write(to: files.store.url(for: page))

        #expect(files.loadNow(page).strokes.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names.count == 1)
        #expect(names.first?.hasPrefix("month-2029-03.dcpage.unreadable-") == true)
    }

    @Test func libraryKeepsEditsAndSavesThem() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = InkLibrary(folder: folder)
        let layout = PageLayoutStamp.current(for: page)
        #expect(library.drawing(for: page, layout: layout).strokes.isEmpty)

        library.update(sampleDrawing(), for: page, layout: layout)
        #expect(library.drawing(for: page, layout: layout).strokes.count == 2)

        library.saveAll(wait: true)
        // A fresh reader (the app after a relaunch) finds the ink on disk.
        #expect(PageFiles(folder: folder).loadNow(page).strokes.count == 2)
    }

    @Test func pagesWithoutEditsAreNeverWritten() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = InkLibrary(folder: folder)
        for month in 1...12 {
            let page = PlannerPage.month(YearMonth(year: 2029, month: month))
            _ = library.drawing(for: page, layout: .current(for: page))
        }
        library.saveAll(wait: true)
        #expect(try LocalPageStore(folder: folder).savedPages().isEmpty)
    }

    @Test func toolsMapToPencilKit() {
        var state = InkToolState()
        #expect((InkToolFactory.tool(for: state) as? PKInkingTool)?.inkType == .pen)
        state.select(.pencil)
        #expect((InkToolFactory.tool(for: state) as? PKInkingTool)?.inkType == .pencil)
        state.select(.highlighter)
        #expect((InkToolFactory.tool(for: state) as? PKInkingTool)?.inkType == .marker)
        state.select(.eraser)
        #expect((InkToolFactory.tool(for: state) as? PKEraserTool)?.eraserType == .bitmap)
        state.eraserMode = .wholeStroke
        #expect((InkToolFactory.tool(for: state) as? PKEraserTool)?.eraserType == .vector)
        state.select(.lasso)
        #expect(InkToolFactory.tool(for: state) is PKLassoTool)
    }

    @Test func inkColours() {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        #expect(InkPalette.colors[2].uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        #expect(red > 0.85 && green < 0.2 && blue < 0.2 && alpha == 1)
    }
}
