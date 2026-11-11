import PencilKit
import PlannerCore
import UIKit

/// The open page: a PencilKit canvas with the printed template underneath.
///
/// Ink is kept in canvas units (1000 x 1400) everywhere else; on this canvas it is drawn
/// at `drawingScale` PencilKit units per canvas unit, chosen so that PencilKit's zoom never
/// goes below 1: below 1 (iPhone, smaller iPads in portrait, Split View) it drew the ink
/// on part of the page only. The scale changes only when the page would need a zoom below
/// 1 (or above 2 at its fitted width); otherwise a new width (rotation) is just a zoom. PencilKit does the zooming (it keeps the ink sharp); the template view sits in
/// the same scroll view at the same scale, so ink and print always line up.
final class InkCanvasView: PKCanvasView {
    static let maximumZoom: CGFloat = 4

    let templateView = PageTemplateView()
    private let pageUndoManager = UndoManager()
    private var fittedWidth: CGFloat = 0

    /// PencilKit units per canvas unit.
    private(set) var drawingScale: CGFloat = 1
    /// PencilKit's zoom with the page fitted to the width: 1...2.
    private var fitZoom: CGFloat = 1
    /// Called with the old and new scale when the width changes (rotation, Split View).
    var onDrawingScaleChange: ((CGFloat, CGFloat) -> Void)?

    /// Each open page has its own undo history (cleared when another page opens).
    override var undoManager: UndoManager? { pageUndoManager }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = false
        bouncesZoom = true
        drawingPolicy = .pencilOnly

        // The template is 1000 x 1400 and scaled from its top-left corner.
        templateView.isUserInteractionEnabled = false
        templateView.layer.anchorPoint = .zero
        templateView.bounds = CGRect(origin: .zero, size: PageCanvas.size)
        templateView.layer.position = .zero
        insertSubview(templateView, at: 0)

        // VoiceOver names the page when entering it; the items printed on it stay reachable.
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var accessibilityElements: [Any]? {
        get {
            #if DEBUG
            let geometry = UIAccessibilityElement(accessibilityContainer: self)
            geometry.accessibilityIdentifier = "debug.inkGeometry"
            geometry.accessibilityLabel = geometryReport
            geometry.accessibilityFrameInContainerSpace = CGRect(x: 0, y: 0, width: 4, height: 4)
            return [templateView, geometry]
            #else
            return [templateView]
            #endif
        }
        set { }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        stopDelayingTouches()
        // PencilKit finishes setting up its views a moment later.
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.stopDelayingTouches() }
        }
    }

    /// No gesture recognizer of the canvas (or of PencilKit's views inside it) holds touches
    /// back. When one did, UIKit crashed on the first finger touch of the page
    /// (`-[UIGestureRecognizer _delayTouchesForEvent:inPhase:]` inserting nil): seen on every
    /// tap and pinch in the iOS 27 simulators, and gone with this. Nothing here uses the
    /// delayed touches; PencilKit works through its gesture recognizers.
    func stopDelayingTouches() {
        func visit(_ view: UIView) {
            for recognizer in view.gestureRecognizers ?? [] {
                if recognizer.delaysTouchesBegan { recognizer.delaysTouchesBegan = false }
                if recognizer.delaysTouchesEnded { recognizer.delaysTouchesEnded = false }
            }
            view.subviews.forEach(visit)
        }
        visit(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // PencilKit adds its own views; the template always stays behind the ink.
        if subviews.first !== templateView {
            sendSubviewToBack(templateView)
        }
        stopDelayingTouches()

        let width = bounds.width
        guard width > 0 else { return }
        guard abs(width - fittedWidth) > 0.5 else {
            followZoom()
            return
        }

        // New width (first layout, rotation, Split View): fit the page to it again and keep
        // the same line of the page at the top of the view (the title stays in view if it was).
        let topFraction = contentSize.height > 0 ? max(0, contentOffset.y) / contentSize.height : 0
        fittedWidth = width
        let oldScale = drawingScale
        let fit = width / PageCanvas.size.width
        if fit < drawingScale || fit > drawingScale * 2 {
            drawingScale = fit
        }
        fitZoom = fit / drawingScale
        minimumZoomScale = fitZoom
        maximumZoomScale = fitZoom * Self.maximumZoom
        zoomScale = fitZoom
        followZoom()
        let maxOffset = max(0, contentSize.height - bounds.height)
        contentOffset = CGPoint(x: 0, y: min(maxOffset, (topFraction * contentSize.height).rounded()))
        if drawingScale != oldScale {
            onDrawingScaleChange?(oldScale, drawingScale)
        }
    }

    /// A newly opened page: fitted to the width, scrolled to the top.
    func showWholeWidthFromTop() {
        guard fittedWidth > 0 else { return }
        zoomScale = fitZoom
        followZoom()
        contentOffset = .zero
    }

    /// Keeps the template and the scrollable area in step with PencilKit's zoom.
    func followZoom() {
        let scale = zoomScale * drawingScale
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        if templateView.transform != transform {
            templateView.transform = transform
            templateView.layer.position = .zero
        }
        let size = CGSize(width: PageCanvas.size.width * scale, height: PageCanvas.size.height * scale)
        if contentSize != size {
            contentSize = size
        }
    }

    #if DEBUG
    /// Zoom, sizes and PencilKit's own views, for UI test failure messages ("debug.inkGeometry").
    /// The last things that happened to the ink (Debug only), for UI test failure messages.
    var debugEvents: [String] = []

    func noteDebugEvent(_ event: String) {
        debugEvents.append(event)
        if debugEvents.count > 12 { debugEvents.removeFirst() }
    }

    var geometryReport: String {
        let ink = drawing
        let events = "events: " + debugEvents.joined(separator: " > ")
        let inkLine = "ink: \(ink.strokes.count) strokes bounds=\(ink.bounds)"
        let views = subviews.map { view in
            "\(type(of: view)) frame=\(view.frame) bounds=\(view.bounds)"
        }
        return (["zoom=\(zoomScale) drawingScale=\(drawingScale) bounds=\(bounds) content=\(contentSize) offset=\(contentOffset)", inkLine, events] + views)
            .joined(separator: "; ")
    }
    #endif

    /// Canvas units of a touch.
    func canvasLocation(of recognizer: UIGestureRecognizer) -> CGPoint {
        recognizer.location(in: templateView)
    }
}

/// Draws the printed template with a tiled layer, so it stays sharp at every zoom level
/// without keeping a huge bitmap in memory. Its bounds are the canvas (1000 x 1400); the
/// canvas view scales it.
final class PageTemplateView: UIView {
    override class var layerClass: AnyClass { PageTiledLayer.self }

    private var tiledLayer: PageTiledLayer { layer as! PageTiledLayer }
    private var elements: [UIAccessibilityElement] = []

    var template: PageTemplate? {
        didSet {
            guard template != oldValue else { return }
            tiledLayer.template = template
        }
    }

    var items: [PageAccessibilityItem] = [] {
        didSet {
            guard items != oldValue else { return }
            rebuildAccessibilityElements()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isOpaque = true
        isAccessibilityElement = false
        // The page is shown from about 0.35x (iPhone) to about 5.5x (iPad landscape, zoomed
        // in 4x) of its canvas size: levels from 0.5x to 8x.
        tiledLayer.levelsOfDetail = 5
        tiledLayer.levelsOfDetailBias = 3
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var accessibilityElements: [Any]? {
        get { elements }
        set { }
    }

    private func rebuildAccessibilityElements() {
        // Frames are in this view's coordinates, the canvas units; UIKit applies the zoom.
        elements = items.map { item in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityIdentifier = item.identifier
            element.accessibilityLabel = item.label
            element.accessibilityValue = item.value
            element.accessibilityTraits = item.traits
            element.accessibilityFrameInContainerSpace = item.rect
            return element
        }
    }
}

/// Something VoiceOver (and the UI tests) can find on the page, in canvas units.
struct PageAccessibilityItem: Equatable {
    var identifier: String
    var label: String
    var value: String?
    var rect: CGRect
    var traits: UIAccessibilityTraits
}

/// Tiled layer that draws the page template. Core Animation calls `draw(in:)` on
/// background threads, one tile at a time, so the template is read under a lock.
final class PageTiledLayer: CATiledLayer {
    private let lock = NSLock()
    private var storedTemplate: PageTemplate?

    override init() {
        super.init()
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? PageTiledLayer {
            storedTemplate = other.template
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// No fade-in of new tiles: the page should look printed, not loading.
    override class func fadeDuration() -> CFTimeInterval { 0 }

    var template: PageTemplate? {
        get { lock.withLock { storedTemplate } }
        set {
            lock.withLock { storedTemplate = newValue }
            setNeedsDisplay()
        }
    }

    override func draw(in context: CGContext) {
        guard let template else { return }
        let scale = PageCanvas.scale(forWidth: bounds.width)
        guard scale > 0 else { return }
        context.setFillColor(Tone.paper.cgColor)
        context.fill(context.boundingBoxOfClipPath)
        context.scaleBy(x: scale, y: scale)
        TemplateRenderer.draw(template, in: context)
    }
}
