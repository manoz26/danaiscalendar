import Foundation

/// Text rules for the printed look of the planner.
public enum PlannerText {
    /// Uppercases text the way a printed planner would.
    ///
    /// Greek capitals carry no accents, and an accent that splits a vowel pair
    /// becomes a diaeresis on the second vowel: "Μάιος" → "ΜΑΪΟΣ", "Νοέμβριος" → "ΝΟΕΜΒΡΙΟΣ".
    /// Other languages use the normal uppercasing for their locale.
    public static func uppercased(_ text: String, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier == "el" else {
            return text.uppercased(with: locale)
        }
        return greekUppercased(text)
    }

    // MARK: - Greek

    private struct Cluster {
        var base: Unicode.Scalar
        var marks: [Unicode.Scalar]
    }

    private static let accents: Set<UInt32> = [
        0x0300, // grave (varia)
        0x0301, // acute (tonos/oxia)
        0x0342, // perispomeni
        0x0313, // psili
        0x0314, // dasia
    ]
    private static let diaeresis = Unicode.Scalar(UInt32(0x0308))!
    private static let firstOfPair: Set<String> = ["α", "ε", "ο", "υ"]
    private static let secondOfPair: Set<String> = ["ι", "υ"]

    private static func greekUppercased(_ text: String) -> String {
        var clusters: [Cluster] = []
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.generalCategory == .nonspacingMark, !clusters.isEmpty {
                clusters[clusters.count - 1].marks.append(scalar)
            } else {
                clusters.append(Cluster(base: scalar, marks: []))
            }
        }

        var output = String.UnicodeScalarView()
        var previousWasAccentedFirstOfPair = false
        for cluster in clusters {
            let hadAccent = cluster.marks.contains { accents.contains($0.value) }
            var marks = cluster.marks.filter { !accents.contains($0.value) }
            let base = String(cluster.base).lowercased()

            // "άι" / "όι" / "άυ": the accent on the first vowel means the pair is not
            // a diphthong. Without the accent, a diaeresis has to say so instead.
            if previousWasAccentedFirstOfPair,
               secondOfPair.contains(base),
               !hadAccent,
               !marks.contains(diaeresis) {
                marks.append(diaeresis)
            }

            output.append(cluster.base)
            output.append(contentsOf: marks)
            previousWasAccentedFirstOfPair = hadAccent && firstOfPair.contains(base)
        }

        return String(output).precomposedStringWithCanonicalMapping.uppercased()
    }
}
