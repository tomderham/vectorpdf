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

import SwiftUI
import AppKit
import Combine

/// Lightweight AppKit bridge to attach NSWindow reference to views and enable native window tabbing.
///
/// Coordinator tracks the last reported window so `onWindow` fires only on actual changes,
/// preventing redundant view re-renders.
public struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    let onWindowAttach: ((NSWindow) -> Void)?

    /// - Parameter onWindowAttach: Callback executed synchronously when the view attaches to its window.
    public init(onWindow: @escaping (NSWindow) -> Void, onWindowAttach: ((NSWindow) -> Void)? = nil) {
        self.onWindow = onWindow
        self.onWindowAttach = onWindowAttach
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public final class Coordinator {
        weak var lastReportedWindow: NSWindow?
    }

    public func makeNSView(context: Context) -> NSView {
        let view = AttachAwareView()
        view.onAttach = { [onWindowAttach] window in
            onWindowAttach?(window)
        }
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

    private final class AttachAwareView: NSView {
        var onAttach: ((NSWindow) -> Void)?
        private var didAttach = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didAttach, let window else { return }
            didAttach = true
            onAttach?(window)
        }
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

    public override func mouseDown(with event: NSEvent) {
        if let canvas = documentView as? PDFCanvasView {
            window?.makeFirstResponder(canvas)
        }
        super.mouseDown(with: event)
    }

    /// When the user last scrolled this view with a mouse wheel or trackpad, which a Compare
    /// Documents tab uses to tell the document being read from the one following it.
    private(set) var lastUserScroll: Date = .distantPast

    public override func scrollWheel(with event: NSEvent) {
        lastUserScroll = Date()
        super.scrollWheel(with: Self.wheelTurnedSideways(event, pagesRunAcross: coordinator?.viewModel.pageLayout.direction == .horizontal,
                                                         fitsTheHeight: (documentView?.frame.height ?? 0) <= contentView.bounds.height + 1))
    }

    /// A mouse wheel only scrolls up and down, so with pages laid across the window and nothing
    /// to scroll up or down, it scrolls across them instead. A trackpad swipes either way already.
    static func wheelTurnedSideways(_ event: NSEvent, pagesRunAcross: Bool, fitsTheHeight: Bool) -> NSEvent {
        guard pagesRunAcross, fitsTheHeight, !event.hasPreciseScrollingDeltas,
              event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let turned = event.cgEvent?.copy() else { return event }
        let fields: [(vertical: CGEventField, horizontal: CGEventField)] = [
            (.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2),
            (.scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2),
            (.scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2),
        ]
        for (vertical, horizontal) in fields {
            if vertical == .scrollWheelEventFixedPtDeltaAxis1 {
                turned.setDoubleValueField(horizontal, value: turned.getDoubleValueField(vertical))
                turned.setDoubleValueField(vertical, value: 0)
            } else {
                turned.setIntegerValueField(horizontal, value: turned.getIntegerValueField(vertical))
                turned.setIntegerValueField(vertical, value: 0)
            }
        }
        return NSEvent(cgEvent: turned) ?? event
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
        // Two-finger scrolling pans in any direction once zoomed in, not one axis at a time.
        scrollView.usesPredominantAxisScrolling = false
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
        viewModel.hostScrollView = scrollView
        viewModel.viewportReadout.centerOn = { [weak coordinator = context.coordinator] page, point in
            coordinator?.center(onPage: page, at: point)
        }
        context.coordinator.installRulers(in: scrollView)
        
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
        private var lastEffectiveZoom: CGFloat = 1.0
        private var lastDisplayScale: CGFloat = 1.0
        private var lastNavigatedPage: Int = -1
        private var lastIsTwoPageMode: Bool = false
        private var lastIsHorizontal: Bool = false
        /// True while a page turn across the window animates, so the pages it passes don't become current.
        private var isAnimatingPageTurn = false
        /// Counts page turns, so a finished animation only clears `isAnimatingPageTurn` if it was the last.
        private var pageTurnGeneration = 0
        /// The place last gone to (a search result, a link's destination, a comment), at `y` in
        /// page space on `page`, and where the view was left showing it. Until the view moves
        /// from there, the ToC follows that place rather than the reading line: a result shown
        /// mid-view can be in a later section than the line near the top.
        private var revealedPlace: (page: Int, y: CGFloat, origin: CGPoint)?
        private var lastViewRotationDegrees: Int = 0
        private var lastSearchMatchIndex: Int = -1
        private var lastScrolledTargetId: String? = nil
        private var lastSearchJumpToken: Int = -1
        private var lastSnapshotJumpToken: Int = -1
        private var lastAnnotationRevealToken: Int = -1
        private var lastSyncTeXRevealToken: Int = -1
        private var lastOutlineJumpToken: Int = -1
        private var rulerCancellable: AnyCancellable?
        
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
            self.lastIsTwoPageMode = viewModel.isTwoPageMode
            self.lastIsHorizontal = viewModel.isHorizontalScrolling
            self.lastViewRotationDegrees = viewModel.viewRotationDegrees
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        func update(viewModel: PDFViewerViewModel, scrollView: NSScrollView) {
            defer { updateVisiblePageRect(page: viewModel.currentPageIndex) }
            self.viewModel = viewModel
            guard let doc = viewModel.document, let canvasView = self.canvasView else {
                if lastDocumentPath != nil {
                    lastDocumentPath = nil
                    self.canvasView?.frame = .zero
                }
                return
            }
            
            let clipView = scrollView.contentView
            viewModel.currentViewportSize = clipView.bounds.size
            let isNewDocument = (lastDocumentPath != doc.filePath)
            let isLayoutModeChanged = (lastIsTwoPageMode != viewModel.isTwoPageMode || lastIsHorizontal != viewModel.isHorizontalScrolling
                                       || lastViewRotationDegrees != viewModel.viewRotationDegrees)
            let isZoomChanged = (abs(lastEffectiveZoom - viewModel.effectiveZoom) > 0.001)
            let isPageJump = (viewModel.currentPageIndex != lastNavigatedPage && !isProgrammaticScroll)
            let isMatchNavigation = (viewModel.searchJumpToken != lastSearchJumpToken && (!viewModel.searchResults.isEmpty || !viewModel.redactionMatches.isEmpty))
            let isSnapshotJump = (viewModel.snapshotJumpToken != lastSnapshotJumpToken && viewModel.activeSnapshotTarget != nil)
            let isAnnotationReveal = (viewModel.annotationReveal.map { $0.token != lastAnnotationRevealToken } ?? false)
            let isOutlineJump = (viewModel.outlineJump.map { $0.token != lastOutlineJumpToken } ?? false)
            let isSyncTeXReveal = (viewModel.syncTeXReveal.map { $0.token != lastSyncTeXRevealToken } ?? false)
            
            if isNewDocument {
                lastDocumentPath = doc.filePath
                lastNavigatedPage = 0
                lastEffectiveZoom = viewModel.effectiveZoom
                lastDisplayScale = viewModel.displayScale
                lastIsTwoPageMode = viewModel.isTwoPageMode
                lastIsHorizontal = viewModel.isHorizontalScrolling
                lastViewRotationDegrees = viewModel.viewRotationDegrees
                lastSearchMatchIndex = -1
                lastScrolledTargetId = nil
                lastSearchJumpToken = -1
                lastSnapshotJumpToken = -1
                lastAnnotationRevealToken = viewModel.annotationReveal?.token ?? -1
                lastOutlineJumpToken = viewModel.outlineJump?.token ?? -1
                lastSyncTeXRevealToken = viewModel.syncTeXReveal?.token ?? -1
            }

            if isLayoutModeChanged {
                lastIsTwoPageMode = viewModel.isTwoPageMode
                lastIsHorizontal = viewModel.isHorizontalScrolling
                lastViewRotationDegrees = viewModel.viewRotationDegrees
                lastEffectiveZoom = viewModel.effectiveZoom
                lastDisplayScale = viewModel.displayScale
            }
            
            // 1. Size the canvas to hold the pages as they're laid out.
            let newCanvasFrame = NSRect(origin: .zero, size: viewModel.pageLayout.canvasSize(zoom: viewModel.effectiveZoom, viewportSize: clipView.bounds.size))

            if canvasView.frame != newCanvasFrame {
                isProgrammaticScroll = true
                canvasView.frame = newCanvasFrame
                isProgrammaticScroll = false
            }

            // 2. Handle Zoom Scale Change (Menu / Toolbar / Shortcuts / Display Scale Change) — skipped during layout mode changes
            // so step 3 handles the combined coordinate repositioning cleanly.
            if isZoomChanged && !isNewDocument && !isPinching && !isLayoutModeChanged {
                lastEffectiveZoom = viewModel.effectiveZoom
                lastDisplayScale = viewModel.displayScale
                let targetPage = viewModel.currentPageIndex
                if let pFrame = canvasView.pageFrame(for: targetPage),
                   let groupFrame = viewModel.pageLayout.groupFrame(containing: targetPage, zoom: viewModel.effectiveZoom, canvasSize: canvasView.bounds.size) {
                    // A spread stays centred on its spine.
                    let targetMidX = groupFrame.midX
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

            // 3. Handle Direct Page Jump (e.g. page buttons, thumbnails, or Layout Mode Change)
            if (isPageJump || isNewDocument || isLayoutModeChanged) && !isMatchNavigation && !isSnapshotJump && !isAnnotationReveal && !isOutlineJump && !isSyncTeXReveal {
                lastNavigatedPage = viewModel.currentPageIndex
                let targetPage = viewModel.currentPageIndex
                if targetPage >= 0 && targetPage < doc.pageCount,
                   let origin = viewModel.pageLayout.scrollOrigin(toShow: targetPage, zoom: viewModel.effectiveZoom,
                                                                  canvasSize: canvasView.bounds.size, viewportSize: clipView.bounds.size) {
                    // Across the window, a page turn slides the pages along.
                    if isPageJump && !isNewDocument && !isLayoutModeChanged && viewModel.pageLayout.direction == .horizontal
                        && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        animateScroll(to: origin, clipView: clipView, scrollView: scrollView)
                    } else {
                        pageTurnGeneration += 1
                        isAnimatingPageTurn = false
                        isProgrammaticScroll = true
                        clipView.scroll(to: origin)
                        scrollView.reflectScrolledClipView(clipView)
                        isProgrammaticScroll = false
                    }
                }
            }
            
            // 4. Handle Precise Search Match Scroll
            if isMatchNavigation {
                lastSearchJumpToken = viewModel.searchJumpToken
                lastScrolledTargetId = viewModel.activeScrollTargetId
                lastSearchMatchIndex = viewModel.activeSearchMatchIndex
                let match = viewModel.searchResults.first(where: { $0.id.uuidString == viewModel.activeScrollTargetId })
                    ?? viewModel.redactionMatches.first(where: { $0.id.uuidString == viewModel.activeScrollTargetId })?.result
                    ?? (viewModel.searchResults.indices.contains(viewModel.activeSearchMatchIndex) ? viewModel.searchResults[viewModel.activeSearchMatchIndex] : nil)
                if let match = match {
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

            // 6. Handle an annotation chosen in the Comments sidebar
            if isAnnotationReveal, let reveal = viewModel.annotationReveal {
                lastAnnotationRevealToken = reveal.token
                lastNavigatedPage = reveal.pageIndex
                scroll(toPageRect: reveal.rect, pageIndex: reveal.pageIndex, minimumSize: CGSize(width: 24, height: 20), doc: doc, clipView: clipView, scrollView: scrollView)
            }

            // 7. Handle an outline entry chosen in the sidebar: its heading, if it isn't on screen
            if isOutlineJump, let jump = viewModel.outlineJump {
                lastOutlineJumpToken = jump.token
                lastNavigatedPage = jump.pageIndex
                if let geometry = canvasView.pageGeometry(for: jump.pageIndex),
                   let origin = OutlineJump.scrollOrigin(toShow: geometry.canvasRect(forPageRect: jump.rect), in: clipView.bounds, canvasSize: canvasView.frame.size) {
                    isProgrammaticScroll = true
                    clipView.scroll(to: origin)
                    scrollView.reflectScrolledClipView(clipView)
                    isProgrammaticScroll = false
                }
            }
            
            // 8. Handle a SyncTeX forward search: the line, if it isn't on screen
            if isSyncTeXReveal, let reveal = viewModel.syncTeXReveal {
                lastSyncTeXRevealToken = reveal.token
                lastNavigatedPage = reveal.pageIndex
                scroll(toPageRect: reveal.bounds, pageIndex: reveal.pageIndex, minimumSize: CGSize(width: 24, height: 20), doc: doc, clipView: clipView, scrollView: scrollView)
            }

            canvasView.needsDisplay = true
            canvasView.syncFormControls()
        }
        
        /// Slides the view to `origin`. The pages it passes on the way don't become current: the
        /// page turned to already is.
        private func animateScroll(to origin: CGPoint, clipView: NSClipView, scrollView: NSScrollView) {
            pageTurnGeneration += 1
            isAnimatingPageTurn = true
            let generation = pageTurnGeneration
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                clipView.animator().setBoundsOrigin(origin)
            } completionHandler: { [weak self, weak scrollView, weak clipView] in
                Task { @MainActor in
                    guard let self, self.pageTurnGeneration == generation else { return }
                    self.isAnimatingPageTurn = false
                    if let clipView { scrollView?.reflectScrolledClipView(clipView) }
                }
            }
        }

        private func scrollToMatch(match: SearchResult, doc: PDFDocumentCore, clipView: NSClipView, scrollView: NSScrollView) {
            let pageIdx = match.pageIndex
            guard pageIdx >= 0 && pageIdx < doc.pageCount else { return }
            let pageBounds = doc.pageBounds[pageIdx]
            let matchRect = match.highlightQuads.first?.boundingRect ?? CGRect(x: pageBounds.midX - 100, y: pageBounds.midY - 10, width: 200, height: 20)
            scroll(toPageRect: matchRect, pageIndex: pageIdx, minimumSize: CGSize(width: 20, height: 16), doc: doc, clipView: clipView, scrollView: scrollView)
        }

        private func scrollToSnapshot(snap: SnapshotTarget, doc: PDFDocumentCore, clipView: NSClipView, scrollView: NSScrollView) {
            let pageIdx = snap.targetPage
            guard pageIdx >= 0 && pageIdx < doc.pageCount else { return }
            scroll(toPageRect: viewModel.resolvedTargetRect(for: snap), pageIndex: pageIdx, minimumSize: CGSize(width: 24, height: 20), doc: doc, clipView: clipView, scrollView: scrollView)
        }

        /// Scrolls to show `pageRect` on page `pageIndex`, only as far as needed: see
        /// `ScrollReveal.origin`.
        private func scroll(toPageRect pageRect: CGRect, pageIndex pageIdx: Int, minimumSize: CGSize, doc: PDFDocumentCore, clipView: NSClipView, scrollView: NSScrollView) {
            guard let canvasView = self.canvasView,
                  let geometry = canvasView.pageGeometry(for: pageIdx) else { return }
            var targetCanvasRect = geometry.canvasRect(forPageRect: pageRect)
            targetCanvasRect.size.width = max(targetCanvasRect.width, minimumSize.width)
            targetCanvasRect.size.height = max(targetCanvasRect.height, minimumSize.height)

            let origin = ScrollReveal.origin(toShow: targetCanvasRect, in: clipView.bounds, canvasSize: canvasView.bounds.size)
            if origin != clipView.bounds.origin {
                isProgrammaticScroll = true
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
                isProgrammaticScroll = false
            }
            // Also when the place was on screen already, and the view didn't move.
            revealedPlace = (pageIdx, pageRect.midY, clipView.bounds.origin)
            updateReadingLine(onPage: pageIdx, pageY: pageRect.midY)
        }
        
        func handleMagnify(with event: NSEvent) {
            guard let scrollView = self.scrollView,
                  let canvasView = self.canvasView,
                  viewModel.document != nil else { return }
            
            let clipView = scrollView.contentView
            let isBegan = event.phase.contains(.began) || (!isPinching && !event.phase.contains(.ended) && !event.phase.contains(.cancelled))
            
            if isBegan {
                isPinching = true
                viewModel.isLiveZooming = true
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
                
                let pageIdx = viewModel.pageLayout.page(at: CGPoint(x: effectiveCanvasX, y: effectiveCanvasY),
                                                        zoom: viewModel.effectiveZoom, canvasSize: canvasView.bounds.size)
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
                viewModel.isLiveZooming = false
                let finalZoom = min(max(pinchBaseZoom * pinchAccumulatedScale, 0.10), 4.0)
                viewModel.setZoom(finalZoom)
                return
            }
            
            pinchAccumulatedScale *= (1.0 + event.magnification)
            let targetZoom = pinchBaseZoom * pinchAccumulatedScale
            let clampedZoom = min(max(targetZoom, 0.10), 4.0)
            
            if abs(clampedZoom - viewModel.zoomScale) < 0.0001 { return }
            
            viewModel.zoomScale = clampedZoom
            lastEffectiveZoom = viewModel.effectiveZoom
            lastDisplayScale = viewModel.displayScale
            
            let canvasSize = viewModel.pageLayout.canvasSize(zoom: viewModel.effectiveZoom, viewportSize: clipView.bounds.size)
            let contentWidth = canvasSize.width, contentHeight = canvasSize.height
            let newCanvasFrame = NSRect(origin: .zero, size: canvasSize)
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
                  viewModel.document != nil else { return }
            
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
            
            let pageIdx = viewModel.pageLayout.page(at: CGPoint(x: effectiveCanvasX, y: effectiveCanvasY),
                                                    zoom: viewModel.effectiveZoom, canvasSize: canvasView.bounds.size)
            
            let targetZoom: CGFloat = (abs(viewModel.zoomScale - 1.0) < 0.05) ? 2.0 : 1.0
            
            if let pFrame = canvasView.pageFrame(for: pageIdx) {
                let relX = (effectiveCanvasX - pFrame.minX) / max(1, pFrame.width)
                let relY = (effectiveCanvasY - pFrame.minY) / max(1, pFrame.height)
                
                viewModel.zoomScale = targetZoom
                lastEffectiveZoom = viewModel.effectiveZoom
                lastDisplayScale = viewModel.displayScale
                
                let canvasSize = viewModel.pageLayout.canvasSize(zoom: viewModel.effectiveZoom, viewportSize: clipView.bounds.size)
                let contentWidth = canvasSize.width, contentHeight = canvasSize.height
                canvasView.frame = NSRect(origin: .zero, size: canvasSize)
                
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
            // Before the guard: a programmatic scroll shows new parts of a page too.
            canvasView?.scheduleDetailRenders()
            guard viewModel.document != nil, let scrollView = self.scrollView else { return }

            let clipView = scrollView.contentView
            let visible = clipView.bounds
            let zoom = viewModel.effectiveZoom
            let canvasSize = canvasView?.bounds.size ?? visible.size
            guard let group = viewModel.pageLayout.leadingGroup(in: visible, zoom: zoom, canvasSize: canvasSize) else { return }
            let activePage = viewModel.currentPage(reading: group)
            // Still showing the place gone to (the view resized without moving): its page and
            // section stay current.
            if let place = revealedPlace, place.origin != visible.origin { revealedPlace = nil }
            if let place = revealedPlace {
                updateReadingLine(onPage: place.page, pageY: place.y)
                updateVisiblePageRect(page: place.page)
            } else {
                // Also after a programmatic scroll (a ToC or page jump), which sets the page itself.
                updateReadingLine(onPage: activePage, canvasY: max(visible.minY, PageLayout.topMargin) + 80 * zoom)
                updateVisiblePageRect(page: activePage)
            }
            guard !isProgrammaticScroll, !isAnimatingPageTurn else { return }
            viewModel.currentViewportSize = clipView.bounds.size
            if revealedPlace == nil, activePage != viewModel.currentPageIndex {
                lastNavigatedPage = activePage
                viewModel.currentPageIndex = activePage
                viewModel.pruneCaches(around: activePage)
            }
            canvasView?.syncFormControls()
        }

        /// Tells the navigator which part of `page` is in view, while it shows.
        func updateVisiblePageRect(page: Int) {
            guard PDFViewerAppCoordinator.shared.showsNavigator,
                  let scrollView, let geometry = canvasView?.pageGeometry(for: page) else { return }
            let visible = scrollView.contentView.bounds.intersection(geometry.frame)
            guard !visible.isNull, !visible.isEmpty else {
                viewModel.viewportReadout.setVisible(nil)
                return
            }
            viewModel.viewportReadout.setVisible(VisiblePageRect(pageIndex: page, rect: geometry.pageRect(forCanvasRect: visible)))
        }

        /// Scrolls so that `pagePoint` on `page` is in the middle of the view (the navigator).
        func center(onPage page: Int, at pagePoint: CGPoint) {
            guard let scrollView, let canvasView, let geometry = canvasView.pageGeometry(for: page) else { return }
            let clipView = scrollView.contentView
            let target = geometry.canvasPoint(forPagePoint: pagePoint)
            let size = clipView.bounds.size
            let origin = CGPoint(
                x: min(max(0, target.x - size.width / 2), max(0, canvasView.bounds.width - size.width)),
                y: min(max(0, target.y - size.height / 2), max(0, canvasView.bounds.height - size.height))
            )
            clipView.scroll(to: origin)
            scrollView.reflectScrolledClipView(clipView)
        }

        /// Gives the scroll view its rulers, shown while View > Show Rulers is on.
        func installRulers(in scrollView: NSScrollView) {
            guard let canvasView else { return }
            let horizontal = PageRulerView(scrollView: scrollView, orientation: .horizontalRuler, canvas: canvasView)
            let vertical = PageRulerView(scrollView: scrollView, orientation: .verticalRuler, canvas: canvasView)
            scrollView.horizontalRulerView = horizontal
            scrollView.verticalRulerView = vertical
            scrollView.hasHorizontalRuler = true
            scrollView.hasVerticalRuler = true
            scrollView.rulersVisible = PDFViewerAppCoordinator.shared.showsRulers
            rulerCancellable = PDFViewerAppCoordinator.shared.$showsRulers
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak scrollView] shows in scrollView?.rulersVisible = shows }
        }

        /// Tells the view model which section is under the reading line, at canvas height
        /// `canvasY` on page `page`. Outline entries point at places on an upright page, so a
        /// rotated view, or pages laid across the window, leave the ToC to follow the page alone.
        private func updateReadingLine(onPage page: Int, canvasY: CGFloat) {
            guard let geometry = canvasView?.pageGeometry(for: page) else {
                viewModel.clearReadingLine()
                return
            }
            let point = geometry.pagePoint(forCanvasPoint: CGPoint(x: geometry.frame.midX, y: canvasY))
            updateReadingLine(onPage: page, pageY: point.y)
        }

        /// Tells the view model which section holds `pageY` (page space, y down) on `page`.
        private func updateReadingLine(onPage page: Int, pageY: CGFloat) {
            guard viewModel.viewRotationDegrees == 0, viewModel.pageLayout.direction == .vertical else {
                viewModel.clearReadingLine()
                return
            }
            viewModel.updateReadingLine(page: page, y: pageY)
        }
    }
}

