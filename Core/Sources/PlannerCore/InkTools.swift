import CoreGraphics
import Foundation

/// The drawing tools of the toolbar.
public enum InkTool: String, CaseIterable, Sendable, Codable {
    case pen, pencil, highlighter, eraser, lasso

    /// Pen, pencil and highlighter leave ink in a colour.
    public var drawsInk: Bool {
        switch self {
        case .pen, .pencil, .highlighter: true
        case .eraser, .lasso: false
        }
    }

    /// Everything but the lasso comes in three widths.
    public var hasWidths: Bool { self != .lasso }
}

public enum EraserMode: String, CaseIterable, Sendable, Codable {
    /// Rubs out only what it touches (pixel eraser).
    case partial
    /// Removes every stroke it touches, whole.
    case wholeStroke
}

/// What the toolbar has selected. Saved between launches.
public struct InkToolState: Sendable, Equatable, Codable {
    public static let widthCount = 3

    public private(set) var tool: InkTool
    /// The tool before the current one (for the Pencil's double tap and squeeze).
    public private(set) var previousTool: InkTool
    /// The last pen, pencil or highlighter, for when a colour is picked with the eraser or lasso selected.
    public private(set) var lastInkTool: InkTool
    public var eraserMode: EraserMode
    /// The ink colour: one of the palette's, or the colour of a favourite pen (it still draws
    /// if it was taken out of the palette since).
    public private(set) var color: InkColor
    /// Width (0...2) per tool, by `InkTool.rawValue`.
    private var widths: [String: Int]
    /// How strong the highlighter is (see `InkOpacities`). Only new strokes use it.
    private var highlighterOpacity: Int

    public init() {
        tool = .pen
        previousTool = .eraser
        lastInkTool = .pen
        eraserMode = .partial
        color = InkPalette.colors[InkPalette.defaultIndex]
        widths = [:]
        highlighterOpacity = InkOpacities.defaultIndex
    }

    private enum CodingKeys: String, CodingKey {
        case tool, previousTool, lastInkTool, eraserMode, color, colorIndex, widths, highlighterOpacity
    }

    /// Tools saved by an older version (without the highlighter's opacity, or with the colour
    /// as a place in the six colours of the first palette) keep everything else.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decode(InkTool.self, forKey: .tool)
        previousTool = try container.decode(InkTool.self, forKey: .previousTool)
        lastInkTool = try container.decode(InkTool.self, forKey: .lastInkTool)
        eraserMode = try container.decode(EraserMode.self, forKey: .eraserMode)
        if let color = try container.decodeIfPresent(InkColor.self, forKey: .color) {
            self.color = color
        } else {
            let index = try container.decodeIfPresent(Int.self, forKey: .colorIndex) ?? InkPalette.defaultIndex
            color = InkPalette.colors[min(max(index, 0), InkPalette.colors.count - 1)]
        }
        widths = try container.decode([String: Int].self, forKey: .widths)
        highlighterOpacity = try container.decodeIfPresent(Int.self, forKey: .highlighterOpacity) ?? InkOpacities.defaultIndex
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tool, forKey: .tool)
        try container.encode(previousTool, forKey: .previousTool)
        try container.encode(lastInkTool, forKey: .lastInkTool)
        try container.encode(eraserMode, forKey: .eraserMode)
        try container.encode(color, forKey: .color)
        try container.encode(widths, forKey: .widths)
        try container.encode(highlighterOpacity, forKey: .highlighterOpacity)
    }

    public mutating func select(_ newTool: InkTool) {
        guard newTool != tool else { return }
        previousTool = tool
        tool = newTool
        if newTool.drawsInk { lastInkTool = newTool }
    }

    /// Picks a colour of the palette. With the eraser or lasso selected, goes back to the last pen.
    public mutating func selectColor(_ index: Int, in palette: [InkColor] = InkPalette.colors) {
        guard !palette.isEmpty else { return }
        selectColor(palette[min(max(index, 0), palette.count - 1)])
    }

    /// Picks an ink colour. With the eraser or lasso selected, goes back to the last pen.
    public mutating func selectColor(_ newColor: InkColor) {
        color = newColor
        if !tool.drawsInk { select(lastInkTool) }
    }

    /// Where the colour is in a palette (by its key, or else the same colour), if it is there.
    public func colorIndex(in palette: [InkColor]) -> Int? {
        palette.firstIndex { $0.key == color.key } ?? palette.firstIndex { $0.hex == color.hex }
    }

    /// The palette was edited: a colour that changed there changes here too. A colour taken
    /// out of it stays until another is picked.
    public mutating func follow(_ palette: [InkColor]) {
        if let edited = palette.first(where: { $0.key == color.key }), edited != color {
            color = edited
        }
    }

    /// Width (0 thin, 1 medium, 2 thick) of a tool.
    public func widthIndex(for tool: InkTool) -> Int {
        min(max(widths[tool.rawValue] ?? 1, 0), Self.widthCount - 1)
    }

    /// Width of the selected tool.
    public var widthIndex: Int { widthIndex(for: tool) }

    public mutating func selectWidth(_ index: Int) {
        guard tool.hasWidths else { return }
        widths[tool.rawValue] = min(max(index, 0), Self.widthCount - 1)
    }

    /// The Pencil's double tap or squeeze set to "switch to eraser": eraser on, or back
    /// to the tool before it.
    public mutating func toggleEraser() {
        if tool == .eraser {
            select(previousTool == .eraser ? lastInkTool : previousTool)
        } else {
            select(.eraser)
        }
    }

    /// The Pencil's double tap or squeeze set to "switch to previous tool".
    public mutating func switchToPrevious() {
        select(previousTool)
    }

    /// Width of the selected tool in canvas units (`nil` for the lasso), with the default widths.
    public var width: CGFloat? {
        width(with: ToolWidths())
    }

    /// Width of the selected tool in canvas units (`nil` for the lasso).
    public func width(with widths: ToolWidths) -> CGFloat? {
        widths.value(for: tool, index: widthIndex)
    }

    /// The highlighter's opacity level (0 faint, 1 medium, 2 strong).
    public var highlighterOpacityIndex: Int {
        min(max(highlighterOpacity, 0), InkOpacities.highlighter.count - 1)
    }

    /// Picks the highlighter's opacity, and the highlighter with it.
    public mutating func selectHighlighterOpacity(_ index: Int) {
        highlighterOpacity = min(max(index, 0), InkOpacities.highlighter.count - 1)
        select(.highlighter)
    }

    /// Opacity of the ink of the selected tool: the highlighter's level, otherwise 1.
    public var opacity: Double {
        tool == .highlighter ? InkOpacities.highlighter[highlighterOpacityIndex] : 1
    }

    // MARK: Favourite pens

    /// The pen, pencil or highlighter selected now, as a favourite (`nil` for the eraser or lasso).
    public func favorite(id: UUID = UUID()) -> FavoritePen? {
        guard tool.drawsInk else { return nil }
        return FavoritePen(
            id: id, tool: tool, color: color, widthIndex: widthIndex,
            opacityIndex: tool == .highlighter ? highlighterOpacityIndex : InkOpacities.defaultIndex
        )
    }

    /// Takes a favourite pen: its tool, colour, width (and the highlighter's opacity).
    public mutating func apply(_ favorite: FavoritePen) {
        guard favorite.tool.drawsInk else { return }
        select(favorite.tool)
        color = favorite.color
        widths[favorite.tool.rawValue] = min(max(favorite.widthIndex, 0), Self.widthCount - 1)
        if favorite.tool == .highlighter {
            highlighterOpacity = min(max(favorite.opacityIndex, 0), InkOpacities.highlighter.count - 1)
        }
    }

    /// The selected tool is exactly that favourite pen.
    public func isUsing(_ favorite: FavoritePen) -> Bool {
        let width = min(max(favorite.widthIndex, 0), Self.widthCount - 1)
        let opacity = min(max(favorite.opacityIndex, 0), InkOpacities.highlighter.count - 1)
        return tool == favorite.tool && color.hex == favorite.color.hex && widthIndex == width
            && (tool != .highlighter || highlighterOpacityIndex == opacity)
    }
}

/// A favourite pen: a tool with its colour and width (and the highlighter's opacity), one tap away.
public struct FavoritePen: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var tool: InkTool
    public var color: InkColor
    public var widthIndex: Int
    public var opacityIndex: Int

    public init(
        id: UUID = UUID(), tool: InkTool, color: InkColor, widthIndex: Int, opacityIndex: Int = InkOpacities.defaultIndex
    ) {
        self.id = id
        self.tool = tool
        self.color = color
        self.widthIndex = widthIndex
        self.opacityIndex = opacityIndex
    }

    /// How many fit in the toolbar.
    public static let maxCount = 4

    /// Each once, only pens, pencils and highlighters, at most `maxCount`.
    public static func valid(_ pens: [FavoritePen]) -> [FavoritePen] {
        var seen: Set<UUID> = []
        return Array(pens.filter { $0.tool.drawsInk && seen.insert($0.id).inserted }.prefix(maxCount))
    }
}

/// How see-through the highlighter is: three levels, from faint to the full colour.
public enum InkOpacities {
    public static let highlighter: [Double] = [0.3, 0.6, 1]
    /// Strong: the highlighter as it was before it had levels.
    public static let defaultIndex = 2
}

/// The three widths of each tool, in canvas units (a page is 1000 wide).
public enum InkWidths {
    public static func values(for tool: InkTool) -> [CGFloat] {
        switch tool {
        case .pen: [1.5, 3, 5.5]
        case .pencil: [2.5, 4.5, 8]
        case .highlighter: [10, 17, 28]
        case .eraser: [8, 20, 45]
        case .lasso: []
        }
    }

    public static func value(for tool: InkTool, index: Int) -> CGFloat? {
        let values = values(for: tool)
        guard !values.isEmpty else { return nil }
        return values[min(max(index, 0), values.count - 1)]
    }

    /// How thin and how thick each width of a tool can be made (Settings → Pens and colours).
    public static func range(for tool: InkTool) -> ClosedRange<CGFloat> {
        switch tool {
        case .pen: 0.5...12
        case .pencil: 1...16
        case .highlighter: 4...60
        case .eraser: 4...90
        case .lasso: 0...0
        }
    }
}

/// The three widths of each tool as she set them (the defaults of `InkWidths` otherwise),
/// in canvas units. JSON: `{"pen": [1.5, 3, 5.5], …}`, only the tools she changed.
public struct ToolWidths: Codable, Sendable, Equatable {
    private var values: [String: [Double]]

    public init() {
        values = [:]
    }

    public init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: [Double]].self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }

    /// The three widths of a tool (none for the lasso), each within the tool's range.
    public func values(for tool: InkTool) -> [CGFloat] {
        let defaults = InkWidths.values(for: tool)
        guard let custom = values[tool.rawValue], custom.count == defaults.count else { return defaults }
        let range = InkWidths.range(for: tool)
        return custom.map { value in
            value.isFinite ? min(max(CGFloat(value), range.lowerBound), range.upperBound) : range.lowerBound
        }
    }

    public func value(for tool: InkTool, index: Int) -> CGFloat? {
        let values = values(for: tool)
        guard !values.isEmpty else { return nil }
        return values[min(max(index, 0), values.count - 1)]
    }

    /// Changes one width of a tool (kept within its range, to a tenth).
    public mutating func set(_ width: CGFloat, for tool: InkTool, index: Int) {
        var current = values(for: tool)
        guard current.indices.contains(index) else { return }
        let range = InkWidths.range(for: tool)
        current[index] = (min(max(width, range.lowerBound), range.upperBound) * 10).rounded() / 10
        values[tool.rawValue] = current == InkWidths.values(for: tool) ? nil : current.map(Double.init)
    }

    /// The tool's widths back to the defaults.
    public mutating func reset(_ tool: InkTool) {
        values[tool.rawValue] = nil
    }

    public var isDefault: Bool { values.isEmpty }
}

/// An ink colour, in sRGB. JSON: `{"key": "pink", "hex": "F0559B"}`.
public struct InkColor: Sendable, Hashable, Codable {
    /// Stable name: "pink", … for the first six (used in identifiers; the UI translates them),
    /// "custom-…" for the ones she added.
    public let key: String
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(key: String, hex: UInt32) {
        self.key = key
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    /// Kept to 8 bits per channel, as the file keeps it.
    public init(key: String, red: Double, green: Double, blue: Double) {
        func byte(_ value: Double) -> UInt32 {
            UInt32((min(max(value.isFinite ? value : 0, 0), 1) * 255).rounded())
        }
        self.init(key: key, hex: byte(red) << 16 | byte(green) << 8 | byte(blue))
    }

    /// A new colour of hers, with a key of its own.
    public static func custom(red: Double, green: Double, blue: Double) -> InkColor {
        let id = UUID().uuidString.lowercased().prefix(8)
        return InkColor(key: "custom-\(id)", red: red, green: green, blue: blue)
    }

    public var hex: UInt32 {
        UInt32((red * 255).rounded()) << 16 | UInt32((green * 255).rounded()) << 8 | UInt32((blue * 255).rounded())
    }

    /// E.g. "F0559B".
    public var hexString: String {
        let digits = String(hex, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 6 - digits.count)) + digits
    }

    /// The same colour with another value (an edited colour of the palette keeps its key).
    public func with(red: Double, green: Double, blue: Double) -> InkColor {
        InkColor(key: key, red: red, green: green, blue: blue)
    }

    private enum CodingKeys: String, CodingKey {
        case key, hex
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decode(String.self, forKey: .key)
        let text = try container.decode(String.self, forKey: .hex)
        guard text.count == 6, let hex = UInt32(text, radix: 16) else {
            throw DecodingError.dataCorruptedError(forKey: .hex, in: container, debugDescription: "Not a colour: \(text)")
        }
        self.init(key: key, hex: hex)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(hexString, forKey: .hex)
    }
}

/// The ink colours of the toolbar: the only colour on screen. She can change, add,
/// remove and reorder them (Settings → Pens and colours); these are the defaults.
public enum InkPalette {
    /// In the order of the reference planner.
    public static let colors: [InkColor] = [
        InkColor(key: "pink", hex: 0xF0559B),
        InkColor(key: "black", hex: 0x111111),
        InkColor(key: "red", hex: 0xE02424),
        InkColor(key: "blue", hex: 0x1E6FE8),
        InkColor(key: "green", hex: 0x1F8A3B),
        InkColor(key: "purple", hex: 0x8A2BB5),
    ]

    /// Black.
    public static let defaultIndex = 1

    /// How many fit in the toolbar (two columns of six).
    public static let maxCount = 12

    /// Each key once, at most `maxCount`, never empty (then the defaults).
    public static func valid(_ palette: [InkColor]) -> [InkColor] {
        var seen: Set<String> = []
        let unique = Array(palette.filter { seen.insert($0.key).inserted }.prefix(maxCount))
        return unique.isEmpty ? colors : unique
    }
}
