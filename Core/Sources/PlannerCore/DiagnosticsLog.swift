import Foundation

/// A small text log on disk that the user can share from the hidden Diagnostics screen.
///
/// There is no device console without a Mac, so this file is how we find out what
/// happened on a real iPad. Safe to call from any thread; writes happen in order on a
/// private queue. The file is capped: past `maxBytes` only the newest `keepBytes`
/// (cut at a line boundary) are kept.
public final class DiagnosticsLog: Sendable {
    public enum Level: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    public let fileURL: URL
    private let maxBytes: Int
    private let keepBytes: Int
    private let timeZone: TimeZone
    private let now: @Sendable () -> Date
    private let queue = DispatchQueue(label: "PlannerCore.DiagnosticsLog")

    static let trimmedMarker = "… older entries removed …\n"

    public init(
        fileURL: URL,
        maxBytes: Int = 512 * 1024,
        keepBytes: Int = 256 * 1024,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(keepBytes < maxBytes, "keepBytes must be smaller than maxBytes")
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.keepBytes = keepBytes
        self.timeZone = timeZone
        self.now = now
    }

    public func info(_ message: String) { log(.info, message) }
    public func warning(_ message: String) { log(.warning, message) }
    public func error(_ message: String) { log(.error, message) }

    public func log(_ level: Level, _ message: String) {
        let line = Self.line(date: now(), level: level, message: message, timeZone: timeZone)
        queue.async { self.append(line) }
    }

    /// The whole log, after every write requested so far has finished.
    public func contents() -> String {
        queue.sync {
            (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        }
    }

    /// Waits until every write requested so far is on disk.
    public func flush() {
        queue.sync {}
    }

    // MARK: - Formatting

    /// One entry, e.g. `2026-11-10 14:03:22.123 ERROR Could not save page`.
    /// Extra lines of a multi-line message are indented so entries stay easy to tell apart.
    static func line(date: Date, level: Level, message: String, timeZone: TimeZone) -> String {
        let label = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
        let body = message.replacingOccurrences(of: "\n", with: "\n    ")
        return "\(timestamp(date, timeZone: timeZone)) \(label) \(body)\n"
    }

    static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date
        )
        return String(
            format: "%04ld-%02ld-%02ld %02ld:%02ld:%02ld.%03ld",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0,
            (parts.nanosecond ?? 0) / 1_000_000
        )
    }

    // MARK: - File

    /// Runs on `queue` only.
    private func append(_ line: String) {
        let data = Data(line.utf8)
        let fileManager = FileManager.default
        do {
            guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: .atomic)
                return
            }
            let size = try appendToExistingFile(data)
            if size > UInt64(maxBytes) {
                try trim()
            }
        } catch {
            // The log is the place errors go; if it cannot be written there is nowhere else.
        }
    }

    /// Appends and returns the new file size. Runs on `queue` only.
    private func appendToExistingFile(_ data: Data) throws -> UInt64 {
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return end + UInt64(data.count)
    }

    /// Keeps the newest `keepBytes`, starting at a whole line. Runs on `queue` only.
    private func trim() throws {
        let data = try Data(contentsOf: fileURL)
        guard data.count > maxBytes else { return }
        var tail = data.suffix(keepBytes)
        if let newline = tail.firstIndex(of: UInt8(ascii: "\n")) {
            tail = tail[tail.index(after: newline)...]
        }
        var trimmed = Data(Self.trimmedMarker.utf8)
        trimmed.append(tail)
        try trimmed.write(to: fileURL, options: .atomic)
    }
}
