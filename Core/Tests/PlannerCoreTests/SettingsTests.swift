import Foundation
import Testing
@testable import PlannerCore

private let t0 = Date(timeIntervalSince1970: 1_900_000_000)

private func at(_ seconds: TimeInterval) -> Date {
    t0.addingTimeInterval(seconds)
}

@Suite("Settings (prompt 9)")
struct SettingsTests {
    @Test func anEmptyFileIsTheDefaults() {
        let settings = PlannerSettings(file: SettingsFile())
        #expect(settings == .defaults)
        #expect(settings.palette == InkPalette.colors)
        #expect(settings.toolbarTools == InkTool.allCases)
        #expect(settings.favorites.isEmpty)
        #expect(settings.paper == PaperSettings())
        #expect(settings.lock == .off)
        #expect(settings.look == .standard)
    }

    @Test func survivesTheFile() throws {
        var file = SettingsFile()
        let teal = InkColor.custom(red: 0.1, green: 0.6, blue: 0.6)
        file.set(.palette, to: [InkPalette.colors[1], teal], at: at(1))
        var widths = ToolWidths()
        widths.set(9, for: .pen, index: 2)
        file.set(.widths, to: widths, at: at(2))
        let favorite = FavoritePen(tool: .highlighter, color: teal, widthIndex: 0, opacityIndex: 1)
        file.set(.favorites, to: [favorite], at: at(3))
        file.set(.toolbarTools, to: [InkTool.pen, .eraser], at: at(4))
        file.set(.paper, to: PaperSettings(journalPaper: .grid, spacing: .wide, lineStrength: .strong, dark: true), at: at(5))
        file.set(.lock, to: LockMode.journal, at: at(6))

        let data = try JSONFileStore<SettingsFile>.encode(file)
        let loaded = try JSONFileStore<SettingsFile>.decode(data)
        #expect(loaded == file)
        let settings = PlannerSettings(file: loaded)
        #expect(settings.palette == [InkPalette.colors[1], teal])
        #expect(settings.widths.values(for: .pen) == [1.5, 3, 9])
        #expect(settings.favorites == [favorite])
        #expect(settings.toolbarTools == [.pen, .eraser])
        #expect(settings.paper.journalPaper == .grid)
        #expect(settings.paper.spacing == .wide)
        #expect(settings.look == TemplateLook(dark: true, lineStrength: .strong))
        #expect(settings.lock == .journal)
        // The same file always gives the same bytes (no endless sync).
        #expect(try JSONFileStore<SettingsFile>.encode(loaded) == data)
    }

    @Test func eachSettingMergesOnItsOwnAndTheNewerWins() {
        var ipad = SettingsFile()
        ipad.set(.palette, to: [InkPalette.colors[0]], at: at(10))
        ipad.set(.paper, to: PaperSettings(dark: true), at: at(5))
        var iphone = SettingsFile()
        iphone.set(.paper, to: PaperSettings(lineStrength: .faint), at: at(20))
        iphone.set(.lock, to: LockMode.app, at: at(1))

        let merged = SettingsFile.merged(ipad, iphone)
        #expect(merged == SettingsFile.merged(iphone, ipad))
        let settings = PlannerSettings(file: merged)
        #expect(settings.palette == [InkPalette.colors[0]])
        #expect(settings.paper == PaperSettings(lineStrength: .faint))
        #expect(settings.lock == .app)
        // Merging again changes nothing.
        #expect(SettingsFile.merged(merged, iphone) == merged)
    }

    @Test func aTieWithinTheSameSecondIsTheSameOnBothDevices() {
        var a = SettingsFile()
        a.set(.lock, to: LockMode.app, at: at(7.2))
        var b = SettingsFile()
        b.set(.lock, to: LockMode.journal, at: at(7.9))
        let ab = SettingsFile.merged(a, b)
        let ba = SettingsFile.merged(b, a)
        #expect(PlannerSettings(file: ab).lock == PlannerSettings(file: ba).lock)
    }

    @Test func aResetReachesTheOtherDevice() {
        var old = SettingsFile()
        old.set(.paper, to: PaperSettings(dark: true), at: at(1))
        var reset = old
        reset.set(.paper, to: PaperSettings?.none, at: at(2))
        #expect(PlannerSettings(file: reset).paper == PaperSettings())
        #expect(PlannerSettings(file: SettingsFile.merged(old, reset)).paper == PaperSettings())
    }

    @Test func settingsOfANewerAppAreKept() throws {
        let newer = #"""
        {"settings":{"lock":{"modified":"2030-03-17T17:46:40Z","value":"app"},"monthLayouts":{"modified":"2030-03-17T17:46:40Z","value":{"from":"2027-01","goals":false}}},"version":1}
        """#
        let file = try JSONFileStore<SettingsFile>.decode(Data(newer.utf8))
        var mine = SettingsFile()
        mine.set(.palette, to: [InkPalette.colors[3]], at: at(1))
        let merged = SettingsFile.merged(mine, file)
        #expect(merged.settings["monthLayouts"]?.value == .object(["from": .string("2027-01"), "goals": .bool(false)]))
        #expect(PlannerSettings(file: merged).lock == .app)
    }

    @Test func unreadableSettingsAreTheDefaults() throws {
        let odd = #"""
        {"settings":{"lock":{"modified":"2030-03-17T17:46:40Z","value":"forever"},"palette":{"modified":"2030-03-17T17:46:40Z","value":[]},"paper":{"modified":"2030-03-17T17:46:40Z","value":{"dark":true,"spacing":"enormous"}}},"version":1}
        """#
        let settings = PlannerSettings(file: try JSONFileStore<SettingsFile>.decode(Data(odd.utf8)))
        #expect(settings.lock == .off)
        #expect(settings.palette == InkPalette.colors)
        // What can be read is kept.
        #expect(settings.paper == PaperSettings(dark: true))
    }

    @Test func theToolbarAlwaysHasSomethingThatDraws() {
        #expect(InkTool.validToolbar([.eraser, .lasso]) == [.pen, .eraser, .lasso])
        #expect(InkTool.validToolbar([.lasso, .pencil, .pencil]) == [.pencil, .lasso])
        #expect(InkTool.validToolbar([]) == [.pen])
    }

    @Test func thePaletteIsNeverEmptyOrTooLong() {
        #expect(InkPalette.valid([]) == InkPalette.colors)
        let many = (0..<20).map { InkColor(key: "c\($0)", hex: UInt32($0)) }
        #expect(InkPalette.valid(many).count == InkPalette.maxCount)
        let twice = [InkPalette.colors[0], InkPalette.colors[0], InkPalette.colors[2]]
        #expect(InkPalette.valid(twice).map(\.key) == ["pink", "red"])
    }
}

@Suite("Colours, widths and favourite pens")
struct InkCustomizationTests {
    @Test func coloursAreKeptToEightBits() throws {
        let color = InkColor(key: "custom-1", red: 0.5, green: 0.25, blue: 1)
        #expect(color.hexString == "8040FF")
        let data = try JSONEncoder().encode(color)
        #expect(String(decoding: data, as: UTF8.self).contains(#""hex":"8040FF""#))
        #expect(try JSONDecoder().decode(InkColor.self, from: data) == color)
        #expect(InkColor(key: "x", hex: 0x0000FF).hexString == "0000FF")
        let custom = InkColor.custom(red: 1, green: 0, blue: 0)
        #expect(custom.key.hasPrefix("custom-"))
        #expect(custom.hex == 0xFF0000)
    }

    @Test func aBadColourIsNotRead() {
        let bad = #"{"key":"pink","hex":"pink"}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(InkColor.self, from: Data(bad.utf8)) }
    }

    @Test func widthsStayInTheirRange() {
        var widths = ToolWidths()
        #expect(widths.isDefault)
        widths.set(500, for: .pen, index: 0)
        #expect(widths.values(for: .pen)[0] == InkWidths.range(for: .pen).upperBound)
        widths.set(2.345, for: .highlighter, index: 1)
        #expect(widths.values(for: .highlighter)[1] == InkWidths.range(for: .highlighter).lowerBound)
        widths.set(7.06, for: .pencil, index: 2)
        #expect(widths.values(for: .pencil)[2] == 7.1)
        widths.set(3, for: .lasso, index: 0)
        #expect(widths.values(for: .lasso).isEmpty)
        widths.reset(.pen)
        #expect(widths.values(for: .pen) == InkWidths.values(for: .pen))
        // Back to the defaults by hand: nothing is stored for that tool.
        widths.reset(.highlighter)
        widths.set(4.5, for: .pencil, index: 2)
        widths.set(8, for: .pencil, index: 2)
        #expect(widths.isDefault)
    }

    @Test func theSelectedToolUsesHerWidths() {
        var widths = ToolWidths()
        widths.set(10, for: .pen, index: 1)
        var state = InkToolState()
        #expect(state.width(with: widths) == 10)
        #expect(state.width == 3)
        state.select(.lasso)
        #expect(state.width(with: widths) == nil)
    }

    @Test func aColourOutsideThePaletteStillDraws() {
        let teal = InkColor.custom(red: 0, green: 0.5, blue: 0.5)
        var state = InkToolState()
        state.select(.eraser)
        state.selectColor(teal)
        #expect(state.tool == .pen)
        #expect(state.color == teal)
        #expect(state.colorIndex(in: InkPalette.colors) == nil)
        #expect(state.colorIndex(in: InkPalette.colors + [teal]) == 6)
    }

    @Test func anEditedColourIsFollowed() {
        var state = InkToolState()
        state.selectColor(0)
        let deeper = InkPalette.colors[0].with(red: 0.8, green: 0.1, blue: 0.4)
        state.follow([deeper] + InkPalette.colors.dropFirst())
        #expect(state.color == deeper)
        #expect(state.colorIndex(in: [deeper]) == 0)
        // Taken out of the palette: kept until another is picked.
        state.follow(Array(InkPalette.colors.dropFirst()))
        #expect(state.color == deeper)
    }

    @Test func favouritePens() throws {
        var state = InkToolState()
        state.select(.highlighter)
        state.selectColor(3)
        state.selectWidth(2)
        state.selectHighlighterOpacity(0)
        let favorite = try #require(state.favorite())
        #expect(favorite.tool == .highlighter && favorite.color.key == "blue" && favorite.widthIndex == 2 && favorite.opacityIndex == 0)
        #expect(state.isUsing(favorite))

        state.select(.pen)
        state.selectColor(0)
        #expect(!state.isUsing(favorite))
        state.apply(favorite)
        #expect(state.tool == .highlighter)
        #expect(state.color.key == "blue")
        #expect(state.widthIndex == 2)
        #expect(state.opacity == 0.3)
        #expect(state.isUsing(favorite))
        // The pen kept its own width.
        #expect(state.widthIndex(for: .pen) == 1)

        state.select(.eraser)
        #expect(state.favorite() == nil)
        #expect(FavoritePen.valid([favorite, favorite, FavoritePen(tool: .lasso, color: favorite.color, widthIndex: 0)]) == [favorite])
    }

    @Test func toolsSavedWithAColourIndexStillLoad() throws {
        // As the versions before prompt 9 saved them: the colour as a place in the six colours.
        let saved = #"{"tool":"pen","previousTool":"eraser","lastInkTool":"pen","eraserMode":"partial","colorIndex":4,"widths":{},"highlighterOpacity":1}"#
        let state = try JSONDecoder().decode(InkToolState.self, from: Data(saved.utf8))
        #expect(state.color.key == "green")
        #expect(state.highlighterOpacityIndex == 1)
        let again = try JSONDecoder().decode(InkToolState.self, from: try JSONEncoder().encode(state))
        #expect(again == state)
    }
}

@Suite("Paper looks")
struct TemplateLookTests {
    @Test func theStandardLookIsThePaperAsItWas() {
        for tone in Tone.allCases {
            #expect(TemplateLook.standard.white(tone) == tone.white)
        }
    }

    @Test func strongerLinesAreDarker() {
        let faint = TemplateLook(lineStrength: .faint)
        let strong = TemplateLook(lineStrength: .strong)
        for tone in [Tone.rule, .border, .fill] {
            #expect(faint.white(tone) > tone.white)
            #expect(strong.white(tone) < tone.white)
        }
        #expect(strong.white(.ink) == 0)
        #expect(faint.white(.paper) == 1)
    }

    @Test func darkPaperTurnsTheGreysAround() {
        let dark = TemplateLook(dark: true)
        #expect(dark.white(.ink) == 1)
        #expect(dark.white(.paper) < 0.1)
        // Still in the same order: lines between the paper and the text.
        #expect(dark.white(.rule) > dark.white(.paper))
        #expect(dark.white(.text) > dark.white(.rule))
        #expect(dark.white(.fill) < dark.white(.rule))
    }

    @Test func spacingChangesTheJournalPaper() {
        func lines(_ spacing: LineSpacing) -> Int {
            JournalPageTemplate.make(paper: .lined, spacing: spacing, label: "", heading: "").shapes.filter {
                if case .line = $0 { return true }
                return false
            }.count
        }
        #expect(lines(.narrow) > lines(.normal))
        #expect(lines(.normal) > lines(.wide))
        // The normal spacing is the paper as it was.
        #expect(JournalPageTemplate.make(paper: .grid, spacing: .normal, label: "", heading: "")
            == JournalPageTemplate.make(paper: .grid, label: "", heading: ""))
        #expect(LineSpacing.normal.linedStep == JournalPageLayout.lineSpacing)
        #expect(LineSpacing.normal.gridStep == JournalPageLayout.gridSpacing)
    }

    @Test func aPageWithNormalSpacingIsSavedAsBefore() throws {
        let page = JournalPage(date: nil, spacing: .normal, created: t0)
        #expect(page.spacing == nil)
        let text = String(decoding: try JSONEncoder().encode(page), as: UTF8.self)
        #expect(!text.contains("spacing"))
        let wide = JournalPage(date: nil, spacing: .wide, created: t0)
        #expect(wide.lineSpacing == .wide)
        #expect(try JSONDecoder().decode(JournalPage.self, from: JSONEncoder().encode(wide)) == wide)
    }
}
