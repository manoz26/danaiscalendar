import Foundation
import Observation
import PlannerCore

/// One of the app's small JSON files (`Application Support/Lists/…`): read once at
/// launch, and saved after each change off the main thread, one save at a time and in
/// order; each save replaces the file in one step. A file that cannot be read is kept
/// aside (never deleted), logged, and the list starts empty.
final class JSONSaver<File: VersionedFile>: Sendable {
    let store: JSONFileStore<File>
    private let queue: DispatchQueue

    init(folder: URL, fileName: String) {
        store = JSONFileStore(folder: folder, fileName: fileName)
        queue = DispatchQueue(label: "DanaisCalendar.\(fileName)", qos: .userInitiated)
    }

    func read() -> File? {
        let name = store.fileName
        do {
            return try store.load()
        } catch {
            AppLog.error("Could not read \(name)", error)
            do {
                if let kept = try store.setAside() {
                    AppLog.warning("Kept the unreadable \(name) as \(kept.lastPathComponent); it starts empty")
                }
            } catch {
                AppLog.error("Could not set aside \(name)", error)
            }
            return nil
        }
    }

    func save(_ file: File) {
        let store = store
        queue.async {
            do {
                try store.save(file)
            } catch {
                AppLog.error("Could not save \(store.fileName)", error)
            }
        }
    }

    /// Waits until every save requested so far is on disk (the app is going to the background).
    func waitUntilSaved() {
        queue.sync {}
    }
}

/// The folder of the app's lists: `Application Support/Lists`.
enum ListsFolder {
    static var url: URL {
        URL.applicationSupportDirectory.appending(path: "Lists", directoryHint: .isDirectory)
    }
}

// MARK: - Journal

/// The journal ("Τετράδιο"): its pages in order, with title, date and paper
/// (`Lists/journal.json`). The ink of each page is a page file like any other
/// (`Pages/journal-<id>.dcpage`), handled by the writing engine.
///
/// Titles are the user's content: they are never written to the log.
@MainActor
@Observable
final class JournalBook {
    private(set) var journal: Journal
    @ObservationIgnored private let saver: JSONSaver<JournalFile>

    init(folder: URL = ListsFolder.url) {
        saver = JSONSaver(folder: folder, fileName: JournalFile.fileName)
        journal = Journal(pages: saver.read()?.pages ?? [])
        AppLog.info("Journal pages: \(journal.pages.count)")
    }

    var pages: [JournalPage] { journal.pages }

    func page(_ id: UUID) -> JournalPage? { journal.page(id) }

    /// A new page at the end of the journal (or right after `after`).
    @discardableResult
    func addPage(date: PlannerDate?, after: UUID? = nil, paper: PaperStyle = .defaultStyle) -> JournalPage {
        let page = JournalPage(date: date, paper: paper)
        journal.insert(page, after: after)
        persist()
        AppLog.info("Journal page added (\(journal.pages.count) pages)")
        return page
    }

    /// New title, date or paper.
    func update(_ page: JournalPage) {
        guard var current = journal.page(page.id), current != page else { return }
        current = page
        current.modified = Date()
        journal.update(current)
        persist()
    }

    /// A copy of the page's details right after it. The caller copies its ink.
    func duplicate(_ id: UUID) -> JournalPage? {
        guard let copy = journal.duplicate(id) else { return nil }
        persist()
        AppLog.info("Journal page duplicated")
        return copy
    }

    func move(_ id: UUID, to index: Int) {
        let before = journal.pages.map(\.id)
        journal.move(id, to: index)
        guard journal.pages.map(\.id) != before else { return }
        persist()
    }

    func move(_ id: UUID, by offset: Int) {
        guard let index = journal.index(of: id) else { return }
        move(id, to: index + offset)
    }

    /// Removes the page from the journal. The caller deletes its ink.
    func delete(_ id: UUID) {
        guard journal.page(id) != nil else { return }
        journal.remove(id)
        persist()
        AppLog.info("Journal page deleted (\(journal.pages.count) left)")
    }

    func waitUntilSaved() {
        saver.waitUntilSaved()
    }

    private func persist() {
        saver.save(JournalFile(pages: journal.pages))
    }

    #if DEBUG
    /// `-DCSampleNotebooks YES`: four pages, one of each paper, if the journal is empty.
    func addSamplesIfRequested() {
        guard LaunchOptions.sampleNotebooks, journal.isEmpty else { return }
        let greek = AppLocale.current.language.languageCode?.identifier == "el"
        let samples: [(String, Int?, PaperStyle)] = [
            (greek ? "Ιδέες" : "Ideas", 5, .lined),
            ("", 12, .grid),
            (greek ? "Κήπος" : "Garden", nil, .dotted),
            ("", 21, .blank),
        ]
        for (title, day, paper) in samples {
            journal.insert(JournalPage(title: title, date: day.map { PlannerDate(year: 2029, month: 3, day: $0) }, paper: paper))
        }
        persist()
        AppLog.info("Sample journal pages added")
    }
    #endif
}

// MARK: - Sketches

/// The sketches (`Lists/sketches.json`), each with its ink in `Pages/sketch-<id>.dcpage`.
@MainActor
@Observable
final class SketchBook {
    private(set) var sketches: [Sketch]
    @ObservationIgnored private let saver: JSONSaver<SketchFile>

    init(folder: URL = ListsFolder.url) {
        saver = JSONSaver(folder: folder, fileName: SketchFile.fileName)
        sketches = saver.read()?.sketches ?? []
        AppLog.info("Sketches: \(sketches.count)")
    }

    /// Newest first.
    var sorted: [Sketch] { Sketch.newestFirst(sketches) }

    func sketch(_ id: UUID) -> Sketch? { sketches.first { $0.id == id } }

    /// Sketches pinned to each day.
    var pinned: [PlannerDate: [Sketch]] { Sketch.pinned(sketches) }

    @discardableResult
    func add() -> Sketch {
        let sketch = Sketch()
        sketches.append(sketch)
        persist()
        AppLog.info("Sketch added (\(sketches.count) sketches)")
        return sketch
    }

    /// Pins a sketch to a day, or unpins it (`nil`).
    func pin(_ id: UUID, to day: PlannerDate?) {
        guard let index = sketches.firstIndex(where: { $0.id == id }), sketches[index].day != day else { return }
        sketches[index].day = day
        sketches[index].modified = Date()
        persist()
        AppLog.info(day == nil ? "Sketch unpinned" : "Sketch pinned to a day")
    }

    /// Removes the sketch from the list. The caller deletes its ink.
    func delete(_ id: UUID) {
        guard sketches.contains(where: { $0.id == id }) else { return }
        sketches.removeAll { $0.id == id }
        persist()
        AppLog.info("Sketch deleted (\(sketches.count) left)")
    }

    func waitUntilSaved() {
        saver.waitUntilSaved()
    }

    private func persist() {
        saver.save(SketchFile(sketches: sketches))
    }

    #if DEBUG
    /// `-DCSampleNotebooks YES`: two sketches, one pinned to 21 March 2029, if there are none.
    func addSamplesIfRequested() {
        guard LaunchOptions.sampleNotebooks, sketches.isEmpty else { return }
        sketches = [
            Sketch(created: Date(timeIntervalSince1970: 1_857_000_000), day: PlannerDate(year: 2029, month: 3, day: 21)),
            Sketch(created: Date(timeIntervalSince1970: 1_856_000_000)),
        ]
        persist()
        AppLog.info("Sample sketches added")
    }
    #endif
}

// MARK: - Typed lists

/// Which typed list: the to-dos of a month, or the things to buy.
enum TypedListKind: Hashable, Identifiable {
    case todo(YearMonth)
    case toBuy

    var id: String {
        switch self {
        case .todo(let month): "todo:\(month)"
        case .toBuy: "tobuy"
        }
    }

    /// Lines of the printed list.
    var lineCount: Int {
        switch self {
        case .todo: MonthPageLayout.listRowCount
        case .toBuy: ToBuyPageLayout.rowsPerColumn * ToBuyPageLayout.columnCount
        }
    }

    /// The page the list is printed on.
    var page: PlannerPage {
        switch self {
        case .todo(let month): .month(month)
        case .toBuy: .toBuy
        }
    }

    /// The line number of an inked region of that page, if it is one of the list's lines.
    func line(of region: RegionID) -> Int? {
        switch (self, region) {
        case (.todo, .todoLine(let line)): line
        case (.toBuy, .toBuyLine(let line)): line
        default: nil
        }
    }
}

/// Typed to-dos (every month, `Lists/todo.json`) and things to buy (`Lists/tobuy.json`).
/// They are printed on the pages under the ink; later the iPhone adds them too.
///
/// Their texts are the user's content: they are never written to the log.
@MainActor
@Observable
final class ListBook {
    private(set) var todos: [ListItem]
    private(set) var toBuy: [ListItem]
    @ObservationIgnored private let todoSaver: JSONSaver<ListFile>
    @ObservationIgnored private let toBuySaver: JSONSaver<ListFile>

    init(folder: URL = ListsFolder.url) {
        todoSaver = JSONSaver(folder: folder, fileName: ListFile.todoFileName)
        toBuySaver = JSONSaver(folder: folder, fileName: ListFile.toBuyFileName)
        todos = todoSaver.read()?.items ?? []
        toBuy = toBuySaver.read()?.items ?? []
        AppLog.info("Typed items: \(todos.count) to-do, \(toBuy.count) to buy")
    }

    /// A list's items, by printed line (items without a line last).
    func items(_ list: TypedListKind) -> [ListItem] {
        let items: [ListItem] = switch list {
        case .todo(let month): todos.filter { $0.month == month }
        case .toBuy: toBuy
        }
        return items.sorted { a, b in
            switch (a.line, b.line) {
            case let (x?, y?): x != y ? x < y : a.created < b.created
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): a.created < b.created
            }
        }
    }

    /// Adds an item on the first line with no item and no ink. Empty texts are ignored.
    @discardableResult
    func add(_ text: String, to list: TypedListKind, inkedLines: Set<Int>) -> ListItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let line = TypedLists.freeLine(count: list.lineCount, items: items(list), inked: inkedLines)
        var item = ListItem(text: trimmed, line: line)
        if case .todo(let month) = list {
            item.month = month
        }
        change(list) { $0.append(item) }
        AppLog.info("Typed item added (\(list.logName))\(line == nil ? " without a free line" : "")")
        return item
    }

    func setDone(_ id: UUID, _ done: Bool, in list: TypedListKind) {
        change(list) { items in
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].done != done else { return }
            items[index].done = done
            items[index].modified = Date()
        }
    }

    /// A finger on the circle or box of a printed item ticks or unticks it.
    func toggle(line: Int, in list: TypedListKind) {
        guard let item = items(list).first(where: { $0.line == line }) else { return }
        setDone(item.id, !item.done, in: list)
    }

    func setText(_ id: UUID, _ text: String, in list: TypedListKind) {
        change(list) { items in
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].text != text else { return }
            items[index].text = text
            items[index].modified = Date()
        }
    }

    func delete(_ id: UUID, from list: TypedListKind) {
        change(list) { items in items.removeAll { $0.id == id } }
    }

    /// Items whose text was erased are removed (when the list closes).
    func removeEmptyItems(in list: TypedListKind) {
        let empty = items(list).filter { $0.trimmedText.isEmpty }.map(\.id)
        guard !empty.isEmpty else { return }
        change(list) { items in items.removeAll { empty.contains($0.id) } }
    }

    func waitUntilSaved() {
        todoSaver.waitUntilSaved()
        toBuySaver.waitUntilSaved()
    }

    private func change(_ list: TypedListKind, _ edit: (inout [ListItem]) -> Void) {
        switch list {
        case .todo:
            let before = todos
            edit(&todos)
            if todos != before { todoSaver.save(ListFile(items: todos)) }
        case .toBuy:
            let before = toBuy
            edit(&toBuy)
            if toBuy != before { toBuySaver.save(ListFile(items: toBuy)) }
        }
    }

    #if DEBUG
    /// `-DCSampleLists YES`: typed to-dos for March 2029 and things to buy, if there are none.
    func addSamplesIfRequested() {
        guard LaunchOptions.sampleLists, todos.isEmpty, toBuy.isEmpty else { return }
        let greek = AppLocale.current.language.languageCode?.identifier == "el"
        let march = YearMonth(year: 2029, month: 3)
        let start = Date(timeIntervalSince1970: 1_850_000_000)
        func item(_ english: String, _ greekText: String, line: Int, done: Bool = false, month: YearMonth? = nil, order: Int) -> ListItem {
            ListItem(text: greek ? greekText : english, done: done, line: line, month: month, created: start.addingTimeInterval(TimeInterval(order)))
        }
        todos = [
            item("Call the bank", "Τηλέφωνο στην τράπεζα", line: 1, month: march, order: 1),
            item("Book the dentist", "Ραντεβού με οδοντίατρο", line: 2, done: true, month: march, order: 2),
            item("Plant the basil", "Φύτεμα βασιλικού", line: 4, month: march, order: 3),
        ]
        toBuy = [
            item("Milk", "Γάλα", line: 1, order: 1),
            item("Bread", "Ψωμί", line: 2, done: true, order: 2),
            item("Batteries", "Μπαταρίες", line: 3, order: 3),
            item("A gift for Maria", "Δώρο για τη Μαρία", line: 37, order: 4),
        ]
        todoSaver.save(ListFile(items: todos))
        toBuySaver.save(ListFile(items: toBuy))
        AppLog.info("Sample typed items added")
    }
    #endif
}

extension TypedListKind {
    /// For the log: never the items themselves.
    var logName: String {
        switch self {
        case .todo: "to-do"
        case .toBuy: "to buy"
        }
    }
}
