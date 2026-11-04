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
    internal enum DraggingAnnotationPart {
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
        
        // Repaint when viewModel properties update
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

    public func pageInfo(at canvasPoint: CGPoint) -> (pageIndex: Int, frame: NSRect, pagePoint: CGPoint)? {
        guard viewModel.document != nil else { return nil }
        let unscaledY = max(0, (canvasPoint.y - 16) / viewModel.effectiveZoom)
        let pageIdx = viewModel.effectivePageIndex(atYOffset: unscaledY)
        guard let pFrame = pageFrame(for: pageIdx) else { return nil }

        if pFrame.contains(canvasPoint) {
            // Note: while rotated, this pagePoint is not corrected for rotation — deliberately,
            // since text selection/link/form hit-testing (the only consumers of pagePoint) are all
            // inert while rotated (see PDFViewerViewModel.viewRotationDegrees's doc comment), so an
            // uncorrected value here is simply never acted on rather than needing to be right.
            let pBounds = viewModel.document!.pageBounds[pageIdx]
            let pageX = pBounds.minX + ((canvasPoint.x - pFrame.minX) / viewModel.effectiveZoom)
            let pageY = pBounds.minY + ((canvasPoint.y - pFrame.minY) / viewModel.effectiveZoom)
            return (pageIdx, pFrame, CGPoint(x: pageX, y: pageY))
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

    /// Computes where an AcroForm widget sits on screen, in canvas coordinates.
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

    /// Maps a page's native rect onto its rotated on-screen footprint.
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

}
