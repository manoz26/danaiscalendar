import Foundation
import Observation
import PencilKit
import PlannerCore
import UIKit

/// Keys of the ink settings in UserDefaults.
enum InkDefaults {
    static let tools = "DCInkTools"
    static let toolbarSide = "DCToolbarSide"
    static let toolbarCollapsed = "DCToolbarCollapsed"
    /// Settings → Apple Pencil → Draw with finger too.
    static let drawWithFinger = "DCDrawWithFinger"

    static let all = [tools, toolbarSide, toolbarCollapsed, drawWithFinger]
}

enum ToolbarSide: String, Sendable {
    case leading, trailing

    var other: ToolbarSide { self == .leading ? .trailing : .leading }
}

/// The writing engine: one PencilKit canvas for the whole app, the toolbar's state, and
/// the ink of each page (through `InkLibrary`).
///
/// Apple Pencil writes; one finger scrolls and taps (months on the year page, the tabs),
/// two fingers zoom. With Settings → "Draw with finger too", a finger writes as well and
/// two fingers scroll. On iPhone there is no drawing: the ink is shown only.
@MainActor
@Observable
final class InkController {
    private(set) var tools: InkToolState
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var toolbarSide: ToolbarSide
    private(set) var toolbarCollapsed: Bool

    /// iPad only; on iPhone the ink is read-only.
    let canDraw: Bool
    let canvas: InkCanvasView

    /// A finger tap on the page, in canvas units.
    @ObservationIgnored var onTap: ((CGPoint) -> Void)?

    private let library: InkLibrary
    private let helper = CanvasHelper()
    @ObservationIgnored private var page: PlannerPage?
    @ObservationIgnored private var template: PageTemplate?
    @ObservationIgnored private var layout = PageLayoutStamp.current(for: .year(2000))
    @ObservationIgnored private var drawWithFinger = false
    /// Set while the app itself replaces the canvas drawing (opening a page).
    @ObservationIgnored private var isReplacingDrawing = false
    /// A drawing the app just put on the canvas, and until when a "drawing changed"
    /// callback with the same strokes is only its echo, not an edit.
    @ObservationIgnored private var replacedDrawing: PKDrawing?
    @ObservationIgnored private var echoDeadline = Date.distantPast

    init(library: InkLibrary? = nil, canDraw: Bool? = nil) {
        self.canDraw = canDraw ?? (UIDevice.current.userInterfaceIdiom == .pad)
        self.library = library ?? InkLibrary()
        canvas = InkCanvasView()
        tools = Self.loadTools()
        let defaults = UserDefaults.standard
        toolbarSide = ToolbarSide(rawValue: defaults.string(forKey: InkDefaults.toolbarSide) ?? "") ?? .leading
        toolbarCollapsed = defaults.bool(forKey: InkDefaults.toolbarCollapsed)

        helper.controller = self
        canvas.delegate = helper

        let tap = UITapGestureRecognizer(target: helper, action: #selector(CanvasHelper.tapped(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.delegate = helper
        canvas.addGestureRecognizer(tap)

        if self.canDraw {
            let pencil = UIPencilInteraction()
            pencil.delegate = helper
            canvas.addInteraction(pencil)
        } else {
            canvas.drawingGestureRecognizer.isEnabled = false
        }
        applyTool()
        observeNotifications()
    }

    // MARK: - Pages

    /// Shows a page: its template and its ink. Called on every SwiftUI update; does
    /// nothing unless the page (or its printed template, e.g. at midnight) changed.
    func show(_ content: PlannerPageContent) {
        if content.page == page {
            if content.template != template {
                setTemplate(content)
            }
            return
        }

        if let page {
            library.save(page)
        }
        page = content.page
        layout = content.layout
        setTemplate(content)
        replaceDrawing(library.drawing(for: content.page, layout: content.layout))
        canvas.undoManager?.removeAllActions()
        canvas.showWholeWidthFromTop()
        library.preload(content.page.neighbors)
        #if DEBUG
        addSampleInkIfRequested(content)
        #endif
        Task { [weak self] in self?.refreshUndoState() }
    }

    func setDrawWithFinger(_ on: Bool) {
        guard canDraw, on != drawWithFinger else { return }
        drawWithFinger = on
        canvas.drawingPolicy = on ? .anyInput : .pencilOnly
        AppLog.info("Drawing with finger: \(on ? "on" : "off")")
    }

    /// Writes unsaved ink to disk before returning (the app is going to the background).
    func saveEverything() {
        library.saveAll(wait: true)
    }

    /// Starts writing unsaved ink to disk.
    func saveSoon() {
        library.saveAll(wait: false)
    }

    // MARK: - Toolbar

    func select(_ tool: InkTool) {
        tools.select(tool)
        toolsChanged()
    }

    func selectColor(_ index: Int) {
        tools.selectColor(index)
        toolsChanged()
    }

    func selectWidth(_ index: Int) {
        tools.selectWidth(index)
        toolsChanged()
    }

    func selectEraserMode(_ mode: EraserMode) {
        tools.eraserMode = mode
        tools.select(.eraser)
        toolsChanged()
    }

    func toggleEraser() {
        tools.toggleEraser()
        toolsChanged()
    }

    func switchToPreviousTool() {
        tools.switchToPrevious()
        toolsChanged()
    }

    func undo() {
        canvas.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        canvas.undoManager?.redo()
        refreshUndoState()
    }

    func setToolbarCollapsed(_ collapsed: Bool) {
        guard collapsed != toolbarCollapsed else { return }
        toolbarCollapsed = collapsed
        UserDefaults.standard.set(collapsed, forKey: InkDefaults.toolbarCollapsed)
    }

    func moveToolbar(to side: ToolbarSide) {
        guard side != toolbarSide else { return }
        toolbarSide = side
        UserDefaults.standard.set(side.rawValue, forKey: InkDefaults.toolbarSide)
    }

    // MARK: - Canvas callbacks

    fileprivate func drawingDidChange() {
        Task { [weak self] in self?.refreshUndoState() }
        guard !isReplacingDrawing, let page else { return }
        let drawing = canvas.drawing
        if let replaced = replacedDrawing, Date() < echoDeadline,
           replaced.strokes.count == drawing.strokes.count, replaced.bounds == drawing.bounds {
            // PencilKit reporting the drawing the app just set, not an edit.
            return
        }
        replacedDrawing = nil
        library.update(drawing, for: page, layout: layout)
    }

    fileprivate func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?(canvas.canvasLocation(of: recognizer))
    }

    /// Double tap (Apple Pencil 2, Pro) and squeeze (Pro), as chosen in the iPad's
    /// Apple Pencil settings.
    fileprivate func performPencilAction(_ action: UIPencilPreferredAction) {
        switch action {
        case .switchEraser:
            toggleEraser()
        case .switchPrevious:
            switchToPreviousTool()
        case .showColorPalette:
            setToolbarCollapsed(false)
        default:
            break
        }
    }

    // MARK: - Private

    private func setTemplate(_ content: PlannerPageContent) {
        template = content.template
        canvas.templateView.template = content.template
        canvas.templateView.items = content.accessibilityItems
        canvas.accessibilityIdentifier = content.identifier
        canvas.accessibilityLabel = content.accessibilityLabel
    }

    private func replaceDrawing(_ drawing: PKDrawing) {
        isReplacingDrawing = true
        canvas.drawing = drawing
        isReplacingDrawing = false
        replacedDrawing = drawing
        echoDeadline = Date().addingTimeInterval(0.5)
    }

    private func toolsChanged() {
        applyTool()
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(tools), forKey: InkDefaults.tools)
        } catch {
            AppLog.error("Could not remember the tools", error)
        }
    }

    private func applyTool() {
        guard canDraw else { return }
        canvas.tool = InkToolFactory.tool(for: tools)
    }

    private func refreshUndoState() {
        let undo = canvas.undoManager?.canUndo ?? false
        let redo = canvas.undoManager?.canRedo ?? false
        if canUndo != undo { canUndo = undo }
        if canRedo != redo { canRedo = redo }
    }

    private static func loadTools() -> InkToolState {
        guard let data = UserDefaults.standard.data(forKey: InkDefaults.tools) else { return InkToolState() }
        do {
            return try JSONDecoder().decode(InkToolState.self, from: data)
        } catch {
            AppLog.warning("Saved tools could not be read; using the defaults")
            return InkToolState()
        }
    }

    private func observeNotifications() {
        let center = NotificationCenter.default
        let undoNames: [Notification.Name] = [
            .NSUndoManagerDidCloseUndoGroup, .NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange,
        ]
        for name in undoNames {
            _ = center.addObserver(forName: name, object: canvas.undoManager, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshUndoState() }
            }
        }
        _ = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.library.releaseMemory() }
        }
    }

    #if DEBUG
    /// `-DCSampleInk YES` (UI tests): sample strokes on every opened page without ink.
    private func addSampleInkIfRequested(_ content: PlannerPageContent) {
        guard LaunchOptions.sampleInk, canvas.drawing.strokes.isEmpty else { return }
        let sample = SampleInk.drawing(for: content.page, template: content.template)
        replaceDrawing(sample)
        library.update(sample, for: content.page, layout: content.layout)
    }
    #endif
}

/// PencilKit tools for the toolbar's state.
enum InkToolFactory {
    static func tool(for state: InkToolState) -> any PKTool {
        let width = state.width ?? 1
        let color = state.color.uiColor
        switch state.tool {
        case .pen:
            return PKInkingTool(.pen, color: color, width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: color, width: width)
        case .highlighter:
            return PKInkingTool(.marker, color: color, width: width)
        case .eraser:
            // A pixel eraser of a fixed width (PencilKit turns `.bitmap` with a width into this anyway).
            return PKEraserTool(state.eraserMode == .partial ? .fixedWidthBitmap : .vector, width: width)
        case .lasso:
            return PKLassoTool()
        }
    }
}

extension InkColor {
    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: 1)
    }
}

/// Delegate of the canvas, its tap and the Pencil interaction (UIKit wants an NSObject).
@MainActor
private final class CanvasHelper: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    weak var controller: InkController?

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        controller?.drawingDidChange()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        (scrollView as? InkCanvasView)?.followZoom()
    }

    @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        controller?.tapped(recognizer)
    }

    /// The tap never blocks scrolling, zooming or (with a finger) drawing.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    /// iOS 17.0–17.4.
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        if #available(iOS 17.5, *) { return }
        controller?.performPencilAction(UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        controller?.performPencilAction(UIPencilInteraction.preferredTapAction)
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
        guard squeeze.phase == .ended else { return }
        controller?.performPencilAction(UIPencilInteraction.preferredSqueezeAction)
    }
}
