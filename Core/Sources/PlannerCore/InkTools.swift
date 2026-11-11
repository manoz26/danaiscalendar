import CoreGraphics

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
    public private(set) var colorIndex: Int
    /// Width (0...2) per tool, by `InkTool.rawValue`.
    private var widths: [String: Int]

    public init() {
        tool = .pen
        previousTool = .eraser
        lastInkTool = .pen
        eraserMode = .partial
        colorIndex = InkPalette.defaultIndex
        widths = [:]
    }

    public mutating func select(_ newTool: InkTool) {
        guard newTool != tool else { return }
        previousTool = tool
        tool = newTool
        if newTool.drawsInk { lastInkTool = newTool }
    }

    /// Picks an ink colour. With the eraser or lasso selected, goes back to the last pen.
    public mutating func selectColor(_ index: Int) {
        colorIndex = min(max(index, 0), InkPalette.colors.count - 1)
        if !tool.drawsInk { select(lastInkTool) }
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

    /// Colour of the ink tools (valid even if a saved index is out of range).
    public var color: InkColor {
        InkPalette.colors[min(max(colorIndex, 0), InkPalette.colors.count - 1)]
    }

    /// Width of the selected tool in canvas units (`nil` for the lasso).
    public var width: CGFloat? {
        InkWidths.value(for: tool, index: widthIndex)
    }
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
}

/// An ink colour, in sRGB.
public struct InkColor: Sendable, Equatable {
    /// Stable English name, e.g. "pink" (used in identifiers; the UI translates it).
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
}

/// The six ink colours of the toolbar: the only colour on screen.
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
}
