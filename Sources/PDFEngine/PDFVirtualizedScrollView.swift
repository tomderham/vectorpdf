import SwiftUI
import AppKit

/// Lightweight AppKit bridge to attach NSWindow reference to views and enable native window tabbing.
///
/// Coordinator tracks the last reported window so `onWindow` fires only on actual changes,
/// preventing redundant view re-renders.
public struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    public init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        weak var lastReportedWindow: NSWindow?
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            reportWindowIfNeeded(for: view, context: context)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            reportWindowIfNeeded(for: nsView, context: context)
        }
    }

    private func reportWindowIfNeeded(for view: NSView, context: Context) {
        guard let window = view.window, window !== context.coordinator.lastReportedWindow else { return }
        context.coordinator.lastReportedWindow = window
        onWindow(window)
    }
}

/// High-performance AppKit virtualized scroll view hosting a single native PDFCanvasView.
/// Completely eliminates SwiftUI layout thrashing and guarantees instant ToC navigation.
public struct PDFVirtualizedScrollView: NSViewRepresentable {
    @ObservedObject var viewModel: PDFViewerViewModel
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.underPageBackgroundColor
        
        let canvasView = PDFCanvasView(viewModel: viewModel)
        scrollView.documentView = canvasView
        
        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: clipView
        )
        
        context.coordinator.scrollView = scrollView
        context.coordinator.canvasView = canvasView
        
        return scrollView
    }
    
    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(viewModel: viewModel, scrollView: scrollView)
    }
    
    @MainActor
    public final class Coordinator: NSObject {
        var viewModel: PDFViewerViewModel
        weak var scrollView: NSScrollView?
        weak var canvasView: PDFCanvasView?
        
        private var isProgrammaticScroll: Bool = false
        private var lastDocumentPath: String? = nil
        private var lastZoomScale: CGFloat = 1.0
        private var lastNavigatedPage: Int = -1
        private var lastSearchMatchIndex: Int = -1
        private var lastScrolledTargetId: String? = nil
        private var lastSnapshotId: UUID? = nil
        
        init(viewModel: PDFViewerViewModel) {
            self.viewModel = viewModel
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        func update(viewModel: PDFViewerViewModel, scrollView: NSScrollView) {
            self.viewModel = viewModel
            guard let doc = viewModel.document, let canvasView = self.canvasView else {
                if lastDocumentPath != nil {
                    lastDocumentPath = nil
                    self.canvasView?.frame = .zero
                }
                return
            }
            
            let clipView = scrollView.contentView
            let isNewDocument = (lastDocumentPath != doc.filePath)
            let isZoomChanged = (abs(lastZoomScale - viewModel.zoomScale) > 0.001)
            let isPageJump = (viewModel.currentPageIndex != lastNavigatedPage && !isProgrammaticScroll)
            let isMatchNavigation = (viewModel.activeScrollTargetId != nil && viewModel.activeScrollTargetId != lastScrolledTargetId && !viewModel.searchResults.isEmpty)
            let isSnapshotJump = (viewModel.activeSnapshotTarget?.id != nil && viewModel.activeSnapshotTarget?.id != lastSnapshotId)
            
            if isNewDocument {
                lastDocumentPath = doc.filePath
                lastNavigatedPage = 0
                lastZoomScale = viewModel.zoomScale
                lastSearchMatchIndex = -1
                lastScrolledTargetId = nil
                lastSnapshotId = nil
            }
            
            // 1. Calculate container bounds based on pre-computed document geometry. Width/height
            // swap at 90°/270° rotation — see PDFViewerViewModel.effectivePageYOffsets's doc
            // comment — is why this reads viewModel.effectiveTotalHeight rather than doc.totalHeight,
            // and picks page height instead of width for the "widest page" scan when rotated
            // sideways (a rotated page's on-screen width is its native height). Two-Page Mode needs
            // roughly double a single page's width (two pages plus the gap between them), not just
            // one page's width, or the right-hand page would be clipped.
            let sideways = viewModel.viewRotationDegrees == 90 || viewModel.viewRotationDegrees == 270
            let widestPage = doc.pageBounds.map { sideways ? $0.height : $0.width }.max() ?? 612
            let maxDocWidth = viewModel.isTwoPageMode ? (widestPage * 2 + 16) : widestPage
            let contentWidth = max(clipView.bounds.width, (maxDocWidth * viewModel.zoomScale) + 64)
            let contentHeight = (viewModel.effectiveTotalHeight * viewModel.zoomScale) + 48
            let newCanvasFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

            if canvasView.frame != newCanvasFrame {
                canvasView.frame = newCanvasFrame
            }

            // 2. Handle Zoom Scale Change
            if isZoomChanged && !isNewDocument {
                lastZoomScale = viewModel.zoomScale
                let targetY = max(0, (viewModel.effectivePageYOffsets[viewModel.currentPageIndex] * viewModel.zoomScale) + 16)
                isProgrammaticScroll = true
                clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
                scrollView.reflectScrolledClipView(clipView)
                isProgrammaticScroll = false
            }

            // 3. Handle Direct Page Jump (e.g. from Table of Contents)
            if (isPageJump || isNewDocument) && !isMatchNavigation && !isSnapshotJump {
                lastNavigatedPage = viewModel.currentPageIndex
                let targetPage = viewModel.currentPageIndex
                if targetPage >= 0 && targetPage < doc.pageCount {
                    let targetY = max(0, (viewModel.effectivePageYOffsets[targetPage] * viewModel.zoomScale) + 16)
                    isProgrammaticScroll = true
                    clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
                    scrollView.reflectScrolledClipView(clipView)
                    isProgrammaticScroll = false
                }
            }
            
            // 4. Handle Precise Search Match Scroll
            if isMatchNavigation {
                lastScrolledTargetId = viewModel.activeScrollTargetId
                lastSearchMatchIndex = viewModel.activeSearchMatchIndex
                if let match = viewModel.searchResults.first(where: { $0.id.uuidString == viewModel.activeScrollTargetId }) {
                    lastNavigatedPage = match.pageIndex
                    scrollToMatch(match: match, doc: doc, clipView: clipView, scrollView: scrollView)
                } else if viewModel.searchResults.indices.contains(viewModel.activeSearchMatchIndex) {
                    let match = viewModel.searchResults[viewModel.activeSearchMatchIndex]
                    lastNavigatedPage = match.pageIndex
                    scrollToMatch(match: match, doc: doc, clipView: clipView, scrollView: scrollView)
                }
            }
            
            // 5. Handle Precise Snapshot Target Scroll
            if isSnapshotJump, let snap = viewModel.activeSnapshotTarget {
                lastSnapshotId = snap.id
                lastNavigatedPage = snap.targetPage
                scrollToSnapshot(snap: snap, doc: doc, clipView: clipView, scrollView: scrollView)
            }
            
            canvasView.needsDisplay = true
            canvasView.syncFormControls()
        }
        
        private func scrollToMatch(match: SearchResult, doc: PDFDocumentCore, clipView: NSClipView, scrollView: NSScrollView) {
            let pageIdx = match.pageIndex
            guard pageIdx >= 0 && pageIdx < doc.pageCount, let canvasView = self.canvasView else { return }
            
            let pageY = viewModel.effectivePageYOffsets[pageIdx]
            let matchRect = match.highlightQuads.first?.boundingRect ?? CGRect(x: 0, y: 0, width: 200, height: 20)
            let absoluteY = (pageY + matchRect.midY) * viewModel.zoomScale + 16
            let scrollY = max(0, absoluteY - (clipView.bounds.height / 2))
            
            let pageBounds = doc.pageBounds[pageIdx]
            let pageX = max(32, (canvasView.bounds.width - (pageBounds.width * viewModel.zoomScale)) / 2)
            let matchX = (matchRect.midX - pageBounds.minX) * viewModel.zoomScale
            let absoluteX = pageX + matchX
            // Upper-clamped too, not just lower: centering a match near the page's right edge could
            // otherwise request a scroll position beyond how far the content can actually scroll
            // (e.g. at a zoom level where the page already fits within the viewport width), which
            // pans the page's own left edge out of view instead.
            let maxScrollX = max(0, canvasView.bounds.width - clipView.bounds.width)
            let scrollX = min(max(0, absoluteX - (clipView.bounds.width / 2)), maxScrollX)

            isProgrammaticScroll = true
            clipView.scroll(to: NSPoint(x: scrollX, y: scrollY))
            scrollView.reflectScrolledClipView(clipView)
            isProgrammaticScroll = false
        }

        private func scrollToSnapshot(snap: SnapshotTarget, doc: PDFDocumentCore, clipView: NSClipView, scrollView: NSScrollView) {
            let pageIdx = snap.targetPage
            guard pageIdx >= 0 && pageIdx < doc.pageCount, let canvasView = self.canvasView else { return }
            
            let pageY = viewModel.effectivePageYOffsets[pageIdx]
            let pageBounds = doc.pageBounds[pageIdx]

            // Cross-reference links only ever carry a targetPoint, not a targetRect (see
            // CrossReferenceResolver.resolveLinks) — prefer centering on that exact point over
            // the generic top-of-page fallback, so "Open in New Window" / Option-click on a
            // reference actually centers the new window on the reference, not just its page.
            let targetMidX: CGFloat
            let targetMidY: CGFloat
            if let rect = snap.targetRect {
                targetMidX = rect.midX
                targetMidY = rect.midY
            } else if let point = snap.targetPoint {
                let isLeftAnchored = point.x <= pageBounds.minX + 40
                targetMidX = isLeftAnchored ? (pageBounds.minX + min(pageBounds.width * 0.35, 180)) : point.x
                targetMidY = point.y
            } else {
                targetMidX = pageBounds.midX
                targetMidY = pageBounds.minY + 40
            }

            let absoluteY = (pageY + targetMidY) * viewModel.zoomScale + 16
            let scrollY = max(0, absoluteY - (clipView.bounds.height / 2))
            
            let pageX = max(32, (canvasView.bounds.width - (pageBounds.width * viewModel.zoomScale)) / 2)
            let snapX = (targetMidX - pageBounds.minX) * viewModel.zoomScale
            // See the identical upper-clamp note in scrollToMatch above — same reasoning here.
            let maxScrollX = max(0, canvasView.bounds.width - clipView.bounds.width)
            let scrollX = min(max(0, pageX + snapX - (clipView.bounds.width / 2)), maxScrollX)
            
            isProgrammaticScroll = true
            clipView.scroll(to: NSPoint(x: scrollX, y: scrollY))
            scrollView.reflectScrolledClipView(clipView)
            isProgrammaticScroll = false
        }
        
        @objc func clipViewBoundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll, viewModel.document != nil, let scrollView = self.scrollView else { return }
            
            let clipView = scrollView.contentView
            let currentScrollY = max(0, clipView.bounds.origin.y - 16)
            let unscaledY = currentScrollY / viewModel.zoomScale
            
            // Rapid O(log N) binary search for active page
            let activePage = viewModel.effectivePageIndex(atYOffset: unscaledY + 80)
            if activePage != viewModel.currentPageIndex {
                lastNavigatedPage = activePage
                viewModel.currentPageIndex = activePage
                viewModel.pruneCaches(around: activePage)
            }
            canvasView?.syncFormControls()
        }
    }
}

