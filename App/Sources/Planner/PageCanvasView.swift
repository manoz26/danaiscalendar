import SwiftUI
import UIKit
import PlannerCore

/// Something VoiceOver (and the UI tests) can find on the page, in canvas units.
struct PageAccessibilityItem: Equatable {
    var identifier: String
    var label: String
    var value: String?
    var rect: CGRect
    var traits: UIAccessibilityTraits
}

/// A printed page, scaled to the available width, with pinch zoom from 1x to 4x and
/// scrolling. A finger tap reports the tapped point in canvas units.
struct PageCanvasView: UIViewRepresentable {
    let template: PageTemplate
    let identifier: String
    let spokenLabel: String
    let accessibilityItems: [PageAccessibilityItem]
    let onTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> PageScrollView {
        PageScrollView()
    }

    func updateUIView(_ view: PageScrollView, context: Context) {
        view.pageView.template = template
        view.pageView.items = accessibilityItems
        view.accessibilityIdentifier = identifier
        view.accessibilityLabel = spokenLabel
        view.onTap = onTap
    }
}

/// Zooming scroll view that holds one page.
final class PageScrollView: UIScrollView, UIScrollViewDelegate {
    static let maximumZoom: CGFloat = 4

    let pageView = PageTemplateView()
    var onTap: ((CGPoint) -> Void)?
    private var laidOutWidth: CGFloat = 0

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = Self.maximumZoom
        bouncesZoom = true
        alwaysBounceVertical = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        backgroundColor = .white
        // VoiceOver names the page when entering it; the items inside stay reachable.
        accessibilityContainerType = .semanticGroup
        addSubview(pageView)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        pageView.addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        guard width > 0, abs(width - laidOutWidth) > 0.5 else { return }

        // New width (first layout, rotation, Split View): fit the page to it again and keep
        // the same line of the page at the top of the view (the title stays in view if it was).
        let topFraction = contentSize.height > 0 ? max(0, contentOffset.y) / contentSize.height : 0
        laidOutWidth = width
        zoomScale = 1
        let size = CGSize(width: width, height: (width * PageCanvas.aspectRatio).rounded())
        pageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        let maxOffset = max(0, size.height - bounds.height)
        contentOffset = CGPoint(x: 0, y: min(maxOffset, topFraction * size.height))
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        pageView
    }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: pageView)
        let scale = PageCanvas.scale(forWidth: pageView.bounds.width)
        guard scale > 0 else { return }
        onTap?(CGPoint(x: point.x / scale, y: point.y / scale))
    }
}

/// Draws the template with a tiled layer, so it stays sharp at every zoom level without
/// keeping a huge bitmap in memory.
final class PageTemplateView: UIView {
    override class var layerClass: AnyClass { PageTiledLayer.self }

    private var tiledLayer: PageTiledLayer { layer as! PageTiledLayer }
    private var elements: [UIAccessibilityElement] = []
    private var laidOutSize: CGSize = .zero

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
        // Up to 4x zoom: levels at 1x, 2x and 4x the screen resolution.
        tiledLayer.levelsOfDetail = 3
        tiledLayer.levelsOfDetailBias = 2
        tiledLayer.tileSize = CGSize(width: 512, height: 512)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != laidOutSize else { return }
        laidOutSize = bounds.size
        tiledLayer.setNeedsDisplay()
        layoutAccessibilityElements()
    }

    override var accessibilityElements: [Any]? {
        get { elements }
        set { }
    }

    private func rebuildAccessibilityElements() {
        elements = items.map { item in
            let element = UIAccessibilityElement(accessibilityContainer: self)
            element.accessibilityIdentifier = item.identifier
            element.accessibilityLabel = item.label
            element.accessibilityValue = item.value
            element.accessibilityTraits = item.traits
            return element
        }
        layoutAccessibilityElements()
    }

    private func layoutAccessibilityElements() {
        let scale = PageCanvas.scale(forWidth: bounds.width)
        for (element, item) in zip(elements, items) {
            element.accessibilityFrameInContainerSpace = item.rect.applying(CGAffineTransform(scaleX: scale, y: scale))
        }
    }
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
