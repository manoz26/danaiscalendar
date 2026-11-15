import Foundation
import Testing
@testable import PlannerCore

private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

private func item(_ text: String, id: UUID = UUID(), created: TimeInterval = 0, modified: TimeInterval? = nil, done: Bool = false, line: Int? = nil) -> ListItem {
    ListItem(id: id, text: text, done: done, line: line, created: at(created), modified: modified.map(at))
}

@Suite("Merging lists from two devices")
struct ListMergeTests {
    @Test func bothSidesItemsAreKeptOnceEachWithTheNewerVersion() {
        let shared = UUID()
        let mine = ListFile(items: [item("Milk", created: 1), item("Bread", id: shared, created: 2, modified: 10)])
        let theirs = ListFile(items: [item("Bread and butter", id: shared, created: 2, modified: 20), item("Eggs", created: 3)])
        let merged = ListFile.merged(mine, theirs, now: at(100))
        #expect(merged.items.map(\.text) == ["Milk", "Bread and butter", "Eggs"])
        #expect(merged.tombstones.isEmpty)
    }

    @Test func theResultIsTheSameOnBothDevicesAndStable() {
        let shared = UUID()
        let a = ListFile(items: [item("A", created: 1), item("Same second, mine", id: shared, created: 2, modified: 30)])
        let b = ListFile(items: [item("B", created: 1.5), item("Same second, theirs", id: shared, created: 2, modified: 30.4)])
        let ab = ListFile.merged(a, b, now: at(100))
        let ba = ListFile.merged(b, a, now: at(100))
        #expect(ab == ba, "both devices must end with the same list")
        #expect(ListFile.merged(ab, b, now: at(100)) == ab, "merging again changes nothing")
        #expect(ListFile.merged(ab, a, now: at(100)) == ab)
        #expect(ab.items.count == 3)
    }

    @Test func aDeletionTravelsUnlessTheItemChangedAfterIt() {
        let deleted = UUID()
        let editedLater = UUID()
        let keep = item("Keep", created: 1)
        let mine = ListFile(items: [keep], deleted: [
            Tombstone(id: deleted, deleted: at(50)), Tombstone(id: editedLater, deleted: at(50)),
        ])
        let theirs = ListFile(items: [
            keep, item("Gone", id: deleted, created: 2, modified: 40),
            item("Changed after the deletion", id: editedLater, created: 3, modified: 60),
        ])
        let merged = ListFile.merged(mine, theirs, now: at(100))
        #expect(merged.items.map(\.text) == ["Keep", "Changed after the deletion"])
        #expect(Set(merged.tombstones.map(\.id)) == [deleted, editedLater])
        #expect(ListFile.merged(theirs, mine, now: at(100)) == merged)
    }

    @Test func datesAreComparedToTheSecond() {
        // In memory a date has fractions of a second; in the file it does not.
        let id = UUID()
        let inMemory = item("Bread", id: id, created: 1, modified: 10.7)
        let fromFile = item("Bread", id: id, created: 1, modified: 10)
        let deletedSameSecond = Tombstone(id: id, deleted: at(10.2))
        #expect(ListMerge.merge(mine: [inMemory], theirs: [], tombstones: [deletedSameSecond]).isEmpty)
        #expect(ListMerge.merge(mine: [fromFile], theirs: [], tombstones: [deletedSameSecond]).isEmpty)
        #expect(ListMerge.newer(inMemory, fromFile).text == "Bread")
    }

    @Test func oldTombstonesAreForgotten() {
        let old = Tombstone(id: UUID(), deleted: at(0))
        let recent = Tombstone(id: UUID(), deleted: at(Tombstone.keptFor))
        let later = Tombstone(id: recent.id, deleted: at(Tombstone.keptFor + 5))
        let merged = Tombstone.merged([old, recent], [later], now: at(Tombstone.keptFor + 10))
        #expect(merged == [later])
    }

    @Test func recordingDeletions() {
        let a = UUID(), b = UUID(), c = UUID()
        let tombstones = Tombstone.recording(deletionsFrom: [a, b, c], to: [b], in: [], at: at(5))
        #expect(Set(tombstones.map(\.id)) == [a, c])
        #expect(tombstones.allSatisfy { $0.deleted == at(5) })
        #expect(Tombstone.recording(deletionsFrom: [a], to: [a], in: tombstones, at: at(6)) == tombstones)
    }

    @Test func oldFilesWithoutDeletionsStillRead() throws {
        let json = #"{"version": 1, "items": [{"id": "00000000-0000-0000-0000-000000000001", "text": "Milk", "done": false, "line": 1, "created": "2030-03-17T17:46:40Z", "modified": "2030-03-17T17:46:40Z"}]}"#
        let file = try JSONFileStore<ListFile>.decode(Data(json.utf8))
        #expect(file.items.map(\.text) == ["Milk"])
        #expect(file.tombstones.isEmpty)
        let written = String(decoding: try JSONFileStore<ListFile>.encode(file), as: UTF8.self)
        #expect(!written.contains("deleted"), "no deletions: no key")
        let withDeletion = ListFile(items: [], deleted: [Tombstone(id: UUID(), deleted: t0)])
        #expect(String(decoding: try JSONFileStore<ListFile>.encode(withDeletion), as: UTF8.self).contains("\"deleted\""))
    }

    @Test func birthdaysWithoutDatesLoseToAnyChange() {
        let id = UUID()
        let old = Birthday(id: id, name: "Manos", month: 11, day: 13)
        let changed = Birthday(id: id, name: "Manos", month: 11, day: 14, modified: t0)
        let merged = BirthdayFile.merged(BirthdayFile(birthdays: [old]), BirthdayFile(birthdays: [changed]), now: at(1))
        #expect(merged.birthdays == [changed])
        #expect(BirthdayFile.merged(BirthdayFile(birthdays: [changed]), BirthdayFile(birthdays: [old]), now: at(1)) == merged)
    }

    @Test func aDeletedPhotoStaysDeleted() {
        let photo = WishlistPhoto(created: at(1), width: 10, height: 10)
        let kept = WishlistPhoto(created: at(2), width: 10, height: 10)
        let mine = WishlistFile(photos: [kept], deleted: [Tombstone(id: photo.id, deleted: at(5))])
        let theirs = WishlistFile(photos: [photo, kept])
        let merged = WishlistFile.merged(mine, theirs, now: at(10))
        #expect(merged.photos == [kept])
        #expect(WishlistFile.merged(theirs, mine, now: at(10)) == merged)
    }

    @Test func restoringBringsBackWhatIsMissingButKeepsNewerChanges() {
        let deleted = UUID(), changed = UUID()
        let mine = ListFile(items: [item("Bread, wholemeal", id: changed, created: 1, modified: 50)], deleted: [Tombstone(id: deleted, deleted: at(40))])
        let backup = ListFile(items: [item("Milk", id: deleted, created: 0, modified: 10), item("Bread", id: changed, created: 1, modified: 20)])
        let restored = ListFile.restored(mine, from: backup, now: at(100))
        #expect(restored.items.map(\.text) == ["Milk", "Bread, wholemeal"])
        #expect(restored.tombstones.isEmpty)
        // On another device that still has the deletion, the brought-back item wins (changed later).
        let other = ListFile(items: [], deleted: [Tombstone(id: deleted, deleted: at(40))])
        #expect(ListFile.merged(other, restored, now: at(101)).items.map(\.text) == ["Milk", "Bread, wholemeal"])
    }
}

@Suite("Merging the journal")
struct JournalMergeTests {
    private func page(_ title: String, created: TimeInterval) -> JournalPage {
        JournalPage(title: title, date: nil, created: at(created))
    }

    @Test func oldFilesKeepTheirOrder() {
        let pages = [page("C", created: 3), page("A", created: 1), page("B", created: 2)]
        let journal = Journal(pages: pages)
        #expect(journal.pages.map(\.title) == ["C", "A", "B"])
        #expect(journal.pages.map(\.position) == [0, 1, 2])
    }

    @Test func aMoveOnOneDeviceAndANewPageOnTheOtherBothArrive() {
        var start = Journal()
        for (index, title) in ["A", "B", "C"].enumerated() {
            start.insert(page(title, created: Double(index)), now: at(0))
        }
        var ipad = start
        ipad.move(start.pages[2].id, to: 0, now: at(10)) // C first
        var iphone = start
        iphone.insert(page("D", created: 20), after: start.pages[0].id, now: at(20)) // after A

        let mine = JournalFile(pages: ipad.pages)
        let theirs = JournalFile(pages: iphone.pages)
        let merged = JournalFile.merged(mine, theirs, now: at(30))
        #expect(merged.pages.map(\.title) == ["C", "A", "D", "B"])
        #expect(JournalFile.merged(theirs, mine, now: at(30)) == merged)
        #expect(JournalFile.merged(merged, mine, now: at(30)) == merged)
        #expect(Journal(pages: merged.pages).pages.map(\.title) == ["C", "A", "D", "B"])
    }

    @Test func movingBetweenPagesThatAreTooCloseNumbersThemAgain() {
        var journal = Journal()
        for (index, title) in ["A", "B", "C"].enumerated() {
            journal.insert(page(title, created: Double(index)), now: at(0))
        }
        // Again and again the last page goes between the first two: the gap halves each time,
        // until there is no number left between them and the pages are numbered again.
        var alwaysInPlace = true
        for step in 0..<1200 {
            let last = journal.pages[2]
            journal.move(last.id, to: 1, now: at(Double(step)))
            alwaysInPlace = alwaysInPlace && journal.pages[1].id == last.id
        }
        #expect(alwaysInPlace)
        let positions = journal.pages.compactMap(\.position)
        #expect(positions.count == 3)
        #expect(positions == positions.sorted())
        #expect(Set(positions).count == 3)
    }

    @Test func aDeletedPageGoesOnBothDevices() {
        let a = page("A", created: 0), b = page("B", created: 1)
        let mine = JournalFile(pages: Journal(pages: [a]).pages, deleted: [Tombstone(id: b.id, deleted: at(5))])
        let theirs = JournalFile(pages: Journal(pages: [a, b]).pages)
        #expect(JournalFile.merged(mine, theirs, now: at(10)).pages.map(\.title) == ["A"])
    }

    @Test func restoredPagesGoAfterTheLastPage() {
        let a = page("A", created: 0), b = page("B", created: 1), c = page("C", created: 2)
        let mine = JournalFile(pages: Journal(pages: [a, c]).pages, deleted: [Tombstone(id: b.id, deleted: at(5))])
        let backup = JournalFile(pages: Journal(pages: [b, a]).pages)
        let restored = JournalFile.restored(mine, from: backup, now: at(10))
        #expect(restored.pages.map(\.title) == ["A", "C", "B"])
        #expect(restored.tombstones.isEmpty)
    }
}

@Suite("Merging the strokes of a page")
struct OrderedMergeTests {
    private func apply(_ sources: [OrderedMerge.Source], mine: [String], theirs: [String]) -> [String] {
        sources.map { source in
            switch source {
            case .mine(let index): mine[index]
            case .theirs(let index): theirs[index]
            }
        }
    }

    @Test func unionKeepsEverythingOnce() {
        let mine = ["a", "b", "c"]
        let theirs = ["b", "d", "a", "e"]
        #expect(apply(OrderedMerge.union(mine: mine, theirs: theirs), mine: mine, theirs: theirs) == ["a", "b", "c", "d", "e"])
    }

    @Test func unionKeepsRepeatedStrokes() {
        // A stroke pasted twice in place has the same key twice.
        let mine = ["a", "a", "b"]
        let theirs = ["a", "c"]
        #expect(apply(OrderedMerge.union(mine: mine, theirs: theirs), mine: mine, theirs: theirs) == ["a", "a", "b", "c"])
    }

    @Test func threeWayKeepsBothSidesAdditionsAndDeletions() {
        let base = ["a", "b", "c"]
        let mine = ["a", "c", "m"] // erased b, wrote m
        let theirs = ["a", "b", "t"] // erased c, wrote t
        #expect(apply(OrderedMerge.threeWay(base: base, mine: mine, theirs: theirs), mine: mine, theirs: theirs) == ["a", "m", "t"])
    }

    @Test func threeWayWithNothingChangedHereIsTheirs() {
        let base = ["a", "b"]
        let theirs = ["b", "x"]
        #expect(apply(OrderedMerge.threeWay(base: base, mine: base, theirs: theirs), mine: base, theirs: theirs) == ["b", "x"])
    }

    @Test func threeWayDoesNotDoubleWhatBothAlreadyHave() {
        // The other device's version already has the stroke written here (it came from here).
        let base = ["a"]
        let mine = ["a", "new"]
        let theirs = ["a", "new", "x"]
        #expect(apply(OrderedMerge.threeWay(base: base, mine: mine, theirs: theirs), mine: mine, theirs: theirs) == ["a", "new", "x"])
    }
}

@Suite("Content hash")
struct ContentHashTests {
    @Test func sha256() {
        #expect(ContentHash.of(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(ContentHash.of(Data()) != ContentHash.of(Data([0])))
    }
}
