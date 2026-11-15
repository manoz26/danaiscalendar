import Foundation

/// Where page files live. Today a local folder (`LocalPageStore`); later the same calls
/// will go to the iCloud Documents container (prompt 7).
public protocol PageStore: Sendable {
    /// The saved page, or `nil` if it was never saved.
    func load(_ page: PlannerPage) throws -> PageFile?
    /// The JSON header of a saved page, without reading its drawing (`nil` if never saved).
    func metadata(of page: PlannerPage) throws -> PageMetadata?
    /// Replaces the page's file in one step: a crash leaves either the old or the new file.
    func save(_ file: PageFile, for page: PlannerPage) throws
    /// Every page that has a file.
    func savedPages() throws -> [PlannerPage]
    /// Moves a page's unreadable file out of the way, so a fresh page can be saved
    /// without destroying it. Returns where it went (`nil` if there was no file).
    @discardableResult
    func setAside(_ page: PlannerPage) throws -> URL?
    /// Removes a page's file (a deleted journal page or sketch). Nothing happens if there is none.
    func delete(_ page: PlannerPage) throws
    /// Copies a page's file to another page (a duplicated journal page), with the new page's
    /// name inside. Returns `false` if the source has no file (nothing was written yet).
    @discardableResult
    func copy(_ source: PlannerPage, to target: PlannerPage) throws -> Bool
}

/// Page files in a folder on this device: one `<page>.dcpage` per page
/// (`year-2026.dcpage`, `month-2026-11.dcpage`, `week-2026-11-09.dcpage`, `tobuy.dcpage`,
/// `journal-<uuid>.dcpage`, `sketch-<uuid>.dcpage`).
public final class LocalPageStore: PageStore {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func url(for page: PlannerPage) -> URL {
        folder.appending(path: "\(page.fileStem).\(PageFile.fileExtension)")
    }

    public func load(_ page: PlannerPage) throws -> PageFile? {
        let data: Data
        do {
            data = try Data(contentsOf: url(for: page))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
        return try PageFile(decoding: data)
    }

    public func metadata(of page: PlannerPage) throws -> PageMetadata? {
        let file = url(for: page)
        guard FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else { return nil }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: PageFile.headerSize) ?? Data()
        let length = try PageFile.metadataLength(header: header)
        let json = try handle.read(upToCount: length) ?? Data()
        guard json.count == length else { throw PageFileError.truncated }
        do {
            return try PageMetadata.makeDecoder().decode(PageMetadata.self, from: json)
        } catch {
            throw PageFileError.badMetadata(String(describing: error))
        }
    }

    public func save(_ file: PageFile, for page: PlannerPage) throws {
        let data = try file.encoded()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Written to a temporary file next to it, then renamed over the old one.
        try data.write(to: url(for: page), options: .atomic)
    }

    public func savedPages() throws -> [PlannerPage] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        return urls
            .filter { $0.pathExtension == PageFile.fileExtension }
            .compactMap { PlannerPage(fileStem: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.fileStem < $1.fileStem }
    }

    @discardableResult
    public func setAside(_ page: PlannerPage) throws -> URL? {
        let source = url(for: page)
        guard FileManager.default.fileExists(atPath: source.path(percentEncoded: false)) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        var target = folder.appending(path: "\(page.fileStem).\(PageFile.fileExtension).unreadable-\(stamp)")
        if FileManager.default.fileExists(atPath: target.path(percentEncoded: false)) {
            target = folder.appending(path: "\(page.fileStem).\(PageFile.fileExtension).unreadable-\(stamp)-\(UUID().uuidString)")
        }
        try FileManager.default.moveItem(at: source, to: target)
        return target
    }

    public func delete(_ page: PlannerPage) throws {
        do {
            try FileManager.default.removeItem(at: url(for: page))
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return
        }
    }

    @discardableResult
    public func copy(_ source: PlannerPage, to target: PlannerPage) throws -> Bool {
        guard var file = try load(source) else { return false }
        file.metadata.page = target.description
        try save(file, for: target)
        return true
    }
}

extension PlannerPage {
    /// File name without extension: "year-2026", "month-2026-11", "week-2026-11-09", "tobuy",
    /// "journal-<uuid>", "sketch-<uuid>" (lowercase uuid).
    public var fileStem: String {
        switch self {
        case .year(let year): String(format: "year-%04ld", year)
        case .month(let month): "month-\(month)"
        case .week(let week): "week-\(week)"
        case .toBuy: "tobuy"
        case .journal(let id): "journal-\(id.uuidString.lowercased())"
        case .sketch(let id): "sketch-\(id.uuidString.lowercased())"
        }
    }

    /// Parses `fileStem`.
    public init?(fileStem: String) {
        if fileStem.hasPrefix("year-"), let year = Int(fileStem.dropFirst(5)), Self.years.contains(year) {
            self = .year(year)
        } else if fileStem.hasPrefix("month-"), let month = YearMonth(String(fileStem.dropFirst(6))),
                  Self.years.contains(month.year) {
            self = .month(month)
        } else if fileStem.hasPrefix("week-"), let week = PlannerWeek(String(fileStem.dropFirst(5))),
                  Self.years.contains(week.start.year) {
            self = .week(week)
        } else if fileStem == "tobuy" {
            self = .toBuy
        } else if fileStem.hasPrefix("journal-"), let id = UUID(uuidString: String(fileStem.dropFirst(8))) {
            self = .journal(id)
        } else if fileStem.hasPrefix("sketch-"), let id = UUID(uuidString: String(fileStem.dropFirst(7))) {
            self = .sketch(id)
        } else {
            return nil
        }
    }

    /// Pages one step away (previous, next, a month's year page, a week's month). They are
    /// loaded in advance so that turning to them is instant.
    public var neighbors: [PlannerPage] {
        var pages = [previous, next]
        switch self {
        case .month(let month): pages.append(.year(month.year))
        case .week(let week): pages.append(.month(week.month))
        default: break
        }
        return pages.filter { $0 != self }
    }
}
