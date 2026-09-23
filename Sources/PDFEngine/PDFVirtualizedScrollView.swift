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

/// High-performance custom NSScrollView capturing native trackpad pinch-to-zoom and smart magnify.
public final class PDFScrollView: NSScrollView {
    weak var coordinator: PDFVirtualizedScrollView.Coordinator?
    
    public override func magnify(with event: NSEvent) {
        if let coordinator = coordinator {
            coordinator.handleMagnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
    
    public override func smartMagnify(with event: NSEvent) {
        if let coordinator = coordinator {
            coordinator.handleSmartMagnify(with: event)
        } else {
            super.smartMagnify(with: event)
        }
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
        let scrollView = PDFScrollView(frame: .zero)
        scrollView.coordinator = context.coordinator
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
        private var lastSnapshotJumpToken: Int = -1
        
        // Pinch-to-zoom tracking
        var isPinching: Bool = false
        private var pinchBaseZoom: CGFloat = 1.0
        private var pinchAccumulatedScale: CGFloat = 1.0
        private var pinchViewportOffset: CGPoint = .zero
        private var pinchAnchorPage: Int = 0
        private var pinchRelX: CGFloat = 0.5
        private var pinchRelY: CGFloat = 0.5
        
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
            let isSnapshotJump = (viewModel.snapshotJumpToken != lastSnapshotJumpToken && viewModel.activeSnapshotTarget != nil)
            
            if isNewDocument {
                lastDocumentPath = doc.filePath
                lastNavigatedPage = 0
                lastZoomScale = viewModel.zoomScale
                lastSearchMatchIndex = -1
                lastScrolledTargetId = nil
                lastSnapshotJumpToken = -1
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
            let contentWidth = max(clipView.bounds.width, (maxDocWidth * viewModel.effectiveZoom) + 64)
            let contentHeight = (viewModel.effectiveTotalHeight * viewModel.effectiveZoom) + 48
            let newCanvasFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)

            if canvasView.frame != newCanvasFrame {
                canvasView.frame = newCanvasFrame
            }

            // 2. Handle Zoom Scale Change (Menu / Toolbar / Shortcuts)
            if isZoomChanged && !isNewDocument && !isPinching {
                lastZoomScale = viewModel.zoomScale
                let targetPage = viewModel.currentPageIndex
                if let pFrame = canvasView.pageFrame(for: targetPage) {
                    let targetMidX = viewModel.isTwoPageMode ? (canvasView.frame.width / 2) : pFrame.midX
                    let targetMidY = pFrame.midY
                    let maxScrollX = max(0, canvasView.frame.width - clipView.bounds.width)
                    let maxScrollY = max(0, canvasView.frame.height - clipView.bounds.height)
                    let scrollX = min(max(0, targetMidX - (clipView.bounds.width / 2)), maxScrollX)
                    let scrollY = min(max(0, targetMidY - (clipView.bounds.height / 2)), maxScrollY)
                    isProgrammaticScroll = true
                    clipView.scroll(to: NSPoint(x: scrollX, y: scrollY))
                    scrollView.reflectScrolledClipView(clipView)
                    isProgrammaticScroll = false
                }
            }

            // 3. Handle Direct Page Jump (e.g. from Table of Contents)
            if (isPageJump || isNewDocument) && !isMatchNavigation && !isSnapshotJump {
                lastNavigatedPage = viewModel.currentPageIndex
                let targetPage = viewModel.currentPageIndex
                if targetPage >= 0 && targetPage < doc.pageCount {
                    let targetY = max(0, (viewModel.effectivePageYOffsets[targetPage] * viewModel.effectiveZoom) + 16)
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
                lastSnapshotJumpToken = viewModel.snapshotJumpToken
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
            let absoluteY = (pageY + matchRect.midY) * viewModel.effectiveZoom + 16
            let scrollY = max(0, absoluteY - (clipView.bounds.height / 2))
            
            let pageBounds = doc.pageBounds[pageIdx]
            let pageX = max(32, (canvasView.bounds.width - (pageBounds.width * viewModel.effectiveZoom)) / 2)
            let matchX = (matchRect.midX - pageBounds.minX) * viewModel.effectiveZoom
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
            guard pageIdx >= 0 && pageIdx < doc.pageCount,
                  let canvasView = self.canvasView,
                  let pFrame = canvasView.pageFrame(for: pageIdx) else { return }
            
            let pageBounds = doc.pageBounds[pageIdx]
            let targetPageRect = viewModel.resolvedTargetRect(for: snap)

            // Map targetPageRect to canvas coordinates matching focusRingRect
            let targetCanvasX = pFrame.minX + (targetPageRect.minX - pageBounds.minX) * viewModel.effectiveZoom
            let targetCanvasY = pFrame.minY + (targetPageRect.minY - pageBounds.minY) * viewModel.effectiveZoom
            let targetCanvasW = max(targetPageRect.width * viewModel.effectiveZoom, 24)
            let targetCanvasH = max(targetPageRect.height * viewModel.effectiveZoom, 20)
            let targetCanvasRect = NSRect(x: targetCanvasX, y: targetCanvasY, width: targetCanvasW, height: targetCanvasH)

            // 1. Vertical Scrolling — center bounding box while keeping its entirety visible
            let maxScrollY = max(0, canvasView.bounds.height - clipView.bounds.height)
            var scrollY: CGFloat

            if targetCanvasRect.height >= clipView.bounds.height {
                // If bounding box is taller than viewport, align top with comfortable margin
                scrollY = targetCanvasRect.minY - 24
            } else {
                // Center the bounding box vertically
                scrollY = targetCanvasRect.midY - (clipView.bounds.height / 2)

                // Clamp viewport bounds so top and bottom margins of the bounding box are preserved
                if scrollY > targetCanvasRect.minY - 24 {
                    scrollY = targetCanvasRect.minY - 24
                }
                if scrollY + clipView.bounds.height < targetCanvasRect.maxY + 24 {
                    scrollY = targetCanvasRect.maxY + 24 - clipView.bounds.height
                }
            }
            scrollY = min(max(0, scrollY), maxScrollY)

            // 2. Horizontal Scrolling — center target midX and keep within viewport bounds
            let maxScrollX = max(0, canvasView.bounds.width - clipView.bounds.width)
            var scrollX: CGFloat

            if targetCanvasRect.width >= clipView.bounds.width {
                scrollX = targetCanvasRect.minX - 32
            } else {
                scrollX = targetCanvasRect.midX - (clipView.bounds.width / 2)
                if scrollX > targetCanvasRect.minX - 32 {
                    scrollX = targetCanvasRect.minX - 32
                }
                if scrollX + clipView.bounds.width < targetCanvasRect.maxX + 32 {
                    scrollX = targetCanvasRect.maxX + 32 - clipView.bounds.width
                }
            }
            scrollX = min(max(0, scrollX), maxScrollX)

            isProgrammaticScroll = true
            clipView.scroll(to: NSPoint(x: scrollX, y: scrollY))
            scrollView.reflectScrolledClipView(clipView)
            isProgrammaticScroll = false
        }
        
        func handleMagnify(with event: NSEvent) {
            guard let scrollView = self.scrollView,
                  let canvasView = self.canvasView,
                  let doc = viewModel.document else { return }
            
            let clipView = scrollView.contentView
            let isBegan = event.phase.contains(.began) || (!isPinching && !event.phase.contains(.ended) && !event.phase.contains(.cancelled))
            
            if isBegan {
                isPinching = true
                pinchBaseZoom = viewModel.zoomScale
                pinchAccumulatedScale = 1.0
                
                let canvasPoint = canvasView.convert(event.locationInWindow, from: nil)
                let viewportX = canvasPoint.x - clipView.bounds.origin.x
                let viewportY = canvasPoint.y - clipView.bounds.origin.y
                let viewW = clipView.bounds.width
                let viewH = clipView.bounds.height
                
                let clampedViewportX = min(max(0, viewportX), viewW)
                let clampedViewportY = min(max(0, viewportY), viewH)
                pinchViewportOffset = CGPoint(x: clampedViewportX, y: clampedViewportY)
                
                let effectiveCanvasX = clipView.bounds.origin.x + clampedViewportX
                let effectiveCanvasY = clipView.bounds.origin.y + clampedViewportY
                
                let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? viewModel.displayScale : 1.0)
                let unscaledY = max(0, (effectiveCanvasY - 16) / (pinchBaseZoom * baseScale))
                let pageIdx = viewModel.effectivePageIndex(atYOffset: unscaledY)
                pinchAnchorPage = pageIdx
                
                if let pFrame = canvasView.pageFrame(for: pageIdx) {
                    pinchRelX = (effectiveCanvasX - pFrame.minX) / max(1, pFrame.width)
                    pinchRelY = (effectiveCanvasY - pFrame.minY) / max(1, pFrame.height)
                } else {
                    pinchRelX = 0.5
                    pinchRelY = 0.5
                }
            }
            
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                isPinching = false
                let finalZoom = min(max(pinchBaseZoom * pinchAccumulatedScale, 0.10), 4.0)
                viewModel.setZoom(finalZoom)
                return
            }
            
            pinchAccumulatedScale *= (1.0 + event.magnification)
            let targetZoom = pinchBaseZoom * pinchAccumulatedScale
            let clampedZoom = min(max(targetZoom, 0.10), 4.0)
            
            if abs(clampedZoom - viewModel.zoomScale) < 0.0001 { return }
            
            lastZoomScale = clampedZoom
            viewModel.zoomScale = clampedZoom
            
            let sideways = viewModel.viewRotationDegrees == 90 || viewModel.viewRotationDegrees == 270
            let widestPage = doc.pageBounds.map { sideways ? $0.height : $0.width }.max() ?? 612
            let maxDocWidth = viewModel.isTwoPageMode ? (widestPage * 2 + 16) : widestPage
            let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? viewModel.displayScale : 1.0)
            let effectiveClamped = clampedZoom * baseScale
            let contentWidth = max(clipView.bounds.width, (maxDocWidth * effectiveClamped) + 64)
            let contentHeight = (viewModel.effectiveTotalHeight * effectiveClamped) + 48
            let newCanvasFrame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
            if canvasView.frame != newCanvasFrame {
                canvasView.frame = newCanvasFrame
            }
            
            let maxScrollX = max(0, contentWidth - clipView.bounds.width)
            let maxScrollY = max(0, contentHeight - clipView.bounds.height)
            
            let newAnchorCanvasX: CGFloat
            let newAnchorCanvasY: CGFloat
            if let newFrame = canvasView.pageFrame(for: pinchAnchorPage) {
                newAnchorCanvasX = newFrame.minX + (pinchRelX * newFrame.width)
                newAnchorCanvasY = newFrame.minY + (pinchRelY * newFrame.height)
            } else {
                newAnchorCanvasX = contentWidth / 2
                newAnchorCanvasY = contentHeight / 2
            }
            
            let newScrollX = min(max(0, newAnchorCanvasX - pinchViewportOffset.x), maxScrollX)
            let newScrollY = min(max(0, newAnchorCanvasY - pinchViewportOffset.y), maxScrollY)
            
            isProgrammaticScroll = true
            clipView.scroll(to: NSPoint(x: newScrollX, y: newScrollY))
            scrollView.reflectScrolledClipView(clipView)
            isProgrammaticScroll = false
            canvasView.needsDisplay = true
        }
        
        func handleSmartMagnify(with event: NSEvent) {
            guard let scrollView = self.scrollView,
                  let canvasView = self.canvasView,
                  let doc = viewModel.document else { return }
            
            let clipView = scrollView.contentView
            let canvasPoint = canvasView.convert(event.locationInWindow, from: nil)
            let viewportX = canvasPoint.x - clipView.bounds.origin.x
            let viewportY = canvasPoint.y - clipView.bounds.origin.y
            let viewW = clipView.bounds.width
            let viewH = clipView.bounds.height
            
            let clampedViewportX = min(max(0, viewportX), viewW)
            let clampedViewportY = min(max(0, viewportY), viewH)
            let effectiveCanvasX = clipView.bounds.origin.x + clampedViewportX
            let effectiveCanvasY = clipView.bounds.origin.y + clampedViewportY
            
            let unscaledY = max(0, (effectiveCanvasY - 16) / viewModel.effectiveZoom)
            let pageIdx = viewModel.effectivePageIndex(atYOffset: unscaledY)
            
            let targetZoom: CGFloat = (abs(viewModel.zoomScale - 1.0) < 0.05) ? 2.0 : 1.0
            
            if let pFrame = canvasView.pageFrame(for: pageIdx) {
                let relX = (effectiveCanvasX - pFrame.minX) / max(1, pFrame.width)
                let relY = (effectiveCanvasY - pFrame.minY) / max(1, pFrame.height)
                
                viewModel.zoomScale = targetZoom
                lastZoomScale = targetZoom
                
                let sideways = viewModel.viewRotationDegrees == 90 || viewModel.viewRotationDegrees == 270
                let widestPage = doc.pageBounds.map { sideways ? $0.height : $0.width }.max() ?? 612
                let maxDocWidth = viewModel.isTwoPageMode ? (widestPage * 2 + 16) : widestPage
                let baseScale = (PDFViewerAppCoordinator.shared.scaleMode == .physical ? viewModel.displayScale : 1.0)
                let effectiveTarget = targetZoom * baseScale
                let contentWidth = max(clipView.bounds.width, (maxDocWidth * effectiveTarget) + 64)
                let contentHeight = (viewModel.effectiveTotalHeight * effectiveTarget) + 48
                canvasView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
                
                if let newFrame = canvasView.pageFrame(for: pageIdx) {
                    let maxScrollX = max(0, contentWidth - clipView.bounds.width)
                    let maxScrollY = max(0, contentHeight - clipView.bounds.height)
                    let newAnchorX = newFrame.minX + (relX * newFrame.width)
                    let newAnchorY = newFrame.minY + (relY * newFrame.height)
                    let newScrollX = min(max(0, newAnchorX - clampedViewportX), maxScrollX)
                    let newScrollY = min(max(0, newAnchorY - clampedViewportY), maxScrollY)
                    
                    isProgrammaticScroll = true
                    clipView.scroll(to: NSPoint(x: newScrollX, y: newScrollY))
                    scrollView.reflectScrolledClipView(clipView)
                    isProgrammaticScroll = false
                }
                
                viewModel.setZoom(targetZoom)
            }
        }
        
        @objc func clipViewBoundsDidChange(_ notification: Notification) {
            guard !isProgrammaticScroll, viewModel.document != nil, let scrollView = self.scrollView else { return }
            
            let clipView = scrollView.contentView
            let currentScrollY = max(0, clipView.bounds.origin.y - 16)
            let unscaledY = currentScrollY / viewModel.effectiveZoom
            
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

