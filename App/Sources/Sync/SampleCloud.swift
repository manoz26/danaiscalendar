#if DEBUG
import Foundation
import PencilKit
import PlannerCore

/// `-DCSampleCloud YES` (UI tests, with `-DCFakeCloud YES`): files another device left in
/// the fake iCloud, put there only if it is empty: two typed things to buy (lines 5 and 6),
/// a birthday on 12 March, and the red sample rectangles on March 2029 (`SampleInk`), so
/// that the tests can see them arrive and line up with the page.
enum SampleCloud {
    static func seed(_ root: URL) {
        let folder = FolderStorage(root: root)
        guard folder.listNow().isEmpty else { return }
        let greek = AppLocale.current.language.languageCode?.identifier == "el"
        let start = Date(timeIntervalSince1970: 1_850_000_100)
        do {
            let items = [
                ListItem(text: greek ? "Καφές" : "Coffee", line: 5, created: start),
                ListItem(text: greek ? "Γραμματόσημα" : "Stamps", line: 6, created: start.addingTimeInterval(1)),
            ]
            try write(JSONFileStore<ListFile>.encode(ListFile(items: items)), to: "Lists/\(ListFile.toBuyFileName)", in: root)

            let birthday = Birthday(name: greek ? "Σοφία" : "Sofia", month: 3, day: 12, modified: start)
            try write(BirthdayFile(birthdays: [birthday]).encoded(), to: "Lists/\(LocalBirthdayStore.fileName)", in: root)

            let march = YearMonth(year: 2029, month: 3)
            let page = PlannerPage.month(march)
            let content = PlannerPageContent(page: page, today: PlannerDate(year: 2029, month: 3, day: 1), locale: AppLocale.current, month: march)
            let drawing = SampleInk.drawing(for: page, template: content.template)
            let metadata = PageMetadata(page: page, layout: content.layout, strokeCount: drawing.strokes.count, modified: start, writtenBy: "another device")
            try write(PageFile(metadata: metadata, drawing: drawing.dataRepresentation()).encoded(), to: SyncPath(page: page).path, in: root)
            AppLog.info("Sample iCloud files added")
        } catch {
            AppLog.error("Could not make the sample iCloud files", error)
        }
    }

    private static func write(_ data: Data, to path: String, in root: URL) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
#endif
