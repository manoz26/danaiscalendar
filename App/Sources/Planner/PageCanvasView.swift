import SwiftUI
import PlannerCore

/// The open page in SwiftUI: always the same PencilKit canvas (kept by `InkController`),
/// which swaps template and ink when another page opens. Keeping one canvas makes
/// turning pages instant and the first stroke on a page as quick as any other.
struct PlannerCanvas: UIViewRepresentable {
    let ink: InkController
    let content: PlannerPageContent
    let drawWithFinger: Bool
    /// The canvas is covered by something else (the iPhone's other tabs): VoiceOver and the
    /// UI tests must not find the page under it.
    var hidden = false
    let onTap: (CGPoint) -> Void
    let onLongPress: (CGPoint) -> Void
    let onSwipe: (Int) -> Void

    func makeUIView(context: Context) -> InkCanvasView {
        ink.canvas
    }

    func updateUIView(_ view: InkCanvasView, context: Context) {
        ink.onTap = onTap
        ink.onLongPress = onLongPress
        ink.onSwipe = onSwipe
        ink.setDrawWithFinger(drawWithFinger)
        if view.isHidden != hidden {
            view.isHidden = hidden
        }
        ink.show(content)
    }
}
