#if DEBUG
import PencilKit
import PlannerCore
import UIKit

/// Strokes the UI tests put on a page (`-DCSampleInk YES`): a pure red rectangle, 20%
/// inside each of a few known regions. The tests look for the red pixels on screen and
/// check that they sit exactly there, so ink and print are proven to line up.
enum SampleInk {
    static let color = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
    /// Fraction of the region's size between its edges and the rectangle.
    static let inset: CGFloat = 0.2

    /// Month page: goals, the 3rd and the 15th, to-do list, memo. Year page: the notes
    /// of February and July, and the small November.
    static func regions(for page: PlannerPage) -> [RegionID] {
        switch page {
        case .month(let month):
            [
                .section(.goals),
                .day(PlannerDate(year: month.year, month: month.month, day: 3)),
                .day(PlannerDate(year: month.year, month: month.month, day: 15)),
                .section(.todo),
                .section(.memo),
            ]
        case .year(let year):
            [
                .monthNotes(YearMonth(year: year, month: 2)),
                .monthNotes(YearMonth(year: year, month: 7)),
                .month(YearMonth(year: year, month: 11)),
            ]
        }
    }

    static func drawing(for page: PlannerPage, template: PageTemplate) -> PKDrawing {
        let strokes = regions(for: page).compactMap { template.region($0) }.map { region in
            rectangle(region.rect.insetBy(dx: region.rect.width * inset, dy: region.rect.height * inset))
        }
        return PKDrawing(strokes: strokes)
    }

    /// A closed rectangle drawn with the pen, with a point every 2 canvas units.
    static func rectangle(_ rect: CGRect, color: UIColor = color, width: CGFloat = 4) -> PKStroke {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY),
        ]
        var locations: [CGPoint] = []
        for (from, to) in zip(corners, corners.dropFirst()) {
            let steps = max(2, Int((hypot(to.x - from.x, to.y - from.y) / 2).rounded()))
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                locations.append(CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
        }
        locations.append(corners[corners.count - 1])
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(
                location: location, timeOffset: TimeInterval(index) * 0.004,
                size: CGSize(width: width, height: width), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2
            )
        }
        return PKStroke(ink: PKInk(.pen, color: color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
    }
}
#endif
