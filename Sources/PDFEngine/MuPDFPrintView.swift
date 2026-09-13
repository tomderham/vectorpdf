import AppKit
import ApplicationServices
import MuPDFBridge

private final class PrintResource: @unchecked Sendable {
    let ctx: FZContext
    var doc: FZDocument?
    
    init(ctx: FZContext, doc: FZDocument?) {
        self.ctx = ctx
        self.doc = doc
    }
    
    deinit {
        if let d = doc {
            mupdf_document_drop(ctx, d)
        }
        PDFContextManager.shared.dropContext(ctx)
    }
}

/// An optimized NSPrintInfo subclass that caches paper size and imageable bounds,
/// preventing macOS PrintingUI from repeatedly querying Carbon print tickets and locking mutexes
/// for thousands of pages in NSCollectionViewFlowLayout.
public final class PDFPrintInfo: NSPrintInfo {
    private var _cachedPaperSize: NSSize?
    private var _cachedImageableBounds: NSRect?

    public override var paperSize: NSSize {
        get {
            if let size = _cachedPaperSize { return size }
            let size = super.paperSize
            _cachedPaperSize = size
            return size
        }
        set {
            _cachedPaperSize = newValue
            super.paperSize = newValue
        }
    }

    public override var imageablePageBounds: NSRect {
        if let bounds = _cachedImageableBounds { return bounds }
        let bounds = super.imageablePageBounds
        _cachedImageableBounds = bounds
        return bounds
    }

    public override var orientation: NSPrintInfo.PaperOrientation {
        get { super.orientation }
        set {
            _cachedPaperSize = nil
            _cachedImageableBounds = nil
            super.orientation = newValue
        }
    }

    public override var paperName: NSPrinter.PaperName? {
        get { super.paperName }
        set {
            _cachedPaperSize = nil
            _cachedImageableBounds = nil
            super.paperName = newValue
        }
    }

    public override func copy(with zone: NSZone? = nil) -> Any {
        let copy = super.copy(with: zone) as! PDFPrintInfo
        copy._cachedPaperSize = self._cachedPaperSize
        copy._cachedImageableBounds = self._cachedImageableBounds
        return copy
    }
}

/// An NSView that renders PDF pages directly using the native MuPDF engine during print operations,
/// guaranteeing 100% visual parity with on-screen viewing and restoring macOS native orientation controls.
public final class MuPDFPrintView: NSView {
    private let resource: PrintResource
    public let pageCount: Int
    public let printInfo: NSPrintInfo
    private var cachedPaperRect: NSRect
    
    public var autoRotate: Bool = true {
        didSet { needsDisplay = true }
    }
    public var scaleMode: Int = 1 { // 1 = scaleToFit, 0 = custom
        didSet { needsDisplay = true }
    }
    public var customScale: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }
    
    public init(filePath: String, password: String?, pageCount: Int, printInfo: NSPrintInfo? = nil) throws {
        let ctx = PDFContextManager.shared.makeClonedContext()
        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let d = docPtr else {
            PDFContextManager.shared.dropContext(ctx)
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to open document for printing"
            throw PDFError.openFailed(msg)
        }
        
        var needsPassword: Int32 = 0
        mupdf_document_needs_password(ctx, d, &needsPassword, &errorMsg)
        if needsPassword != 0 {
            guard let password else {
                mupdf_document_drop(ctx, d)
                PDFContextManager.shared.dropContext(ctx)
                throw PDFError.passwordRequired
            }
            var authenticated: Int32 = 0
            mupdf_document_authenticate_password(ctx, d, password, &authenticated, &errorMsg)
            guard authenticated != 0 else {
                mupdf_document_drop(ctx, d)
                PDFContextManager.shared.dropContext(ctx)
                throw PDFError.incorrectPassword
            }
        }
        
        self.resource = PrintResource(ctx: ctx, doc: d)
        self.pageCount = pageCount
        let resolvedInfo = printInfo ?? (NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo())
        self.printInfo = resolvedInfo
        let paperRect = NSRect(origin: .zero, size: resolvedInfo.paperSize)
        self.cachedPaperRect = paperRect
        super.init(frame: paperRect)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(1, pageCount))
        return true
    }
    
    public override func rectForPage(_ page: Int) -> NSRect {
        return cachedPaperRect
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        let printOp = NSPrintOperation.current
        let activePrintInfo = printOp?.printInfo ?? self.printInfo
        let paperSize = activePrintInfo.paperSize
        self.cachedPaperRect = NSRect(origin: .zero, size: paperSize)
        
        let rawPage = printOp?.currentPage ?? 1
        let pageIndex = max(0, min(pageCount - 1, rawPage > 0 ? (rawPage - 1) : 0))
        guard let doc = resource.doc else { return }
        let ctx = resource.ctx
        
        var pagePtr: FZPage?
        guard mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, nil) == 0, let page = pagePtr else {
            return
        }
        defer { mupdf_page_drop(ctx, page) }
        
        var rect = fz_rect()
        mupdf_page_bounds(ctx, page, &rect, nil)
        let pageW = CGFloat(rect.x1 - rect.x0)
        let pageH = CGFloat(rect.y1 - rect.y0)
        guard pageW > 0 && pageH > 0 else { return }
        
        let imageableBounds = activePrintInfo.imageablePageBounds
        
        // Check if auto-rotation is needed to match paper orientation
        let paperIsLandscape = paperSize.width > paperSize.height
        let pageIsLandscape = pageW > pageH
        let shouldRotate = autoRotate && (paperIsLandscape != pageIsLandscape)
        
        let effectivePageW = shouldRotate ? pageH : pageW
        let effectivePageH = shouldRotate ? pageW : pageH
        
        // Determine target drawing rect on paper
        let targetRect: NSRect
        let renderScaleFactor: CGFloat
        
        if scaleMode == 1 { // Scale to fit
            let availableWidth = max(72.0, imageableBounds.width)
            let availableHeight = max(72.0, imageableBounds.height)
            let scaleX = availableWidth / effectivePageW
            let scaleY = availableHeight / effectivePageH
            let fitFactor = min(scaleX, scaleY)
            let fittedW = effectivePageW * fitFactor
            let fittedH = effectivePageH * fitFactor
            
            let originX = (paperSize.width - fittedW) / 2.0
            let originY = (paperSize.height - fittedH) / 2.0
            targetRect = NSRect(x: originX, y: originY, width: fittedW, height: fittedH)
            renderScaleFactor = fitFactor
        } else { // Custom scale
            let factor = max(0.1, min(4.0, customScale))
            let scaledW = effectivePageW * factor
            let scaledH = effectivePageH * factor
            let originX = (paperSize.width - scaledW) / 2.0
            let originY = (paperSize.height - scaledH) / 2.0
            targetRect = NSRect(x: originX, y: originY, width: scaledW, height: scaledH)
            renderScaleFactor = factor
        }
        
        // Use responsive 144 DPI for UI previews to ensure instant responsiveness without network printer delays,
        // and 600 DPI for physical printing for maximum print resolution and quality.
        // Avoid synchronous PMPrinter/CUPS capability queries to prevent 15-20s network printer discovery hangs.
        let isResponsive = (printOp == nil || printOp?.preferredRenderingQuality == .responsive)
        let renderDPI: CGFloat = isResponsive ? 144.0 : 600.0
        let dpiScale = Float(renderDPI / 72.0)
        let totalScale = dpiScale * Float(renderScaleFactor)
        
        var pixmapPtr: FZPixmap?
        guard mupdf_render_page(ctx, page, totalScale, totalScale, &pixmapPtr, nil) == 0, let pix = pixmapPtr else {
            return
        }
        defer {
            mupdf_pixmap_drop(ctx, pix)
        }
        
        guard let cgImage = makeCGImage(from: pix) else { return }
        let imageToDraw = NSImage(cgImage: cgImage, size: NSSize(width: pageW * renderScaleFactor, height: pageH * renderScaleFactor))
        
        guard let cgContext = NSGraphicsContext.current?.cgContext else { return }
        
        if shouldRotate {
            cgContext.saveGState()
            cgContext.translateBy(x: targetRect.midX, y: targetRect.midY)
            cgContext.rotate(by: -.pi / 2) // 90 degrees clockwise to match orientation
            let drawBounds = NSRect(
                x: -(pageW * renderScaleFactor) / 2.0,
                y: -(pageH * renderScaleFactor) / 2.0,
                width: pageW * renderScaleFactor,
                height: pageH * renderScaleFactor
            )
            imageToDraw.draw(in: drawBounds)
            cgContext.restoreGState()
        } else {
            imageToDraw.draw(in: targetRect)
        }
    }
    
    private func makeCGImage(from pix: FZPixmap) -> CGImage? {
        let w = Int(mupdf_pixmap_width(pix))
        let h = Int(mupdf_pixmap_height(pix))
        let stride = Int(mupdf_pixmap_stride(pix))
        let n = Int(mupdf_pixmap_n(pix))
        guard let samples = mupdf_pixmap_samples(pix), w > 0, h > 0 else {
            return nil
        }
        // Zero-copy data provider directly wrapping pixmap samples buffer.
        // Valid for the duration of draw(_:) where pix is guaranteed alive by defer.
        guard let provider = CGDataProvider(dataInfo: nil, data: samples, size: stride * h, releaseData: { _, _, _ in }) else {
            return nil
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo
        if n == 4 {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        } else {
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        }
        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: n * 8,
            bytesPerRow: stride,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

