import Foundation
import Testing
@testable import PlannerCore

@Suite("Month titles")
struct MonthTitleTests {
    @Test func englishTitles() {
        let expected = [
            "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
            "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
        ]
        let locale = Locale(identifier: "en_GR")
        for (index, title) in expected.enumerated() {
            #expect(MonthTitle.text(for: YearMonth(year: 2026, month: index + 1), locale: locale) == title)
        }
    }

    @Test func greekTitlesUseNominativeWithoutAccents() {
        let expected = [
            "ΙΑΝΟΥΑΡΙΟΣ", "ΦΕΒΡΟΥΑΡΙΟΣ", "ΜΑΡΤΙΟΣ", "ΑΠΡΙΛΙΟΣ", "ΜΑΪΟΣ", "ΙΟΥΝΙΟΣ",
            "ΙΟΥΛΙΟΣ", "ΑΥΓΟΥΣΤΟΣ", "ΣΕΠΤΕΜΒΡΙΟΣ", "ΟΚΤΩΒΡΙΟΣ", "ΝΟΕΜΒΡΙΟΣ", "ΔΕΚΕΜΒΡΙΟΣ",
        ]
        let locale = Locale(identifier: "el_GR")
        for (index, title) in expected.enumerated() {
            #expect(MonthTitle.text(for: YearMonth(year: 2026, month: index + 1), locale: locale) == title)
        }
    }

    @Test func monthFollowsTheDeviceTimeZone() throws {
        // 30 Nov 2026, 23:30 UTC is already 1 December in Athens.
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-30T23:30:00Z"))
        let athens = try #require(TimeZone(identifier: "Europe/Athens"))
        let utc = try #require(TimeZone(identifier: "UTC"))
        let locale = Locale(identifier: "el_GR")
        #expect(YearMonth(date: instant, calendar: PlannerLocale.calendar(locale: locale, timeZone: athens)) == YearMonth(year: 2026, month: 12))
        #expect(YearMonth(date: instant, calendar: PlannerLocale.calendar(locale: locale, timeZone: utc)) == YearMonth(year: 2026, month: 11))
    }

    @Test func yearMonthIdentifierAndOrder() {
        #expect(YearMonth(year: 2026, month: 3).description == "2026-03")
        #expect(YearMonth(year: 2026, month: 12) < YearMonth(year: 2027, month: 1))
    }
}

@Suite("Locale")
struct PlannerLocaleTests {
    @Test func usesTheAppLanguageWithTheDeviceRegion() {
        let greek = PlannerLocale.resolve(preferredLocalization: "el", region: "GR")
        #expect(greek.language.languageCode?.identifier == "el")
        #expect(greek.region?.identifier == "GR")

        let englishInGreece = PlannerLocale.resolve(preferredLocalization: "en", region: "GR")
        #expect(englishInGreece.language.languageCode?.identifier == "en")
    }

    @Test func unsupportedOrMissingLanguageFallsBackToEnglish() {
        #expect(PlannerLocale.resolve(preferredLocalization: "fr", region: "FR").language.languageCode?.identifier == "en")
        #expect(PlannerLocale.resolve(preferredLocalization: nil, region: nil).language.languageCode?.identifier == "en")
        #expect(PlannerLocale.resolve(preferredLocalization: "Base", region: "US").language.languageCode?.identifier == "en")
    }

    @Test func calendarIsAlwaysGregorian() {
        let calendar = PlannerLocale.calendar(locale: Locale(identifier: "th_TH@calendar=buddhist"))
        #expect(calendar.identifier == .gregorian)
    }
}

@Suite("Page canvas")
struct PageCanvasTests {
    @Test func canvasIsPortrait1000x1400() {
        #expect(PageCanvas.size.width == 1000)
        #expect(PageCanvas.size.height == 1400)
    }

    @Test func scalesToTheViewWidth() {
        #expect(PageCanvas.scale(forWidth: 1032) == 1.032)
        #expect(PageCanvas.scale(forWidth: 0) == 0)
    }
}
