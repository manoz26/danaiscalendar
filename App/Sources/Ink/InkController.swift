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
    /// The weeks whose page has ink: their WEEKLY buttons on the month page get a dot.
    private(set) var inkedWeeks: Set<PlannerWeek> = []

    /// iPad only; on iPhone the ink is read-only.
    let canDraw: Bool
    let canvas: InkCanvasView

    /// A finger tap on the page, in canvas units.
    @ObservationIgnored var onTap: ((CGPoint) -> Void)?
    /// A long press of a finger on the page (e.g. on a day, to open its journal page), in canvas units.
    @ObservationIgnored var onLongPress: ((CGPoint) -> Void)?
    /// A finger swiped across the page while it is not zoomed in: 1 to the next page
    /// (swipe to the left), -1 to the previous one.
    @ObservationIgnored var onSwipe: ((Int) -> Void)?

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
    /// The page's ink was just put on the canvas; PencilKit has not drawn it yet.
    @ObservationIgnored private var awaitingRender = false

    /// Hold at the end of a stroke to make it a straight line (`StraightLineHold`).
    private let strokeTracker = StrokeTracker()
    @ObservationIgnored private var lineHold = StraightLineHold()
    @ObservationIgnored private var lineTimer: Timer?
    /// Where the followed stroke began and where it is now, in PencilKit units.
    @ObservationIgnored private var lineStart = CGPoint.zero
    @ObservationIgnored private var lineEnd = CGPoint.zero
    /// The stroke became a straight line and the pencil is still down.
    @ObservationIgnored private var activeLine: ActiveLine?
    /// How PencilKit draws each ink just now (from the user's latest stroke with it), for straight lines.
    @ObservationIgnored private var strokeLooks: [PKInk.InkType: StrokeLook] = [:]
    @ObservationIgnored private var lookedAtStroke: Date?

    /// Ink from another device changed the open page while the canvas still shows the ink
    /// before it (`remoteBase`, canvas units): shown as soon as no stroke is being drawn.
    @ObservationIgnored private var remoteBase: PKDrawing?
    @ObservationIgnored private var remoteTimer: Timer?

    init(library: InkLibrary? = nil, canDraw: Bool? = nil) {
        self.canDraw = canDraw ?? (UIDevice.current.userInterfaceIdiom == .pad)
        self.library = library ?? InkLibrary()
        canvas = InkCanvasView()
        tools = Self.loadTools()
        let defaults = UserDefaults.standard
        toolbarSide = ToolbarSide(rawValue: defaults.string(forKey: InkDefaults.toolbarSide) ?? "") ?? .leading
        toolbarCollapsed = defaults.bool(forKey: InkDefaults.toolbarCollapsed)

        inkedWeeks = self.library.files.weeksWithInk()
        self.library.onInkChange = { [weak self] page, hasInk in
            self?.inkChanged(page, hasInk: hasInk)
        }
        self.library.onRemoteInk = { [weak self] page, before, _ in
            self?.remoteInkArrived(page, before: before)
        }

        helper.controller = self
        canvas.delegate = helper
        canvas.onDrawingScaleChange = { [weak self] old, new in
            self?.drawingScaleChanged(from: old, to: new)
        }

        // A finger tap opens things printed on the page. It only listens: it never delays
        // or cancels the touches PencilKit and the scroll view get (that crashed on taps
        // and pinches in the simulator).
        let tap = UITapGestureRecognizer(target: helper, action: #selector(CanvasHelper.tapped(_:)))
        tap.delaysTouchesEnded = false
        tap.cancelsTouchesInView = false
        tap.delegate = helper
        canvas.addGestureRecognizer(tap)

        // A long press (a day opens its journal page) and a swipe (turning journal pages)
        // listen the same way. The tap waits for the long press to fail, which happens as
        // soon as a short tap ends, so a long press never also counts as a tap.
        let longPress = UILongPressGestureRecognizer(target: helper, action: #selector(CanvasHelper.longPressed(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delaysTouchesBegan = false
        longPress.delaysTouchesEnded = false
        longPress.cancelsTouchesInView = false
        longPress.delegate = helper
        canvas.addGestureRecognizer(longPress)
        canvas.dayLongPress = longPress
        tap.require(toFail: longPress)
        var ownRecognizers: [UIGestureRecognizer] = [tap, longPress]
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: helper, action: #selector(CanvasHelper.swiped(_:)))
            swipe.direction = direction
            swipe.delaysTouchesBegan = false
            swipe.delaysTouchesEnded = false
            swipe.cancelsTouchesInView = false
            swipe.delegate = helper
            canvas.addGestureRecognizer(swipe)
            ownRecognizers.append(swipe)
        }

        if self.canDraw {
            let pencil = UIPencilInteraction()
            pencil.delegate = helper
            canvas.addInteraction(pencil)
            setUpStraightLines()
        } else {
            canvas.drawingGestureRecognizer.isEnabled = false
            // iPhone: two taps zoom in on that place of the page (on a month, on that week),
            // and two more zoom back out. A single tap waits a moment to see if a second follows.
            let doubleTap = UITapGestureRecognizer(target: helper, action: #selector(CanvasHelper.doubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delaysTouchesBegan = false
            doubleTap.delaysTouchesEnded = false
            doubleTap.cancelsTouchesInView = false
            doubleTap.delegate = helper
            canvas.addGestureRecognizer(doubleTap)
            tap.require(toFail: doubleTap)
            canvas.appRecognizers = ownRecognizers + [doubleTap]
            canvas.isReadOnly = true
            canvas.stopDelayingTouches()
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

        finishLine()
        if let page {
            library.save(page)
        }
        remoteBase = nil
        page = content.page
        layout = content.layout
        setTemplate(content)
        #if DEBUG
        addSampleInkIfRequested(content)
        #endif
        putInkOnCanvas(resetZoom: true)
        library.preload(content.page.neighbors)
    }

    func setDrawWithFinger(_ on: Bool) {
        guard canDraw, on != drawWithFinger else { return }
        drawWithFinger = on
        canvas.drawingPolicy = on ? .anyInput : .pencilOnly
        AppLog.info("Drawing with finger: \(on ? "on" : "off")")
    }

    /// Reads pages in the background so they open instantly (e.g. the journal pages next
    /// to the open one).
    func preload(_ pages: [PlannerPage]) {
        library.preload(pages)
    }

    /// The ink of any page, in canvas units (thumbnails, exports).
    func drawing(of page: PlannerPage) -> PKDrawing {
        library.peekDrawing(for: page)
    }

    func hasInk(_ page: PlannerPage) -> Bool {
        !library.peekDrawing(for: page).strokes.isEmpty
    }

    /// The regions of a page that have ink (the region of each stroke, see `InkAnchor`).
    func inkedRegions(of page: PlannerPage, template: PageTemplate) -> Set<RegionID> {
        Set(library.peekDrawing(for: page).strokes.compactMap { stroke in
            InkAnchor.region(forStrokeBounds: stroke.renderBounds, in: template)
        })
    }

    /// A journal page or sketch was deleted: its ink goes too. It must not be the open page.
    func deleteInk(of page: PlannerPage) {
        library.forget(page)
    }

    /// A duplicated journal page gets a copy of the original's ink.
    func copyInk(from source: PlannerPage, to target: PlannerPage) {
        library.copy(source, to: target)
    }

    /// Writes unsaved ink to disk before returning (the app is going to the background).
    func saveEverything() {
        library.saveAll(wait: true)
    }

    // MARK: - Ink from other devices (iCloud, prompt 7)

    /// Another version of a page (another device, an iCloud conflict, a backup): see
    /// `InkLibrary.receive`. Returns the page file's bytes afterwards.
    func receivePage(_ data: Data, for page: PlannerPage, replacing expected: String?) async throws -> Data {
        try await library.receive(data, for: page, replacing: expected)
    }

    /// Whether the page is open now.
    func isOpen(_ page: PlannerPage) -> Bool {
        self.page == page
    }

    /// Deletes a page's ink (deleted on another device), unless it is open: then `false`.
    func forgetIfNotOpen(_ page: PlannerPage) -> Bool {
        guard page != self.page else { return false }
        library.forget(page)
        return true
    }

    /// The open page's ink changed in memory (from another device): the canvas shows it as
    /// soon as no stroke is being drawn. A stroke finished meanwhile is kept (`commit`).
    private func remoteInkArrived(_ page: PlannerPage, before: PKDrawing) {
        guard page == self.page else { return }
        if remoteBase == nil {
            remoteBase = before
        }
        showRemoteInk()
    }

    private func showRemoteInk() {
        guard remoteBase != nil, page != nil else { return }
        if isTouchingCanvas {
            remoteTimer?.invalidate()
            let timer = Timer(timeInterval: 0.3, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.showRemoteInk() }
            }
            RunLoop.main.add(timer, forMode: .common)
            remoteTimer = timer
            return
        }
        remoteBase = nil
        showLibraryInk()
        #if DEBUG
        canvas.noteDebugEvent("remote(\(canvas.drawing.strokes.count))")
        #endif
    }

    /// Something is drawing on the canvas right now (a stroke, a straight line).
    private var isTouchingCanvas: Bool {
        let active: [UIGestureRecognizer.State] = [.began, .changed]
        return activeLine != nil || active.contains(canvas.drawingGestureRecognizer.state) || active.contains(strokeTracker.state)
    }

    /// The open page's ink as the library has it, on the canvas (same zoom). The undo
    /// history starts again: it referred to the ink before.
    private func showLibraryInk() {
        guard let page else { return }
        replaceDrawing(Self.asNewStrokes(library.drawing(for: page, scale: canvas.drawingScale, layout: layout)))
        canvas.undoManager?.removeAllActions()
        refreshUndoState()
    }

    /// An edit of the canvas (at `scale` PencilKit units per canvas unit) goes to the
    /// library. If ink from another device is waiting to be shown, both are kept: the
    /// canvas showed `remoteBase`, the library has the other device's version.
    private func commit(_ drawing: PKDrawing, scale: CGFloat) {
        guard let page else { return }
        guard let base = remoteBase else {
            library.update(drawing, scale: scale, for: page, layout: layout)
            return
        }
        remoteBase = nil
        let mine = InkLibrary.rescaled(drawing, from: scale, to: 1)
        let merged = InkMerge.threeWay(base: base, mine: mine, theirs: library.peekDrawing(for: page))
        library.update(merged, scale: 1, for: page, layout: layout)
        if !isTouchingCanvas {
            showLibraryInk()
        } else {
            remoteBase = InkLibrary.rescaled(drawing, from: scale, to: 1)
            showRemoteInk()
        }
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

    func selectHighlighterOpacity(_ index: Int) {
        tools.selectHighlighterOpacity(index)
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
        finishLine()
        canvas.undoManager?.undo()
        refreshUndoState()
    }

    func redo() {
        finishLine()
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
        guard !isReplacingDrawing, page != nil else { return }
        if let line = activeLine {
            // While a straight line is drawn, the canvas shows exactly that. A stroke more is
            // the one PencilKit was drawing when it was told to drop it.
            if canvas.drawing.strokes.count != line.before.strokes.count + 1 {
                #if DEBUG
                canvas.noteDebugEvent("dropped stroke came back")
                #endif
                showLine(force: true)
            }
            return
        }
        let drawing = canvas.drawing
        if let replaced = replacedDrawing, Date() < echoDeadline,
           replaced.strokes.count == drawing.strokes.count, replaced.bounds == drawing.bounds {
            // PencilKit reporting the drawing the app just set, not an edit.
            #if DEBUG
            canvas.noteDebugEvent("echo")
            #endif
            return
        }
        #if DEBUG
        canvas.noteDebugEvent("edit(\(drawing.strokes.count), w=\(Int(drawing.bounds.width)), s=\(canvas.drawingScale))")
        #endif
        replacedDrawing = nil
        commit(drawing, scale: canvas.drawingScale)
        learnLook(from: drawing)
    }

    /// A stroke the user just drew shows how PencilKit draws its ink now (`StrokeLook`).
    private func learnLook(from drawing: PKDrawing) {
        guard let stroke = drawing.strokes.last, stroke.path.creationDate != lookedAtStroke,
              stroke.path.creationDate.timeIntervalSinceNow > -10,
              let type = StraightStroke.inkType(for: tools.tool), stroke.ink.inkType == type,
              let width = tools.width,
              let look = StrokeLook(stroke, toolWidth: width * canvas.drawingScale) else { return }
        lookedAtStroke = stroke.path.creationDate
        strokeLooks[type] = look
    }

    fileprivate func tapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        onTap?(canvas.canvasLocation(of: recognizer))
    }

    /// Two taps (iPhone): zooms in around the place tapped, or back out to the whole width.
    /// On a day of the month page the zoom centres on that day's week row.
    fileprivate func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        var center = canvas.canvasLocation(of: recognizer)
        let day = template?.regions(at: center).first { region in
            if case .day = region.id { return true }
            return false
        }
        if let day {
            center.y = day.rect.midY
        }
        canvas.toggleZoom(centeredOn: center)
        dismissPencilKitMenu()
    }

    fileprivate func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress?(canvas.canvasLocation(of: recognizer))
            dismissPencilKitMenu()
        case .ended, .cancelled, .failed:
            // PencilKit's menu shows when the finger lifts: close it then too.
            dismissPencilKitMenu()
        default:
            break
        }
    }

    /// In case PencilKit opened its long-press menu over the day's page, closes it now and
    /// a moment later.
    private func dismissPencilKitMenu() {
        canvas.dismissEditMenus()
        for delay in [0.1, 0.3, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.canvas.dismissEditMenus() }
            }
        }
    }

    /// The long press begins only on a day (month or week page, or a small month on the year page).
    fileprivate func wantsLongPress(at point: CGPoint) -> Bool {
        template?.regions(at: point).contains { region in
            switch region.id {
            case .day, .weekDay: true
            default: false
            }
        } ?? false
    }

    /// Keeps `inkedWeeks` up to date (changed only when a week gains its first stroke or loses its last).
    private func inkChanged(_ page: PlannerPage, hasInk: Bool) {
        guard case .week(let week) = page, inkedWeeks.contains(week) != hasInk else { return }
        if hasInk {
            inkedWeeks.insert(week)
        } else {
            inkedWeeks.remove(week)
        }
    }

    fileprivate func swiped(_ recognizer: UISwipeGestureRecognizer) {
        guard recognizer.state == .ended, !canvas.isZoomedIn else { return }
        onSwipe?(recognizer.direction == .left ? 1 : -1)
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

    // MARK: - Straight lines

    /// A stroke with pen, pencil or highlighter that is held still at its end for half a second
    /// becomes a straight line (as in Apple Notes); moving on without lifting moves its end.
    /// PencilKit gives no access to the stroke it is drawing, so the touch is followed here as
    /// well (`StrokeTracker`). At the hold PencilKit is told to drop its stroke (its drawing
    /// gesture is switched off until the touch lifts), and the canvas shows the page's ink plus
    /// the straight line, redrawn as the end moves. On lifting it is one edit, undone in one step.
    private func setUpStraightLines() {
        strokeTracker.delaysTouchesBegan = false
        strokeTracker.delaysTouchesEnded = false
        strokeTracker.cancelsTouchesInView = false
        strokeTracker.canFollow = { [weak self] touch in
            self?.drawsInk(with: touch) ?? false
        }
        strokeTracker.onBegin = { [weak self] touch in
            self?.strokeBegan(touch)
        }
        strokeTracker.onMove = { [weak self] samples, touch in
            self?.strokeMoved(samples, latest: touch)
        }
        strokeTracker.onEnd = { [weak self] touch, _ in
            self?.strokeEnded(touch)
        }
        canvas.addGestureRecognizer(strokeTracker)
    }

    /// PencilKit draws ink with this touch: pen, pencil or highlighter, with the Apple Pencil
    /// (or a finger, with "Draw with finger too").
    private func drawsInk(with touch: UITouch) -> Bool {
        canDraw && page != nil && activeLine == nil && tools.tool.drawsInk
            && canvas.drawingGestureRecognizer.isEnabled
            && (touch.type == .pencil || (drawWithFinger && touch.type == .direct))
    }

    private func strokeBegan(_ touch: UITouch) {
        lineStart = drawingLocation(of: touch)
        lineEnd = lineStart
        lineHold.begin(at: touch.location(in: nil), time: touch.timestamp)
        startLineTimer()
    }

    private func strokeMoved(_ samples: [UITouch], latest touch: UITouch) {
        for sample in samples {
            lineHold.move(to: sample.location(in: nil), time: sample.timestamp)
        }
        lineEnd = drawingLocation(of: touch)
        if activeLine != nil {
            showLine(force: false)
        } else if lineHold.checkHold(at: touch.timestamp) {
            straighten()
        }
    }

    /// Every 0.05 s while a stroke is followed: a finger held still sends no touches.
    private func lineTick() {
        if activeLine != nil {
            showLine(force: false)
        } else if lineHold.checkHold(at: ProcessInfo.processInfo.systemUptime) {
            straighten()
        }
    }

    private func strokeEnded(_ touch: UITouch) {
        stopLineTimer()
        guard activeLine != nil else { return }
        lineEnd = drawingLocation(of: touch)
        showLine(force: true)
        finishLine()
    }

    private func straighten() {
        guard page != nil, let undoManager = canvas.undoManager, activeLine == nil else { return }
        // The page's ink without the stroke being drawn (PencilKit adds it only on lifting).
        let before = canvas.drawing
        // Nothing PencilKit does now is an edit of its own: the line is one edit, at the end.
        undoManager.disableUndoRegistration()
        canvas.drawingGestureRecognizer.isEnabled = false
        activeLine = ActiveLine(before: before)
        showLine(force: true)
        #if DEBUG
        canvas.noteDebugEvent("straight(\(before.strokes.count))")
        #endif
    }

    /// Shows the straight line to the current end (at most once a frame, unless `force`).
    private func showLine(force: Bool) {
        guard var line = activeLine else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || (lineEnd != line.shownEnd && now - line.shownAt >= 1.0 / 60) else { return }
        let look = StraightStroke.inkType(for: tools.tool).flatMap { strokeLooks[$0] } ?? .plain
        guard let stroke = StraightStroke.make(
            from: lineStart, to: lineEnd, tools: tools, scale: canvas.drawingScale, look: look
        ) else { return }
        var drawing = line.before
        drawing.strokes.append(stroke)
        setCanvasDrawing(drawing)
        line.shownEnd = lineEnd
        line.shownAt = now
        activeLine = line
    }

    /// The pencil lifted (or the page is going away): the straight line becomes an edit of
    /// the page, undone in one step. `drawingScale`: the scale of the canvas's drawing, if it
    /// just changed.
    private func finishLine(drawingScale: CGFloat? = nil) {
        guard let line = activeLine else { return }
        activeLine = nil
        stopLineTimer()
        canvas.drawingGestureRecognizer.isEnabled = true
        canvas.undoManager?.enableUndoRegistration()
        let after = canvas.drawing
        registerLineUndo(restoring: line.before, redoing: after)
        commit(after, scale: drawingScale ?? canvas.drawingScale)
        refreshUndoState()
        #if DEBUG
        canvas.noteDebugEvent("line(\(after.strokes.count))")
        #endif
    }

    /// Undo puts back the ink as it was before the line; redo brings the line back.
    private func registerLineUndo(restoring drawing: PKDrawing, redoing other: PKDrawing) {
        let restore = DrawingBox(drawing: drawing)
        let redo = DrawingBox(drawing: other)
        canvas.undoManager?.registerUndo(withTarget: helper) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.undoLine(restore: restore, redo: redo)
            }
        }
    }

    private func undoLine(restore: DrawingBox, redo: DrawingBox) {
        setCanvasDrawing(restore.drawing)
        commit(restore.drawing, scale: canvas.drawingScale)
        registerLineUndo(restoring: redo.drawing, redoing: restore.drawing)
        Task { [weak self] in self?.refreshUndoState() }
    }

    /// Puts a drawing on the canvas that is not PencilKit's own edit (it is never one of
    /// PencilKit's undo steps).
    private func setCanvasDrawing(_ drawing: PKDrawing) {
        let undoManager = canvas.undoManager
        let pause = undoManager?.isUndoRegistrationEnabled == true
        if pause { undoManager?.disableUndoRegistration() }
        isReplacingDrawing = true
        canvas.drawing = drawing
        isReplacingDrawing = false
        if pause { undoManager?.enableUndoRegistration() }
    }

    /// PencilKit units of a touch.
    private func drawingLocation(of touch: UITouch) -> CGPoint {
        let point = touch.location(in: canvas.templateView)
        return CGPoint(x: point.x * canvas.drawingScale, y: point.y * canvas.drawingScale)
    }

    private func startLineTimer() {
        lineTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lineTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        lineTimer = timer
    }

    private func stopLineTimer() {
        lineTimer?.invalidate()
        lineTimer = nil
    }

    // MARK: - Private

    private func setTemplate(_ content: PlannerPageContent) {
        template = content.template
        canvas.templateView.template = content.template
        canvas.templateView.items = content.accessibilityItems
        canvas.accessibilityIdentifier = content.identifier
        canvas.accessibilityLabel = content.accessibilityLabel
    }

    /// The view's width changed: the same ink, re-expressed at the new scale. The undo
    /// history refers to the old scale, so it starts again.
    ///
    /// PencilKit kept tiles drawn at the old scale when it got the same strokes rescaled, so
    /// the canvas is emptied first and gets the ink back as new strokes a moment later.
    /// (The library always has the latest ink: every edit reaches it right away.)
    private func drawingScaleChanged(from old: CGFloat, to new: CGFloat) {
        #if DEBUG
        canvas.noteDebugEvent("scale \(old)->\(new) page=\(page?.description ?? "none")")
        #endif
        finishLine(drawingScale: old)
        applyTool()
        putInkOnCanvas(resetZoom: false)
    }

    /// Puts the open page's ink on the canvas so that nothing of the previous ink stays on
    /// screen. PencilKit kept showing tiles of the previous drawing for a while (after a
    /// change of scale, and on the iPad when going from a zoomed-in month to the year), so:
    /// its views are hidden, the canvas is emptied (and fitted to the width for a newly
    /// opened page), the ink is given back a moment later as new strokes, and the views
    /// come back once PencilKit has drawn it (at most 0.8 s later). The undo history
    /// starts again.
    private func putInkOnCanvas(resetZoom: Bool) {
        guard let page else { return }
        // The library has any ink from other devices too.
        remoteBase = nil
        let ink = Self.asNewStrokes(library.drawing(for: page, scale: canvas.drawingScale, layout: layout))
        canvas.hideInk(forAtMost: 0.8)
        awaitingRender = false
        replaceDrawing(PKDrawing())
        canvas.undoManager?.removeAllActions()
        if resetZoom {
            canvas.showWholeWidthFromTop()
        }
        Task { [weak self] in
            guard let self, self.page == page else { return }
            self.awaitingRender = true
            self.replaceDrawing(ink)
            self.canvas.undoManager?.removeAllActions()
            self.refreshUndoState()
        }
    }

    fileprivate func inkDidFinishRendering() {
        guard awaitingRender else { return }
        awaitingRender = false
        canvas.revealInk()
    }

    /// The same strokes as new objects, so PencilKit draws them from scratch.
    private static func asNewStrokes(_ drawing: PKDrawing) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.map { stroke in
            PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: stroke.mask, randomSeed: stroke.randomSeed)
        })
    }

    private func replaceDrawing(_ drawing: PKDrawing) {
        #if DEBUG
        canvas.noteDebugEvent("replace(\(drawing.strokes.count), w=\(Int(drawing.bounds.width)), s=\(canvas.drawingScale))")
        #endif
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
        canvas.tool = InkToolFactory.tool(for: tools, scale: canvas.drawingScale)
        // A new tool can bring new gesture recognizers with it.
        canvas.stopDelayingTouches()
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
    /// Puts the sample into the library (in canvas units); `show` then puts it on the canvas.
    private func addSampleInkIfRequested(_ content: PlannerPageContent) {
        guard LaunchOptions.sampleInk,
              library.drawing(for: content.page, layout: content.layout).strokes.isEmpty else { return }
        let sample = SampleInk.drawing(for: content.page, template: content.template)
        library.update(sample, scale: 1, for: content.page, layout: content.layout)
    }
    #endif
}

/// A stroke that became a straight line while the pencil is still down.
private struct ActiveLine {
    /// The page's ink without it.
    let before: PKDrawing
    /// The end of the line on the canvas now, and when it was put there.
    var shownEnd: CGPoint?
    var shownAt: TimeInterval = 0
}

/// PencilKit tools for the toolbar's state.
enum InkToolFactory {
    /// `scale`: PencilKit units per canvas unit (the widths are in canvas units).
    static func tool(for state: InkToolState, scale: CGFloat = 1) -> any PKTool {
        let width = (state.width ?? 1) * scale
        // The highlighter's opacity; the other tools are never see-through.
        let color = state.color.uiColor.withAlphaComponent(state.opacity)
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

    func canvasViewDidFinishRendering(_ canvasView: PKCanvasView) {
        controller?.inkDidFinishRendering()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        (scrollView as? InkCanvasView)?.followZoom()
    }

    @objc func tapped(_ recognizer: UITapGestureRecognizer) {
        controller?.tapped(recognizer)
    }

    @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
        controller?.longPressed(recognizer)
    }

    @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
        controller?.doubleTapped(recognizer)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let press = gestureRecognizer as? UILongPressGestureRecognizer,
              let canvas = press.view as? InkCanvasView else { return true }
        return controller?.wantsLongPress(at: canvas.canvasLocation(of: press)) ?? false
    }

    @objc func swiped(_ recognizer: UISwipeGestureRecognizer) {
        controller?.swiped(recognizer)
    }

    /// The Apple Pencil writes; only fingers tap (a dot on a month title must not open it).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.type != .pencil
    }

    /// With "Draw with finger too", a finger tap may also start a stroke. A long press and
    /// a swipe only listen: they never stop scrolling, zooming or drawing.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer is UILongPressGestureRecognizer || gestureRecognizer is UISwipeGestureRecognizer {
            return true
        }
        return otherGestureRecognizer === (gestureRecognizer.view as? PKCanvasView)?.drawingGestureRecognizer
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
