import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

@Suite("Page templates")
struct PageTemplateTests {
    private let english = Locale(identifier: "en_US")
    private let greek = Locale(identifier: "el_GR")
    private let greekLabels = MonthPageLabels(
        goals: "Στόχοι", todo: "Να κάνω", memo: "Σημειώσεις", toBuy: "Να αγοράσω", weekly: "Εβδομάδες"
    )
    private let november = YearMonth(year: 2026, month: 11)

    @Test func monthPagePrintsTitleLabelsHeadersAndDays() {
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english)
        let strings = template.texts.map(\.string)
        for expected in ["2026", "NOVEMBER", "WEEKLY", "GOALS", "TO DO LIST", "TO BUY", "MEMO",
                         "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] {
            #expect(strings.contains(expected), "missing \(expected)")
        }
        // WEEKLY 1-6 for a 6-week month.
        for number in 1...6 {
            #expect(strings.contains(String(number)))
        }
        // 42 day numbers: 6 days of October, 30 of November, 6 of December.
        let dayTexts = template.texts.filter { $0.size == MonthPageLayout.dayNumberSize }
        #expect(dayTexts.count == 42)
        #expect(dayTexts.filter { $0.tone == .faint }.count == 12)
    }

    @Test func greekMonthPageIsInGreekCapitals() {
        let template = MonthPageTemplate.make(month: YearMonth(year: 2026, month: 5), locale: greek, labels: greekLabels)
        let strings = template.texts.map(\.string)
        for expected in ["ΜΑΪΟΣ", "ΣΤΟΧΟΙ", "ΝΑ ΚΑΝΩ", "ΣΗΜΕΙΩΣΕΙΣ", "ΝΑ ΑΓΟΡΑΣΩ", "ΕΒΔΟΜΑΔΕΣ", "ΔΕΥ", "ΚΥΡ"] {
            #expect(strings.contains(expected), "missing \(expected)")
        }
    }

    @Test func sundaysAreGreyAndOtherMonthsFaint() throws {
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english)
        let layout = MonthPageLayout(month: november)
        func number(_ date: PlannerDate) throws -> TemplateText {
            let cell = try #require(layout.cell(for: date))
            return try #require(template.texts.first {
                $0.string == String(date.day) && cell.frame.contains($0.anchor)
            })
        }
        #expect(try number(PlannerDate(year: 2026, month: 11, day: 8)).tone == .secondary) // Sunday
        #expect(try number(PlannerDate(year: 2026, month: 11, day: 9)).tone == .text)
        #expect(try number(PlannerDate(year: 2026, month: 10, day: 26)).tone == .faint)
        #expect(try number(PlannerDate(year: 2026, month: 12, day: 6)).tone == .faint)
        #expect(template.texts.first { $0.string == "SUN" }?.tone == .secondary)
    }

    @Test func todayIsMarkedOnlyInItsOwnMonth() {
        let today = PlannerDate(year: 2026, month: 11, day: 10)
        func marks(_ template: PageTemplate) -> Int {
            template.shapes.filter {
                if case .circle(_, _, .ink?, _, _) = $0 { true } else { false }
            }.count
        }
        #expect(marks(MonthPageTemplate.make(month: november, locale: english, labels: .english, today: today)) == 1)
        #expect(marks(MonthPageTemplate.make(month: november, locale: english, labels: .english)) == 0)
        // 1 December is printed on the November page, but is marked only on December's.
        let december1 = PlannerDate(year: 2026, month: 12, day: 1)
        #expect(marks(MonthPageTemplate.make(month: november, locale: english, labels: .english, today: december1)) == 0)
        #expect(marks(MonthPageTemplate.make(month: november.next, locale: english, labels: .english, today: december1)) == 1)
        #expect(marks(YearPageTemplate.make(year: 2026, locale: english, today: today)) == 1)
        #expect(marks(YearPageTemplate.make(year: 2027, locale: english, today: today)) == 0)
        // The marked number is printed in white on the black mark.
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english, today: today)
        #expect(template.texts.filter { $0.tone == .paper }.map(\.string) == ["10"])
    }

    @Test func yearPagePrintsTwelveNumberedMonths() {
        let template = YearPageTemplate.make(year: 2028, locale: english)
        let strings = template.texts.map(\.string)
        #expect(strings.first == "2028")
        #expect(strings.contains("01 JANUARY"))
        #expect(strings.contains("02 FEBRUARY"))
        #expect(strings.contains("12 DECEMBER"))
        // Only the days of each month, no days of other months: 366 numbers in 2028.
        let dayTexts = template.texts.filter { $0.size == YearPageLayout.dayNumberSize }
        #expect(dayTexts.count == 366)
        // 12 grey notes boxes.
        let notes = template.shapes.filter { if case .rect(_, .fill?, nil, _, _) = $0 { true } else { false } }
        #expect(notes.count == 12)
    }

    @Test func greekYearPage() {
        let strings = YearPageTemplate.make(year: 2026, locale: greek).texts.map(\.string)
        #expect(strings.contains("05 ΜΑΪΟΣ"))
        #expect(strings.contains("Δ"))
        #expect(strings.contains("Κ"))
    }

    @Test func templatesUseOnlyGreysAndInter() {
        let templates = [
            MonthPageTemplate.make(month: november, locale: greek, labels: greekLabels, today: PlannerDate(year: 2026, month: 11, day: 10)),
            YearPageTemplate.make(year: 2026, locale: english),
        ]
        for template in templates {
            for text in template.texts {
                #expect(PlannerFont.allCases.contains(text.font))
                #expect(text.size >= 9 && text.size <= 40)
            }
        }
        // Tones are greys by construction (CGColor(gray:)); paper is white, ink black.
        #expect(Tone.paper.white == 1)
        #expect(Tone.ink.white == 0)
        #expect(Tone.allCases.allSatisfy { (0...1).contains($0.white) })
    }
}
