import CoreText
import Foundation
import Testing
import UIKit

/// Runs inside the app, so `Bundle.main` is the real app bundle.
@Suite("App bundle resources")
@MainActor
struct BundleResourcesTests {
    @Test(arguments: ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"])
    func interIsRegistered(postScriptName: String) throws {
        let font = try #require(UIFont(name: postScriptName, size: 20), "\(postScriptName) is not registered")
        #expect(font.fontName == postScriptName)
    }

    @Test func interHasGreekGlyphs() throws {
        let font = try #require(UIFont(name: "Inter-Bold", size: 20))
        let text = "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩΪΫαβγδεζηθικλμνξοπρσςτυφχψωάέήίόύώ"
        let characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        let allFound = CTFontGetGlyphsForCharacters(font as CTFont, characters, &glyphs, characters.count)
        #expect(allFound)
        #expect(!glyphs.contains(0))
    }

    @Test func greekAndEnglishLocalizationsAreBundled() throws {
        #expect(Bundle.main.localizations.contains("en"))
        #expect(Bundle.main.localizations.contains("el"))

        let greekPath = try #require(Bundle.main.path(forResource: "el", ofType: "lproj"))
        let greek = try #require(Bundle(path: greekPath))
        #expect(greek.localizedString(forKey: "Month page for %@", value: nil, table: nil) == "Σελίδα μήνα: %@")
    }

    @Test func infoPlistBasics() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect(info["CFBundleDisplayName"] as? String == "Danai's Calendar")
        #expect(info["UIUserInterfaceStyle"] as? String == "Light")
    }
}
