import Foundation
import Testing
@testable import PlannerCore

@Suite("Diagnostics log")
struct DiagnosticsLogTests {
    /// 10 Nov 2026, 12:00:00 UTC.
    private static let noon = Date(timeIntervalSince1970: 1_794_312_000)
    private static let utc = TimeZone(identifier: "UTC")!

    private func makeLog(maxBytes: Int = 512 * 1024, keepBytes: Int = 256 * 1024) -> DiagnosticsLog {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "DiagnosticsLogTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        return DiagnosticsLog(
            fileURL: folder.appending(path: "log.txt"),
            maxBytes: maxBytes,
            keepBytes: keepBytes,
            timeZone: Self.utc,
            now: { Self.noon }
        )
    }

    @Test func timestampIsLocalTimeWithMilliseconds() {
        let athens = TimeZone(identifier: "Europe/Athens")!
        let date = Self.noon.addingTimeInterval(0.25)
        #expect(DiagnosticsLog.timestamp(date, timeZone: Self.utc) == "2026-11-10 12:00:00.250")
        #expect(DiagnosticsLog.timestamp(date, timeZone: athens) == "2026-11-10 14:00:00.250")
    }

    @Test func writesOneLinePerEntryInOrder() {
        let log = makeLog()
        log.info("App launched")
        log.warning("Memory warning")
        log.error("Could not save page")
        #expect(log.contents() == """
            2026-11-10 12:00:00.000 INFO  App launched
            2026-11-10 12:00:00.000 WARN  Memory warning
            2026-11-10 12:00:00.000 ERROR Could not save page

            """)
    }

    @Test func multiLineMessagesAreIndented() {
        let log = makeLog()
        log.error("Crash report\n{\"signal\": 11}")
        #expect(log.contents() == "2026-11-10 12:00:00.000 ERROR Crash report\n    {\"signal\": 11}\n")
    }

    @Test func emptyWhenNothingWasLogged() {
        #expect(makeLog().contents() == "")
    }

    @Test func greekTextSurvives() {
        let log = makeLog()
        log.info("Νοέμβριος — ΜΑΪΟΣ")
        #expect(log.contents().hasSuffix("INFO  Νοέμβριος — ΜΑΪΟΣ\n"))
    }

    @Test func trimsOldEntriesAtALineBoundary() {
        let log = makeLog(maxBytes: 1_000, keepBytes: 400)
        for index in 1...100 {
            log.info("entry \(index)")
        }
        let contents = log.contents()
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false).dropLast()

        #expect(contents.utf8.count <= 1_000)
        #expect(contents.hasPrefix(DiagnosticsLog.trimmedMarker))
        #expect(lines.last == "2026-11-10 12:00:00.000 INFO  entry 100")
        // Every kept line is whole.
        for line in lines.dropFirst() {
            #expect(line.hasPrefix("2026-11-10 12:00:00.000 INFO  entry "), "Broken line: \(line)")
        }
    }

    @Test func writesFromManyThreadsAreAllKept() {
        let log = makeLog()
        DispatchQueue.concurrentPerform(iterations: 200) { index in
            log.info("thread entry \(index)")
        }
        let lines = log.contents().split(separator: "\n")
        #expect(lines.count == 200)
        #expect(Set(lines).count == 200)
    }
}
