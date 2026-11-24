import CoreGraphics
import Foundation

/// One planner page on disk: a small JSON header and the PencilKit drawing.
///
/// File layout (`month-2026-11.dcpage`):
/// - 4 bytes: `DCPG`
/// - 1 byte: container version (`containerVersion`)
/// - 4 bytes: length of the JSON metadata, big-endian
/// - the JSON metadata (UTF-8)
/// - the drawing (`PKDrawing.dataRepresentation()`) up to the end of the file
///
/// Core does not know PencilKit: here the drawing is opaque bytes.
public struct PageFile: Sendable, Equatable {
    public static let fileExtension = "dcpage"
    public static let containerVersion: UInt8 = 1
    static let signature: [UInt8] = Array("DCPG".utf8)
    static let headerSize = 9

    public var metadata: PageMetadata
    public var drawing: Data

    public init(metadata: PageMetadata, drawing: Data) {
        self.metadata = metadata
        self.drawing = drawing
    }

    public func encoded() throws -> Data {
        let json = try PageMetadata.makeEncoder().encode(metadata)
        var data = Data(capacity: Self.headerSize + json.count + drawing.count)
        data.append(contentsOf: Self.signature)
        data.append(Self.containerVersion)
        let length = UInt32(json.count)
        data.append(contentsOf: [
            UInt8(truncatingIfNeeded: length >> 24),
            UInt8(truncatingIfNeeded: length >> 16),
            UInt8(truncatingIfNeeded: length >> 8),
            UInt8(truncatingIfNeeded: length),
        ])
        data.append(json)
        data.append(drawing)
        return data
    }

    /// Checks the first `headerSize` bytes of a file and returns the length of its JSON.
    static func metadataLength(header data: Data) throws -> Int {
        let header = [UInt8](data.prefix(Self.headerSize))
        guard header.count >= 4, Array(header[0..<4]) == Self.signature else {
            throw PageFileError.notAPageFile
        }
        guard header.count == Self.headerSize else { throw PageFileError.truncated }
        guard header[4] == Self.containerVersion else {
            throw PageFileError.unsupportedVersion(Int(header[4]))
        }
        return Int(header[5]) << 24 | Int(header[6]) << 16 | Int(header[7]) << 8 | Int(header[8])
    }

    public init(decoding data: Data) throws {
        let length = try Self.metadataLength(header: data)
        guard data.count >= Self.headerSize + length else { throw PageFileError.truncated }

        let jsonStart = data.startIndex + Self.headerSize
        let drawingStart = jsonStart + length
        do {
            metadata = try PageMetadata.makeDecoder().decode(PageMetadata.self, from: data.subdata(in: jsonStart..<drawingStart))
        } catch {
            throw PageFileError.badMetadata(String(describing: error))
        }
        drawing = data.subdata(in: drawingStart..<data.endIndex)
    }
}

/// The JSON part of a page file.
public struct PageMetadata: Codable, Sendable, Equatable {
    /// The page, e.g. "month:2026-11".
    public var page: String
    /// The printed layout the ink was written on, e.g. "month-v1" (see `PageLayoutStamp`).
    public var layout: String
    /// First column of the week grid the ink was written on, e.g. "monday".
    public var firstWeekday: String
    public var strokeCount: Int
    public var modified: Date
    /// The app that wrote the file, e.g. "0.1.0 (5)".
    public var writtenBy: String
    /// Month pages on her own layout (prompt 9): the layout, and when she chose it. Not
    /// written for the standard page, so those files are as before.
    public var monthLayout: MonthLayout?
    public var layoutChanged: Date?

    public init(page: PlannerPage, layout: PageLayoutStamp, strokeCount: Int, modified: Date, writtenBy: String) {
        self.page = page.description
        self.layout = layout.name
        self.firstWeekday = layout.firstWeekday.key
        self.strokeCount = strokeCount
        self.modified = modified
        self.writtenBy = writtenBy
        monthLayout = layout.monthLayout
        layoutChanged = layout.changed
    }

    /// The layout the file's ink was written on.
    public var stamp: PageLayoutStamp {
        PageLayoutStamp(
            name: layout, firstWeekday: Weekday(key: firstWeekday) ?? .defaultFirst,
            monthLayout: monthLayout, changed: layoutChanged
        )
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public enum PageFileError: Error, Equatable, Sendable {
    /// The file does not start with `DCPG`.
    case notAPageFile
    /// The file ends before its header or metadata does.
    case truncated
    /// Written by a newer version of the app.
    case unsupportedVersion(Int)
    case badMetadata(String)
}

/// Which printed layout a page's ink was written on. It is saved with the ink so that
/// when a layout changes (prompt 9: boxes, lines, first day of the week), every stroke
/// can be moved with its region (see `InkAnchor`) instead of staying in the wrong place.
public struct PageLayoutStamp: Sendable, Equatable {
    public let name: String
    public let firstWeekday: Weekday
    /// A month page on her own layout (`nil`: the standard page).
    public let monthLayout: MonthLayout?
    /// When she chose the month page's layout (`nil`: never; the standard page). Of two
    /// versions of a page on different layouts, the later choice wins.
    public let changed: Date?

    public init(name: String, firstWeekday: Weekday, monthLayout: MonthLayout? = nil, changed: Date? = nil) {
        self.name = name
        self.firstWeekday = firstWeekday
        self.monthLayout = monthLayout.flatMap { $0.isStandard ? nil : $0.validated }
        self.changed = changed
    }

    /// The same printed places (the date of the choice aside): no ink has to move.
    public static func == (a: PageLayoutStamp, b: PageLayoutStamp) -> Bool {
        a.firstWeekday == b.firstWeekday && a.monthLayout == b.monthLayout && a.geometryName == b.geometryName
    }

    /// `month-v1` and `month-v2` print their boxes in the same places.
    private var geometryName: String {
        name.hasPrefix("month-") ? "month" : name
    }

    /// The regions ink is anchored to on this layout, parked ones included, for pages whose
    /// layout can change (month pages); `nil` for the others.
    public func anchorRegions(for page: PlannerPage) -> [PageRegion]? {
        guard case .month(let month) = page else { return nil }
        return MonthPageLayout(month: month, firstWeekday: firstWeekday, layout: monthLayout ?? .standard).anchorRegions
    }

    /// Where each stroke (by its bounds, in canvas units) goes when the page moves from this
    /// layout to `new`: one transform per stroke (`nil`: it stays), or `nil` when nothing moves.
    public func migration(to new: PageLayoutStamp, page: PlannerPage, strokeBounds: [CGRect]) -> [CGAffineTransform?]? {
        guard self != new, let old = anchorRegions(for: page), let target = new.anchorRegions(for: page) else { return nil }
        let transforms = strokeBounds.map { LayoutMigration.transform(forStrokeBounds: $0, from: old, to: target) }
        return transforms.contains { $0 != nil } ? transforms : nil
    }

    /// Of two layouts of the same page, the one chosen later (the standard page before any choice).
    public static func later(_ a: PageLayoutStamp, _ b: PageLayoutStamp) -> PageLayoutStamp {
        (a.changed ?? .distantPast) >= (b.changed ?? .distantPast) ? a : b
    }

    /// The layout the app prints today for a page.
    ///
    /// - `month-v1`: TO DO LIST, TO BUY and MEMO (an open box) at the bottom.
    /// - `month-v2`: TO DO LIST and MEMO as ruled lines over the space of the old TO BUY and
    ///   MEMO. The bottom of the page did not move, so v1 ink keeps its coordinates.
    public static func current(
        for page: PlannerPage, firstWeekday: Weekday = .defaultFirst, monthLayouts: MonthLayouts = MonthLayouts()
    ) -> PageLayoutStamp {
        switch page {
        case .year: PageLayoutStamp(name: "year-v1", firstWeekday: firstWeekday)
        case .month(let month):
            PageLayoutStamp(
                name: "month-v2", firstWeekday: firstWeekday,
                monthLayout: monthLayouts.entry(for: month)?.layout, changed: monthLayouts.entry(for: month)?.changed
            )
        case .week: PageLayoutStamp(name: "week-v1", firstWeekday: firstWeekday)
        case .toBuy: PageLayoutStamp(name: "tobuy-v1", firstWeekday: firstWeekday)
        case .journal: PageLayoutStamp(name: "journal-v1", firstWeekday: firstWeekday)
        case .sketch: PageLayoutStamp(name: "sketch-v1", firstWeekday: firstWeekday)
        }
    }
}
