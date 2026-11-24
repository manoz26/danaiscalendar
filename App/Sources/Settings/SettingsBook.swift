import Foundation
import Observation
import PlannerCore

/// The settings that make the app hers (prompt 9): palette, widths, favourite pens, the
/// toolbar's tools, the paper and the lock. Kept in `Application Support/Lists/settings.json`
/// and synced through iCloud like the lists (each setting on its own, the newer wins).
///
/// Settings of this device only (drawing with a finger, which side the toolbar is on, the
/// Apple Calendar's calendars, whose ids differ per device) stay in UserDefaults.
@MainActor
@Observable
final class SettingsBook {
    private(set) var settings: PlannerSettings

    /// Called after every change, from here, another device or a backup.
    @ObservationIgnored var onChange: ((PlannerSettings) -> Void)?

    @ObservationIgnored private var file: SettingsFile
    @ObservationIgnored private let store: JSONFileStore<SettingsFile>
    @ObservationIgnored private let queue = DispatchQueue(label: "DanaisCalendar.Settings", qos: .userInitiated)

    init(folder: URL = BirthdayBook.defaultFolder) {
        let store = JSONFileStore<SettingsFile>(folder: folder, fileName: SettingsFile.fileName)
        self.store = store
        let file = Self.read(from: store) ?? SettingsFile()
        self.file = file
        settings = PlannerSettings(file: file)
    }

    // MARK: - Changing

    func setPalette(_ palette: [InkColor]) {
        set(.palette, InkPalette.valid(palette) == InkPalette.colors ? nil : InkPalette.valid(palette))
    }

    func setWidths(_ widths: ToolWidths) {
        set(.widths, widths.isDefault ? nil : widths)
    }

    func setFavorites(_ favorites: [FavoritePen]) {
        let valid = FavoritePen.valid(favorites)
        set(.favorites, valid.isEmpty ? nil : valid)
    }

    func setToolbarTools(_ tools: [InkTool]) {
        let valid = InkTool.validToolbar(tools)
        set(.toolbarTools, valid == InkTool.allCases ? nil : valid)
    }

    func setPaper(_ paper: PaperSettings) {
        set(.paper, paper == PaperSettings() ? nil : paper)
    }

    func setLock(_ lock: LockMode) {
        set(.lock, lock == .off ? nil : lock)
    }

    /// Settings back to the defaults ("Reset" of a section), on every device.
    func reset(_ keys: [SettingKey]) {
        for key in keys {
            file.set(key, to: Int?.none)
        }
        changed()
    }

    private func set<Value: Codable & Equatable>(_ key: SettingKey, _ value: Value?) {
        // Unchanged: nothing to save or sync.
        guard file.value(key, as: Value.self) != value else { return }
        file.set(key, to: value)
        changed()
    }

    private func changed() {
        let new = PlannerSettings(file: file)
        if new != settings {
            settings = new
        }
        onChange?(new)
        persist()
    }

    // MARK: - Sync and backup

    /// Another device's settings merged in. Returns the file's bytes.
    func receive(_ data: Data) throws -> Data {
        let merged = SettingsFile.merged(file, try JSONFileStore<SettingsFile>.decode(data))
        apply(merged)
        let store = store
        try queue.sync { try store.save(merged) }
        return try JSONFileStore<SettingsFile>.encode(merged)
    }

    /// A backup's settings: each one the newer of the two.
    func restore(_ data: Data) throws {
        apply(SettingsFile.merged(file, try JSONFileStore<SettingsFile>.decode(data)))
        persist()
    }

    private func apply(_ merged: SettingsFile) {
        file = merged
        let new = PlannerSettings(file: merged)
        guard new != settings else { return }
        settings = new
        onChange?(new)
        AppLog.info("Settings changed on another device")
    }

    /// Waits until every change so far is on disk (the app is going to the background).
    func waitUntilSaved() {
        queue.sync {}
    }

    private func persist() {
        let snapshot = file
        let store = store
        queue.async {
            do {
                try store.save(snapshot)
                LocalChanges.post("\(SyncPath.listsFolder)/\(SettingsFile.fileName)")
            } catch {
                AppLog.error("Could not save the settings", error)
            }
        }
    }

    /// Never fails: an unreadable file is logged and set aside (kept, not deleted), and the
    /// settings start from the defaults.
    private static func read(from store: JSONFileStore<SettingsFile>) -> SettingsFile? {
        do {
            let file = try store.load()
            if let file {
                AppLog.info("Settings: \(file.settings.keys.sorted().joined(separator: ", "))")
            }
            return file
        } catch {
            AppLog.error("Could not read the settings", error)
            do {
                if let kept = try store.setAside() {
                    AppLog.warning("Kept the unreadable settings file as \(kept.lastPathComponent); using the defaults")
                }
            } catch {
                AppLog.error("Could not set aside the settings file", error)
            }
            return nil
        }
    }

    #if DEBUG
    /// `-DCSampleSettings YES` (UI tests): a palette of eight, two favourite pens, wider pens
    /// and no lasso, as if she had set them. `-DCDarkPaper YES`: dark paper; `-DCLineStrength
    /// faint|strong`, `-DCLock app|journal`.
    func applyTestSettingsIfRequested() {
        if LaunchOptions.sampleSettings {
            var palette = InkPalette.colors
            palette.append(InkColor(key: "custom-teal", hex: 0x12A3A3))
            palette.append(InkColor(key: "custom-orange", hex: 0xF08A1C))
            setPalette(palette)
            var widths = ToolWidths()
            widths.set(4, for: .pen, index: 1)
            setWidths(widths)
            setFavorites([
                FavoritePen(tool: .pen, color: palette[3], widthIndex: 0),
                FavoritePen(tool: .highlighter, color: palette[6], widthIndex: 1, opacityIndex: 0),
            ])
            setToolbarTools([.pen, .pencil, .highlighter, .eraser])
        }
        var paper = settings.paper
        if LaunchOptions.darkPaper { paper.dark = true }
        if let strength = LaunchOptions.lineStrength { paper.lineStrength = strength }
        setPaper(paper)
        if let lock = LaunchOptions.lockMode { setLock(lock) }
    }
    #endif
}
