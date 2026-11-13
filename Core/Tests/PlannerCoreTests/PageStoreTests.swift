import Foundation
import Testing
@testable import PlannerCore

private func sampleFile(page: PlannerPage = .month(YearMonth(year: 2026, month: 11)), drawing: Data = Data([0, 1, 2, 3, 250, 255])) -> PageFile {
    PageFile(
        metadata: PageMetadata(
            page: page,
            layout: .current(for: page),
            strokeCount: 3,
            modified: Date(timeIntervalSince1970: 1_800_000_000),
            writtenBy: "0.1.0 (5)"
        ),
        drawing: drawing
    )
}

/// A new empty folder for one test.
private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "PlannerCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

@Suite("Page file format")
struct PageFileTests {
    @Test func roundTrip() throws {
        let file = sampleFile()
        let decoded = try PageFile(decoding: try file.encoded())
        #expect(decoded == file)
        #expect(decoded.metadata.page == "month:2026-11")
        #expect(decoded.metadata.layout == "month-v1")
        #expect(decoded.metadata.firstWeekday == "monday")
    }

    @Test func emptyDrawingRoundTrips() throws {
        let file = sampleFile(drawing: Data())
        #expect(try PageFile(decoding: try file.encoded()) == file)
    }

    @Test func largeDrawingRoundTrips() throws {
        let drawing = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let file = sampleFile(drawing: drawing)
        #expect(try PageFile(decoding: try file.encoded()).drawing == drawing)
    }

    @Test func headerIsReadable() throws {
        let data = try sampleFile().encoded()
        #expect(Array(data.prefix(4)) == Array("DCPG".utf8))
        #expect(data[4] == PageFile.containerVersion)
        // The metadata is plain JSON right after the 9-byte header.
        let length = Int(data[5]) << 24 | Int(data[6]) << 16 | Int(data[7]) << 8 | Int(data[8])
        let json = try #require(String(data: data.subdata(in: 9..<(9 + length)), encoding: .utf8))
        #expect(json.contains("\"page\":\"month:2026-11\""))
        #expect(json.contains("\"modified\":\"2027-01-15T08:00:00Z\""))
    }

    @Test func decodesFromASlice() throws {
        // Data slices keep their parent's indices; decoding must not assume they start at 0.
        var data = Data([9, 9, 9])
        data.append(try sampleFile().encoded())
        let slice = data.dropFirst(3)
        #expect(try PageFile(decoding: slice) == sampleFile())
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: PageFileError.notAPageFile) { try PageFile(decoding: Data()) }
        #expect(throws: PageFileError.notAPageFile) { try PageFile(decoding: Data("hello world".utf8)) }
    }

    @Test func rejectsTruncatedFiles() throws {
        let data = try sampleFile().encoded()
        #expect(throws: PageFileError.truncated) { try PageFile(decoding: data.prefix(6)) }
        #expect(throws: PageFileError.truncated) { try PageFile(decoding: data.prefix(20)) }
    }

    @Test func rejectsNewerVersions() throws {
        var data = try sampleFile().encoded()
        data[4] = 2
        #expect(throws: PageFileError.unsupportedVersion(2)) { try PageFile(decoding: data) }
    }

    @Test func rejectsBrokenMetadata() throws {
        var data = try sampleFile().encoded()
        data[10] = UInt8(ascii: "#")
        do {
            _ = try PageFile(decoding: data)
            Issue.record("Broken metadata was accepted")
        } catch PageFileError.badMetadata {
            // Expected.
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func layoutStamps() {
        #expect(PageLayoutStamp.current(for: .year(2026)).name == "year-v1")
        #expect(PageLayoutStamp.current(for: .month(YearMonth(year: 2026, month: 1))).name == "month-v2")
        #expect(PageLayoutStamp.current(for: .toBuy).name == "tobuy-v1")
        #expect(PageLayoutStamp.current(for: .year(2026), firstWeekday: .sunday).firstWeekday == .sunday)
    }
}

@Suite("Local page store")
struct LocalPageStoreTests {
    @Test func missingPageIsNil() throws {
        let store = LocalPageStore(folder: temporaryFolder())
        #expect(try store.load(.year(2026)) == nil)
        #expect(try store.savedPages().isEmpty)
    }

    @Test func saveAndLoad() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalPageStore(folder: folder)
        let page = PlannerPage.month(YearMonth(year: 2026, month: 11))
        try store.save(sampleFile(page: page), for: page)
        #expect(try store.load(page) == sampleFile(page: page))
        #expect(store.url(for: page).lastPathComponent == "month-2026-11.dcpage")

        // A second store on the same folder (the app relaunched) sees the same page.
        #expect(try LocalPageStore(folder: folder).load(page) == sampleFile(page: page))
    }

    @Test func savingReplacesTheFileAndLeavesNothingBehind() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalPageStore(folder: folder)
        let page = PlannerPage.year(2026)
        for byte in UInt8(0)..<20 {
            try store.save(sampleFile(page: page, drawing: Data(repeating: byte, count: 1000 + Int(byte))), for: page)
        }
        #expect(try store.load(page)?.drawing == Data(repeating: 19, count: 1019))
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        #expect(names == ["year-2026.dcpage"], "Temporary files left: \(names)")
    }

    @Test func listsOnlyPageFiles() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalPageStore(folder: folder)
        let november = PlannerPage.month(YearMonth(year: 2026, month: 11))
        try store.save(sampleFile(page: november), for: november)
        try store.save(sampleFile(page: .year(2026)), for: .year(2026))
        try Data("x".utf8).write(to: folder.appending(path: "notes.txt"))
        try Data("x".utf8).write(to: folder.appending(path: "month-2026-13.dcpage"))
        #expect(try store.savedPages() == [november, .year(2026)])
    }

    @Test func unreadableFileIsSetAsideNotDeleted() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LocalPageStore(folder: folder)
        let page = PlannerPage.month(YearMonth(year: 2027, month: 2))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.url(for: page))

        #expect(throws: PageFileError.notAPageFile) { try store.load(page) }
        let moved = try #require(try store.setAside(page))
        #expect(try Data(contentsOf: moved) == Data("garbage".utf8))
        #expect(try store.load(page) == nil)
        #expect(try store.savedPages().isEmpty)
        #expect(try store.setAside(page) == nil)
    }

    @Test func fileStems() {
        let november = PlannerPage.month(YearMonth(year: 2026, month: 11))
        #expect(november.fileStem == "month-2026-11")
        #expect(PlannerPage.year(2026).fileStem == "year-2026")
        #expect(PlannerPage.year(987).fileStem == "year-0987")
        #expect(PlannerPage.toBuy.fileStem == "tobuy")
        for page in [november, .year(2026), .year(1), .month(YearMonth(year: 9999, month: 12)), .toBuy] {
            #expect(PlannerPage(fileStem: page.fileStem) == page)
        }
        #expect(PlannerPage(fileStem: "month-2026-13") == nil)
        #expect(PlannerPage(fileStem: "year-0") == nil)
        #expect(PlannerPage(fileStem: "week-2026-11-14") == nil)
    }

    @Test func neighbors() {
        let november = PlannerPage.month(YearMonth(year: 2026, month: 11))
        #expect(november.neighbors == [
            .month(YearMonth(year: 2026, month: 10)),
            .month(YearMonth(year: 2026, month: 12)),
            .year(2026),
        ])
        #expect(PlannerPage.year(2026).neighbors == [.year(2025), .year(2027)])
        #expect(PlannerPage.year(1).neighbors == [.year(2)])
        #expect(PlannerPage.month(YearMonth(year: 2027, month: 1)).neighbors.first == .month(YearMonth(year: 2026, month: 12)))
    }
}
