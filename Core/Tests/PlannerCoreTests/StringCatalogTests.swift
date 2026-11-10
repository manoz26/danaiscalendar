import Foundation
import Testing

/// Checks the app's String Catalog (App/Resources/Localizable.xcstrings) from the source
/// tree, so a missing Greek or English text fails in the first seconds of CI.
@Suite("String catalog")
struct StringCatalogTests {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // PlannerCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Core
        .deletingLastPathComponent() // repo root
        .appending(path: "App/Resources/Localizable.xcstrings")

    @Test func everyStringIsTranslatedIntoEnglishAndGreek() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(catalog["sourceLanguage"] as? String == "en")
        let strings = try #require(catalog["strings"] as? [String: Any])
        #expect(!strings.isEmpty)

        for (key, value) in strings {
            let entry = value as? [String: Any] ?? [:]
            if entry["shouldTranslate"] as? Bool == false { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in ["en", "el"] {
                let localization = localizations[language] as? [String: Any]
                // Plural/device variations are checked by Xcode; only make sure they exist.
                if localization?["variations"] != nil { continue }
                let unit = localization?["stringUnit"] as? [String: Any]
                let translated = unit?["state"] as? String == "translated"
                let text = unit?["value"] as? String ?? ""
                #expect(translated && !text.isEmpty, "\"\(key)\" has no \(language) translation")
            }
        }
    }
}
