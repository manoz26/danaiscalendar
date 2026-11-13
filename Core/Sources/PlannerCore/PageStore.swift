import Foundation

/// Where page files live. Today a local folder (`LocalPageStore`); later the same calls
/// will go to the iCloud Documents container (prompt 7).
public protocol PageStore: Sendable {
    /// The saved page, or `nil` if it was never saved.
    func load(_ page: PlannerPage) throws -> PageFile?
    /// Replaces the page's file in one step: a crash leaves either the old or the new file.
    func save(_ file: PageFile, for page: PlannerPage) throws
    /// Every page that has a file.
    func savedPages() throws -> [PlannerPage]
    /// Moves a page's unreadable file out of the way, so a fresh page can be saved
    /// without destroying it. Returns where it went (`nil` if there was no file).
    @discardableResult
    func setAside(_ page: PlannerPage) throws -> URL?
}

/// Page files in a folder on this device: one `<page>.dcpage` per page
/// (`year-2026.dcpage`, `month-2026-11.dcpage`, `tobuy.dcpage`).
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
}

extension PlannerPage {
    /// File name without extension: "year-2026", "month-2026-11", "tobuy".
    public var fileStem: String {
        switch self {
        case .year(let year): String(format: "year-%04ld", year)
        case .month(let month): "month-\(month)"
        case .toBuy: "tobuy"
        }
    }

    /// Parses `fileStem`.
    public init?(fileStem: String) {
        if fileStem.hasPrefix("year-"), let year = Int(fileStem.dropFirst(5)), Self.years.contains(year) {
            self = .year(year)
        } else if fileStem.hasPrefix("month-"), let month = YearMonth(String(fileStem.dropFirst(6))),
                  Self.years.contains(month.year) {
            self = .month(month)
        } else if fileStem == "tobuy" {
            self = .toBuy
        } else {
            return nil
        }
    }

    /// Pages one step away (previous, next, and a month's year page). They are loaded in
    /// advance so that turning to them is instant.
    public var neighbors: [PlannerPage] {
        var pages = [previous, next]
        if case .month(let month) = self { pages.append(.year(month.year)) }
        return pages.filter { $0 != self }
    }
}
