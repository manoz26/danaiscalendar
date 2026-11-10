import Foundation
import Testing
@testable import PlannerCore

@Suite("Printed uppercase")
struct PlannerTextTests {
    private let greek = Locale(identifier: "el_GR")
    private let english = Locale(identifier: "en_US")

    @Test("Greek capitals drop accents, split vowel pairs get a diaeresis", arguments: [
        ("Μάιος", "ΜΑΪΟΣ"),
        ("Νοέμβριος", "ΝΟΕΜΒΡΙΟΣ"),
        ("Αύγουστος", "ΑΥΓΟΥΣΤΟΣ"),
        ("ρολόι", "ΡΟΛΟΪ"),
        ("νεράιδα", "ΝΕΡΑΪΔΑ"),
        ("άυλος", "ΑΫΛΟΣ"),
        ("πρωί", "ΠΡΩΙ"),
        ("προϊόν", "ΠΡΟΪΟΝ"),
        ("Κυριακή", "ΚΥΡΙΑΚΗ"),
        ("όλες οι μέρες", "ΟΛΕΣ ΟΙ ΜΕΡΕΣ"),
        ("Ήδη ΆΝΩ", "ΗΔΗ ΑΝΩ"),
        ("ευχαριστώ", "ΕΥΧΑΡΙΣΤΩ"),
        ("οίκος", "ΟΙΚΟΣ"),
        ("Λίστα To Do", "ΛΙΣΤΑ TO DO"),
    ])
    func greekUppercase(input: String, expected: String) {
        #expect(PlannerText.uppercased(input, locale: greek) == expected)
    }

    @Test func greekOutputHasNoAccentMarks() {
        let result = PlannerText.uppercased("άέήίόύώΐΰ", locale: greek)
        let scalars = result.decomposedStringWithCanonicalMapping.unicodeScalars.map(\.value)
        #expect(!scalars.contains(0x0301))
        #expect(result == "ΑΕΗΙΟΥΩΪΫ")
    }

    @Test func englishUppercase() {
        #expect(PlannerText.uppercased("To do list", locale: english) == "TO DO LIST")
        #expect(PlannerText.uppercased("Memo", locale: Locale(identifier: "en")) == "MEMO")
    }
}
