import PencilKit
import PlannerCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Follows the touch PencilKit draws with, so that a stroke held still at its end can become a
/// straight line (`StraightLineHold`, `InkController`). It only listens: it never begins (it
/// stays "possible", so it also hears every next stroke while a palm rests on the glass), and
/// it never stops drawing, scrolling, zooming or the page's taps.
final class StrokeTracker: UIGestureRecognizer {
    /// Whether PencilKit draws with this touch (the pencil, or a finger with "Draw with finger too").
    var canFollow: ((UITouch) -> Bool)?
    /// A stroke began with this touch.
    var onBegin: ((UITouch) -> Void)?
    /// The followed touch moved: every sample the screen reported (oldest first), and the touch.
    var onMove: (([UITouch], UITouch) -> Void)?
    /// The followed touch lifted (or, `cancelled`, a second finger came or the system took it).
    var onEnd: ((UITouch, _ cancelled: Bool) -> Void)?

    private var followed: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if let followed {
                // A second finger while a finger draws: scrolling or zooming, not a stroke.
                // (A palm or a finger while the pencil draws changes nothing.)
                if followed.type == .direct, touch.type == .direct {
                    end(followed, cancelled: true)
                }
                ignore(touch, for: event)
            } else if canFollow?(touch) == true, Self.isAlone(touch, in: event) {
                followed = touch
                onBegin?(touch)
            } else {
                ignore(touch, for: event)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followed, touches.contains(followed) else { return }
        let samples = event.coalescedTouches(for: followed) ?? []
        onMove?(samples.isEmpty ? [followed] : samples, followed)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followed, touches.contains(followed) else { return }
        end(followed, cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let followed, touches.contains(followed) else { return }
        end(followed, cancelled: true)
    }

    /// However UIKit resets it, a followed stroke ends.
    override func reset() {
        super.reset()
        if let followed {
            end(followed, cancelled: true)
        }
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    /// No other touch of the same kind is down (two fingers scroll or zoom; a palm next to the
    /// pencil does not count).
    private static func isAlone(_ touch: UITouch, in event: UIEvent) -> Bool {
        let others = (event.allTouches ?? []).filter { other in
            other !== touch && other.type == touch.type && other.phase != .ended && other.phase != .cancelled
        }
        return others.isEmpty
    }

    private func end(_ touch: UITouch, cancelled: Bool) {
        followed = nil
        onEnd?(touch, cancelled)
    }
}

/// The straight stroke that replaces a held one: the selected tool, colour, opacity and width.
enum StraightStroke {
    /// `from`/`to` in PencilKit units; `scale`: PencilKit units per canvas unit.
    static func make(from start: CGPoint, to end: CGPoint, tools: InkToolState, scale: CGFloat) -> PKStroke? {
        guard let inkType = inkType(for: tools.tool), let width = tools.width else { return nil }
        let size = width * scale
        let length = hypot(end.x - start.x, end.y - start.y)
        // A point every 2 units at the canvas's scale, like the strokes PencilKit makes.
        let count = max(1, Int((length / (2 * scale)).rounded(.up)))
        let creation = Date()
        let points = (0...count).map { index in
            let t = CGFloat(index) / CGFloat(count)
            return PKStrokePoint(
                location: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t),
                timeOffset: TimeInterval(index) * 0.004,
                size: CGSize(width: size, height: size), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2
            )
        }
        let color = tools.color.uiColor.withAlphaComponent(tools.opacity)
        return PKStroke(ink: PKInk(inkType, color: color), path: PKStrokePath(controlPoints: points, creationDate: creation))
    }

    static func inkType(for tool: InkTool) -> PKInk.InkType? {
        switch tool {
        case .pen: .pen
        case .pencil: .pencil
        case .highlighter: .marker
        case .eraser, .lasso: nil
        }
    }
}
