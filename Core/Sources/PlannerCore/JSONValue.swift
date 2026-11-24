import Foundation

/// Any JSON value. The settings file keeps each setting as one, so that a setting this
/// version of the app does not know (written by a newer one on another device) survives
/// a merge here instead of being dropped.
public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// A Codable value as JSON (dates as ISO 8601, like the app's files).
    public init<Value: Encodable>(encoding value: Value) throws {
        let data = try Self.encoder.encode(value)
        self = try Self.decoder.decode(JSONValue.self, from: data)
    }

    /// The value as a Codable type.
    public func decoded<Value: Decodable>(as type: Value.Type) throws -> Value {
        try Self.decoder.decode(Value.self, from: try Self.encoder.encode(self))
    }

    /// The same bytes for the same value on every device (keys sorted): used to break ties.
    public var canonicalText: String {
        (try? Self.encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
