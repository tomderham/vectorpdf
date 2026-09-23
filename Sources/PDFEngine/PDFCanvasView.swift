import AppKit
import Combine
import CoreGraphics
import Accelerate

/// High-performance AppKit canvas view for rendering PDF pages, search highlights, and text selection.
/// Directly paints via Quartz 2D in draw(_:) without any NSHostingView overhead or focus engine bloat.
public final class PDFCanvasView: NSView, NSUserInterfaceValidations, NSTextFieldDelegate {
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { true }
    public override var mouseDownCanMoveWindow: Bool { false }
    
    public unowned var viewModel: PDFViewerViewModel
    private var cancellables = Set<AnyCancellable>()
    
    // Mouse interaction state
    private var hoveredLink: SnapshotTarget?
    private var pendingLinkTarget: (target: SnapshotTarget, isOption: Bool)?
    private var dragStartCanvasPoint: CGPoint?
    private var isDraggingSelection: Bool = false
    private var hasDraggedPastThreshold: Bool = false
    private var activeDragPage: Int?
    private var lastContextMenuLocation: CGPoint = .zero
    
    // Freehand drawing in-progress state
    private var currentDrawingPoints: [CGPoint] = []
    private var currentDrawingPageIndex: Int?

    // Inline text box editing state
    private var activeInlineTextField: NSTextField?
    private var activeEditingAnnotation: PDFAnnotation?
    private var activeEditingPageIndex: Int?
    private var activeEditingPagePoint: CGPoint?
    
    // Visible AcroForm controls cache (keyed by widget.id, e.g. "p0_w1")
    private var activeFormControls: [String: NSView] = [:]

    // Dark-mode page rendering: inverts each rendered page bitmap so pages read as light-on-dark
    // instead of a jarring bright-white rectangle in an otherwise dark app. Keyed by page index,
    // storing the source image alongside its inverted counterpart so a page only gets reprocessed
    // when its actual rendered bitmap changes (e.g. after a zoom-triggered re-render) — not on
    // every redraw.
    private var invertedPageCache: [Int: (source: NSImage, inverted: NSImage)] = [:]

    /// Whether *this page's rendering* should be dark, which follows PDFViewerAppCoordinator's
    /// global PDF Color setting (View menu) rather than the system appearance directly — that
    /// setting defaults to following the system, but can be pinned to Light or Dark independent of
    /// it, e.g. to keep the app's own UI dark while still seeing a document's true colors.
    private var isDarkMode: Bool {
        switch PDFViewerAppCoordinator.shared.pdfColorAppearance {
        case .light: return false
        case .dark: return true
        case .system: return effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // The cache keys off the *source* image identity, not light/dark state, so it doesn't
        // need clearing here — only a redraw, so the newly-current isDarkMode value takes effect.
        needsDisplay = true
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        viewModel.updateDisplayScale(for: window)
        needsDisplay = true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let win = window {
            viewModel.updateDisplayScale(for: win)
        }
    }

    /// The image actually drawn on screen for a page — the rendered bitmap as-is in light mode,
    /// or a cached inverted version in dark mode. Falls back to the un-inverted image if inversion
    /// fails for any reason (never worth blocking the page from showing at all).
    private func displayImage(for pageIdx: Int, source: NSImage) -> NSImage {
        guard isDarkMode else { return source }
        if let cached = invertedPageCache[pageIdx], cached.source === source {
            return cached.inverted
        }
        guard let inverted = Self.invertedImage(from: source) else { return source }
        invertedPageCache[pageIdx] = (source: source, inverted: inverted)
        return inverted
    }

    /// Drops any cached inversion whose page is no longer in viewModel.renderedPages (already
    /// bounded to a handful of pages around the current one — see PDFViewerViewModel.pruneCaches)
    /// or whose cached source no longer matches the current render (e.g. re-rendered after a
    /// zoom change), so this cache tracks the render cache instead of growing unboundedly while
    /// scrolling through a long document in dark mode.
    private func pruneInvertedPageCache() {
        guard !invertedPageCache.isEmpty else { return }
        for (pageIdx, cached) in invertedPageCache {
            if viewModel.renderedPages[pageIdx] !== cached.source {
                invertedPageCache.removeValue(forKey: pageIdx)
            }
        }
    }

    /// Fixed target grays for the dark-mode remap below: a moderate dark gray in line with macOS's
    /// own dark-mode chrome, on the darker side of it so the page reads as similar to or slightly
    /// darker than the surrounding UI rather than identical to it.
    private static let darkModeBackgroundGray: UInt8 = 22
    private static let darkModeLabelGray: UInt8 = 235

    /// Remaps white (255) to darkModeBackgroundGray and black (0) to darkModeLabelGray by
    /// manipulating raw 8-bit RGBA bytes directly via CGContext. Deliberately not Core Image's
    /// CIColorMatrix: Core Image computes in a linear-light working space and only gamma-encodes
    /// at final output, so bias/scale math meant for plain gamma-encoded 0–255 values lands lighter
    /// than intended, especially at the dark end where linear/gamma curves diverge most. Operating
    /// on the raw bytes directly has no color-management step to second-guess.
    private static func invertedImage(from image: NSImage) -> NSImage? {
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

        // output = label + (background - label) * (input / 255), computed once as a 256-entry
        // lookup table rather than per-channel-per-pixel, since there are only 256 possible input
        // byte values.
        let label = Double(darkModeLabelGray)
        let scale = (Double(darkModeBackgroundGray) - label) / 255.0
        var lookup = [UInt8](repeating: 0, count: 256)
        for input in 0...255 {
            lookup[input] = UInt8(max(0, min(255, (label + scale * Double(input)).rounded())))
        }

        // SIMD-vectorized remap via Accelerate rather than a manual per-byte loop: at 2x Retina on
        // a large page this buffer is tens of MB, and it's computed synchronously on the main
        // thread inside draw(_:) (see displayImage's caching for when this actually runs).
        // vImageTableLookUp_ARGB8888 operates on the four interleaved bytes exactly as they sit in
        // memory, regardless of what its parameter names call them — our layout is R,G,B,A
        // (premultipliedLast), so the same `lookup` table is passed for the first three parameters
        // and `identity` (a pass-through table) for the fourth to leave alpha untouched.
        var identity = [UInt8](repeating: 0, count: 256)
        for i in 0...255 { identity[i] = UInt8(i) }
        var vImageBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(buffer),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: bytesPerRow
        )
        let error = lookup.withUnsafeBufferPointer { lut in
            identity.withUnsafeBufferPointer { identityLut in
                vImageTableLookUp_ARGB8888(&vImageBuffer, &vImageBuffer, lut.baseAddress, lut.baseAddress, lut.baseAddress, identityLut.baseAddress, vImage_Flags(kvImageNoFlags))
            }
        }
        if error != kvImageNoError {
            // Extremely unlikely (same-size in-place lookup on a buffer we just allocated), but
            // fall back to the always-correct manual loop rather than showing a half-remapped page.
            let totalBytes = height * bytesPerRow
            var offset = 0
            while offset < totalBytes {
                buffer[offset] = lookup[Int(buffer[offset])]
                buffer[offset + 1] = lookup[Int(buffer[offset + 1])]
                buffer[offset + 2] = lookup[Int(buffer[offset + 2])]
                offset += bytesPerPixel
            }
        }

        guard let outputCG = context.makeImage() else { return nil }
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

        // Repaint (and re-sync form controls' own .appearance, see syncFormControls) when the
        // app-wide PDF Color setting changes (View menu) — isDarkMode reads it directly, but
        // nothing else would trigger either when it's toggled.
        PDFViewerAppCoordinator.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
                self?.syncFormControls()
            }
            .store(in: &cancellables)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        guard let doc = viewModel.document, pageIndex >= 0, pageIndex < doc.pageCount else { return nil }
        let pBounds = doc.pageBounds[pageIndex]
        let y = 16 + (viewModel.effectivePageYOffsets[pageIndex] * viewModel.effectiveZoom)

        if viewModel.isTwoPageMode {
            // Both pages of a pair share the same row (same y, computed above), placed left/right
            // of a shared center instead of each individually centered — consecutive pairing
            // (0,1), (2,3), ... matching effectivePageYOffsets's two-page branch.
            let pageGap: CGFloat = 16.0
            let isLeft = pageIndex % 2 == 0
            let pairStart = isLeft ? pageIndex : pageIndex - 1
            let rightIndex = pairStart + 1
            let hasRight = rightIndex < doc.pageCount
            let leftWidth = doc.pageBounds[pairStart].width * viewModel.effectiveZoom
            let rightWidth = hasRight ? doc.pageBounds[rightIndex].width * viewModel.effectiveZoom : 0
            let pairWidth = leftWidth + (hasRight ? pageGap + rightWidth : 0)
            let pairX = max(32, (bounds.width - pairWidth) / 2)
            let w = pBounds.width * viewModel.effectiveZoom
            let h = pBounds.height * viewModel.effectiveZoom
            let x = isLeft ? pairX : pairX + leftWidth + pageGap
            return NSRect(x: x, y: y, width: w, height: h)
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
    private func internalLinkInfo(at canvasPoint: CGPoint) -> SnapshotTarget? {
        guard let (pageIdx, _, pagePoint) = pageInfo(at: canvasPoint),
              let links = viewModel.pageLinks[pageIdx],
              let link = links.first(where: { $0.sourceRect?.contains(pagePoint) == true }),
              link.targetPage >= 0 else {
            return nil
        }
        return link
    }

    /// The single source of truth for where an AcroForm widget sits on screen, in canvas
    /// coordinates. Used both to paint the opaque mask that hides the widget's static PDF
    /// appearance (in `draw(_:)`) and to size/position its live `NSControl` overlay (in
    /// `syncFormControls()`) — the two MUST stay pixel-identical, or the mask either leaves a
    /// sliver of the original PDF-baked appearance visible around the control, or bleeds past it
    /// and blanks out neighboring page content.
    // Not `private`: exercised directly by PDFEngineTests via @testable import to verify
    // the mask (draw()) and control (syncFormControls()) geometry can never diverge.
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

    /// The transform mapping a page's native (unrotated) rect — origin at its top-left in this
    /// flipped view's coordinate space, extending (nativeWidth, nativeHeight) — onto its rotated
    /// on-screen footprint (the width/height swap computed in pageFrame for 90°/270°). Verified by
    /// tracing where each corner of the native rect must land under each rotation (e.g. at 90°,
    /// the native top-left corner lands at the rotated footprint's top-right corner) rather than
    /// an unverified formula — see PDFViewerViewModel.viewRotationDegrees's doc comment for why
    /// this is the *only* place rotation math lives, deliberately not threaded through search
    /// highlights/selection/form widgets too.
    private static func rotationTransform(degrees: Int, nativeWidth: CGFloat, nativeHeight: CGFloat) -> CGAffineTransform {
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

    // MARK: - Direct Quartz 2D Drawing
    
    public override func draw(_ dirtyRect: NSRect) {
        guard let doc = viewModel.document else {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()
            return
        }
        
        // High-quality area-averaging interpolation for razor-sharp downscaled text and lines
        NSGraphicsContext.current?.imageInterpolation = .high
        
        // Canvas background
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        pruneInvertedPageCache()

        // Determine visible page range intersecting dirtyRect via binary search
        let unscaledMinY = max(0, (dirtyRect.minY - 16) / viewModel.effectiveZoom)
        let unscaledMaxY = max(0, (dirtyRect.maxY - 16) / viewModel.effectiveZoom)
        let firstPage = viewModel.effectivePageIndex(atYOffset: unscaledMinY)
        let lastPage = viewModel.effectivePageIndex(atYOffset: unscaledMaxY)
        
        let start = max(0, firstPage - 1)
        let end = min(doc.pageCount - 1, lastPage + 1)
        guard start <= end else { return }
        
        for pageIdx in start...end {
            guard let pFrame = pageFrame(for: pageIdx) else { continue }
            guard pFrame.intersects(dirtyRect) else { continue }
            
            let pBounds = doc.pageBounds[pageIdx]
            
            // Page fill color follows dark mode too — matters mainly while a page is still
            // rendering (below) and briefly shows just this background. Uses the same fixed gray
            // the inverted page itself resolves to (see Self.darkModeBackgroundGray), not plain
            // black, so there's no visible mismatch between this placeholder and the actual page
            // once it finishes rendering.
            let pageFillColor: NSColor = isDarkMode
                ? NSColor(calibratedWhite: CGFloat(Self.darkModeBackgroundGray) / 255.0, alpha: 1.0)
                : .white

            // 1. Page Background & Drop Shadow
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
            shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowBlurRadius = 4
            shadow.set()

            pageFillColor.setFill()
            let pagePath = NSBezierPath(rect: pFrame)
            pagePath.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Page border
            NSColor.separatorColor.setStroke()
            pagePath.lineWidth = 0.5
            pagePath.stroke()

            // 2. Rendered Page Bitmap — inverted in dark mode (see displayImage) so pages read as
            // light-on-dark rather than a bright rectangle breaking up an otherwise dark app.
            if let image = viewModel.renderedPages[pageIdx] {
                let displayImg = displayImage(for: pageIdx, source: image)
                let alignedFrame = backingAlignedRect(pFrame, options: .alignAllEdgesNearest)
                if viewModel.viewRotationDegrees == 0 {
                    displayImg.draw(in: alignedFrame)
                } else if let cgContext = NSGraphicsContext.current?.cgContext {
                    // Draws the page's native (unrotated) bitmap through the same rotation
                    // transform pageFrame used to compute pFrame's swapped width/height, so the
                    // rotated image always exactly fills pFrame with no gap or overflow.
                    let scaledW = pBounds.width * viewModel.effectiveZoom
                    let scaledH = pBounds.height * viewModel.effectiveZoom
                    cgContext.saveGState()
                    cgContext.translateBy(x: alignedFrame.minX, y: alignedFrame.minY)
                    cgContext.concatenate(Self.rotationTransform(degrees: viewModel.viewRotationDegrees, nativeWidth: scaledW, nativeHeight: scaledH))
                    displayImg.draw(in: CGRect(x: 0, y: 0, width: scaledW, height: scaledH))
                    cgContext.restoreGState()
                } else {
                    displayImg.draw(in: alignedFrame)
                }
            } else {
                // Asynchronously render on demand
                Task { @MainActor [weak self] in
                    await self?.viewModel.renderPage(pageIdx)
                    self?.viewModel.loadPageMetadata(pageIdx)
                    self?.setNeedsDisplay(pFrame)
                    self?.syncFormControls()
                }
            }
            
            // Mask underlying PDF appearance behind active form widgets so underlying static text never bleeds through
            if viewModel.pageFormWidgets[pageIdx] == nil {
                // Deferred: draw(_:) is an AppKit render callback that can run while SwiftUI's own
                // update cycle is mid-pass. Mutating @Published state (pageLinks/pageStructuredData/
                // pageFormWidgets, via loadPageMetadata) synchronously from here is exactly what
                // "Publishing changes from within view updates is not allowed" describes — not just
                // a warning, it corrupts AppKit/SwiftUI object lifecycle bookkeeping in ways that
                // crash much later, elsewhere. The mask for this page simply skips a frame until
                // the deferred load completes and requests a redraw — harmless, since pages without
                // form widgets never needed a mask anyway.
                Task { @MainActor [weak self] in
                    self?.viewModel.loadPageMetadata(pageIdx)
                    self?.setNeedsDisplay(pFrame)
                }
            }
            // Form widgets are inert while rotated or in Two-Page Mode (see syncFormControls), so
            // the mask that hides their underlying static PDF appearance is skipped too — the
            // appearance is baked into the page image itself; masking it with a rect computed for
            // the plain single-column layout would blank out the wrong part of the page otherwise.
            if viewModel.isInteractiveViewingMode, let widgets = viewModel.pageFormWidgets[pageIdx] {
                for widget in widgets {
                    // Signature fields must not be masked: unlike other widget types, a signature
                    // stamp *is* the real, final page content, which PDFSignatureStampButton relies
                    // on showing through once signed (see hasSignatureStamp).
                    guard widget.type != .signature else { continue }
                    let maskRect = widgetScreenFrame(for: widget, pageFrame: pFrame, pageBounds: pBounds)
                    // Matches the page's own background color (see pageFillColor above) rather
                    // than always white, so the mask blends into an inverted dark-mode page
                    // instead of punching a bright hole in it.
                    pageFillColor.setFill()
                    maskRect.fill()
                }
            }

            // Search highlights, text/marquee selection, the active-snapshot focus ring, and the
            // hovered-link highlight (sections 3–6 below) are all positioned via the same linear
            // scale+translate assuming the plain single-column, unrotated layout — correct only
            // when isInteractiveViewingMode is true. Rather than teach each of these four
            // independent overlays the math for every other layout mode (four more chances to get
            // a highlight subtly misplaced), they're simply not drawn otherwise; switch back to
            // the normal single-page, unrotated view to use search/selection/links/forms again.
            guard viewModel.isInteractiveViewingMode else { continue }

            // 2.5 Page Annotations (Highlights, Underlines, Strikeouts, Freehand Ink, FreeText)
            if let annots = viewModel.pageAnnotations[pageIdx] {
                for annot in annots {
                    switch annot.type {
                    case .highlight:
                        annot.color.highlightFillColor.setFill()
                        for quad in annot.quads {
                            let r = quad.boundingRect
                            let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                            let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                            let qw = max(r.width * viewModel.effectiveZoom, 2)
                            let qh = max(r.height * viewModel.effectiveZoom, 4)
                            let quadRect = NSRect(x: qx, y: qy, width: qw, height: qh)
                            let path = NSBezierPath(roundedRect: quadRect, xRadius: 2, yRadius: 2)
                            path.fill()
                        }
                    case .underline:
                        annot.color.nsColor.setStroke()
                        let lineWidth = max(1.5 * viewModel.effectiveZoom, 1.5)
                        for quad in annot.quads {
                            let r = quad.boundingRect
                            let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                            let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                            let qw = max(r.width * viewModel.effectiveZoom, 2)
                            let qh = max(r.height * viewModel.effectiveZoom, 4)
                            let yPos = qy + qh - lineWidth * 0.5
                            let path = NSBezierPath()
                            path.lineWidth = lineWidth
                            path.move(to: NSPoint(x: qx, y: yPos))
                            path.line(to: NSPoint(x: qx + qw, y: yPos))
                            path.stroke()
                        }
                    case .strikeout:
                        annot.color.nsColor.setStroke()
                        let lineWidth = max(1.5 * viewModel.effectiveZoom, 1.5)
                        for quad in annot.quads {
                            let r = quad.boundingRect
                            let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                            let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                            let qw = max(r.width * viewModel.effectiveZoom, 2)
                            let qh = max(r.height * viewModel.effectiveZoom, 4)
                            let yPos = qy + qh * 0.55
                            let path = NSBezierPath()
                            path.lineWidth = lineWidth
                            path.move(to: NSPoint(x: qx, y: yPos))
                            path.line(to: NSPoint(x: qx + qw, y: yPos))
                            path.stroke()
                        }
                    case .ink:
                        guard !annot.inkPoints.isEmpty else { continue }
                        annot.color.nsColor.setStroke()
                        annot.color.nsColor.setFill()
                        let lineWidth = max(annot.strokeWidth * viewModel.effectiveZoom, 1.0)
                        if annot.inkPoints.count == 1 {
                            let p = annot.inkPoints[0]
                            let cx = pFrame.minX + (p.x - pBounds.minX) * viewModel.effectiveZoom
                            let cy = pFrame.minY + (p.y - pBounds.minY) * viewModel.effectiveZoom
                            let dotRect = NSRect(x: cx - lineWidth * 0.5, y: cy - lineWidth * 0.5, width: lineWidth, height: lineWidth)
                            let dot = NSBezierPath(ovalIn: dotRect)
                            dot.fill()
                        } else {
                            let path = NSBezierPath()
                            path.lineWidth = lineWidth
                            path.lineCapStyle = .round
                            path.lineJoinStyle = .round
                            let first = annot.inkPoints[0]
                            path.move(to: NSPoint(
                                x: pFrame.minX + (first.x - pBounds.minX) * viewModel.effectiveZoom,
                                y: pFrame.minY + (first.y - pBounds.minY) * viewModel.effectiveZoom
                            ))
                            for pt in annot.inkPoints.dropFirst() {
                                path.line(to: NSPoint(
                                    x: pFrame.minX + (pt.x - pBounds.minX) * viewModel.effectiveZoom,
                                    y: pFrame.minY + (pt.y - pBounds.minY) * viewModel.effectiveZoom
                                ))
                            }
                            path.stroke()
                        }
                    case .freeText:
                        guard let rect = annot.rect, !annot.text.isEmpty else { continue }
                        let rx = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
                        let ry = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
                        let rw = max(rect.width * viewModel.effectiveZoom, 60)
                        let rh = max(rect.height * viewModel.effectiveZoom, 20)
                        let boxRect = NSRect(x: rx, y: ry, width: rw, height: rh)

                        // If currently editing this annotation inline, draw dashed focus outline
                        if activeEditingAnnotation?.id == annot.id {
                            let borderPath = NSBezierPath(roundedRect: boxRect, xRadius: 2, yRadius: 2)
                            borderPath.lineWidth = 1.0
                            let dashes: [CGFloat] = [3.0, 3.0]
                            borderPath.setLineDash(dashes, count: 2, phase: 0)
                            annot.color.nsColor.setStroke()
                            borderPath.stroke()
                            continue
                        }

                        let fSize = max((annot.fontSize ?? 13.0) * viewModel.effectiveZoom, 8.0)
                        let font = NSFont.systemFont(ofSize: fSize)
                        let attrs: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: annot.color.nsColor
                        ]
                        let str = annot.text as NSString
                        str.draw(with: boxRect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
                    }
                }
            }

            // 2.6 Live Drawing Stroke in Progress
            if currentDrawingPageIndex == pageIdx && !currentDrawingPoints.isEmpty {
                viewModel.selectedAnnotationColor.nsColor.setStroke()
                viewModel.selectedAnnotationColor.nsColor.setFill()
                let lineWidth = max(viewModel.drawStrokeWidth * viewModel.effectiveZoom, 1.0)
                if currentDrawingPoints.count == 1 {
                    let p = currentDrawingPoints[0]
                    let cx = pFrame.minX + (p.x - pBounds.minX) * viewModel.effectiveZoom
                    let cy = pFrame.minY + (p.y - pBounds.minY) * viewModel.effectiveZoom
                    let dotRect = NSRect(x: cx - lineWidth * 0.5, y: cy - lineWidth * 0.5, width: lineWidth, height: lineWidth)
                    let dot = NSBezierPath(ovalIn: dotRect)
                    dot.fill()
                } else {
                    let path = NSBezierPath()
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    let first = currentDrawingPoints[0]
                    path.move(to: NSPoint(
                        x: pFrame.minX + (first.x - pBounds.minX) * viewModel.effectiveZoom,
                        y: pFrame.minY + (first.y - pBounds.minY) * viewModel.effectiveZoom
                    ))
                    for pt in currentDrawingPoints.dropFirst() {
                        path.line(to: NSPoint(
                            x: pFrame.minX + (pt.x - pBounds.minX) * viewModel.effectiveZoom,
                            y: pFrame.minY + (pt.y - pBounds.minY) * viewModel.effectiveZoom
                        ))
                    }
                    path.stroke()
                }
            }

            // 3. Search Highlights
            let matches = viewModel.matches(on: pageIdx)
            for match in matches {
                let isActive = viewModel.isActiveMatch(match)
                for quad in match.highlightQuads {
                    let r = quad.boundingRect
                    let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                    let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                    let qw = max(r.width * viewModel.effectiveZoom, 4)
                    let qh = max(r.height * viewModel.effectiveZoom, 8)
                    let quadRect = NSRect(x: qx, y: qy, width: qw, height: qh)
                    let path = NSBezierPath(roundedRect: quadRect, xRadius: 2, yRadius: 2)
                    
                    if isActive {
                        NSColor.systemOrange.withAlphaComponent(0.60).setFill()
                        path.fill()
                        NSColor.systemOrange.setStroke()
                        path.lineWidth = 1.5
                        path.stroke()
                    } else {
                        NSColor.systemYellow.withAlphaComponent(0.40).setFill()
                        path.fill()
                        NSColor.systemYellow.withAlphaComponent(0.70).setStroke()
                        path.lineWidth = 0.8
                        path.stroke()
                    }
                }
            }
            
            // 4. Text / Marquee Drag Selection Highlights — combines the primary selection (if
            // this is its page) with any further pages a cross-page text selection spans into
            // (see PDFViewerViewModel.additionalSelectionPages), so each page just draws whatever
            // slice of the overall selection actually falls on it.
            var selectionResultsForPage: [SelectionResult] = []
            if let sel = viewModel.activeSelection, sel.pageIndex == pageIdx {
                selectionResultsForPage.append(sel.result)
            }
            if let extra = viewModel.additionalSelectionPages.first(where: { $0.pageIndex == pageIdx }) {
                selectionResultsForPage.append(extra.result)
            }
            for selResult in selectionResultsForPage {
                let isRectMode = (selResult.mode == .rectangularArea)
                for quad in selResult.highlightQuads {
                    let r = quad.boundingRect
                    let qx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                    let qy = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                    let qw = max(r.width * viewModel.effectiveZoom, 2)
                    let qh = max(r.height * viewModel.effectiveZoom, 4)
                    let quadRect = NSRect(x: qx, y: qy, width: qw, height: qh)
                    let path = NSBezierPath(roundedRect: quadRect, xRadius: 2, yRadius: 2)

                    if isRectMode {
                        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
                        path.fill()
                        NSColor.controlAccentColor.setStroke()
                        path.lineWidth = 1.5
                        let pattern: [CGFloat] = [5, 3]
                        path.setLineDash(pattern, count: 2, phase: 0)
                        path.stroke()
                    } else {
                        NSColor.selectedTextBackgroundColor.withAlphaComponent(0.40).setFill()
                        path.fill()
                    }
                }
            }
            
            // 5. Active Snapshot Focus Ring
            if let activeSnap = viewModel.activeSnapshotTarget, activeSnap.targetPage == pageIdx {
                let snapRect = focusRingRect(for: activeSnap, on: pageIdx, pageBounds: pBounds, pageFrame: pFrame)
                
                let path = NSBezierPath(roundedRect: snapRect, xRadius: 4, yRadius: 4)
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 3.0
                path.stroke()
            }
            
            // 6. Hovered Link Highlight
            if let hLink = hoveredLink, hLink.sourcePage == pageIdx, let r = hLink.sourceRect {
                let lx = pFrame.minX + (r.minX - pBounds.minX) * viewModel.effectiveZoom
                let ly = pFrame.minY + (r.minY - pBounds.minY) * viewModel.effectiveZoom
                let lw = max(r.width * viewModel.effectiveZoom, 10)
                let lh = max(r.height * viewModel.effectiveZoom, 10)
                let linkRect = NSRect(x: lx, y: ly, width: lw, height: lh)
                
                let path = NSBezierPath(roundedRect: linkRect, xRadius: 2, yRadius: 2)
                NSColor.systemBlue.withAlphaComponent(0.12).setFill()
                path.fill()
            }
        }
    }
    
    /// Computes the canvas frame for an active snapshot / reference target's focus ring,
    /// ensuring it wraps the target content cleanly and never falls outside the page boundaries.
    private func focusRingRect(for activeSnap: SnapshotTarget, on pageIdx: Int, pageBounds: CGRect, pageFrame: CGRect) -> NSRect {
        let targetRect = viewModel.resolvedTargetRect(for: activeSnap)

        // Map to canvas coordinates
        let sx = pageFrame.minX + (targetRect.minX - pageBounds.minX) * viewModel.effectiveZoom
        let sy = pageFrame.minY + (targetRect.minY - pageBounds.minY) * viewModel.effectiveZoom
        let sw = max(targetRect.width * viewModel.effectiveZoom, 24)
        let sh = max(targetRect.height * viewModel.effectiveZoom, 20)

        // Ensure the focus ring stays strictly within the visible page frame
        let safeMargin: CGFloat = 4
        let safeMinX = pageFrame.minX + safeMargin
        let safeMaxX = pageFrame.maxX - safeMargin
        let safeMinY = pageFrame.minY + safeMargin
        let safeMaxY = pageFrame.maxY - safeMargin

        let finalX = max(safeMinX, min(sx, safeMaxX - 24))
        let finalY = max(safeMinY, min(sy, safeMaxY - 20))
        let finalW = min(sw, safeMaxX - finalX)
        let finalH = min(sh, safeMaxY - finalY)

        return NSRect(x: finalX, y: finalY, width: max(finalW, 24), height: max(finalH, 20))
    }
    
    // MARK: - Mouse & Gesture Interaction
    
    public override func mouseDown(with event: NSEvent) {
        PDFViewerViewModel.active = viewModel
        PDFViewerAppCoordinator.shared.registerActive(viewModel)
        window?.makeFirstResponder(self)
        // Link-clicking and drag-selection both depend on pageInfo(at:)'s pagePoint and page
        // layout, neither of which is meaningful outside the plain single-column, unrotated view
        // (see pageInfo's doc comment) — inert whenever isInteractiveViewingMode is false, same as
        // search/selection/forms elsewhere in this file. mouseDragged never needs its own check
        // for this: it only acts when isDraggingSelection is already true, which never happens if
        // this return fires first.
        guard viewModel.isInteractiveViewingMode else { return }
        let point = convert(event.locationInWindow, from: nil)

        // In draw mode: capture start point for freehand ink stroke
        if viewModel.canvasMode == .draw {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                currentDrawingPageIndex = pageIdx
                currentDrawingPoints = [pagePoint]
                needsDisplay = true
            }
            return
        }

        // In eraser mode: remove annotation at clicked point
        if viewModel.canvasMode == .eraser {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.removeAnnotation(at: pagePoint, pageIndex: pageIdx)
                needsDisplay = true
            }
            return
        }

        // In text mode: create new or edit existing text box
        if viewModel.canvasMode == .text {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                if let tf = activeInlineTextField, tf.frame.contains(point) {
                    return
                }
                commitActiveInlineTextField()
                if let list = viewModel.pageAnnotations[pageIdx],
                   let hit = list.first(where: { $0.type == .freeText && $0.contains(pagePoint: pagePoint) }) {
                    startInlineEditing(annotation: hit, pageIndex: pageIdx)
                } else {
                    startInlineEditing(newAt: pagePoint, pageIndex: pageIdx)
                }
                return
            }
        } else {
            if activeInlineTextField != nil {
                commitActiveInlineTextField()
            }
        }

        // Double-click to select word, triple-click to select line
        if event.clickCount == 2 {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.selectWord(at: pagePoint, pageIndex: pageIdx)
                isDraggingSelection = false
                needsDisplay = true
                return
            }
        } else if event.clickCount >= 3 {
            if let (pageIdx, _, pagePoint) = pageInfo(at: point) {
                viewModel.selectLine(at: pagePoint, pageIndex: pageIdx)
                isDraggingSelection = false
                needsDisplay = true
                return
            }
        }

        // Check clickable links / cross-references
        if let (pageIdx, _, pagePoint) = pageInfo(at: point),
           let links = viewModel.pageLinks[pageIdx],
           let clickedLink = links.first(where: { $0.sourceRect?.contains(pagePoint) == true }) {
            pendingLinkTarget = (target: clickedLink, isOption: event.modifierFlags.contains(.option))
            dragStartCanvasPoint = point
            activeDragPage = pageIdx
            isDraggingSelection = true
            hasDraggedPastThreshold = false
            return
        }
        
        // Otherwise begin drag selection
        if let (pageIdx, _, _) = pageInfo(at: point) {
            dragStartCanvasPoint = point
            activeDragPage = pageIdx
            isDraggingSelection = true
            hasDraggedPastThreshold = false
            viewModel.clearSelection()
            needsDisplay = true
        }
    }
    
    public override func mouseDragged(with event: NSEvent) {
        if viewModel.canvasMode == .draw {
            guard let dragPageIdx = currentDrawingPageIndex,
                  let pFrame = pageFrame(for: dragPageIdx),
                  let doc = viewModel.document else { return }
            let currentCanvas = convert(event.locationInWindow, from: nil)
            let pBounds = doc.pageBounds[dragPageIdx]
            let currentPagePoint = CGPoint(
                x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
                y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
            )
            currentDrawingPoints.append(currentPagePoint)
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .eraser {
            let currentCanvas = convert(event.locationInWindow, from: nil)
            if let (pageIdx, _, pagePoint) = pageInfo(at: currentCanvas) {
                viewModel.removeAnnotation(at: pagePoint, pageIndex: pageIdx)
                needsDisplay = true
            }
            return
        }

        guard isDraggingSelection,
              let startCanvas = dragStartCanvasPoint,
              let dragPageIdx = activeDragPage,
              let pFrame = pageFrame(for: dragPageIdx),
              let doc = viewModel.document else { return }

        let currentCanvas = convert(event.locationInWindow, from: nil)
        let dragDistance = hypot(currentCanvas.x - startCanvas.x, currentCanvas.y - startCanvas.y)

        if !hasDraggedPastThreshold {
            if dragDistance > 3.0 {
                hasDraggedPastThreshold = true
                if pendingLinkTarget != nil {
                    pendingLinkTarget = nil
                    viewModel.clearSelection()
                    hoveredLink = nil
                }
                let isOption = event.modifierFlags.contains(.option)
                if isOption {
                    NSCursor.crosshair.set()
                } else {
                    NSCursor.iBeam.set()
                }
            } else {
                return
            }
        }

        let pBounds = doc.pageBounds[dragPageIdx]

        let startPagePoint = CGPoint(
            x: pBounds.minX + ((startCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
            y: pBounds.minY + ((startCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
        )

        let isOptionPressed = event.modifierFlags.contains(.option)
        let mode: SelectionMode = isOptionPressed ? .rectangularArea : viewModel.selectionMode

        // Reading-order (text) selection can cross a page boundary — if the drag has moved onto
        // a *different* page than where it started, select across both (and any pages fully in
        // between) instead of silently clamping to the starting page's own bounds, which is what
        // made it impossible to select text spanning a page break. Area/marquee selection
        // deliberately keeps the single-page-only behavior below: a rectangle spanning two
        // separate page images doesn't have one well-defined crop.
        if mode == .readingOrder,
           let (currentPageIdx, _, currentPagePoint) = pageInfo(at: currentCanvas),
           currentPageIdx != dragPageIdx {
            viewModel.handleCrossPageDragSelect(pageA: dragPageIdx, pointA: startPagePoint, pageB: currentPageIdx, pointB: currentPagePoint)
            needsDisplay = true
            return
        }

        let currentPagePoint = CGPoint(
            x: pBounds.minX + ((currentCanvas.x - pFrame.minX) / viewModel.effectiveZoom),
            y: pBounds.minY + ((currentCanvas.y - pFrame.minY) / viewModel.effectiveZoom)
        )

        viewModel.handleDragSelect(
            pageIndex: dragPageIdx,
            startPagePoint: startPagePoint,
            currentPagePoint: currentPagePoint,
            forceMode: mode
        )
        needsDisplay = true
    }
    
    public override func mouseUp(with event: NSEvent) {
        if viewModel.canvasMode == .draw {
            if let pIdx = currentDrawingPageIndex, !currentDrawingPoints.isEmpty {
                viewModel.addInkAnnotation(
                    pageIndex: pIdx,
                    points: currentDrawingPoints,
                    strokeWidth: viewModel.drawStrokeWidth,
                    color: viewModel.selectedAnnotationColor
                )
            }
            currentDrawingPoints = []
            currentDrawingPageIndex = nil
            needsDisplay = true
            return
        }

        if viewModel.canvasMode == .eraser {
            needsDisplay = true
            return
        }

        let pending = pendingLinkTarget
        pendingLinkTarget = nil
        let wasDragged = hasDraggedPastThreshold
        hasDraggedPastThreshold = false
        isDraggingSelection = false
        dragStartCanvasPoint = nil
        activeDragPage = nil

        if let pending = pending, !wasDragged {
            hoveredLink = nil
            needsDisplay = true

            // Confirm release point is still within or immediately adjacent to link source rectangle
            let releasePoint = convert(event.locationInWindow, from: nil)
            if let (upPageIdx, _, upPagePoint) = pageInfo(at: releasePoint) {
                if upPageIdx != pending.target.sourcePage ||
                   (pending.target.sourceRect != nil && !pending.target.sourceRect!.insetBy(dx: -4, dy: -4).contains(upPagePoint)) {
                    return
                }
            } else {
                return
            }

            if let uri = pending.target.uri, (uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:")), let url = URL(string: uri) {
                NSWorkspace.shared.open(url)
                return
            } else if pending.target.targetPage >= 0 {
                // Option-click opens the target in a separate snapshot window instead of
                // navigating away in place — a shortcut alongside the equivalent context-menu
                // item, for comparing it against the text that pointed to it without losing your
                // reading position. Plain click keeps its existing in-place-navigate behavior.
                if pending.isOption {
                    viewModel.openSnapshotInNewWindow(pending.target)
                } else {
                    viewModel.clearSelection()
                    viewModel.jumpToSnapshot(pending.target)
                }
                return
            }
        }
    }
    
    public override func magnify(with event: NSEvent) {
        if let sv = enclosingScrollView as? PDFScrollView {
            sv.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
    
    public override func smartMagnify(with event: NSEvent) {
        if let sv = enclosingScrollView as? PDFScrollView {
            sv.smartMagnify(with: event)
        } else {
            super.smartMagnify(with: event)
        }
    }
    
    public override func mouseMoved(with event: NSEvent) {
        // Same rationale as mouseDown: link targets aren't meaningful outside the plain
        // single-column, unrotated layout, so don't hint at a clickable link (cursor/highlight)
        // that clicking wouldn't actually do anything about.
        guard viewModel.isInteractiveViewingMode else {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.arrow.set()
            return
        }
        if viewModel.canvasMode == .draw || viewModel.canvasMode == .eraser {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.crosshair.set()
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let (pageIdx, _, pagePoint) = pageInfo(at: point),
           let links = viewModel.pageLinks[pageIdx],
           let link = links.first(where: { $0.sourceRect?.contains(pagePoint) == true }) {
            if hoveredLink?.id != link.id {
                hoveredLink = link
                needsDisplay = true
            }
            NSCursor.pointingHand.set()
        } else {
            if hoveredLink != nil {
                hoveredLink = nil
                needsDisplay = true
            }
            NSCursor.arrow.set()
        }
    }
    
    public override func cursorUpdate(with event: NSEvent) {
        if hoveredLink != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if hoveredLink != nil {
            hoveredLink = nil
            needsDisplay = true
        }
        NSCursor.arrow.set()
    }
    
    /// Builds a target for a canvas point with no link or selection under
    /// it — extracting the surrounding words/sentence text if near text, or a page target if in margin.
    private func pointTarget(at canvasPoint: CGPoint) -> SnapshotTarget? {
        guard let (pageIdx, _, pagePoint) = pageInfo(at: canvasPoint) else { return nil }
        return viewModel.buildSnapshotTarget(at: pagePoint, pageIndex: pageIdx)
    }

    private func makeOpenInNewWindowItem(target: SnapshotTarget) -> NSMenuItem {
        let item = NSMenuItem(title: "Open in New Window", action: #selector(openTargetInNewWindowAction(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        item.target = self
        item.representedObject = target
        return item
    }

    // MARK: - Native Context Menu

    public override func menu(for event: NSEvent) -> NSMenu? {
        // Every item this menu can offer (selection actions, link actions, snapshot-at-point) is
        // meaningless outside the plain single-column, unrotated layout — no context menu at all
        // there, rather than one offering actions that don't correspond to what's under the click.
        guard viewModel.isInteractiveViewingMode else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        self.lastContextMenuLocation = point

        // An active selection takes priority over a coincidental cross-reference link at the same
        // point.
        if let sel = viewModel.activeSelection, !sel.result.highlightQuads.isEmpty || !viewModel.additionalSelectionPages.isEmpty {
            return buildSelectionMenu(for: sel)
        }

        // Right-clicking a cross-reference link (with no active selection) offers anchor & open actions.
        if let link = internalLinkInfo(at: point) {
            let menu = NSMenu(title: "Anchor")

            if !viewModel.isTransientWindow {
                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotTargetAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                snapItem.representedObject = link
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenTargetAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                snapAndOpenItem.representedObject = link
                menu.addItem(snapAndOpenItem)

                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(makeOpenInNewWindowItem(target: link))
            return menu
        }

        // Right-clicking an existing annotation offers removal
        if let (pIdx, _, pPoint) = pageInfo(at: point),
           let annots = viewModel.pageAnnotations[pIdx],
           let hitAnnot = annots.first(where: { $0.contains(pagePoint: pPoint) }) {
            let menu = NSMenu(title: "Annotation")
            if hitAnnot.type == .freeText {
                let editItem = NSMenuItem(title: "Edit Text Box", action: #selector(editHitAnnotationAction(_:)), keyEquivalent: "")
                editItem.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
                editItem.target = self
                editItem.representedObject = hitAnnot
                menu.addItem(editItem)
                menu.addItem(NSMenuItem.separator())
            }
            let removeTitle: String
            switch hitAnnot.type {
            case .highlight: removeTitle = "Remove Highlight"
            case .underline: removeTitle = "Remove Underline"
            case .strikeout: removeTitle = "Remove Strikethrough"
            case .ink: removeTitle = "Delete Drawing"
            case .freeText: removeTitle = "Delete Text Box"
            }
            let removeItem = NSMenuItem(title: removeTitle, action: #selector(removeHitAnnotationAction(_:)), keyEquivalent: "")
            removeItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            removeItem.target = self
            removeItem.representedObject = hitAnnot
            menu.addItem(removeItem)
            return menu
        }

        // No link, no selection — offer to create an anchor from surrounding text or open here in a new window.
        if let target = pointTarget(at: point) {
            let menu = NSMenu(title: "Page")

            if !viewModel.isTransientWindow {
                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotTargetAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                snapItem.representedObject = target
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenTargetAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                snapAndOpenItem.representedObject = target
                menu.addItem(snapAndOpenItem)

                menu.addItem(NSMenuItem.separator())
            }

            menu.addItem(makeOpenInNewWindowItem(target: target))
            return menu
        }
        return nil
    }

    private func buildSelectionMenu(for sel: (pageIndex: Int, result: SelectionResult)) -> NSMenu {
        let menu = NSMenu(title: "Selection")

        if sel.result.mode == .rectangularArea {
            if !sel.result.text.isEmpty {
                let copyTextItem = NSMenuItem(title: "Copy Extracted Text", action: #selector(copyTextAction(_:)), keyEquivalent: "")
                copyTextItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                copyTextItem.target = self
                menu.addItem(copyTextItem)
            }

            let copyScreenshotItem = NSMenuItem(title: "Copy Screenshot", action: #selector(copyScreenshotAction(_:)), keyEquivalent: "c")
            copyScreenshotItem.image = NSImage(systemSymbolName: "camera", accessibilityDescription: nil)
            copyScreenshotItem.target = self
            menu.addItem(copyScreenshotItem)

            let saveScreenshotItem = NSMenuItem(title: "Save Screenshot As...", action: #selector(saveScreenshotAction(_:)), keyEquivalent: "s")
            saveScreenshotItem.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: nil)
            saveScreenshotItem.target = self
            menu.addItem(saveScreenshotItem)

            if !viewModel.isTransientWindow {
                menu.addItem(NSMenuItem.separator())

                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenSelectionAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                menu.addItem(snapAndOpenItem)
            }
        } else {
            // Only include Copy Text if extracted text is non-empty across all spanned pages.
            if !viewModel.activeSelectionCombinedText.isEmpty {
                let copyItem = NSMenuItem(title: "Copy Text", action: #selector(copyTextAction(_:)), keyEquivalent: "c")
                copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
                copyItem.target = self
                menu.addItem(copyItem)

                let rawSelectedText = viewModel.activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let truncated = rawSelectedText.truncatedAtWordBoundary(maxLength: 24)

                let lookUpItem = NSMenuItem(title: "Look Up \"\(truncated)\"", action: #selector(lookUpSelectionAction(_:)), keyEquivalent: "")
                lookUpItem.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
                lookUpItem.target = self
                menu.addItem(lookUpItem)

                let translateItem = NSMenuItem(title: "Translate Selection", action: #selector(translateSelectionAction(_:)), keyEquivalent: "t")
                translateItem.keyEquivalentModifierMask = [.control, .option]
                translateItem.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: nil)
                translateItem.target = self
                menu.addItem(translateItem)

                menu.addItem(NSMenuItem.separator())

                // Highlight submenu with colors
                let highlightMenu = NSMenu(title: "Highlight")
                for color in AnnotationColor.allCases {
                    let colorItem = NSMenuItem(title: color.displayName, action: #selector(highlightWithColorAction(_:)), keyEquivalent: "")
                    colorItem.image = color.menuIcon
                    colorItem.target = self
                    colorItem.representedObject = color
                    highlightMenu.addItem(colorItem)
                }
                let highlightParentItem = NSMenuItem(title: "Highlight", action: #selector(highlightDefaultAction(_:)), keyEquivalent: "h")
                highlightParentItem.keyEquivalentModifierMask = [.command, .shift]
                highlightParentItem.image = NSImage(systemSymbolName: "highlighter", accessibilityDescription: nil)
                highlightParentItem.target = self
                highlightParentItem.submenu = highlightMenu
                menu.addItem(highlightParentItem)

                // Underline submenu with colors
                let underlineMenu = NSMenu(title: "Underline")
                for color in AnnotationColor.allCases {
                    let colorItem = NSMenuItem(title: color.displayName, action: #selector(underlineWithColorAction(_:)), keyEquivalent: "")
                    colorItem.image = color.menuIcon
                    colorItem.target = self
                    colorItem.representedObject = color
                    underlineMenu.addItem(colorItem)
                }
                let underlineParentItem = NSMenuItem(title: "Underline", action: #selector(underlineDefaultAction(_:)), keyEquivalent: "u")
                underlineParentItem.keyEquivalentModifierMask = [.command, .shift]
                underlineParentItem.image = NSImage(systemSymbolName: "underline", accessibilityDescription: nil)
                underlineParentItem.target = self
                underlineParentItem.submenu = underlineMenu
                menu.addItem(underlineParentItem)

                // Strikethrough submenu with colors
                let strikeMenu = NSMenu(title: "Strikethrough")
                for color in AnnotationColor.allCases {
                    let colorItem = NSMenuItem(title: color.displayName, action: #selector(strikethroughWithColorAction(_:)), keyEquivalent: "")
                    colorItem.image = color.menuIcon
                    colorItem.target = self
                    colorItem.representedObject = color
                    strikeMenu.addItem(colorItem)
                }
                let strikeParentItem = NSMenuItem(title: "Strikethrough", action: #selector(strikethroughDefaultAction(_:)), keyEquivalent: "x")
                strikeParentItem.keyEquivalentModifierMask = [.command, .shift]
                strikeParentItem.image = NSImage(systemSymbolName: "strikethrough", accessibilityDescription: nil)
                strikeParentItem.target = self
                strikeParentItem.submenu = strikeMenu
                menu.addItem(strikeParentItem)
            }

            if !viewModel.isTransientWindow {
                if !viewModel.activeSelectionCombinedText.isEmpty {
                    menu.addItem(NSMenuItem.separator())
                }

                let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotAction(_:)), keyEquivalent: "")
                snapItem.image = NSImage.anchorIcon
                snapItem.target = self
                menu.addItem(snapItem)

                let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenSelectionAction(_:)), keyEquivalent: "")
                snapAndOpenItem.image = NSImage.anchorIcon
                snapAndOpenItem.target = self
                menu.addItem(snapAndOpenItem)
            }
        }

        if menu.numberOfItems > 0 {
            menu.addItem(NSMenuItem.separator())
        }

        // Available for any selection (text or area), not just cross-reference links
        let openWindowItem = NSMenuItem(title: "Open in New Window", action: #selector(openSelectionInNewWindowAction(_:)), keyEquivalent: "")
        openWindowItem.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        return menu
    }

    @objc private func lookUpSelectionAction(_ sender: NSMenuItem) {
        let text = viewModel.activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let targetPoint = (lastContextMenuLocation != .zero) ? lastContextMenuLocation : currentSelectionAnchorPoint()
        self.showDefinition(for: NSAttributedString(string: text), at: targetPoint)
    }

    @objc private func translateSelectionAction(_ sender: NSMenuItem) {
        viewModel.translateSelection()
    }

    private func currentSelectionAnchorPoint() -> CGPoint {
        if let sel = viewModel.activeSelection, let firstQuad = sel.result.highlightQuads.first {
            let pIdx = sel.pageIndex
            let pageY = (viewModel.document?.pageYOffsets.indices.contains(pIdx) == true) ? viewModel.document!.pageYOffsets[pIdx] : 0
            return CGPoint(x: firstQuad.ul.x, y: pageY + firstQuad.ul.y)
        }
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }

    @objc private func snapshotTargetAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapshotTarget else { return }
        viewModel.addSnapshotTarget(target)
    }

    @objc private func snapshotAndOpenTargetAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapshotTarget else { return }
        viewModel.addSnapshotAndOpen(target)
    }

    @objc private func snapshotAndOpenSelectionAction(_ sender: Any) {
        viewModel.addSnapshotAndOpenFromSelection()
    }

    @objc private func openTargetInNewWindowAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SnapshotTarget else { return }
        viewModel.openSnapshotInNewWindow(target)
    }

    @objc public override func selectAll(_ sender: Any?) {
        viewModel.selectAllOnCurrentPage()
    }

    @objc public func copy(_ sender: Any?) {
        if let sel = viewModel.activeSelection, sel.result.mode == .rectangularArea {
            viewModel.copyActiveScreenshot()
        } else {
            viewModel.copyActiveSelection()
        }
    }
    
    @objc private func copyScreenshotAction(_ sender: Any) {
        viewModel.copyActiveScreenshot()
    }
    
    @objc private func saveScreenshotAction(_ sender: Any) {
        viewModel.saveActiveScreenshot()
    }
    
    @objc private func copyTextAction(_ sender: Any) {
        viewModel.copyActiveSelection()
    }
    
    @objc private func snapshotAction(_ sender: Any) {
        viewModel.addSnapshotFromSelection()
    }

    @objc private func openSelectionInNewWindowAction(_ sender: Any) {
        viewModel.openSelectionInNewWindow()
    }

    @objc private func highlightDefaultAction(_ sender: Any) {
        viewModel.highlightSelection(color: .yellow)
        needsDisplay = true
    }

    @objc private func highlightWithColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? AnnotationColor else { return }
        viewModel.highlightSelection(color: color)
        needsDisplay = true
    }

    @objc private func underlineDefaultAction(_ sender: Any) {
        viewModel.underlineSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    @objc private func underlineWithColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? AnnotationColor else { return }
        viewModel.underlineSelection(color: color)
        needsDisplay = true
    }

    @objc private func strikethroughDefaultAction(_ sender: Any) {
        viewModel.strikethroughSelection(color: viewModel.selectedAnnotationColor)
        needsDisplay = true
    }

    @objc private func strikethroughWithColorAction(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? AnnotationColor else { return }
        viewModel.strikethroughSelection(color: color)
        needsDisplay = true
    }

    @objc private func removeHitAnnotationAction(_ sender: NSMenuItem) {
        guard let annot = sender.representedObject as? PDFAnnotation else { return }
        viewModel.removeAnnotation(annot)
        needsDisplay = true
    }

    @objc private func editHitAnnotationAction(_ sender: NSMenuItem) {
        guard let annot = sender.representedObject as? PDFAnnotation else { return }
        startInlineEditing(annotation: annot, pageIndex: annot.pageIndex)
    }

    // MARK: - Inline Text Box Editing

    private func commitActiveInlineTextField() {
        guard let tf = activeInlineTextField,
              let pIdx = activeEditingPageIndex,
              let doc = viewModel.document,
              pIdx >= 0, pIdx < doc.pageCount else {
            activeInlineTextField?.removeFromSuperview()
            activeInlineTextField = nil
            activeEditingAnnotation = nil
            activeEditingPageIndex = nil
            activeEditingPagePoint = nil
            needsDisplay = true
            return
        }
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = viewModel.selectedAnnotationColor
        let fontSize = viewModel.selectedFontSize

        if let existing = activeEditingAnnotation {
            if text.isEmpty {
                viewModel.removeAnnotation(existing)
            } else if text != existing.text || color != existing.color || fontSize != (existing.fontSize ?? 13.0) {
                viewModel.removeAnnotation(existing)
                let r = existing.rect ?? CGRect(x: 50, y: 50, width: 200, height: fontSize * 1.5)
                viewModel.addFreeTextAnnotation(pageIndex: pIdx, rect: r, text: text, fontSize: fontSize, color: color)
            }
        } else if !text.isEmpty, let pagePt = activeEditingPagePoint {
            let pBounds = doc.pageBounds[pIdx]
            let approxWidth = min(max(CGFloat(text.count) * fontSize * 0.65 + 16, 80), pBounds.width - pagePt.x)
            let approxHeight = max(fontSize * 1.5, 20)
            let r = CGRect(x: pagePt.x, y: pagePt.y, width: approxWidth, height: approxHeight)
            viewModel.addFreeTextAnnotation(pageIndex: pIdx, rect: r, text: text, fontSize: fontSize, color: color)
        }

        tf.removeFromSuperview()
        activeInlineTextField = nil
        activeEditingAnnotation = nil
        activeEditingPageIndex = nil
        activeEditingPagePoint = nil
        needsDisplay = true
    }

    private func cancelActiveInlineTextField() {
        activeInlineTextField?.removeFromSuperview()
        activeInlineTextField = nil
        activeEditingAnnotation = nil
        activeEditingPageIndex = nil
        activeEditingPagePoint = nil
        needsDisplay = true
    }

    private func startInlineEditing(annotation: PDFAnnotation, pageIndex: Int) {
        commitActiveInlineTextField()
        guard let pFrame = pageFrame(for: pageIndex),
              let doc = viewModel.document,
              let rect = annotation.rect else { return }

        let pBounds = doc.pageBounds[pageIndex]
        let canvasX = pFrame.minX + (rect.minX - pBounds.minX) * viewModel.effectiveZoom
        let canvasY = pFrame.minY + (rect.minY - pBounds.minY) * viewModel.effectiveZoom
        let canvasW = max(rect.width * viewModel.effectiveZoom, 120)
        let canvasH = max(rect.height * viewModel.effectiveZoom, 26)

        let tf = NSTextField(frame: NSRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH))
        tf.stringValue = annotation.text
        tf.font = NSFont.systemFont(ofSize: max((annotation.fontSize ?? viewModel.selectedFontSize) * viewModel.effectiveZoom, 10.0))
        tf.textColor = annotation.color.nsColor
        tf.backgroundColor = isDarkMode ? NSColor.windowBackgroundColor : NSColor.white
        tf.drawsBackground = true
        tf.isBordered = true
        tf.focusRingType = .exterior
        tf.delegate = self
        addSubview(tf)
        window?.makeFirstResponder(tf)

        activeInlineTextField = tf
        activeEditingAnnotation = annotation
        activeEditingPageIndex = pageIndex
        activeEditingPagePoint = rect.origin
        needsDisplay = true
    }

    private func startInlineEditing(newAt pagePoint: CGPoint, pageIndex: Int) {
        commitActiveInlineTextField()
        guard let pFrame = pageFrame(for: pageIndex),
              let doc = viewModel.document else { return }

        let pBounds = doc.pageBounds[pageIndex]
        let canvasX = pFrame.minX + (pagePoint.x - pBounds.minX) * viewModel.effectiveZoom
        let canvasY = pFrame.minY + (pagePoint.y - pBounds.minY) * viewModel.effectiveZoom
        let canvasW: CGFloat = 160
        let canvasH = max(viewModel.selectedFontSize * viewModel.effectiveZoom + 10, 26)

        let tf = NSTextField(frame: NSRect(x: canvasX, y: canvasY, width: canvasW, height: canvasH))
        tf.placeholderString = "Type text..."
        tf.font = NSFont.systemFont(ofSize: max(viewModel.selectedFontSize * viewModel.effectiveZoom, 10.0))
        tf.textColor = viewModel.selectedAnnotationColor.nsColor
        tf.backgroundColor = isDarkMode ? NSColor.windowBackgroundColor : NSColor.white
        tf.drawsBackground = true
        tf.isBordered = true
        tf.focusRingType = .exterior
        tf.delegate = self
        addSubview(tf)
        window?.makeFirstResponder(tf)

        activeInlineTextField = tf
        activeEditingAnnotation = nil
        activeEditingPageIndex = pageIndex
        activeEditingPagePoint = pagePoint
        needsDisplay = true
    }

    // MARK: - NSTextFieldDelegate

    public func controlTextDidEndEditing(_ obj: Notification) {
        commitActiveInlineTextField()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitActiveInlineTextField()
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelActiveInlineTextField()
            return true
        }
        return false
    }

    // MARK: - Keyboard Shortcuts
    
    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        
        // Cmd + S: Save
        if flags == .command && event.charactersIgnoringModifiers == "s" {
            viewModel.saveDocument()
            return
        }
        
        // Shift + Cmd + S: Save As
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "s" {
            viewModel.saveDocumentAs()
            return
        }
        
        // Cmd + P: Print
        if flags == .command && event.charactersIgnoringModifiers == "p" {
            viewModel.printDocument()
            return
        }
        
        // Cmd + C
        if flags == .command && event.charactersIgnoringModifiers == "c" {
            copy(nil)
            return
        }
        
        // Cmd + G: Find Next
        if flags == .command && event.charactersIgnoringModifiers == "g" {
            viewModel.nextSearchMatch()
            return
        }
        
        // Shift + Cmd + G: Find Previous
        if flags == [.command, .shift] && event.charactersIgnoringModifiers == "g" {
            viewModel.previousSearchMatch()
            return
        }

        // Shift + Cmd + H: Highlight selection with default yellow
        if flags == [.command, .shift] && event.charactersIgnoringModifiers?.lowercased() == "h" {
            viewModel.highlightSelection(color: .yellow)
            needsDisplay = true
            return
        }

        // Cmd + [ : Back in navigation history
        if flags == .command && event.charactersIgnoringModifiers == "[" {
            viewModel.goBack()
            return
        }

        // Cmd + ] : Forward in navigation history
        if flags == .command && event.charactersIgnoringModifiers == "]" {
            viewModel.goForward()
            return
        }
        
        // Cmd + = / Cmd + +: Zoom In
        if flags.contains(.command) && (event.charactersIgnoringModifiers == "=" || event.charactersIgnoringModifiers == "+") {
            viewModel.zoomIn()
            return
        }
        
        // Cmd + -: Zoom Out
        if flags.contains(.command) && event.charactersIgnoringModifiers == "-" {
            viewModel.zoomOut()
            return
        }

        // Cmd + 9: Zoom to Fit Width
        if flags == .command && event.charactersIgnoringModifiers == "9" {
            viewModel.zoomToFitWidth()
            return
        }

        // Opt + Cmd + 0: Zoom to Fit Page / Window
        if (flags == [.command, .option] || (flags.contains(.command) && flags.contains(.option))) && event.charactersIgnoringModifiers == "0" {
            viewModel.zoomToFitPage()
            return
        }
        
        // Cmd + 0: Reset Zoom (100%)
        if flags == .command && event.charactersIgnoringModifiers == "0" {
            viewModel.resetZoom()
            return
        }

        // Cmd + Up Arrow or Cmd + Home: Go to First Page
        if flags == .command && (event.keyCode == 126 || event.keyCode == 115 || event.specialKey == .upArrow || event.specialKey == .home) {
            viewModel.goToFirstPage()
            return
        }

        // Cmd + Down Arrow or Cmd + End: Go to Last Page
        if flags == .command && (event.keyCode == 125 || event.keyCode == 119 || event.specialKey == .downArrow || event.specialKey == .end) {
            viewModel.goToLastPage()
            return
        }
        
        // Escape: Clear selection
        if event.keyCode == 53 {
            viewModel.clearSelection()
            needsDisplay = true
            return
        }
        
        super.keyDown(with: event)
    }
    
    // MARK: - AppKit Menu Responder Chain Support
    
    @objc public func saveDocument(_ sender: Any?) {
        viewModel.saveDocument()
    }
    
    @objc public func save(_ sender: Any?) {
        viewModel.saveDocument()
    }
    
    @objc public func saveDocumentAs(_ sender: Any?) {
        viewModel.saveDocumentAs()
    }
    
    @objc public func printDocument(_ sender: Any?) {
        viewModel.printDocument()
    }
    
    public override func printView(_ sender: Any?) {
        viewModel.printDocument()
    }
    
    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        if action == #selector(saveDocument(_:)) || action == #selector(save(_:)) ||
           action == #selector(saveDocumentAs(_:)) || action == #selector(printDocument(_:)) ||
           action == #selector(printView(_:)) {
            return viewModel.document != nil
        }
        return true
    }
    
    // MARK: - AcroForm Control Synchronization
    
    public func syncFormControls() {
        // Form fields are inert outside the plain single-column, unrotated view (rotation or
        // Two-Page Mode) — their screen position is computed the same way as search highlights/
        // selection, which is only correct in that one layout. Hiding them here rather than
        // mispositioning them.
        guard let doc = viewModel.document, viewModel.isInteractiveViewingMode else {
            for (_, view) in activeFormControls {
                view.removeFromSuperview()
            }
            activeFormControls.removeAll()
            return
        }

        let visible = visibleRect
        guard visible.width > 0 && visible.height > 0 else { return }
        
        let unscaledMinY = max(0, (visible.minY - 16) / viewModel.effectiveZoom)
        let unscaledMaxY = max(0, (visible.maxY - 16) / viewModel.effectiveZoom)
        let firstPage = viewModel.effectivePageIndex(atYOffset: unscaledMinY)
        let lastPage = viewModel.effectivePageIndex(atYOffset: unscaledMaxY)
        
        let start = max(0, firstPage - 1)
        let end = min(doc.pageCount - 1, lastPage + 1)
        guard start <= end else { return }
        
        var visibleKeys = Set<String>()
        
        for pageIdx in start...end {
            guard let pFrame = pageFrame(for: pageIdx) else { continue }
            guard pFrame.intersects(visible) || abs(pFrame.midY - visible.midY) < visible.height else { continue }
            
            if viewModel.pageFormWidgets[pageIdx] == nil {
                // Deferred, same reasoning as the identical call in draw(): syncFormControls() is
                // called from layout() (an AppKit callback with the same mid-SwiftUI-update-cycle
                // risk), so mutating @Published state here synchronously is unsafe. No explicit
                // follow-up call is needed — the Combine subscription in init() already re-invokes
                // syncFormControls() on the next objectWillChange, which this mutation triggers.
                Task { @MainActor [weak self] in
                    self?.viewModel.loadPageMetadata(pageIdx)
                }
                // This page is still on screen — its widgets just haven't been (re)loaded yet.
                // Keep any already-live controls for it so the prune below doesn't tear them down
                // (and their client-side-only state, like a signature preview) only to recreate
                // them blank moments later once metadata arrives.
                let pagePrefix = "p\(pageIdx)_"
                for key in activeFormControls.keys where key.hasPrefix(pagePrefix) {
                    visibleKeys.insert(key)
                }
                continue
            }

            guard let widgets = viewModel.pageFormWidgets[pageIdx], !widgets.isEmpty else { continue }
            let pBounds = doc.pageBounds[pageIdx]
            
            for widget in widgets {
                let key = widget.id
                visibleKeys.insert(key)

                let widgetFrame = widgetScreenFrame(for: widget, pageFrame: pFrame, pageBounds: pBounds)

                // Native AppKit controls follow the system's actual effective appearance by
                // default, independent of isDarkMode's PDF Color override — so forcing "Light"
                // while the system is in Dark Mode left the page bitmap white but every fillable
                // field dark, an odd mismatch. Pinning each control's own .appearance to match
                // keeps them visually consistent with whatever the page itself is doing.
                let controlAppearance = NSAppearance(named: isDarkMode ? .darkAqua : .aqua)

                if let existing = activeFormControls[key] {
                    if existing.frame != widgetFrame {
                        existing.frame = widgetFrame
                    }
                    existing.appearance = controlAppearance
                    updateExistingControl(existing, for: widget)
                } else {
                    if let newControl = PDFFormControlFactory.makeControl(for: widget, viewModel: viewModel, frame: widgetFrame) {
                        newControl.appearance = controlAppearance
                        addSubview(newControl)
                        activeFormControls[key] = newControl
                    }
                }
            }
        }
        
        let keysToRemove = activeFormControls.keys.filter { !visibleKeys.contains($0) }
        for key in keysToRemove {
            if let view = activeFormControls[key] {
                let isEditing = (view.window?.firstResponder as? NSView)?.isDescendant(of: view) == true || view.window?.firstResponder == view
                if !isEditing {
                    view.removeFromSuperview()
                    activeFormControls.removeValue(forKey: key)
                }
            }
        }
        
        // Chain key-view loop in reading order (top-to-bottom, left-to-right) for Tab and Shift+Tab navigation
        let sortedControls = activeFormControls.values
            .filter { $0.canBecomeKeyView }
            .sorted { a, b in
                if abs(a.frame.maxY - b.frame.maxY) > 4 {
                    return a.frame.maxY > b.frame.maxY
                }
                return a.frame.minX < b.frame.minX
            }
        if sortedControls.count > 1 {
            for i in 0..<(sortedControls.count - 1) {
                sortedControls[i].nextKeyView = sortedControls[i + 1]
            }
        }
    }
    
    private var isActivelyEditingFormControl: Bool {
        guard let firstResponder = window?.firstResponder as? NSView else { return false }
        for control in activeFormControls.values {
            if firstResponder.isDescendant(of: control) || firstResponder == control {
                return true
            }
        }
        return false
    }
    
    private func updateExistingControl(_ view: NSView, for widget: PDFFormWidget) {
        if let tf = view as? PDFFormTextField {
            tf.updateZoom(frame: tf.frame)
            let isEditing = (tf.window?.firstResponder as? NSView)?.isDescendant(of: tf) == true
            if !isEditing && tf.stringValue != widget.value {
                tf.stringValue = widget.value
            }
        } else if let ctf = view as? PDFFormCombTextField {
            ctf.updateZoom(frame: ctf.frame)
            let isEditing = ctf.window?.firstResponder == ctf
            if !isEditing && ctf.stringValue != widget.value {
                ctf.stringValue = widget.value
            }
        } else if let stf = view as? PDFFormSecureTextField {
            stf.updateZoom(frame: stf.frame)
            let isEditing = (stf.window?.firstResponder as? NSView)?.isDescendant(of: stf) == true
            if !isEditing && stf.stringValue != widget.value {
                stf.stringValue = widget.value
            }
        } else if let btn = view as? PDFFormButton {
            btn.updateZoom(frame: btn.frame)
            let isChecked = PDFFormButton.isValueChecked(widget.value)
            let targetState: NSControl.StateValue = isChecked ? .on : .off
            if btn.state != targetState {
                btn.state = targetState
            }
        } else if let popup = view as? PDFFormChoiceButton {
            popup.updateZoom(frame: popup.frame)
            if popup.titleOfSelectedItem != widget.value && !widget.value.isEmpty {
                popup.selectItem(withTitle: widget.value)
            }
        } else if let ecf = view as? PDFFormEditableChoiceField {
            ecf.updateZoom(frame: ecf.frame)
            let isEditing = (ecf.window?.firstResponder as? NSView)?.isDescendant(of: ecf) == true
            if !isEditing && ecf.stringValue != widget.value {
                ecf.stringValue = widget.value
            }
        } else if let pb = view as? PDFFormPushButton {
            pb.updateZoom(frame: pb.frame)
        } else if let sig = view as? PDFSignatureStampButton {
            sig.updateZoom(frame: sig.frame)
        }
    }
}
