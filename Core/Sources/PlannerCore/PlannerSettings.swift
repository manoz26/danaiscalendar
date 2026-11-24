import CoreGraphics
import Foundation

// MARK: - The settings file

/// The settings that make the app hers (prompt 9), the same on every device:
/// `Lists/settings.json`, `{"version": 1, "settings": {"palette": {"value": …, "modified": …}, …}}`.
///
/// Each setting is merged on its own: of two versions, the newer one wins (to the second;
/// on a tie, the same one on every device). A reset writes `null` with the date of the
/// reset, so that it reaches the other devices too. Settings this version does not know
/// (from a newer app) are kept as they are.
public struct SettingsFile: VersionedFile, Equatable {
    public static let currentVersion = 1
    public static let fileName = "settings.json"

    public var version: Int
    public var settings: [String: StoredSetting]

    public init(settings: [String: StoredSetting] = [:]) {
        version = Self.currentVersion
        self.settings = settings
    }

    /// A setting's value, or `nil` when it is the default (never set, reset, or unreadable).
    public func value<Value: Decodable>(_ key: SettingKey, as type: Value.Type) -> Value? {
        guard let stored = settings[key.rawValue], stored.value != .null else { return nil }
        return try? stored.value.decoded(as: type)
    }

    /// Sets a setting (`nil`: back to the default) as changed at `date`.
    public mutating func set<Value: Encodable>(_ key: SettingKey, to value: Value?, at date: Date = Date()) {
        let json = value.flatMap { try? JSONValue(encoding: $0) } ?? .null
        settings[key.rawValue] = StoredSetting(value: json, modified: date)
    }

    /// When a setting last changed here (`nil`: never).
    public func modified(_ key: SettingKey) -> Date? {
        settings[key.rawValue]?.modified
    }

    /// Two versions (two devices, or a backup): each setting from the one that changed it last.
    /// The result does not depend on the order of the two.
    public static func merged(_ mine: SettingsFile, _ theirs: SettingsFile) -> SettingsFile {
        var result: [String: StoredSetting] = [:]
        for key in Set(mine.settings.keys).union(theirs.settings.keys) {
            switch (mine.settings[key], theirs.settings[key]) {
            case let (a?, b?): result[key] = StoredSetting.newer(a, b)
            case let (a?, nil): result[key] = a
            case let (nil, b?): result[key] = b
            case (nil, nil): break
            }
        }
        return SettingsFile(settings: result)
    }
}

/// One setting in the file: its value and when it last changed.
public struct StoredSetting: Codable, Sendable, Equatable {
    public var value: JSONValue
    public var modified: Date

    public init(value: JSONValue, modified: Date) {
        self.value = value
        self.modified = modified
    }

    /// The one changed last (whole seconds, as the file keeps them); on a tie, the same on every device.
    static func newer(_ a: StoredSetting, _ b: StoredSetting) -> StoredSetting {
        let (ta, tb) = (ListMerge.seconds(a.modified), ListMerge.seconds(b.modified))
        if ta != tb { return ta > tb ? a : b }
        return a.value.canonicalText >= b.value.canonicalText ? a : b
    }
}

/// The settings that are synced, by their name in the file.
public enum SettingKey: String, CaseIterable, Sendable {
    /// The ink colours of the toolbar, in order.
    case palette
    /// The three widths of each tool.
    case widths
    /// Favourite pens: tool, colour and width with one tap.
    case favorites
    /// Which tools the toolbar shows.
    case toolbarTools
    /// The journal's default paper, the lines' spacing and strength, dark paper.
    case paper
    /// Face ID / Touch ID / passcode.
    case lock
}

// MARK: - The settings

/// Every synced setting, read from the file with the defaults for what is not set.
public struct PlannerSettings: Sendable, Equatable {
    public var palette: [InkColor]
    public var widths: ToolWidths
    public var favorites: [FavoritePen]
    /// The tools the toolbar shows, in the toolbar's order (at least one that draws).
    public var toolbarTools: [InkTool]
    public var paper: PaperSettings
    public var lock: LockMode

    public init(
        palette: [InkColor] = InkPalette.colors, widths: ToolWidths = ToolWidths(), favorites: [FavoritePen] = [],
        toolbarTools: [InkTool] = InkTool.allCases, paper: PaperSettings = PaperSettings(), lock: LockMode = .off
    ) {
        self.palette = InkPalette.valid(palette)
        self.widths = widths
        self.favorites = FavoritePen.valid(favorites)
        self.toolbarTools = InkTool.validToolbar(toolbarTools)
        self.paper = paper
        self.lock = lock
    }

    public init(file: SettingsFile) {
        self.init(
            palette: file.value(.palette, as: [InkColor].self) ?? InkPalette.colors,
            widths: file.value(.widths, as: ToolWidths.self) ?? ToolWidths(),
            favorites: file.value(.favorites, as: [FavoritePen].self) ?? [],
            toolbarTools: file.value(.toolbarTools, as: [InkTool].self) ?? InkTool.allCases,
            paper: file.value(.paper, as: PaperSettings.self) ?? PaperSettings(),
            lock: file.value(.lock, as: LockMode.self) ?? .off
        )
    }

    public static let defaults = PlannerSettings()

    /// How the printed pages look with these settings.
    public var look: TemplateLook {
        TemplateLook(dark: paper.dark, lineStrength: paper.lineStrength)
    }
}

extension InkTool {
    /// The toolbar's tools: in the usual order, each once, and at least one that draws (the pen).
    public static func validToolbar(_ tools: [InkTool]) -> [InkTool] {
        let shown = allCases.filter(tools.contains)
        return shown.contains(where: \.drawsInk) ? shown : [.pen] + shown
    }
}

// MARK: - Paper

/// The paper (Settings → Paper).
public struct PaperSettings: Codable, Sendable, Equatable {
    /// The paper of new journal pages.
    public var journalPaper: PaperStyle
    /// The spacing of the lines, squares or dots of new journal pages.
    public var spacing: LineSpacing
    /// How dark the printed lines and boxes are, on every page.
    public var lineStrength: LineStrength
    /// Black paper with white lines (the ink's black shows white).
    public var dark: Bool

    public init(
        journalPaper: PaperStyle = .defaultStyle, spacing: LineSpacing = .normal,
        lineStrength: LineStrength = .normal, dark: Bool = false
    ) {
        self.journalPaper = journalPaper
        self.spacing = spacing
        self.lineStrength = lineStrength
        self.dark = dark
    }

    private enum CodingKeys: String, CodingKey {
        case journalPaper, spacing, lineStrength, dark
    }

    /// Anything missing or unknown (e.g. from a newer app) is the default.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        journalPaper = (try? container.decodeIfPresent(PaperStyle.self, forKey: .journalPaper)) ?? .defaultStyle
        spacing = (try? container.decodeIfPresent(LineSpacing.self, forKey: .spacing)) ?? .normal
        lineStrength = (try? container.decodeIfPresent(LineStrength.self, forKey: .lineStrength)) ?? .normal
        dark = (try? container.decodeIfPresent(Bool.self, forKey: .dark)) ?? false
    }
}

/// The spacing of a journal page's lines, squares or dots.
public enum LineSpacing: String, Codable, CaseIterable, Sendable {
    case narrow, normal, wide

    /// Lined paper: the step of the month page's lists (33) by default.
    public var linedStep: CGFloat {
        switch self {
        case .narrow: 26
        case .normal: 33
        case .wide: 42
        }
    }

    /// Grid and dotted paper.
    public var gridStep: CGFloat {
        switch self {
        case .narrow: 20
        case .normal: 25
        case .wide: 32
        }
    }
}

/// How dark the printed lines and boxes are (faint to strong).
public enum LineStrength: String, Codable, CaseIterable, Sendable {
    case faint, normal, strong
}

/// Locking the app with Face ID, Touch ID or the device passcode.
public enum LockMode: String, Codable, CaseIterable, Sendable {
    case off
    /// The whole app.
    case app
    /// Only the journal and the sketches.
    case journal
}

/// How the printed template is coloured: light or dark paper, and the strength of the lines.
/// Still black and white: only greys.
public struct TemplateLook: Sendable, Equatable {
    public var dark: Bool
    public var lineStrength: LineStrength

    public init(dark: Bool = false, lineStrength: LineStrength = .normal) {
        self.dark = dark
        self.lineStrength = lineStrength
    }

    /// White paper, normal lines: the pages as they always were (and every export).
    public static let standard = TemplateLook()

    /// The darkest grey of dark paper (not pure black, so that the page still reads as paper).
    static let darkPaper: CGFloat = 0.08

    /// 0 = black, 1 = white.
    public func white(_ tone: Tone) -> CGFloat {
        let light = lightWhite(tone)
        guard dark else { return light }
        return Self.darkPaper + (1 - light) * (1 - Self.darkPaper)
    }

    public func color(_ tone: Tone) -> CGColor {
        CGColor(gray: white(tone), alpha: 1)
    }

    private func lightWhite(_ tone: Tone) -> CGFloat {
        switch (tone, lineStrength) {
        case (.rule, .faint): 0.88
        case (.rule, .strong): 0.66
        case (.border, .faint): 0.45
        case (.border, .strong): 0.15
        case (.fill, .faint): 0.97
        case (.fill, .strong): 0.92
        default: tone.white
        }
    }
}
