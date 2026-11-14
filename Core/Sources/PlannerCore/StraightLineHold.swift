import CoreGraphics
import Foundation

/// "Hold to draw a straight line", as in Apple Notes: a stroke that is roughly straight, with
/// the pencil (or finger) kept still at its end for half a second, becomes a straight line from
/// where it began to where it stopped. Moving on without lifting then moves the line's end.
/// Lifting without holding changes nothing.
///
/// Points are in screen points (movement on the glass, whatever the zoom) and times in
/// seconds on the clock of `UITouch.timestamp`.
public struct StraightLineHold: Sendable {
    public struct Settings: Sendable, Equatable {
        /// How long the pencil must stay still at the end of the stroke.
        public var holdDuration: TimeInterval = 0.5
        /// Moving less than this from where it stopped still counts as still (a hand trembles).
        public var stillRadius: CGFloat = 5
        /// Shorter strokes (a dot, a letter) never become lines.
        public var minimumLength: CGFloat = 24
        /// How far the stroke may stray from the straight line: this fraction of its length…
        public var maximumDeviation: CGFloat = 0.15
        /// …but at least this much, for short lines.
        public var minimumDeviation: CGFloat = 8
        /// The stroke's own length over the straight line's. More is writing or a scribble.
        public var maximumDetour: CGFloat = 1.35

        public init() {}
    }

    public let settings: Settings
    /// Where the stroke began.
    public private(set) var start: CGPoint?
    /// The latest point of the stroke (the end of the straight line once it is one).
    public private(set) var end: CGPoint?
    /// The stroke has become a straight line (stays so until the stroke ends).
    public private(set) var isStraight = false

    /// The places where the stroke moved on, each more than `stillRadius` from the one before:
    /// a trembling pencil's jitter never counts as path.
    private var path: [CGPoint] = []
    private var pathLength: CGFloat = 0
    /// The last of `path`.
    private var stillPoint = CGPoint.zero
    private var stillSince: TimeInterval = 0
    /// This still moment was already looked at (and the stroke was not a line).
    private var checkedThisStill = false

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// A new stroke begins.
    public mutating func begin(at point: CGPoint, time: TimeInterval) {
        start = point
        end = point
        isStraight = false
        path = [point]
        pathLength = 0
        stillPoint = point
        stillSince = time
        checkedThisStill = false
    }

    /// The stroke goes on to `point`.
    public mutating func move(to point: CGPoint, time: TimeInterval) {
        guard start != nil else {
            begin(at: point, time: time)
            return
        }
        end = point
        guard !isStraight else { return }
        let moved = Self.distance(point, stillPoint)
        if moved > settings.stillRadius {
            pathLength += moved
            path.append(point)
            stillPoint = point
            stillSince = time
            checkedThisStill = false
        }
    }

    /// When the stroke will have been still long enough, unless it moves again (`nil` when
    /// there is nothing left to wait for).
    public var holdDeadline: TimeInterval? {
        guard start != nil, !isStraight, !checkedThisStill else { return nil }
        return stillSince + settings.holdDuration
    }

    /// Looks at the stroke at `time` (on a timer, and on every move). True once: at the moment
    /// the stroke should become a straight line from `start` to `end`.
    public mutating func checkHold(at time: TimeInterval) -> Bool {
        guard let deadline = holdDeadline, time >= deadline else { return false }
        checkedThisStill = true
        guard isLineLike else { return false }
        isStraight = true
        return true
    }

    /// The stroke so far is long enough and close enough to the straight line from its start
    /// to its latest point.
    public var isLineLike: Bool {
        guard let start, let end else { return false }
        let length = Self.distance(start, end)
        guard length >= settings.minimumLength else { return false }
        let allowed = max(settings.minimumDeviation, settings.maximumDeviation * length)
        for point in path where Self.distance(point, toSegmentFrom: start, to: end) > allowed {
            return false
        }
        let travelled = pathLength + Self.distance(stillPoint, end)
        return travelled <= settings.maximumDetour * length
    }

    // MARK: - Geometry

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Distance from `point` to the segment from `a` to `b`.
    static func distance(_ point: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return distance(point, a) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return distance(point, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }
}
