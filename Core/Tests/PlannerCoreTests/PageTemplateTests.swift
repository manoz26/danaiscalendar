import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

@Suite("Page templates")
struct PageTemplateTests {
    private let english = Locale(identifier: "en_US")
    private let greek = Locale(identifier: "el_GR")
    private let greekLabels = MonthPageLabels(
        goals: "Στόχοι", todo: "Να κάνω", memo: "Σημειώσεις", weekly: "Εβδομάδες"
    )
    private let november = YearMonth(year: 2026, month: 11)

    @Test func monthPagePrintsTitleLabelsHeadersAndDays() {
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english)
        let strings = template.texts.map(\.string)
        for expected in ["2026", "NOVEMBER", "WEEKLY", "GOALS", "TO DO LIST", "MEMO",
                         "MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"] {
            #expect(strings.contains(expected), "missing \(expected)")
        }
        #expect(!strings.contains("TO BUY"))
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
        for expected in ["ΜΑΪΟΣ", "ΣΤΟΧΟΙ", "ΝΑ ΚΑΝΩ", "ΣΗΜΕΙΩΣΕΙΣ", "ΕΒΔΟΜΑΔΕΣ", "ΔΕΥ", "ΚΥΡ"] {
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

    @Test func notesAreRuledLinesWithoutMarkers() {
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english)
        let memo = MonthPageLayout(month: november).memo
        let lines = template.shapes.filter {
            if case .line(let from, let to, _, _) = $0 { from.y == to.y && from.x == memo.frame.minX && to.x == memo.frame.maxX } else { false }
        }
        // The strong rule on top, and one line under each row.
        #expect(lines.count == memo.rows.count + 1)
        let markers = template.shapes.filter {
            switch $0 {
            case .circle(let center, _, _, _, _): memo.frame.contains(center)
            case .rect(let rect, _, _, _, _): memo.frame.intersects(rect)
            default: false
            }
        }
        #expect(markers.isEmpty)
    }

    @Test func birthdaysAreMarkedOnTheirDayAndWrittenInTheNotes() throws {
        let manos = BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 13), text: "Manos's birthday")
        let eleni = BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 21), text: "Eleni's birthday")
        let template = MonthPageTemplate.make(month: november, locale: english, labels: .english, birthdays: [manos, eleni])
        let layout = MonthPageLayout(month: november)
        let plain = MonthPageTemplate.make(month: november, locale: english, labels: .english)

        // A small gift (lid and box) in each day's cell, at the top right.
        for note in [manos, eleni] {
            let cell = try #require(layout.cell(for: note.date))
            let gifts = template.shapes.filter {
                if case .rect(let rect, nil, .text?, _, _) = $0 { cell.frame.contains(rect) && rect.minX > cell.frame.midX } else { false }
            }
            #expect(gifts.count == 2, "gift in \(note.date)")
        }

        // One line each in the notes, in order, from the first line.
        let texts = template.texts.filter { layout.memo.frame.contains($0.anchor) }
        #expect(texts.map(\.string) == ["13", "Manos's birthday", "21", "Eleni's birthday"])
        #expect(layout.memo.rows[0].contains(texts[0].anchor))
        #expect(layout.memo.rows[1].contains(texts[2].anchor))
        #expect(plain.texts.filter { layout.memo.frame.contains($0.anchor) }.isEmpty)

        // A birthday of another month is not printed, even on a day shown on this page.
        let december = BirthdayNote(date: PlannerDate(year: 2026, month: 12, day: 2), text: "Nikos's birthday")
        let other = MonthPageTemplate.make(month: november, locale: english, labels: .english, birthdays: [december])
        #expect(other == plain)
    }

    @Test func manyBirthdaysShareTheNotesLines() {
        let rows = MonthPageLayout.listRowCount
        func notes(_ count: Int) -> [BirthdayNote] {
            (0..<count).map { BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: $0 % 30 + 1), text: "Friend \($0)") }
        }
        let layout = MonthPageLayout(month: november)
        func printed(_ count: Int) -> [String] {
            MonthPageTemplate.make(month: november, locale: english, labels: .english, birthdays: notes(count))
                .texts.filter { layout.memo.frame.contains($0.anchor) && $0.font == .medium }.map(\.string)
        }
        #expect(printed(rows).count == rows)
        // Two per line when they don't fit, all inside the notes.
        #expect(printed(rows + 3).count == rows + 3)
        // Beyond two per line, the last place says how many more.
        let all = MonthPageTemplate.make(month: november, locale: english, labels: .english, birthdays: notes(2 * rows + 5))
            .texts.filter { layout.memo.frame.contains($0.anchor) }
        #expect(all.filter { $0.font == .medium }.count == 2 * rows - 1)
        #expect(all.last?.string == "+6")
    }

    @Test func toBuyPage() {
        let template = ToBuyPageTemplate.make(locale: greek, title: "Να αγοράσω")
        #expect(template.texts.map(\.string) == ["ΝΑ ΑΓΟΡΑΣΩ"])
        let layout = ToBuyPageLayout()
        let boxes = template.shapes.filter { if case .rect = $0 { true } else { false } }
        #expect(boxes.count == layout.rows.count)
        #expect(layout.rows.count == ToBuyPageLayout.rowsPerColumn * ToBuyPageLayout.columnCount)
        #expect(template.region(.title) != nil)
        #expect(template.region(.section(.tobuy))?.rect == layout.frame)
        #expect(template.region(.toBuyLine(1))?.rect == layout.rows[0])
        #expect(template.region(.toBuyLine(ToBuyPageLayout.rowsPerColumn + 1))?.rect.minY == layout.rows[0].minY)
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
            MonthPageTemplate.make(
                month: november, locale: greek, labels: greekLabels, today: PlannerDate(year: 2026, month: 11, day: 10),
                birthdays: [BirthdayNote(date: PlannerDate(year: 2026, month: 11, day: 13), text: "Μάνος — γενέθλια")]
            ),
            YearPageTemplate.make(year: 2026, locale: english),
            ToBuyPageTemplate.make(locale: english, title: "To buy"),
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
