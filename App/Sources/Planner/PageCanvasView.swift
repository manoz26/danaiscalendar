import SwiftUI
import PlannerCore

/// The open page in SwiftUI: always the same PencilKit canvas (kept by `InkController`),
/// which swaps template and ink when another page opens. Keeping one canvas makes
/// turning pages instant and the first stroke on a page as quick as any other.
struct PlannerCanvas: UIViewRepresentable {
    let ink: InkController
    let content: PlannerPageContent
    let drawWithFinger: Bool
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> InkCanvasView {
        ink.canvas
    }

    func updateUIView(_ view: InkCanvasView, context: Context) {
        ink.onTap = onTap
        ink.setDrawWithFinger(drawWithFinger)
        ink.show(content)
    }
}
