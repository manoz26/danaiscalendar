import UIKit

/// Temporary (Debug builds only): finding out why UIKit crashes when a finger touches the
/// PencilKit canvas in the simulator (`DiagnosticTouchTests`).
enum TouchDiagnosis {
    #if DEBUG
    private static func flag(_ name: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(name)
    }

    /// `-DCDiagReport YES`: list every gesture recognizer around the canvas.
    static var report: Bool { flag("-DCDiagReport") }
    /// `-DCDiagNoDelays YES`: no gesture recognizer around the canvas delays touches.
    static var noDelays: Bool { flag("-DCDiagNoDelays") }
    /// `-DCDiagNoKitGestures YES`: only the scroll view's own pan and pinch stay enabled on the canvas.
    static var noKitGestures: Bool { flag("-DCDiagNoKitGestures") }
    #else
    static let report = false
    static let noDelays = false
    static let noKitGestures = false
    #endif

    // Kept so the switches of the previous diagnosis still compile; always off now.
    static let noTap = false
    static let noToolbar = false
    static let noContentDelay = false
    static let noDrawing = false
    static let noOverrides = false
    static let noPencilInteraction = false
    static let noTemplateView = false

    /// Every gesture recognizer on the canvas, inside it and above it (up to the window).
    @MainActor
    static func recognizers(around canvas: UIScrollView) -> [(view: UIView, recognizer: UIGestureRecognizer, place: String)] {
        var found: [(view: UIView, recognizer: UIGestureRecognizer, place: String)] = []
        var ancestor: UIView? = canvas.superview
        var level = 1
        while let view = ancestor {
            for recognizer in view.gestureRecognizers ?? [] {
                found.append((view: view, recognizer: recognizer, place: "up\(level)"))
            }
            ancestor = view.superview
            level += 1
        }
        func walk(_ view: UIView, depth: Int) {
            for recognizer in view.gestureRecognizers ?? [] {
                found.append((view: view, recognizer: recognizer, place: depth == 0 ? "canvas" : "down\(depth)"))
            }
            for subview in view.subviews {
                walk(subview, depth: depth + 1)
            }
        }
        walk(canvas, depth: 0)
        return found
    }

    @MainActor
    static func describe(around canvas: UIScrollView) -> String {
        recognizers(around: canvas).map { view, recognizer, place in
            let types = (recognizer.allowedTouchTypes).map { "\($0.intValue)" }.joined(separator: ",")
            return "\(place) \(type(of: view)) | \(type(of: recognizer)) | began=\(recognizer.delaysTouchesBegan) ended=\(recognizer.delaysTouchesEnded) cancels=\(recognizer.cancelsTouchesInView) enabled=\(recognizer.isEnabled) types=\(types)"
        }
        .joined(separator: "\n")
    }

    /// Applies `noDelays` / `noKitGestures`.
    @MainActor
    static func apply(to canvas: UIScrollView) {
        for (view, recognizer, _) in recognizers(around: canvas) {
            if noDelays {
                recognizer.delaysTouchesBegan = false
                recognizer.delaysTouchesEnded = false
            }
            if noKitGestures, view === canvas || view.isDescendant(of: canvas),
               recognizer !== canvas.panGestureRecognizer, recognizer !== canvas.pinchGestureRecognizer,
               !(recognizer is UITapGestureRecognizer && view === canvas) {
                recognizer.isEnabled = false
            }
        }
    }
}
