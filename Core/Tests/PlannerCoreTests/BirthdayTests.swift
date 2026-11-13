import Foundation
import Testing
@testable import PlannerCore

@Suite("Birthdays")
struct BirthdayTests {
    private let november = YearMonth(year: 2026, month: 11)

    @Test func dayCounts() {
        #expect(Birthday.dayCount(ofMonth: 1) == 31)
        #expect(Birthday.dayCount(ofMonth: 2) == 29)
        #expect(Birthday.dayCount(ofMonth: 4) == 30)
        #expect(Birthday.dayCount(ofMonth: 12) == 31)
    }

    @Test func validity() {
        #expect(Birthday(name: "Μάνος", month: 11, day: 13).isValid)
        #expect(Birthday(name: "Leap", month: 2, day: 29).isValid)
        #expect(!Birthday(name: "   ", month: 11, day: 13).isValid)
        #expect(!Birthday(name: "Nobody", month: 2, day: 30).isValid)
        #expect(!Birthday(name: "Nobody", month: 13, day: 1).isValid)
        #expect(!Birthday(name: "Nobody", month: 4, day: 0).isValid)
        #expect(Birthday(name: "  Μάνος \n", month: 11, day: 13).trimmedName == "Μάνος")
    }

    @Test func leapDayBirthdaysFallOnThe28thInOtherYears() {
        let leap = Birthday(name: "Leap", month: 2, day: 29)
        #expect(leap.date(in: 2028) == PlannerDate(year: 2028, month: 2, day: 29))
        #expect(leap.date(in: 2027) == PlannerDate(year: 2027, month: 2, day: 28))
        #expect(Birthday(name: "Μάνος", month: 11, day: 13).date(in: 2030) == PlannerDate(year: 2030, month: 11, day: 13))
    }

    @Test func notesOfAMonthAreSortedByDayThenName() {
        let birthdays = [
            Birthday(name: "Νίκος", month: 11, day: 21),
            Birthday(name: "Μάνος", month: 11, day: 13),
            Birthday(name: "Ελένη", month: 11, day: 21),
            Birthday(name: "Άννα", month: 12, day: 1),
            Birthday(name: " ", month: 11, day: 2),
        ]
        let notes = Birthday.notes(for: november, in: birthdays) { "\($0) — γενέθλια" }
        #expect(notes == [
            BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 13), text: "Μάνος — γενέθλια"),
            BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 21), text: "Ελένη — γενέθλια"),
            BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 21), text: "Νίκος — γενέθλια"),
        ])
        let february = Birthday.notes(for: YearMonth(year: 2027, month: 2), in: [Birthday(name: "Leap", month: 2, day: 29)]) { $0 }
        #expect(february.map(\.date) == [PlannerDate(year: 2027, month: 2, day: 28)])
    }

    @Test func longNamesAreShortenedOnOneLine() {
        #expect(Birthday.shortened("Μάνος") == "Μάνος")
        #expect(Birthday.shortened("Ann\nMarie") == "Ann Marie")
        let long = String(repeating: "α", count: 40)
        let short = Birthday.shortened(long)
        #expect(short.count == Birthday.longestPrintedName)
        #expect(short.hasSuffix("…"))
        #expect(Birthday.shortened("Αλεξάνδρα Παπαδοπούλου", to: 12) == "Αλεξάνδρα Π…")
    }

    @Test func sortedForTheList() {
        let birthdays = [
            Birthday(name: "b", month: 3, day: 1),
            Birthday(name: "a", month: 3, day: 1),
            Birthday(name: "c", month: 1, day: 30),
        ]
        #expect(Birthday.sortedByDate(birthdays).map(\.name) == ["c", "a", "b"])
    }
}

@Suite("Birthday store")
struct BirthdayStoreTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "BirthdayStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func noFileMeansNoBirthdays() throws {
        let store = LocalBirthdayStore(folder: temporaryFolder())
        #expect(try store.load().isEmpty)
        #expect(try store.setAside() == nil)
    }

    @Test func roundTrip() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalBirthdayStore(folder: folder)
        let birthdays = [
            Birthday(name: "Μάνος", month: 11, day: 13),
            Birthday(name: "Leap", month: 2, day: 29),
        ]
        try store.save(birthdays)
        #expect(try store.load() == birthdays)
        #expect(try LocalBirthdayStore(folder: folder).load() == birthdays)

        try store.save([birthdays[1]])
        #expect(try store.load() == [birthdays[1]])
        // Only the file itself: the temporary file of the atomic write is gone.
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(files == [LocalBirthdayStore.fileName])
    }

    @Test func fileFormat() throws {
        let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let data = try BirthdayFile(birthdays: [Birthday(id: id, name: "Μάνος", month: 11, day: 13)]).encoded()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        let first = try #require((json["birthdays"] as? [[String: Any]])?.first)
        #expect(first["name"] as? String == "Μάνος")
        #expect(first["month"] as? Int == 11)
        #expect(first["day"] as? Int == 13)
        #expect(first["id"] as? String == id.uuidString)
    }

    @Test func unreadableAndNewerFilesAreRefusedAndKept() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalBirthdayStore(folder: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        try Data("not json".utf8).write(to: store.url)
        #expect(throws: BirthdayFileError.self) { try store.load() }
        let kept = try #require(try store.setAside())
        #expect(kept.lastPathComponent.hasPrefix("birthdays.json.unreadable-"))
        #expect(try store.load().isEmpty)

        try Data(#"{"version": 2, "birthdays": []}"#.utf8).write(to: store.url)
        #expect(throws: BirthdayFileError.unsupportedVersion(2)) { try store.load() }
    }
}
