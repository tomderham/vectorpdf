import Foundation
import CoreGraphics
import AppKit
import MuPDFBridge

public enum PDFError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case pageLoadFailed(Int, String)
    case renderFailed(String)
    case stextFailed(String)
    case saveFailed(String)
    case outOfBounds(Int)
    /// The document is encrypted and no password was supplied yet — distinct from
    /// `incorrectPassword` so the caller knows to prompt for the first time rather than show a
    /// "wrong password" message.
    case passwordRequired
    /// A password was supplied but didn't authenticate.
    case incorrectPassword

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Failed to open document: \(msg)"
        case .pageLoadFailed(let p, let msg): return "Failed to load page \(p): \(msg)"
        case .renderFailed(let msg): return "Failed to render: \(msg)"
        case .stextFailed(let msg): return "Failed to extract structured text: \(msg)"
        case .saveFailed(let msg): return "Failed to save document: \(msg)"
        case .outOfBounds(let p): return "Page index \(p) is out of bounds"
        case .passwordRequired: return "This document requires a password."
        case .incorrectPassword: return "Incorrect password."
        }
    }
}

/// Represents a loaded document, providing thread-safe metadata, layout geometry, and outline access.
/// Note: Concurrency safety with background actors (PDFRenderActor, PDFSearchActor) is maintained
/// by isolating each actor to its own cloned context and document instance. PDFDocumentCore guards
/// its internal MuPDF pointers with `lock` for any concurrent access.
public final class PDFDocumentCore: @unchecked Sendable {
    public let filePath: String
    private let ctx: FZContext
    private let doc: FZDocument
    public let pageCount: Int
    // `var`, not `let`, so a page's placeholder geometry (see hasExactBounds below) can be
    // corrected once its real size is known — see recordActualPageBounds. Only ever touched from
    // the main actor (PDFCanvasView, PDFVirtualizedScrollView, PDFViewerViewModel); the render/
    // search actors compute their own page bounds independently, so no locking is needed here
    // despite this class's broader @unchecked Sendable marking.
    public private(set) var pageBounds: [CGRect]
    public private(set) var pageYOffsets: [CGFloat]
    public private(set) var totalHeight: CGFloat
    public let outline: [PDFOutlineNode]

    /// Whether pageBounds[i] is that page's own real, inspected dimensions rather than an assumed
    /// placeholder — see init's "large documents" branch. Always all-true for documents <= 60
    /// pages, since every page is measured up front there.
    private var hasExactBounds: [Bool]
    private static let pageSpacing: CGFloat = 16.0

    private let lock = NSLock()
    
    public init(filePath: String, password: String? = nil) throws {
        self.filePath = filePath
        let ctx = PDFContextManager.shared.makeClonedContext()
        self.ctx = ctx

        var docPtr: FZDocument?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_document_open(ctx, filePath, &docPtr, &errorMsg)
        guard ret == 0, let doc = docPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            PDFContextManager.shared.dropContext(ctx)
            throw PDFError.openFailed(msg)
        }

        // Must happen before any other document access (page count, rendering, etc.) — those can
        // fail or return incorrect results on an unauthenticated encrypted document.
        var needsPassword: Int32 = 0
        mupdf_document_needs_password(ctx, doc, &needsPassword, &errorMsg)
        if needsPassword != 0 {
            guard let password else {
                mupdf_document_drop(ctx, doc)
                PDFContextManager.shared.dropContext(ctx)
                throw PDFError.passwordRequired
            }
            var authenticated: Int32 = 0
            mupdf_document_authenticate_password(ctx, doc, password, &authenticated, &errorMsg)
            guard authenticated != 0 else {
                mupdf_document_drop(ctx, doc)
                PDFContextManager.shared.dropContext(ctx)
                throw PDFError.incorrectPassword
            }
        }

        self.doc = doc
        
        // Count pages
        var count: Int32 = 0
        mupdf_document_count_pages(ctx, doc, &count, &errorMsg)
        let totalPages = Int(count)
        self.pageCount = totalPages
        
        // Rapid page bounds indexing for virtualized scrolling layout
        var bounds: [CGRect] = []
        var yOffsets: [CGFloat] = []
        var hasExact: [Bool] = []
        var currentY: CGFloat = 0.0
        let pageSpacing = Self.pageSpacing
        
        // Fast-path baseline geometry: sample page 0
        var baselineRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        if totalPages > 0 {
            autoreleasepool {
                var page0Ptr: FZPage?
                if mupdf_page_load(ctx, doc, 0, &page0Ptr, nil) == 0, let page0 = page0Ptr {
                    var rect = fz_rect()
                    mupdf_page_bounds(ctx, page0, &rect, nil)
                    let w = CGFloat(rect.x1 - rect.x0)
                    let h = CGFloat(rect.y1 - rect.y0)
                    baselineRect = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: max(w, 100), height: max(h, 100))
                    mupdf_page_drop(ctx, page0)
                }
            }
        }
        
        if totalPages <= 60 {
            // For smaller documents, inspect exact bounds for every page
            bounds.reserveCapacity(totalPages)
            yOffsets.reserveCapacity(totalPages)
            hasExact.reserveCapacity(totalPages)
            for i in 0..<totalPages {
                if i == 0 {
                    bounds.append(baselineRect)
                    yOffsets.append(currentY)
                    hasExact.append(true)
                    currentY += baselineRect.height + pageSpacing
                } else {
                    autoreleasepool {
                        var pagePtr: FZPage?
                        if mupdf_page_load(ctx, doc, Int32(i), &pagePtr, nil) == 0, let page = pagePtr {
                            var rect = fz_rect()
                            mupdf_page_bounds(ctx, page, &rect, nil)
                            let w = CGFloat(rect.x1 - rect.x0)
                            let h = CGFloat(rect.y1 - rect.y0)
                            let pageRect = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: max(w, 100), height: max(h, 100))
                            bounds.append(pageRect)
                            yOffsets.append(currentY)
                            hasExact.append(true)
                            currentY += pageRect.height + pageSpacing
                            mupdf_page_drop(ctx, page)
                        } else {
                            bounds.append(baselineRect)
                            yOffsets.append(currentY)
                            hasExact.append(true)
                            currentY += baselineRect.height + pageSpacing
                        }
                    }
                }
            }
        } else {
            // For large documents (e.g. 100 - 7,000+ pages), pre-populate with baseline geometry in
            // < 1 ms instead of loading and measuring every page up front, since 99.9% of large
            // documents maintain uniform page dimensions anyway. Pages other than 0 are marked
            // !hasExact, so if one turns out to actually be a different size (e.g. a landscape
            // foldout in an otherwise-portrait document), recordActualPageBounds patches in its
            // real dimensions the first time it's actually rendered.
            bounds.reserveCapacity(totalPages)
            yOffsets.reserveCapacity(totalPages)
            hasExact.reserveCapacity(totalPages)
            let pageHeightWithSpacing = baselineRect.height + pageSpacing
            for i in 0..<totalPages {
                bounds.append(baselineRect)
                yOffsets.append(currentY)
                hasExact.append(i == 0)
                currentY += pageHeightWithSpacing
            }
        }
        mupdf_context_empty_store(ctx)
        self.pageBounds = bounds
        self.pageYOffsets = yOffsets
        self.totalHeight = currentY
        self.hasExactBounds = hasExact
        
        // Load outline
        var outlinePtr: FZOutline?
        if mupdf_document_load_outline(ctx, doc, &outlinePtr, nil) == 0, let out = outlinePtr {
            self.outline = PDFDocumentCore.parseOutline(out)
            mupdf_outline_drop(ctx, out)
        } else {
            self.outline = []
        }
    }
    
    deinit {
        mupdf_document_drop(ctx, doc)
        PDFContextManager.shared.dropContext(ctx)
    }
    
    /// Recursively converts MuPDF outline tree to Swift PDFOutlineNode array
    private static func parseOutline(_ outline: FZOutline) -> [PDFOutlineNode] {
        var nodes: [PDFOutlineNode] = []
        var curr: FZOutline? = outline
        
        while let item = curr {
            let titleStr: String
            if let cTitle = mupdf_outline_title(item) {
                titleStr = String(cString: cTitle)
            } else {
                titleStr = "Untitled"
            }
            
            let uriStr: String?
            if let cUri = mupdf_outline_uri(item) {
                uriStr = String(cString: cUri)
            } else {
                uriStr = nil
            }
            
            let p = Int(mupdf_outline_page(item))
            let pageIndex = p >= 0 ? p : nil
            
            let children: [PDFOutlineNode]
            if let down = mupdf_outline_down(item) {
                children = parseOutline(down)
            } else {
                children = []
            }
            
            nodes.append(PDFOutlineNode(title: titleStr, uri: uriStr, targetPage: pageIndex, children: children))
            curr = mupdf_outline_next(item)
        }
        
        return nodes
    }
    
    /// Finds which page index is located at a vertical scroll offset
    public func pageIndex(atYOffset y: CGFloat) -> Int {
        guard !pageYOffsets.isEmpty else { return 0 }
        var low = 0
        var high = pageYOffsets.count - 1
        var result = 0
        
        while low <= high {
            let mid = (low + high) / 2
            if pageYOffsets[mid] <= y {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return min(max(result, 0), pageCount - 1)
    }

    /// Patches in a page's real bounds once known (called by PDFViewerViewModel.renderPage after
    /// PDFRenderActor measures the page). See hasExactBounds for why this only does anything for
    /// documents > 60 pages, and only once per page. Shifts every later page's Y offset by however
    /// much this page's height changed; earlier pages are unaffected. Returns whether anything
    /// changed, so the caller knows whether a re-layout is needed.
    @discardableResult
    public func recordActualPageBounds(_ actualBounds: CGRect, forPage pageIndex: Int) -> Bool {
        guard pageBounds.indices.contains(pageIndex), hasExactBounds.indices.contains(pageIndex) else { return false }
        guard !hasExactBounds[pageIndex] else { return false }
        hasExactBounds[pageIndex] = true
        guard actualBounds.width > 0, actualBounds.height > 0 else { return false }
        // Same floor init applies to every page's bounds, so a pathologically tiny real page can't
        // produce a near-zero-size frame that breaks scale math elsewhere (thumbnail cropping,
        // widget positioning, etc.).
        let clampedBounds = CGRect(x: actualBounds.minX, y: actualBounds.minY, width: max(actualBounds.width, 100), height: max(actualBounds.height, 100))
        guard clampedBounds != pageBounds[pageIndex] else { return false }

        pageBounds[pageIndex] = clampedBounds
        var currentY = pageYOffsets[pageIndex]
        for i in pageIndex..<pageBounds.count {
            pageYOffsets[i] = currentY
            currentY += pageBounds[i].height + Self.pageSpacing
        }
        totalHeight = currentY
        return true
    }

    /// Thread-safe scoped page inspection using this core's context
    public func withPage<T>(pageIndex: Int, _ body: (FZPage) throws -> T) throws -> T {
        guard pageIndex >= 0 && pageIndex < pageCount else {
            throw PDFError.outOfBounds(pageIndex)
        }
        lock.lock()
        defer { lock.unlock() }
        
        var pagePtr: FZPage?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, &errorMsg)
        guard ret == 0, let page = pagePtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to load page"
            throw PDFError.pageLoadFailed(pageIndex, msg)
        }
        defer {
            mupdf_page_drop(ctx, page)
        }
        return try body(page)
    }
    
    /// Adds a highlight annotation to a page
    public func addHighlight(pageIndex: Int, quad: PDFQuad, red: Float, green: Float, blue: Float) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let fzQ = quad.toFZQuad()
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_highlight_annot(ctx, doc, Int32(pageIndex), fzQ, red, green, blue, &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to add highlight"
            throw PDFError.saveFailed(msg)
        }
    }
    
    /// Stamps `imageData` (PNG or JPEG bytes) into `rect` (native bottom-up PDF coordinates) on a
    /// page as a visual signature stamp — not a filled-in AcroForm field value, not a cryptographic
    /// signature.
    public func stampImage(pageIndex: Int, rect: CGRect, imageData: Data) throws {
        lock.lock()
        defer { lock.unlock() }

        var errorMsg: UnsafePointer<CChar>?
        let ret = imageData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int32 in
            let bytes = raw.bindMemory(to: UInt8.self).baseAddress
            return mupdf_pdf_stamp_image_annot(
                ctx, doc, Int32(pageIndex),
                Float(rect.minX), Float(rect.minY), Float(rect.maxX), Float(rect.maxY),
                bytes, raw.count, &errorMsg
            )
        }
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to stamp signature image"
            throw PDFError.saveFailed(msg)
        }
    }

    /// Whether a stamp annotation already sits at `widgetRect` (top-down, like PDFFormWidget.rect)
    /// on `pageIndex` — lets a freshly (re)loaded PDFSignatureStampButton know a field was already
    /// signed instead of showing its "Sign" placeholder over the baked-in stamp.
    public func hasSignatureStamp(pageIndex: Int, widgetRect: CGRect) -> Bool {
        guard pageIndex >= 0, pageIndex < pageBounds.count else { return false }
        let pageTopY = pageBounds[pageIndex].maxY
        let nativeRect = CGRect(x: widgetRect.minX, y: pageTopY - widgetRect.maxY, width: widgetRect.width, height: widgetRect.height)

        lock.lock()
        defer { lock.unlock() }

        var found: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_page_has_stamp_near_rect(
            ctx, doc, Int32(pageIndex),
            Float(nativeRect.minX), Float(nativeRect.minY), Float(nativeRect.maxX), Float(nativeRect.maxY),
            &found, &errorMsg
        )
        return ret == 0 && found != 0
    }

    /// Saves the modified PDF, using atomic file swapping if overwriting the original document
    public func save(to path: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        let destinationURL = URL(fileURLWithPath: path)
        let isSameFile = (path == self.filePath)
        
        let tempURL = destinationURL.deletingLastPathComponent().appendingPathComponent(".~\(destinationURL.lastPathComponent).tmp")
        let targetSavePath = isSameFile ? tempURL.path : path
        
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_pdf_save(ctx, doc, targetSavePath, &errorMsg)
        if ret != 0 {
            if isSameFile { try? FileManager.default.removeItem(at: tempURL) }
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to save PDF"
            throw PDFError.saveFailed(msg)
        }
        
        if isSameFile {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
        }
    }
}

extension PDFDocumentCore {
    /// Loads interactive links for a page
    public func loadLinks(for pageIndex: Int) -> [SnapshotTarget] {
        let resolver = CrossReferenceResolver()
        return (try? withPage(pageIndex: pageIndex) { page in
            resolver.resolveLinks(on: page, pageIndex: pageIndex, doc: self.doc, ctx: self.ctx)
        }) ?? []
    }
    
    /// Loads structured text hierarchy for a page
    public func loadStructuredPage(for pageIndex: Int) -> StructuredPage? {
        return try? withPage(pageIndex: pageIndex) { page in
            try StructuredPage.load(from: page, pageIndex: pageIndex, ctx: self.ctx)
        }
    }
    
    /// Loads interactive form widgets (text fields, checkboxes, dropdowns) for a page
    public func loadFormWidgets(for pageIndex: Int) -> [PDFFormWidget] {
        lock.lock()
        defer { lock.unlock() }
        
        var count: Int32 = 0
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_count_widgets(ctx, doc, Int32(pageIndex), &count, &errorMsg)
        guard ret == 0, count > 0 else { return [] }
        
        var widgets: [PDFFormWidget] = []
        widgets.reserveCapacity(Int(count))
        
        for idx in 0..<count {
            var rawType: Int32 = 0
            var fzRect = fz_rect()
            var cName: UnsafeMutablePointer<CChar>? = nil
            var cValue: UnsafeMutablePointer<CChar>? = nil
            var flags: Int32 = 0
            var fontSize: Float = 0
            var maxLen: Int32 = 0
            var textAlign: Int32 = 0
            
            let infoRet = mupdf_page_get_widget_info(
                ctx, doc, Int32(pageIndex), idx,
                &rawType, &fzRect, &cName, &cValue, &flags, &fontSize,
                &maxLen, &textAlign, &errorMsg
            )
            
            guard infoRet == 0 else { continue }
            
            let name = cName != nil ? String(cString: cName!) : ""
            let value = cValue != nil ? String(cString: cValue!) : ""
            if let cName = cName { free(cName) }
            if let cValue = cValue { free(cValue) }
            
            let widgetType = PDFWidgetType(rawValue: Int(rawType)) ?? .unknown
            let rect = CGRect(
                x: CGFloat(fzRect.x0),
                y: CGFloat(fzRect.y0),
                width: CGFloat(fzRect.x1 - fzRect.x0),
                height: CGFloat(fzRect.y1 - fzRect.y0)
            )
            
            let isReadOnly = (flags & 1) != 0
            let isMultiline = (flags & (1 << 12)) != 0
            let isPassword = (flags & (1 << 13)) != 0
            let isPushButton = (flags & (1 << 16)) != 0
            let isEditableChoice = (flags & (1 << 18)) != 0
            let isComb = ((flags & (1 << 24)) != 0) && (maxLen > 0)
            let alignment: NSTextAlignment = textAlign == 1 ? .center : (textAlign == 2 ? .right : .left)
            
            var options: [String] = []
            if widgetType == .combobox || widgetType == .listbox {
                var cOptions: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>? = nil
                var optCount: Int32 = 0
                if mupdf_page_get_choice_options(ctx, doc, Int32(pageIndex), idx, &cOptions, &optCount, nil) == 0, optCount > 0, let opts = cOptions {
                    for i in 0..<Int(optCount) {
                        if let optStr = opts[i] {
                            options.append(String(cString: optStr))
                        }
                    }
                    mupdf_free_choice_options(ctx, opts, optCount)
                }
            }
            
            let widget = PDFFormWidget(
                pageIndex: pageIndex,
                widgetIndex: Int(idx),
                type: widgetType,
                rect: rect,
                name: name,
                value: value,
                isReadOnly: isReadOnly,
                isMultiline: isMultiline,
                isPassword: isPassword,
                fontSize: CGFloat(fontSize),
                maxLen: Int(maxLen),
                isComb: isComb,
                isPushButton: isPushButton,
                isEditableChoice: isEditableChoice,
                textAlignment: alignment,
                options: options
            )
            widgets.append(widget)
        }
        
        return widgets
    }
    
    /// Resets all interactive AcroForm fields in the document to their default values
    public func resetForm() throws {
        lock.lock()
        defer { lock.unlock() }
        var errorMsg: UnsafePointer<CChar>? = nil
        let ret = mupdf_document_reset_form(ctx, doc, &errorMsg)
        if ret != 0 {
            let desc = errorMsg != nil ? String(cString: errorMsg!) : "Failed to reset form"
            throw PDFError.renderFailed(desc)
        }
    }
    
    /// Updates the value of an AcroForm widget on a page
    public func setFormWidgetValue(pageIndex: Int, widgetIndex: Int, value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_page_set_widget_value(ctx, doc, Int32(pageIndex), Int32(widgetIndex), value, &errorMsg)
        if ret != 0 {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to set form widget value"
            throw PDFError.saveFailed(msg)
        }
    }
}
