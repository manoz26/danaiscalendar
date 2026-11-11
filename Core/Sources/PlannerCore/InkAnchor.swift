import CoreGraphics

/// Which printed area of a page a stroke of ink belongs to.
///
/// A stroke belongs to the region that contains the centre of its bounds. When several
/// regions do (a to-do line inside the to-do list, a day inside a small month), the
/// smallest one wins. Strokes in the margins belong to no region.
///
/// When a layout changes (prompt 9: boxes moved or hidden, more lines, another first
/// day of the week), each stroke moves and scales with its region, so ink never ends
/// up in the wrong box.
public enum InkAnchor {
    /// The region of a stroke, from its bounds (`PKStroke.renderBounds`).
    public static func region(forStrokeBounds bounds: CGRect, in template: PageTemplate) -> RegionID? {
        guard !bounds.isNull, !bounds.isInfinite else { return nil }
        return region(at: CGPoint(x: bounds.midX, y: bounds.midY), in: template)
    }

    /// The region of a stroke, from the points of its path.
    public static func region(forStrokePoints points: [CGPoint], in template: PageTemplate) -> RegionID? {
        guard let first = points.first else { return nil }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return region(at: CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2), in: template)
    }

    /// The smallest region under a point, or `nil` in the margins.
    public static func region(at point: CGPoint, in template: PageTemplate) -> RegionID? {
        template.regions(at: point).first?.id
    }
}
