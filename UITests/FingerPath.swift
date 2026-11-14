import ObjectiveC
import XCTest

/// One finger moving through many points in a single touch, with pauses: a trembling line,
/// a hold at its end, a move after the hold.
///
/// XCUITest's public API only drags in a straight line (`press(forDuration:thenDragTo:…)`),
/// so this uses the XCTest classes that API is made of, `XCPointerEventPath` and
/// `XCSynthesizedEventRecord`, through the Objective-C runtime. Points are in screen points
/// (the app is in portrait), times in seconds from touching down.
enum FingerPath {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private typealias AllocIMP = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
    private typealias InitTouchIMP = @convention(c) (UnsafeMutableRawPointer, Selector, CGPoint, Double) -> UnsafeMutableRawPointer?
    private typealias InitRecordIMP = @convention(c) (UnsafeMutableRawPointer, Selector, NSString, Int) -> UnsafeMutableRawPointer?
    private typealias MoveIMP = @convention(c) (AnyObject, Selector, CGPoint, Double) -> Void
    private typealias OffsetIMP = @convention(c) (AnyObject, Selector, Double) -> Void
    private typealias AddIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
    private typealias SynthesizeIMP = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer?) -> ObjCBool

    /// Touches down at the first point, moves through the others at their times, and lifts
    /// at `liftAt`. Returns once the touch has been played.
    @MainActor
    static func perform(_ points: [(point: CGPoint, time: TimeInterval)], liftAt: TimeInterval) throws {
        guard let first = points.first else { return }
        guard let pathClass = NSClassFromString("XCPointerEventPath"),
              let recordClass = NSClassFromString("XCSynthesizedEventRecord") else {
            throw Failure(description: "XCTest's event classes were not found")
        }

        let path = try make(pathClass, "initForTouchAtPoint:offset:", as: InitTouchIMP.self) { initialize, raw, selector in
            initialize(raw, selector, first.point, first.time)
        }
        let (move, moveSelector) = try method(pathClass, "moveToPoint:atOffset:", as: MoveIMP.self)
        for step in points.dropFirst() {
            move(path, moveSelector, step.point, step.time)
        }
        let (lift, liftSelector) = try method(pathClass, "liftUpAtOffset:", as: OffsetIMP.self)
        lift(path, liftSelector, liftAt)

        let record = try make(recordClass, "initWithName:interfaceOrientation:", as: InitRecordIMP.self) { initialize, raw, selector in
            initialize(raw, selector, "finger path" as NSString, UIInterfaceOrientation.portrait.rawValue)
        }
        let (add, addSelector) = try method(recordClass, "addPointerEventPath:", as: AddIMP.self)
        add(record, addSelector, path)
        let (synthesize, synthesizeSelector) = try method(recordClass, "synthesizeWithError:", as: SynthesizeIMP.self)
        guard synthesize(record, synthesizeSelector, nil).boolValue else {
            throw Failure(description: "XCTest could not play the finger path")
        }
    }

    /// A trembling line: a zigzag `wobble` points to either side of the straight line, every
    /// `every` points along it, at `speed` points per second, a point every 1/100 s.
    static func trembling(
        from a: CGPoint, to b: CGPoint, startingAt start: TimeInterval = 0,
        wobble: CGFloat = 12, every: CGFloat = 40, speed: CGFloat = 350
    ) -> [(point: CGPoint, time: TimeInterval)] {
        let length = hypot(b.x - a.x, b.y - a.y)
        let normal = CGPoint(x: -(b.y - a.y) / length, y: (b.x - a.x) / length)
        let count = max(2, Int((length / speed) * 100))
        return (0...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            let phase = (t * length / every).truncatingRemainder(dividingBy: 2)
            let side = (index == 0 || index == count) ? 0 : (phase < 1 ? phase : 2 - phase) * 2 - 1
            let point = CGPoint(
                x: a.x + (b.x - a.x) * t + normal.x * side * wobble,
                y: a.y + (b.y - a.y) * t + normal.y * side * wobble
            )
            return (point, start + TimeInterval(index) / 100)
        }
    }

    /// A steady move from `a` to `b` taking `duration` seconds.
    static func straight(
        from a: CGPoint, to b: CGPoint, startingAt start: TimeInterval, duration: TimeInterval
    ) -> [(point: CGPoint, time: TimeInterval)] {
        let count = max(2, Int(duration * 100))
        return (1...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return (CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t), start + duration * Double(t))
        }
    }

    // MARK: - Runtime

    private static func method<T>(_ cls: AnyClass, _ name: String, as type: T.Type) throws -> (T, Selector) {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(cls, selector) else {
            throw Failure(description: "\(NSStringFromClass(cls)) has no \(name)")
        }
        return (unsafeBitCast(method_getImplementation(method), to: type), selector)
    }

    /// alloc + an init method, by hand: the raw pointers keep ARC out of the init's ownership rules.
    private static func make<T>(
        _ cls: AnyClass, _ initName: String, as type: T.Type,
        _ call: (T, UnsafeMutableRawPointer, Selector) -> UnsafeMutableRawPointer?
    ) throws -> AnyObject {
        let allocSelector = NSSelectorFromString("alloc")
        guard let allocMethod = class_getClassMethod(cls, allocSelector) else {
            throw Failure(description: "\(NSStringFromClass(cls)) has no alloc")
        }
        let alloc = unsafeBitCast(method_getImplementation(allocMethod), to: AllocIMP.self)
        let (initialize, selector) = try method(cls, initName, as: type)
        guard let raw = alloc(cls, allocSelector), let made = call(initialize, raw, selector) else {
            throw Failure(description: "\(NSStringFromClass(cls)) \(initName) returned nil")
        }
        return Unmanaged<AnyObject>.fromOpaque(made).takeRetainedValue()
    }
}
