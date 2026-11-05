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

// A page's bitmap is capped at PDFRenderActor.maxRenderDimension, so a large drawing (an ARCH E
// sheet already needs ~6900 px at 100% on a Retina screen) is drawn soft. For such pages, once
// scrolling and zooming settle, the canvas renders just the visible part, plus a margin, at full
// resolution and draws it over the page bitmap. The page bitmap stays as the backdrop that shows
// while scrolling and while the detail renders.
extension PDFCanvasView {
    struct PageDetail {
        let zoom: CGFloat
        /// The page bitmap this sharpens. A new one (after an edit, layer change or eviction)
        /// makes the detail stale, which is how it notices the page's content changed.
        let base: NSImage
        /// The page rect it covers, in page points.
        let rect: CGRect
        let image: NSImage
        var themed: (appearance: PDFColorAppearance, image: NSImage)?
    }

    struct DetailRequest: Equatable {
        let visible: NSRect
        let zoom: CGFloat
    }

    /// How far beyond the visible area to render, as a fraction of its size each side, so small
    /// scrolls stay sharp.
    static let detailOverscan: CGFloat = 0.25
    /// Pixels a detail's margin may grow it to; the visible part itself is always rendered.
    static let maxDetailPixels: CGFloat = 16_000_000
    static let detailRenderDelay: Duration = .milliseconds(120)

    /// The page rect (page points) to render in detail for this view of a page, or nil if none of
    /// the page is visible.
    static func detailRect(visible: NSRect, geometry: PageGeometry, backingScale: CGFloat) -> CGRect? {
        let pageFrame = geometry.frame
        guard visible.intersects(pageFrame), geometry.zoom > 0 else { return nil }
        let pixels = visible.width * visible.height * backingScale * backingScale
        let fit = pixels > 0 ? (sqrt(maxDetailPixels / pixels) - 1) / 2 : 0
        let margin = min(detailOverscan, max(0, fit))
        let region = visible.insetBy(dx: -visible.width * margin, dy: -visible.height * margin).intersection(pageFrame)
        guard !region.isNull, region.width > 0, region.height > 0 else { return nil }
        return geometry.pageRect(forCanvasRect: region)
    }

    /// Draws the page's detail, if it has a current one, over its bitmap. Called with the graphics
    /// context in the page's layout space (see PageGeometry), so a rotated view turns it with the page.
    func drawPageDetail(_ pageIdx: Int, geometry: PageGeometry) {
        guard var detail = pageDetails[pageIdx], isCurrent(detail, page: pageIdx) else { return }
        let appearance = activeColorAppearance
        var image = detail.image
        if appearance != .light {
            if let themed = detail.themed, themed.appearance == appearance {
                image = themed.image
            } else if let themed = Self.transformedImage(from: detail.image, appearance: appearance) {
                detail.themed = (appearance, themed)
                pageDetails[pageIdx] = detail
                image = themed
            }
        }
        let frame = detail.rect.applying(geometry.pageToLayout)
        // backingAlignedRect aligns canvas rects; a rotated view's layout space is turned.
        let align: (NSRect) -> NSRect = { geometry.isRotated ? $0 : self.backingAlignedRect($0, options: .alignAllEdgesNearest) }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: align(geometry.layoutFrame)).addClip()
        image.draw(in: align(frame))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func isCurrent(_ detail: PageDetail, page: Int) -> Bool {
        detail.zoom == viewModel.effectiveZoom && viewModel.renderedPages[page] === detail.base
    }

    /// Renders details for the visible pages that need them, once the view has been still for
    /// detailRenderDelay. Called on every draw and scroll, so it returns quickly when nothing changed.
    func scheduleDetailRenders() {
        guard let doc = viewModel.document, let window, !viewModel.isLiveZooming else {
            cancelDetailRenders()
            return
        }
        let zoom = viewModel.effectiveZoom
        let backingScale = window.backingScaleFactor
        let scale = zoom * backingScale
        let visible = visibleRect
        guard visible.width > 0, visible.height > 0 else { return }

        let firstPage = viewModel.effectivePageIndex(atYOffset: max(0, (visible.minY - 16) / zoom))
        let lastPage = viewModel.effectivePageIndex(atYOffset: max(0, (visible.maxY - 16) / zoom))
        let start = max(0, firstPage - 1), end = min(doc.pageCount - 1, lastPage + 1)
        guard start <= end else { return }

        var showing = Set<Int>()
        var wanted: [(page: Int, rect: CGRect)] = []
        for page in start...end {
            guard let geometry = pageGeometry(for: page), geometry.frame.intersects(visible), viewModel.hasCurrentRender(of: page) else { continue }
            let pBounds = doc.pageBounds[page]
            guard PDFRenderActor.clampsRender(scale: scale, pageBounds: pBounds) else { continue }
            showing.insert(page)
            if let detail = pageDetails[page], isCurrent(detail, page: page) {
                let shown = geometry.pageRect(forCanvasRect: visible.intersection(geometry.frame))
                if detail.rect.insetBy(dx: -1 / scale, dy: -1 / scale).contains(shown) { continue }
            }
            if let rect = Self.detailRect(visible: visible, geometry: geometry, backingScale: backingScale) {
                wanted.append((page, rect))
            }
        }
        // Only the details on screen are kept: each can be tens of megabytes.
        pageDetails = pageDetails.filter { showing.contains($0.key) && isCurrent($0.value, page: $0.key) }

        guard !wanted.isEmpty else {
            cancelDetailRenders()
            return
        }
        // Unrelated redraws while a render is pending mustn't restart it.
        let request = DetailRequest(visible: visible, zoom: zoom)
        guard request != pendingDetailRequest else { return }
        detailRenderTask?.cancel()
        pendingDetailRequest = request
        detailRenderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.detailRenderDelay)
            guard !Task.isCancelled else { return }
            for (page, rect) in wanted {
                guard let self, let base = self.viewModel.renderedPages[page] else { continue }
                guard let rendered = try? await self.viewModel.renderActor.renderPageDetail(pageIndex: page, rect: rect, scale: scale) else { continue }
                // Kept even if a scroll cancelled this task meanwhile, as long as it still fits.
                if self.viewModel.effectiveZoom == zoom, self.viewModel.renderedPages[page] === base {
                    let size = NSSize(width: rendered.rect.width * zoom, height: rendered.rect.height * zoom)
                    self.pageDetails[page] = PageDetail(zoom: zoom, base: base, rect: rendered.rect, image: NSImage(cgImage: rendered.image, size: size))
                    if let pFrame = self.pageFrame(for: page) { self.setNeedsDisplay(pFrame) }
                }
                if Task.isCancelled { return }
            }
            if self?.pendingDetailRequest == request { self?.pendingDetailRequest = nil }
        }
    }

    func cancelDetailRenders() {
        detailRenderTask?.cancel()
        detailRenderTask = nil
        pendingDetailRequest = nil
    }
}
