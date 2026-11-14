import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

/// A new empty folder for one test.
private func newFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "NotebookTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private let pageID = UUID(uuidString: "1E2D3C4B-5A69-4788-9900-AABBCCDDEEFF")!

@Suite("Journal and sketch pages")
struct NotebookPageTests {
    @Test func identifiersAndFileNames() {
        let journal = PlannerPage.journal(pageID)
        let sketch = PlannerPage.sketch(pageID)
        #expect(journal.description == "journal:1e2d3c4b-5a69-4788-9900-aabbccddeeff")
        #expect(sketch.description == "sketch:1e2d3c4b-5a69-4788-9900-aabbccddeeff")
        #expect(journal.fileStem == "journal-1e2d3c4b-5a69-4788-9900-aabbccddeeff")
        #expect(sketch.fileStem == "sketch-1e2d3c4b-5a69-4788-9900-aabbccddeeff")
        for page in [journal, sketch] {
            #expect(PlannerPage(page.description) == page)
            #expect(PlannerPage(fileStem: page.fileStem) == page)
            #expect(page.year == nil)
            #expect(!page.isCalendarPage)
            #expect(page.isNotebookPage)
            #expect(page.previous == page)
            #expect(page.next == page)
            #expect(page.neighbors.isEmpty)
        }
        #expect(!PlannerPage.toBuy.isNotebookPage)
        #expect(PlannerPage("journal:not-a-uuid") == nil)
        #expect(PageLayoutStamp.current(for: journal).name == "journal-v1")
        #expect(PageLayoutStamp.current(for: sketch).name == "sketch-v1")
    }

    @Test func storeDeletesAndCopiesPageFiles() throws {
        let folder = newFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalPageStore(folder: folder)
        let original = PlannerPage.journal(pageID)
        let copy = PlannerPage.journal(UUID())
        let file = PageFile(
            metadata: PageMetadata(page: original, layout: .current(for: original), strokeCount: 1, modified: Date(timeIntervalSince1970: 1_800_000_000), writtenBy: "tests"),
            drawing: Data([1, 2, 3])
        )

        #expect(try store.copy(original, to: copy) == false)
        try store.save(file, for: original)
        #expect(try store.copy(original, to: copy))
        let copied = try #require(try store.load(copy))
        #expect(copied.drawing == file.drawing)
        #expect(copied.metadata.page == copy.description)
        #expect(Set(try store.savedPages()) == [original, copy])

        try store.delete(original)
        #expect(try store.load(original) == nil)
        #expect(try store.savedPages() == [copy])
        // Deleting a page without a file is fine.
        try store.delete(original)
    }

    @Test func newRegionIdentifiersRoundTrip() {
        let date = PlannerDate(year: 2026, month: 11, day: 14)
        let ids: [RegionID] = [.section(.body), .addItem(.todo), .addItem(.tobuy), .itemMarker(.todo, 3), .itemMarker(.tobuy, 40), .sketchMark(date)]
        for id in ids {
            #expect(RegionID(id.description) == id, "\(id)")
        }
        #expect(RegionID.itemMarker(.todo, 3).description == "check:todo:3")
        #expect(RegionID.sketchMark(date).description == "sketches:2026-11-14")
        #expect(RegionID("check:todo:0") == nil)
        #expect(RegionID("check:todo") == nil)
    }

    @Test func datesAreSavedAsTheirIdentifiers() throws {
        struct Holder: Codable, Equatable {
            var day: PlannerDate
            var month: YearMonth
        }
        let holder = Holder(day: PlannerDate(year: 2028, month: 2, day: 29), month: YearMonth(year: 2026, month: 11))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(holder)
        #expect(String(decoding: data, as: UTF8.self) == #"{"day":"2028-02-29","month":"2026-11"}"#)
        #expect(try JSONDecoder().decode(Holder.self, from: data) == holder)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Holder.self, from: Data(#"{"day":"2027-02-29","month":"2026-11"}"#.utf8))
        }
    }
}

@Suite("JSON files")
struct JSONFileStoreTests {
    @Test func roundTripAndMissingFile() throws {
        let folder = newFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JSONFileStore<JournalFile>(folder: folder, fileName: JournalFile.fileName)
        #expect(try store.load() == nil)

        let page = JournalPage(id: pageID, title: "Ιδέες", date: PlannerDate(year: 2026, month: 11, day: 14), paper: .grid, created: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(JournalFile(pages: [page]))
        let loaded = try #require(try store.load())
        #expect(loaded.version == 1)
        #expect(loaded.pages == [page])
        let text = try String(contentsOf: store.url, encoding: .utf8)
        #expect(text.contains(#""date" : "2026-11-14""#))
        #expect(text.contains(#""paper" : "grid""#))
        // Nothing else is left in the folder (the save is atomic).
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == [JournalFile.fileName])
    }

    @Test func unreadableAndNewerFiles() throws {
        let folder = newFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JSONFileStore<SketchFile>(folder: folder, fileName: SketchFile.fileName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try Data(#"{"version": 9, "sketches": []}"#.utf8).write(to: store.url)
        #expect(throws: JSONFileError.unsupportedVersion(9)) { try store.load() }

        try Data("not json".utf8).write(to: store.url)
        #expect(throws: (any Error).self) { try store.load() }
        let kept = try #require(try store.setAside())
        #expect(kept.lastPathComponent.hasPrefix("sketches.json.unreadable-"))
        #expect(try store.load() == nil)
        #expect(try store.setAside() == nil)
    }
}

@Suite("Journal")
struct JournalTests {
    private func page(_ title: String, _ day: Int? = nil) -> JournalPage {
        JournalPage(title: title, date: day.map { PlannerDate(year: 2026, month: 11, day: $0) })
    }

    @Test func insertDuplicateMoveRemove() throws {
        let a = page("A", 3), b = page("B"), c = page("C", 14)
        var journal = Journal()
        #expect(journal.isEmpty)
        journal.insert(a)
        journal.insert(b)
        journal.insert(c, after: a.id)
        #expect(journal.pages.map(\.title) == ["A", "C", "B"])
        journal.insert(a)
        #expect(journal.pages.count == 3, "a page is never in the journal twice")

        let copy = try #require(journal.duplicate(c.id))
        #expect(journal.pages.map(\.title) == ["A", "C", "C", "B"])
        #expect(journal.index(of: copy.id) == 2)
        #expect(copy.id != c.id)
        #expect(copy.date == c.date && copy.paper == c.paper)

        journal.move(b.id, by: -1)
        #expect(journal.pages.map(\.id) == [a.id, c.id, b.id, copy.id])
        journal.move(a.id, to: 99)
        #expect(journal.pages.last?.id == a.id)
        journal.move(a.id, by: -99)
        #expect(journal.pages.first?.id == a.id)

        #expect(journal.neighbor(of: a.id, offset: 1)?.id == c.id)
        #expect(journal.neighbor(of: a.id, offset: -1) == nil)

        journal.remove(copy.id)
        #expect(journal.pages.map(\.id) == [a.id, c.id, b.id])
    }

    @Test func pagesOfDays() {
        let first = page("First", 14), second = page("Second", 14), other = page("Other", 3)
        let journal = Journal(pages: [other, first, second, page("No date")])
        #expect(journal.page(on: PlannerDate(year: 2026, month: 11, day: 14))?.id == first.id)
        #expect(journal.page(on: PlannerDate(year: 2026, month: 11, day: 15)) == nil)
        #expect(journal.datedDays == [PlannerDate(year: 2026, month: 11, day: 3), PlannerDate(year: 2026, month: 11, day: 14)])
    }

    @Test func duplicatesInAFileAreDropped() {
        let a = page("A")
        #expect(Journal(pages: [a, a]).pages.count == 1)
    }

    @Test func updateKeepsThePlace() {
        var a = page("A"), b = page("B")
        var journal = Journal(pages: [a, b])
        a.paper = .dotted
        a.title = "Changed"
        journal.update(a)
        #expect(journal.pages.map(\.title) == ["Changed", "B"])
        #expect(journal.pages.first?.paper == .dotted)
        b.id = UUID()
        journal.update(b)
        #expect(journal.pages.count == 2)
    }

    @Test func titlesOnOneLine() {
        #expect(JournalPage(title: "  Ideas\nfor  ", date: nil).trimmedTitle == "Ideas for")
    }
}

@Suite("Sketches")
struct SketchTests {
    @Test func newestFirstAndPinnedDays() {
        let day = PlannerDate(year: 2026, month: 11, day: 20)
        let old = Sketch(created: Date(timeIntervalSince1970: 1_000), day: day)
        let new = Sketch(created: Date(timeIntervalSince1970: 2_000), day: day)
        let loose = Sketch(created: Date(timeIntervalSince1970: 3_000))
        #expect(Sketch.newestFirst([old, loose, new]).map(\.id) == [loose.id, new.id, old.id])
        let pinned = Sketch.pinned([old, loose, new])
        #expect(pinned.keys.sorted() == [day])
        #expect(pinned[day]?.map(\.id) == [new.id, old.id])
    }
}

@Suite("Typed lists")
struct TypedListTests {
    private func item(_ text: String, line: Int?, done: Bool = false, at seconds: TimeInterval = 0) -> ListItem {
        ListItem(text: text, done: done, line: line, created: Date(timeIntervalSince1970: seconds))
    }

    @Test func freeLineSkipsItemsAndInk() {
        #expect(TypedLists.freeLine(count: 9, items: [], inked: []) == 1)
        #expect(TypedLists.freeLine(count: 9, items: [item("a", line: 1)], inked: [2, 3]) == 4)
        #expect(TypedLists.freeLine(count: 3, items: [item("a", line: 1)], inked: [2, 3]) == nil)
        #expect(TypedLists.freeLine(count: 0, items: [], inked: []) == nil)
        // An item without a line takes none.
        #expect(TypedLists.freeLine(count: 2, items: [item("a", line: nil)], inked: []) == 1)
    }

    @Test func printedByLineWithOverflow() {
        let items = [
            item("Milk", line: 3, at: 1),
            item("Bread  \n", line: 1, done: true, at: 2),
            item("No room", line: nil, at: 3),
            item("Same line, newer", line: 3, at: 4),
            item("Beyond the page", line: 12, at: 5),
        ]
        let (printed, overflow) = TypedLists.printed(items, lineCount: 9)
        #expect(printed == [PrintedItem(line: 1, text: "Bread", done: true), PrintedItem(line: 3, text: "Milk", done: false)])
        #expect(overflow == 3)
    }

    @Test func fileRoundTrip() throws {
        let folder = newFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = JSONFileStore<ListFile>(folder: folder, fileName: ListFile.todoFileName)
        let todo = ListItem(text: "Call", line: 2, month: YearMonth(year: 2026, month: 11), created: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(ListFile(items: [todo]))
        #expect(try store.load()?.items == [todo])
        #expect(try String(contentsOf: store.url, encoding: .utf8).contains(#""month" : "2026-11""#))
    }
}

@Suite("Journal and sketch templates")
struct NotebookTemplateTests {
    private let english = Locale(identifier: "en_US")
    private let greek = Locale(identifier: "el_GR")
    private let saturday = PlannerDate(year: 2026, month: 11, day: 14)

    @Test func headingTexts() {
        let withTitle = JournalHeading.texts(title: " Ideas ", date: saturday, locale: english)
        #expect(withTitle.heading == "Ideas")
        #expect(withTitle.label.contains("SATURDAY"))
        #expect(withTitle.label.contains("NOVEMBER 14"))
        #expect(withTitle.label.contains("2026"))

        let day = JournalHeading.texts(title: "", date: saturday, locale: greek)
        #expect(day.label == "2026")
        #expect(day.heading.contains("ΣΑΒΒΑΤΟ"), "\(day.heading)")
        #expect(day.heading.contains("14 ΝΟΕΜΒΡΙΟΥ"), "\(day.heading)")

        let undated = JournalHeading.texts(title: "Λίστα", date: nil, locale: greek)
        #expect(undated.label.isEmpty && undated.heading == "Λίστα")
        let nothing = JournalHeading.texts(title: "", date: nil, locale: greek)
        #expect(nothing.label.isEmpty && nothing.heading.isEmpty)
    }

    @Test func everyPaperKeepsTheSameAreas() {
        let layout = JournalPageLayout()
        var counts: [PaperStyle: Int] = [:]
        for style in PaperStyle.allCases {
            let template = JournalPageTemplate.make(paper: style, label: "2026", heading: "SATURDAY, NOVEMBER 14")
            #expect(template.region(.section(.body))?.rect == layout.paper)
            #expect(template.region(.title) != nil)
            #expect(template.texts.map(\.string) == ["2026", "SATURDAY, NOVEMBER 14"])
            counts[style] = template.shapes.count
            for shape in template.shapes {
                if case .line(let from, let to, _, _) = shape {
                    #expect(layout.paper.insetBy(dx: -1, dy: -1).contains(from) && layout.paper.insetBy(dx: -1, dy: -1).contains(to))
                }
            }
        }
        // Texts and the rule under them; then the lines, the grid or the dots.
        #expect(counts[.blank] == 3)
        #expect(counts[.lined] == 3 + 36)
        #expect(counts[.grid] == 3 + 48 + 37)
        #expect(counts[.dotted] == 3 + 48 * 37)
    }

    @Test func longHeadingsAreShortened() throws {
        _ = TestFonts.registered
        let long = String(repeating: "Πολύ μεγάλος τίτλος ", count: 10)
        let template = JournalPageTemplate.make(paper: .blank, label: "", heading: long)
        let heading = try #require(template.texts.first)
        #expect(heading.string.hasSuffix("…"))
        #expect(TemplateRenderer.width(of: heading) <= JournalPageLayout().paper.width)
    }

    @Test func sketchIsBlank() {
        let template = SketchPageTemplate.make()
        #expect(template.shapes.isEmpty)
        #expect(template.region(.section(.body))?.rect == SketchPageTemplate.body)
    }

    @Test func monthMarksJournalDaysAndPinnedSketches() throws {
        let november = YearMonth(year: 2026, month: 11)
        let layout = MonthPageLayout(month: november)
        let journalDay = PlannerDate(year: 2026, month: 11, day: 5)
        let sketchDay = PlannerDate(year: 2026, month: 11, day: 20)
        let otherMonth = PlannerDate(year: 2026, month: 12, day: 2)
        let template = MonthPageTemplate.make(
            month: november, locale: english, labels: .english,
            journalDays: [journalDay, otherMonth], sketchDays: [sketchDay, otherMonth]
        )
        let dots = template.shapes.filter {
            if case .circle(_, let radius, .text?, _, _) = $0 { radius < 3 } else { false }
        }
        #expect(dots.count == 1, "only the day of this month")
        let cell = try #require(layout.cell(for: journalDay))
        if case .circle(let center, _, _, _, _) = try #require(dots.first) {
            #expect(cell.frame.contains(center))
        }
        let mark = try #require(template.control(.sketchMark(sketchDay)))
        #expect(try #require(layout.cell(for: sketchDay)).frame.contains(mark.rect))
        #expect(template.control(.sketchMark(otherMonth)) == nil)
        // Controls never anchor ink: the regions are the same with or without them.
        #expect(template.regions == MonthPageTemplate.make(month: november, locale: english, labels: .english).regions)
        #expect(template.control(at: CGPoint(x: mark.rect.midX, y: mark.rect.midY))?.id == .sketchMark(sketchDay))
    }

    @Test func monthPrintsTypedToDosAndAPlus() throws {
        let november = YearMonth(year: 2026, month: 11)
        let layout = MonthPageLayout(month: november)
        let todos = [PrintedItem(line: 1, text: "Call the bank", done: false), PrintedItem(line: 4, text: "Pay rent", done: true)]
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english, todos: todos, todoOverflow: 2)

        let call = try #require(template.texts.first { $0.string == "Call the bank" })
        #expect(layout.todo.rows[0].contains(call.anchor))
        #expect(call.tone == .text)
        let rent = try #require(template.texts.first { $0.string == "Pay rent" })
        #expect(layout.todo.rows[3].contains(rent.anchor))
        #expect(rent.tone == .secondary)
        #expect(template.texts.contains { $0.string == "+2" })

        #expect(template.control(.itemMarker(.todo, 1)) != nil)
        #expect(template.control(.itemMarker(.todo, 4)) != nil)
        #expect(template.control(.itemMarker(.todo, 2)) == nil)
        let add = try #require(template.control(.addItem(.todo)))
        #expect(add.rect.midY < layout.todo.frame.minY)
        #expect(add.rect.maxX > layout.todo.frame.maxX - 20)
        // The + is printed even without typed items.
        #expect(MonthPageTemplate.make(month: november, locale: english, labels: .english).control(.addItem(.todo)) != nil)
    }

    @Test func toBuyPrintsTypedItemsAndAPlus() throws {
        let layout = ToBuyPageLayout()
        let items = [PrintedItem(line: 2, text: "Milk", done: false), PrintedItem(line: 40, text: "Batteries", done: true)]
        let template = ToBuyPageTemplate.make(locale: english, title: "To buy", items: items)
        let milk = try #require(template.texts.first { $0.string == "Milk" })
        #expect(layout.rows[1].contains(milk.anchor))
        let batteries = try #require(template.texts.first { $0.string == "Batteries" })
        #expect(layout.rows[39].contains(batteries.anchor))
        #expect(template.control(.itemMarker(.tobuy, 40)) != nil)
        let add = try #require(template.control(.addItem(.tobuy)))
        #expect(add.rect.maxY < layout.frame.minY)
    }
}
