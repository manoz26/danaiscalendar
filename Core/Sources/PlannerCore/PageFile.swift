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

    public init(decoding data: Data) throws {
        let header = [UInt8](data.prefix(Self.headerSize))
        guard header.count >= 4, Array(header[0..<4]) == Self.signature else {
            throw PageFileError.notAPageFile
        }
        guard header.count == Self.headerSize else { throw PageFileError.truncated }
        guard header[4] == Self.containerVersion else {
            throw PageFileError.unsupportedVersion(Int(header[4]))
        }
        let length = Int(header[5]) << 24 | Int(header[6]) << 16 | Int(header[7]) << 8 | Int(header[8])
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

    public init(page: PlannerPage, layout: PageLayoutStamp, strokeCount: Int, modified: Date, writtenBy: String) {
        self.page = page.description
        self.layout = layout.name
        self.firstWeekday = layout.firstWeekday.key
        self.strokeCount = strokeCount
        self.modified = modified
        self.writtenBy = writtenBy
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

    public init(name: String, firstWeekday: Weekday) {
        self.name = name
        self.firstWeekday = firstWeekday
    }

    /// The layout the app prints today for a page.
    ///
    /// - `month-v1`: TO DO LIST, TO BUY and MEMO (an open box) at the bottom.
    /// - `month-v2`: TO DO LIST and MEMO as ruled lines over the space of the old TO BUY and
    ///   MEMO. The bottom of the page did not move, so v1 ink keeps its coordinates.
    public static func current(for page: PlannerPage, firstWeekday: Weekday = .defaultFirst) -> PageLayoutStamp {
        switch page {
        case .year: PageLayoutStamp(name: "year-v1", firstWeekday: firstWeekday)
        case .month: PageLayoutStamp(name: "month-v2", firstWeekday: firstWeekday)
        case .toBuy: PageLayoutStamp(name: "tobuy-v1", firstWeekday: firstWeekday)
        }
    }
}
