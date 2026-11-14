import CoreGraphics
import Foundation
import Testing
@testable import PlannerCore

/// Points with times, the way a pencil reports them (in screen points and seconds).
private struct Samples {
    var points: [CGPoint] = []
    var times: [TimeInterval] = []

    var lastTime: TimeInterval { times.last ?? 0 }
    var lastPoint: CGPoint { points.last ?? .zero }

    /// A trembling line from `a` to `b`: a zigzag `wobble` points to either side every
    /// `every` points, at `speed` points per second, a sample every 1/240 s.
    mutating func line(
        from a: CGPoint, to b: CGPoint, wobble: CGFloat = 5, every: CGFloat = 15, speed: CGFloat = 400
    ) {
        let length = hypot(b.x - a.x, b.y - a.y)
        let normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        let count = max(2, Int((length / speed) * 240))
        let start = times.isEmpty ? 0 : lastTime + 1.0 / 240
        for index in 0...count {
            let t = CGFloat(index) / CGFloat(count)
            let along = t * length
            // A triangle wave: 0 at the ends, ±wobble in between.
            let phase = (along / every).truncatingRemainder(dividingBy: 2)
            let side = (index == 0 || index == count) ? 0 : (phase < 1 ? phase : 2 - phase) * 2 - 1
            let offset = side * wobble
            points.append(CGPoint(
                x: a.x + (b.x - a.x) * t + normal.x * offset,
                y: a.y + (b.y - a.y) * t + normal.y * offset
            ))
            times.append(start + TimeInterval(index) / 240)
        }
    }

    /// The pencil stays at the last point for `seconds`, trembling up to `tremor` points.
    mutating func stay(for seconds: TimeInterval, tremor: CGFloat = 0) {
        let center = lastPoint
        let start = lastTime
        let count = Int(seconds * 240)
        for index in 1...max(1, count) {
            let angle = CGFloat(index) * 2.4
            points.append(CGPoint(x: center.x + cos(angle) * tremor, y: center.y + sin(angle) * tremor))
            times.append(start + TimeInterval(index) / 240)
        }
    }

    func feed(_ hold: inout StraightLineHold, from first: Int = 0) {
        for index in first..<points.count {
            if index == 0 {
                hold.begin(at: points[index], time: times[index])
            } else {
                hold.move(to: points[index], time: times[index])
            }
        }
    }
}

private func isAbout(_ value: TimeInterval?, _ expected: TimeInterval, within tolerance: TimeInterval = 1e-9) -> Bool {
    value.map { abs($0 - expected) <= tolerance } ?? false
}

@Suite("Hold at the end of a line to make it straight")
struct StraightLineHoldTests {
    private let start = CGPoint(x: 100, y: 200)
    private let end = CGPoint(x: 400, y: 330)

    @Test func aTremblingLineHeldStillBecomesStraight() {
        var samples = Samples()
        samples.line(from: start, to: end)
        var hold = StraightLineHold()
        samples.feed(&hold)
        let stopped = samples.lastTime

        // No events while a finger rests on the glass: the app asks on a timer.
        #expect(!hold.checkHold(at: stopped + 0.2))
        #expect(!hold.checkHold(at: stopped + 0.45))
        #expect(isAbout(hold.holdDeadline, stopped + 0.5, within: 0.02))
        #expect(hold.checkHold(at: stopped + 0.5))
        #expect(hold.isStraight)
        #expect(hold.start == start)
        #expect(hold.end == end)
        // Once only.
        #expect(!hold.checkHold(at: stopped + 2))
        #expect(hold.holdDeadline == nil)
    }

    @Test func aTremblingPencilStillCountsAsHeld() {
        var samples = Samples()
        samples.line(from: start, to: end)
        let stopped = samples.lastTime
        samples.stay(for: 0.6, tremor: 2)
        var hold = StraightLineHold()
        var straightAt: TimeInterval?
        for index in samples.points.indices {
            if index == 0 {
                hold.begin(at: samples.points[0], time: samples.times[0])
            } else {
                hold.move(to: samples.points[index], time: samples.times[index])
            }
            if straightAt == nil, hold.checkHold(at: samples.times[index]) {
                straightAt = samples.times[index]
            }
        }
        #expect(isAbout(straightAt, stopped + 0.5, within: 0.04), "Straight at \(String(describing: straightAt)), stopped at \(stopped)")
        #expect(hold.isLineLike)
    }

    @Test func liftingWithoutHoldingChangesNothing() {
        var samples = Samples()
        samples.line(from: start, to: end)
        var hold = StraightLineHold()
        samples.feed(&hold)
        // Lifted 0.3 s after stopping: the app never asks again.
        #expect(!hold.checkHold(at: samples.lastTime + 0.3))
        #expect(!hold.isStraight)
    }

    @Test func pausingInTheMiddleOfAStrokeCounts() {
        // Still for 0.5 s anywhere in a line-like stroke (the end so far) makes it straight.
        var samples = Samples()
        samples.line(from: start, to: CGPoint(x: 250, y: 265))
        var hold = StraightLineHold()
        samples.feed(&hold)
        #expect(hold.checkHold(at: samples.lastTime + 0.5))
    }

    @Test func drawingSlowlyIsNotHolding() {
        // 12 points a second: it gets 5 points away in less than half a second, so it is
        // never still for long enough.
        var hold = StraightLineHold()
        hold.begin(at: start, time: 0)
        var time: TimeInterval = 0
        var x = start.x
        while time < 3 {
            time += 1.0 / 60
            x += 12.0 / 60
            hold.move(to: CGPoint(x: x, y: start.y), time: time)
            #expect(!hold.checkHold(at: time), "Held at \(time)")
        }
    }

    @Test func shortStrokesStayAsTheyAre() {
        var samples = Samples()
        samples.line(from: start, to: CGPoint(x: start.x + 18, y: start.y + 6), wobble: 1, every: 4)
        var hold = StraightLineHold()
        samples.feed(&hold)
        #expect(!hold.checkHold(at: samples.lastTime + 1))
        #expect(!hold.isStraight)
    }

    @Test func curvesStayAsTheyAre() {
        // Half a circle, 100 points across.
        var hold = StraightLineHold()
        let center = CGPoint(x: 300, y: 300)
        for index in 0...180 {
            let angle = CGFloat(index) * .pi / 180
            let point = CGPoint(x: center.x - cos(angle) * 100, y: center.y - sin(angle) * 100)
            if index == 0 {
                hold.begin(at: point, time: 0)
            } else {
                hold.move(to: point, time: TimeInterval(index) / 240)
            }
        }
        #expect(!hold.isLineLike)
        #expect(!hold.checkHold(at: 2))
        // A gentle bow is still a line.
        var bow = StraightLineHold()
        for index in 0...100 {
            let t = CGFloat(index) / 100
            let point = CGPoint(x: 100 + 300 * t, y: 200 + 4 * 30 * t * (1 - t))
            if index == 0 { bow.begin(at: point, time: 0) } else { bow.move(to: point, time: TimeInterval(index) / 240) }
        }
        #expect(bow.isLineLike)
    }

    @Test func writingStaysAsItIs() {
        // Up-and-down strokes along a line, like handwriting: close to the line, but much longer.
        var hold = StraightLineHold()
        var time: TimeInterval = 0
        hold.begin(at: CGPoint(x: 100, y: 200), time: 0)
        for index in 1...40 {
            time += 0.03
            let point = CGPoint(x: 100 + CGFloat(index) * 4, y: index.isMultiple(of: 2) ? 200 : 214)
            hold.move(to: point, time: time)
        }
        #expect(!hold.isLineLike)
        #expect(!hold.checkHold(at: time + 1))
        // A line drawn back over itself is not one line either.
        var back = StraightLineHold()
        back.begin(at: CGPoint(x: 100, y: 200), time: 0)
        back.move(to: CGPoint(x: 300, y: 200), time: 0.2)
        back.move(to: CGPoint(x: 150, y: 200), time: 0.4)
        #expect(!back.checkHold(at: 1))
    }

    @Test func movingAfterTheHoldMovesTheEnd() {
        var samples = Samples()
        samples.line(from: start, to: end)
        var hold = StraightLineHold()
        samples.feed(&hold)
        #expect(hold.checkHold(at: samples.lastTime + 0.6))

        let later = samples.lastTime + 0.7
        hold.move(to: CGPoint(x: 380, y: 120), time: later)
        hold.move(to: CGPoint(x: 360, y: 90), time: later + 0.1)
        #expect(hold.isStraight)
        #expect(hold.start == start)
        #expect(hold.end == CGPoint(x: 360, y: 90))
        // Holding again changes nothing more.
        #expect(!hold.checkHold(at: later + 2))
    }

    @Test func aStrokeThatIsNotALineIsLookedAtOnceForEachStop() {
        var hold = StraightLineHold()
        hold.begin(at: CGPoint(x: 100, y: 100), time: 0)
        hold.move(to: CGPoint(x: 200, y: 200), time: 0.1)
        hold.move(to: CGPoint(x: 300, y: 100), time: 0.2)
        #expect(isAbout(hold.holdDeadline, 0.7))
        #expect(!hold.checkHold(at: 0.8))
        #expect(hold.holdDeadline == nil)
        // It goes on and comes back into line: the next stop is looked at again.
        hold.move(to: CGPoint(x: 600, y: 100), time: 1.0)
        #expect(isAbout(hold.holdDeadline, 1.5))
    }

    @Test func aNewStrokeStartsAfresh() {
        var samples = Samples()
        samples.line(from: start, to: end)
        var hold = StraightLineHold()
        samples.feed(&hold)
        #expect(hold.checkHold(at: samples.lastTime + 0.5))
        hold.begin(at: CGPoint(x: 10, y: 10), time: 20)
        #expect(!hold.isStraight)
        #expect(hold.start == CGPoint(x: 10, y: 10))
        #expect(isAbout(hold.holdDeadline, 20.5))
        #expect(!hold.checkHold(at: 21))
    }

    @Test func distanceToASegment() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
        #expect(StraightLineHold.distance(CGPoint(x: 5, y: 3), toSegmentFrom: a, to: b) == 3)
        #expect(StraightLineHold.distance(CGPoint(x: -4, y: 3), toSegmentFrom: a, to: b) == 5)
        #expect(StraightLineHold.distance(CGPoint(x: 13, y: 4), toSegmentFrom: a, to: b) == 5)
        #expect(StraightLineHold.distance(CGPoint(x: 3, y: 4), toSegmentFrom: a, to: a) == 5)
    }
}
