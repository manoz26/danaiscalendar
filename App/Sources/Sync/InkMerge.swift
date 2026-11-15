import PencilKit
import PlannerCore
import UIKit

/// The ink of two versions of a page, merged stroke by stroke (prompt 7), so that no
/// handwriting is ever thrown away.
///
/// PencilKit strokes have no ids, so a stroke is known by a key made of what it is: its
/// ink and colour, transform, when it was drawn, its points, its mask and its random seed.
/// Both drawings first go through PencilKit's file format, so that the same stroke read
/// from a file and kept in memory gives the same key.
enum InkMerge {
    /// Every stroke of both, each once: `mine` in its order, then what only `theirs` has.
    static func union(_ mine: PKDrawing, _ theirs: PKDrawing) -> PKDrawing {
        let a = normalized(mine)
        let b = normalized(theirs)
        return assemble(OrderedMerge.union(mine: keys(a), theirs: keys(b)), mine: a, theirs: b)
    }

    /// What was written or erased on each side since `base` is kept on both.
    static func threeWay(base: PKDrawing, mine: PKDrawing, theirs: PKDrawing) -> PKDrawing {
        let a = normalized(mine)
        let b = normalized(theirs)
        return assemble(OrderedMerge.threeWay(base: keys(normalized(base)), mine: keys(a), theirs: keys(b)), mine: a, theirs: b)
    }

    /// The same strokes, in the same order.
    static func sameStrokes(_ a: PKDrawing, _ b: PKDrawing) -> Bool {
        guard a.strokes.count == b.strokes.count else { return false }
        return keys(normalized(a)) == keys(normalized(b))
    }

    /// The drawing as PencilKit reads it back from a file.
    static func normalized(_ drawing: PKDrawing) -> PKDrawing {
        guard !drawing.strokes.isEmpty else { return drawing }
        return (try? PKDrawing(data: drawing.dataRepresentation())) ?? drawing
    }

    static func keys(_ drawing: PKDrawing) -> [String] {
        drawing.strokes.map(key)
    }

    static func key(_ stroke: PKStroke) -> String {
        let t = stroke.transform
        let path = stroke.path
        var parts = [
            stroke.ink.inkType.rawValue,
            color(stroke.ink.color),
            [t.a, t.b, t.c, t.d].map { number($0, 10_000) }.joined(separator: ",")
                + ";" + [t.tx, t.ty].map { number($0, 1000) }.joined(separator: ","),
            number(path.creationDate.timeIntervalSinceReferenceDate, 1000),
            String(path.count),
        ]
        if let first = path.first, let last = path.last {
            parts.append(point(first.location))
            parts.append(point(last.location))
            parts.append(number(first.size.width, 1000))
        }
        if let mask = stroke.mask {
            let bounds = mask.bounds
            parts.append([bounds.minX, bounds.minY, bounds.width, bounds.height].map { number($0, 100) }.joined(separator: ","))
        }
        parts.append(stroke.maskedPathRanges.map { "\(number($0.lowerBound, 1000))-\(number($0.upperBound, 1000))" }.joined(separator: ","))
        parts.append(String(stroke.randomSeed))
        return parts.joined(separator: "|")
    }

    private static func assemble(_ sources: [OrderedMerge.Source], mine: PKDrawing, theirs: PKDrawing) -> PKDrawing {
        let a = mine.strokes
        let b = theirs.strokes
        return PKDrawing(strokes: sources.map { source in
            switch source {
            case .mine(let index): a[index]
            case .theirs(let index): b[index]
            }
        })
    }

    private static func number(_ value: CGFloat, _ scale: CGFloat) -> String {
        let scaled = (value * scale).rounded()
        guard scaled.isFinite, abs(scaled) < 9e15 else { return "~" }
        return String(Int64(scaled))
    }

    private static func point(_ point: CGPoint) -> String {
        "\(number(point.x, 1000)),\(number(point.y, 1000))"
    }

    private static func color(_ color: UIColor) -> String {
        let cgColor = color.cgColor
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB).flatMap {
            cgColor.converted(to: $0, intent: .defaultIntent, options: nil)
        } ?? cgColor
        return (sRGB.components ?? []).map { number($0, 255) }.joined(separator: ",")
    }
}
