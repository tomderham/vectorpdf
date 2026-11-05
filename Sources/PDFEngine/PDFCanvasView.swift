//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import AppKit
import Combine
import CoreGraphics
import MuPDFBridge

/// High-performance AppKit canvas view for rendering PDF pages, search highlights, and text selection.
/// Directly paints via Quartz 2D in draw(_:) without any NSHostingView overhead or focus engine bloat.
public final class PDFCanvasView: NSView, NSUserInterfaceValidations, NSTextFieldDelegate {
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override func becomeFirstResponder() -> Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    
    public unowned var viewModel: PDFViewerViewModel
    private var cancellables = Set<AnyCancellable>()
    
    // Mouse interaction state
    var hoveredLink: SnapshotTarget?
    var pendingLinkTarget: (target: SnapshotTarget, opensInNewWindow: Bool, didPeek: Bool)?

    // Command-hover / Force Click link peek
    let linkPeek = LinkPeekController()
    let referencePeek = ReferencePeekController()
    var referenceSearchTask: Task<Void, Never>?

    // Sharp renders of the visible part of pages too big to render whole (PDFCanvasView+Detail).
    var pageDetails: [Int: PageDetail] = [:]
    var detailRenderTask: Task<Void, Never>?
    var pendingDetailRequest: DetailRequest?
    var linkPeekEventMonitor: Any?
    /// Set when a key, click or scroll cancels a peek, until the modifiers next change.
    var isLinkPeekSuppressed = false
    var dragStartCanvasPoint: CGPoint?
    var isDraggingSelection: Bool = false
    var hasDraggedPastThreshold: Bool = false
    var activeDragPage: Int?
    var lastContextMenuLocation: CGPoint = .zero
    
    // Freehand drawing in-progress state
    var currentDrawingPoints: [CGPoint] = []
    var currentDrawingPageIndex: Int?

    // Redaction drafting in-progress state
    var currentRedactionPage: Int?
    var currentRedactionStart: CGPoint?
    var currentRedactionEnd: CGPoint?

    // Callout drafting in-progress state
    var currentCalloutPage: Int?
    var currentCalloutStart: CGPoint?
    var currentCalloutEnd: CGPoint?

    // Shape drafting in-progress state
    var currentShapePage: Int?
    var currentShapeStart: CGPoint?
    var currentShapeEnd: CGPoint?
    /// The path dragged so far for a revision cloud, which follows it.
    var currentShapePath: [CGPoint] = []
    /// An annotation chosen in the Comments sidebar, outlined for a moment so it can be found.
    var revealedAnnotationOutline: (pageIndex: Int, rect: CGRect)?
    /// Pictures of annotations from the file being edited, as the document draws them, by object
    /// number, with the revision and scale each was drawn for.
    var fileAnnotationPictures: [Int: (revision: Int, scale: CGFloat, image: CGImage, bounds: CGRect)] = [:]

    /// The comments popover anchored to an annotation, while it's open.
    var commentsPopover: NSPopover?
    var commentsPopoverDelegate: CommentsPopoverDelegate?

    // Engineering measurement drafting in-progress state
    var currentMeasurePage: Int?
    var currentMeasurePoints: [CGPoint] = []
    var currentMeasureCandidatePoint: CGPoint?
    var isSnappedOrtho: Bool = false
    var isSnappedVertex: Bool = false
    var currentSnappedGuideOrigin: CGPoint?

    // Inline text box editing state
    var activeInlineTextField: NSTextField?
    var activeEditingAnnotation: PDFAnnotation?
    var activeEditingPageIndex: Int?
    var activeEditingPagePoint: CGPoint?
    var isCommittingInlineText: Bool = false
    
    // Annotation selection and drag-to-move state
    internal enum DraggingAnnotationPart: Equatable {
        case entireAnnotation
        case resizeTopLeft
        case resizeTopRight
        case resizeBottomLeft
        case resizeBottomRight
        case calloutTextBox
        case calloutTargetPoint
        case calloutKneePoint
        case lineStart
        case lineEnd
        /// One of a measurement's points, by index.
        case measurementPoint(Int)
        /// A length's dimension line, moved sideways nearer to or further from what it measures.
        case measurementLeader
    }
    var selectedAnnotation: (id: UUID, pageIndex: Int)?
    var activeAnnotationDrag: (
        id: UUID,
        pageIndex: Int,
        part: DraggingAnnotationPart,
        initialAnnotation: PDFAnnotation,
        startPagePoint: CGPoint,
        currentDelta: CGSize
    )?
    
    // Tracks mouse position for live ghost stamp previews
    var currentHoverCanvasPoint: CGPoint? = nil

    // Visible AcroForm controls cache (keyed by widget.id, e.g. "p0_w1")
    var activeFormControls: [String: NSView] = [:]
    /// The layout rect and rotation each subview on a page (form control, inline text field) was
    /// last placed at, by `place(_:layoutRect:geometry:)`.
    var subviewPlacements: [ObjectIdentifier: (layoutRect: NSRect, frame: NSRect, rotation: Int)] = [:]

    // Inverted dark-mode page bitmap cache, keyed by page index.
    private struct CachedThemedPage {
        let source: NSImage
        let appearance: PDFColorAppearance
        let transformed: NSImage
    }
    private var themedPageCache: [Int: CachedThemedPage] = [:]

    /// Resolves the effective color appearance for page rendering:
    /// - .light: un-inverted original page bitmap
    /// - .dark: dark gray background with brightened text
    /// - .sepia: warm parchment background with dark espresso text
    /// - .system: follows macOS aqua/darkAqua
    var activeColorAppearance: PDFColorAppearance {
        switch PDFViewerAppCoordinator.shared.pdfColorAppearance {
        case .light: return .light
        case .dark: return .dark
        case .sepia: return .sepia
        case .system:
            let isDarkAqua = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDarkAqua ? .dark : .light
        }
    }

    var isDarkMode: Bool {
        activeColorAppearance == .dark
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The cache keys off source image identity and active appearance mode, so a redraw
        // updates the view with the newly-current effective appearance.
        needsDisplay = true
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        viewModel.updateDisplayScale(for: window)
        needsDisplay = true
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        linkPeek.dismiss()
        referenceSearchTask?.cancel()
        referencePeek.dismiss()
        if let monitor = linkPeekEventMonitor {
            NSEvent.removeMonitor(monitor)
            linkPeekEventMonitor = nil
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = window {
            installLinkPeekEventMonitor()
            viewModel.updateDisplayScale(for: win)
            DispatchQueue.main.async { [weak self, weak win] in
                guard let self = self, let win = win else { return }
                if win.firstResponder == nil || win.firstResponder === win {
                    win.makeFirstResponder(self)
                }
            }
        }
    }

    /// The image actually drawn on screen for a page — the rendered bitmap as-is in light mode,
    /// or a cached themed version in dark or sepia modes.
    func displayImage(for pageIdx: Int, source: NSImage) -> NSImage {
        let appearance = activeColorAppearance
        guard appearance != .light else { return source }
        if let cached = themedPageCache[pageIdx], cached.source === source, cached.appearance == appearance {
            return cached.transformed
        }
        guard let transformed = Self.transformedImage(from: source, appearance: appearance) else { return source }
        themedPageCache[pageIdx] = CachedThemedPage(source: source, appearance: appearance, transformed: transformed)
        return transformed
    }

    /// Drops any cached themed page whose page is no longer in viewModel.renderedPages (already
    /// bounded to a handful of pages around the current one — see PDFViewerViewModel.pruneCaches)
    /// or whose cached appearance mode no longer matches the current active mode.
    func pruneThemedPageCache() {
        guard !themedPageCache.isEmpty else { return }
        let currentMode = activeColorAppearance
        for (pageIdx, cached) in themedPageCache {
            if viewModel.renderedPages[pageIdx] !== cached.source || cached.appearance != currentMode {
                themedPageCache.removeValue(forKey: pageIdx)
            }
        }
    }

    /// Dark-mode page placeholder gray while rendering; matches what fz_invert_pixmap_luminance
    /// turns a white page into.
    static let darkModeBackgroundGray: UInt8 = 4

    /// Sepia page placeholder while rendering: warm parchment ivory (#F6EED9), matching the white
    /// point of the tint in mupdf_apply_color_appearance.
    static let sepiaBackgroundR: UInt8 = 246
    static let sepiaBackgroundG: UInt8 = 238
    static let sepiaBackgroundB: UInt8 = 217

    /// Applies the dark (fz_invert_pixmap_luminance) or sepia (fz_tint_pixmap) theme to a copy of the page bitmap.
    static func transformedImage(from image: NSImage, appearance: PDFColorAppearance) -> NSImage? {
        guard appearance != .light else { return image }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)

        let ctx = PDFContextManager.shared.makeClonedContext()
        defer { PDFContextManager.shared.dropContext(ctx) }

        let mode: Int32 = (appearance == .dark) ? 1 : (appearance == .sepia ? 2 : 0)
        let ret = mupdf_apply_color_appearance(ctx, buffer, Int32(width), Int32(height), Int32(bytesPerRow), 4, mode)
        guard ret == 0, let outputCG = context.makeImage() else { return nil }
        return NSImage(cgImage: outputCG, size: image.size)
    }

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.drawsAsynchronously = true
        
        // Any @Published change on the view model redraws the whole canvas and re-syncs form
        // controls, so keep state that changes often but isn't drawn (progress, in-flight
        // bookkeeping such as isLiveZooming) out of @Published.
        viewModel.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
                self?.syncFormControls()
            }
            .store(in: &cancellables)
            
        NotificationCenter.default.publisher(for: .formWidgetDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.isActivelyEditingFormControl {
                    self.needsDisplay = true
                }
                self.syncFormControls()
            }
            .store(in: &cancellables)

        // Repaint and re-sync form controls when PDF color mode changes.
        PDFViewerAppCoordinator.shared.$pdfColorAppearance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.themedPageCache.removeAll()
                self.needsDisplay = true
                self.syncFormControls()
            }
            .store(in: &cancellables)

        // React immediately in real-time when font size or annotation color changes
        viewModel.$selectedFontSize
            .dropFirst()          // the current value, replayed on subscribe — not a change
            .removeDuplicates()   // selecting an annotation re-sets these to its own values
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSize in
                self?.handleFontSizeChanged(newSize)
            }
            .store(in: &cancellables)

        viewModel.$selectedAnnotationColor
            .dropFirst()          // the current value, replayed on subscribe — not a change
            .removeDuplicates()   // selecting an annotation re-sets these to its own values
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newColor in
                self?.handleAnnotationColorChanged(newColor)
            }
            .store(in: &cancellables)

        viewModel.$drawStrokeWidth
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] width in
                self?.restyleSelectedShape(strokeWidth: width)
            }
            .store(in: &cancellables)

        viewModel.$annotationReveal
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reveal in
                self?.showRevealedAnnotation(reveal)
            }
            .store(in: &cancellables)

        viewModel.$selectedShapeLineEnding
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ending in
                self?.restyleSelectedShape(lineEnding: ending)
            }
            .store(in: &cancellables)

        // An annotation on a layer just hidden can't stay selected.
        viewModel.$layerVisibility
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let sel = self.selectedAnnotation else { return }
                if !self.viewModel.shownAnnotations(onPage: sel.pageIndex).contains(where: { $0.id == sel.id }) {
                    self.selectedAnnotation = nil
                    self.needsDisplay = true
                }
            }
            .store(in: &cancellables)

        // Clear in-progress drafting state on mode change.
        viewModel.$canvasMode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.discardInProgressDrafts()
            }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func discardInProgressDrafts() {
        currentMeasurePage = nil
        currentMeasurePoints = []
        currentMeasureCandidatePoint = nil
        currentCalloutPage = nil
        currentCalloutStart = nil
        currentCalloutEnd = nil
        currentShapePage = nil
        currentShapeStart = nil
        currentShapeEnd = nil
        currentShapePath = []
        currentRedactionPage = nil
        currentRedactionStart = nil
        currentRedactionEnd = nil
        currentDrawingPoints = []
        currentDrawingPageIndex = nil
        needsDisplay = true
    }
    
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseMoved, .cursorUpdate, .mouseEnteredAndExited]
        addTrackingArea(NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil))
    }
    
    public override func layout() {
        super.layout()
        syncFormControls()
    }
    
    // MARK: - Geometry & Page Framing
    
    public func pageFrame(for pageIndex: Int) -> NSRect? {
        // The layout is rebuilt after the document changes, and can briefly be shorter than it.
        guard let doc = viewModel.document, pageIndex >= 0, pageIndex < doc.pageCount,
              pageIndex < viewModel.effectivePageYOffsets.count else { return nil }
        let pBounds = doc.pageBounds[pageIndex]
        let y = 16 + (viewModel.effectivePageYOffsets[pageIndex] * viewModel.effectiveZoom)

        if viewModel.isTwoPageMode {
            // Book Mode (Cover Page Offset):
            // Page 0 (Cover) sits alone on Row 0, positioned on the right-hand side of the spread
            // (aligned with the right-hand recto page column, spine down the center).
            // Subsequent pages 1..N are paired (1,2), (3,4)... with odd indices on the Left (verso)
            // and even indices on the Right (recto).
            let pageGap: CGFloat = 16.0
            let w = pBounds.width * viewModel.effectiveZoom
            let h = pBounds.height * viewModel.effectiveZoom

            if pageIndex == 0 {
                let leftSlotWidth = (doc.pageCount > 1 ? doc.pageBounds[1].width : pBounds.width) * viewModel.effectiveZoom
                let pairWidth = leftSlotWidth + pageGap + w
                let pairX = max(32, (bounds.width - pairWidth) / 2)
                let x = pairX + leftSlotWidth + pageGap
                return NSRect(x: x, y: y, width: w, height: h)
            } else {
                let isLeft = pageIndex % 2 == 1
                let pairStart = isLeft ? pageIndex : pageIndex - 1
                let rightIndex = pairStart + 1
                let hasRight = rightIndex < doc.pageCount
                let leftWidth = doc.pageBounds[pairStart].width * viewModel.effectiveZoom
                let rightSlotWidth = (hasRight ? doc.pageBounds[rightIndex].width : doc.pageBounds[pairStart].width) * viewModel.effectiveZoom
                let pairWidth = leftWidth + pageGap + rightSlotWidth
                let pairX = max(32, (bounds.width - pairWidth) / 2)
                let x = isLeft ? pairX : pairX + leftWidth + pageGap
                return NSRect(x: x, y: y, width: w, height: h)
            }
        }

        // At 90°/270°, the page's on-screen footprint has width/height swapped from its native
        // bounds — see effectivePageYOffsets's doc comment. viewRotationDegrees is 0 far more often
        // than not, so this stays exactly the pre-rotation math in the common case.
        let sideways = viewModel.viewRotationDegrees == 90 || viewModel.viewRotationDegrees == 270
        let w = (sideways ? pBounds.height : pBounds.width) * viewModel.effectiveZoom
        let h = (sideways ? pBounds.width : pBounds.height) * viewModel.effectiveZoom
        let x = max(32, (bounds.width - w) / 2)
        return NSRect(x: x, y: y, width: w, height: h)
    }

    /// Where page `pageIndex` sits on the canvas and how its page points map there, in every view
    /// (single page, two-page spreads, rotated). Every conversion between page points and canvas
    /// points goes through this.
    public func pageGeometry(for pageIndex: Int) -> PageGeometry? {
        guard let doc = viewModel.document, let frame = pageFrame(for: pageIndex) else { return nil }
        return PageGeometry(frame: frame, pageBounds: doc.pageBounds[pageIndex], zoom: viewModel.effectiveZoom, rotation: viewModel.viewRotationDegrees)
    }

    /// The page point under `canvasPoint` on page `pageIndex`, whether or not it's on the page —
    /// for drags that leave the page they started on.
    func pagePoint(forCanvasPoint canvasPoint: CGPoint, onPage pageIndex: Int) -> CGPoint? {
        pageGeometry(for: pageIndex)?.pagePoint(forCanvasPoint: canvasPoint)
    }

    public func pageInfo(at canvasPoint: CGPoint) -> (pageIndex: Int, frame: NSRect, pagePoint: CGPoint)? {
        guard let doc = viewModel.document else { return nil }
        let unscaledY = max(0, (canvasPoint.y - 16) / viewModel.effectiveZoom)
        let pageIdx = viewModel.effectivePageIndex(atYOffset: unscaledY)
        // In two-page mode that's one page of the spread; the point may be on the other.
        let candidates = viewModel.isTwoPageMode ? [pageIdx, pageIdx - 1, pageIdx + 1] : [pageIdx]
        for idx in candidates where idx >= 0 && idx < doc.pageCount {
            guard let geometry = pageGeometry(for: idx), geometry.frame.contains(canvasPoint) else { continue }
            return (idx, geometry.frame, geometry.pagePoint(forCanvasPoint: canvasPoint))
        }
        return nil
    }

    /// Finds the internal cross-reference/link at a canvas point, if any. Internal links only
    /// (not external URLs/mailto), since those are the only ones with a meaningful "open in a
    /// new window at this location" action.
    func internalLinkInfo(at canvasPoint: CGPoint) -> SnapshotTarget? {
        guard let (pageIdx, _, pagePoint) = pageInfo(at: canvasPoint),
              let links = viewModel.pageLinks[pageIdx],
              let link = links.first(where: { $0.sourceRect?.contains(pagePoint) == true }),
              link.targetPage >= 0 else {
            return nil
        }
        return link
    }

    /// Places a subview over `layoutRect` (in the layout space of the page `geometry` describes),
    /// turned with the page in a rotated view. Does nothing when it's already there, so that an
    /// edit in progress isn't disturbed.
    func place(_ view: NSView, layoutRect: NSRect, geometry: PageGeometry) {
        let frame = geometry.subviewFrame(forLayoutRect: layoutRect)
        let key = ObjectIdentifier(view)
        if let placed = subviewPlacements[key], placed.frame == frame, placed.rotation == geometry.rotation,
           view.frameCenterRotation == geometry.subviewRotation {
            return
        }
        if geometry.isRotated || view.frameCenterRotation != 0 {
            // frameCenterRotation moves the frame's origin, so set the frame unturned first.
            view.frameCenterRotation = 0
            view.frame = frame
            view.frameCenterRotation = geometry.subviewRotation
        } else if view.frame != frame {
            view.frame = frame
        }
        subviewPlacements[key] = (layoutRect, frame, geometry.rotation)
    }

    /// AppKit hit-tests a subview by its `frame`, which for a view turned by frameCenterRotation
    /// isn't where it's shown, so clicks on a form field or text box in a rotated view would miss
    /// it. Turned subviews are found here by their bounds instead.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        for sub in subviews.reversed() where sub.frameCenterRotation != 0 && !sub.isHidden {
            let inSub = sub.convert(local, from: self)
            guard sub.bounds.contains(inSub) else { continue }
            for child in sub.subviews.reversed() where !child.isHidden {
                if let hit = child.hitTest(inSub) { return hit }
            }
            return sub
        }
        // Nor may a turned subview take a click by its frame where it isn't shown.
        let hit = super.hitTest(point)
        if let hit, hit !== self, subviews.contains(where: { $0.frameCenterRotation != 0 && hit.isDescendant(of: $0) }) {
            return self
        }
        return hit
    }

    /// Forgets a subview's placement once it's removed.
    func forgetPlacement(of view: NSView) {
        subviewPlacements.removeValue(forKey: ObjectIdentifier(view))
    }

    /// The layout rect a subview was placed at, or its frame if it wasn't placed.
    func layoutRect(of view: NSView) -> NSRect {
        subviewPlacements[ObjectIdentifier(view)]?.layoutRect ?? view.frame
    }

    /// Computes where an AcroForm widget sits on its page, in the page's layout space (see
    /// PageGeometry) when given `layoutFrame`.
    /// Kept identical to syncFormControls() positioning to mask static appearance without clipping.
    func widgetScreenFrame(for widget: PDFFormWidget, pageFrame: NSRect, pageBounds: CGRect) -> NSRect {
        let isChoice = (widget.type == .combobox || widget.type == .listbox)
        let isButton = (widget.type == .checkbox || widget.type == .radiobutton)
        let vx = pageFrame.minX + (widget.rect.minX - pageBounds.minX) * viewModel.effectiveZoom
        let vy = pageFrame.minY + (widget.rect.minY - pageBounds.minY) * viewModel.effectiveZoom

        let vw: CGFloat
        let vh: CGFloat
        if isButton {
            // Checkboxes and radio buttons strictly scale with zoom, with no minimum size,
            // so the mask/control never intrude on adjacent form labels or sibling rows.
            vw = widget.rect.width * viewModel.effectiveZoom
            vh = widget.rect.height * viewModel.effectiveZoom
        } else if isChoice {
            let baseWidth = max(widget.rect.width, 85.0)
            vw = max(baseWidth * viewModel.effectiveZoom, 40)
            vh = max(widget.rect.height * viewModel.effectiveZoom, 14)
        } else {
            // Text fields keep a legibility/click-target floor at low zoom.
            vw = max(widget.rect.width * viewModel.effectiveZoom, 16)
            vh = max(widget.rect.height * viewModel.effectiveZoom, 14)
        }
        return NSRect(x: vx, y: vy, width: vw, height: vh)
    }

}

/// How one page maps onto the canvas.
///
/// There are three spaces:
/// - **page** points, as MuPDF gives them (y down, from `pageBounds.origin`);
/// - the page's **layout** space: canvas points as if the view weren't rotated, the page drawn
///   unrotated at `layoutFrame` (same origin as `frame`, the page's native size times zoom). The
///   canvas draws annotations and overlays here, inside `viewRotation`, so their arithmetic
///   (`layoutFrame.minX + (x - pageBounds.minX) * zoom`) is the same in every view;
/// - **canvas** points, where the page really is: `frame`, which is `layoutFrame` turned by the
///   view rotation. Mouse events arrive in this space.
public struct PageGeometry: Equatable, Sendable {
    /// The page's on-screen footprint (width and height swapped at 90° and 270°).
    public let frame: NSRect
    public let pageBounds: CGRect
    public let zoom: CGFloat
    /// The view rotation: 0, 90, 180 or 270 degrees clockwise.
    public let rotation: Int

    public init(frame: NSRect, pageBounds: CGRect, zoom: CGFloat, rotation: Int) {
        self.frame = frame
        self.pageBounds = pageBounds
        self.zoom = zoom
        self.rotation = rotation
    }

    public var isRotated: Bool { rotation != 0 }

    /// Where the page would be if the view weren't rotated.
    public var layoutFrame: NSRect {
        NSRect(x: frame.minX, y: frame.minY, width: pageBounds.width * zoom, height: pageBounds.height * zoom)
    }

    /// Layout space → canvas space: turns `layoutFrame` onto `frame`. Identity when unrotated.
    public var viewRotation: CGAffineTransform {
        guard isRotated else { return .identity }
        let size = layoutFrame.size
        return CGAffineTransform(translationX: -frame.minX, y: -frame.minY)
            .concatenating(Self.rotationTransform(degrees: rotation, nativeWidth: size.width, nativeHeight: size.height))
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
    }

    /// Maps a native rect of `nativeWidth` x `nativeHeight` at the origin onto its footprint
    /// turned clockwise by `degrees` (in the flipped canvas), also at the origin.
    static func rotationTransform(degrees: Int, nativeWidth: CGFloat, nativeHeight: CGFloat) -> CGAffineTransform {
        switch degrees {
        case 90:
            return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: nativeHeight, ty: 0)
        case 180:
            return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: nativeWidth, ty: nativeHeight)
        case 270:
            return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: nativeWidth)
        default:
            return .identity
        }
    }

    /// Page space → layout space.
    public var pageToLayout: CGAffineTransform {
        CGAffineTransform(translationX: -pageBounds.minX, y: -pageBounds.minY)
            .concatenating(CGAffineTransform(scaleX: zoom, y: zoom))
            .concatenating(CGAffineTransform(translationX: frame.minX, y: frame.minY))
    }

    /// Page space → canvas space.
    public var pageToCanvas: CGAffineTransform { pageToLayout.concatenating(viewRotation) }

    public func canvasPoint(forPagePoint p: CGPoint) -> CGPoint { p.applying(pageToCanvas) }
    public func pagePoint(forCanvasPoint p: CGPoint) -> CGPoint { p.applying(pageToCanvas.inverted()) }
    public func layoutPoint(forCanvasPoint p: CGPoint) -> CGPoint { p.applying(viewRotation.inverted()) }
    public func canvasPoint(forLayoutPoint p: CGPoint) -> CGPoint { p.applying(viewRotation) }

    /// The canvas rect covering a page rect (exact, since the rotation is a multiple of 90°).
    public func canvasRect(forPageRect r: CGRect) -> CGRect { r.applying(pageToCanvas) }
    /// The page rect covering a canvas rect.
    public func pageRect(forCanvasRect r: CGRect) -> CGRect { r.applying(pageToCanvas.inverted()) }

    /// A canvas-space vector (a drag or an arrow key) in page space.
    public func pageVector(forCanvasVector v: CGSize) -> CGSize {
        let t = pageToCanvas.inverted()
        return CGSize(width: t.a * v.width + t.c * v.height, height: t.b * v.width + t.d * v.height)
    }

    /// The view rotation as an AppKit `frameCenterRotation` for a subview of the flipped canvas.
    public var subviewRotation: CGFloat {
        // frameCenterRotation is counterclockwise in the superview's coordinates; the canvas is
        // flipped, so that's clockwise on screen, as `rotation` is.
        CGFloat(rotation)
    }

    /// The frame to give a subview so that, turned by `subviewRotation` about its centre, it
    /// covers `layoutRect` as rotated onto the canvas.
    public func subviewFrame(forLayoutRect layoutRect: NSRect) -> NSRect {
        guard isRotated else { return layoutRect }
        let center = canvasPoint(forLayoutPoint: CGPoint(x: layoutRect.midX, y: layoutRect.midY))
        return NSRect(x: center.x - layoutRect.width / 2, y: center.y - layoutRect.height / 2, width: layoutRect.width, height: layoutRect.height)
    }
}
