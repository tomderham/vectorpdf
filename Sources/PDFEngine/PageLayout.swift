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

import CoreGraphics

/// Where every page sits in the document view: one page at a time or facing pages in spreads,
/// down the window or across it, upright or turned. Sizes are at a zoom of 1; the methods that
/// take a zoom and a canvas size place pages on the canvas.
///
/// Pages are grouped (a single page, or the two pages of a spread), and the pages of a group sit
/// side by side. Groups follow one another down the canvas, each centred across it, or along it
/// left to right, each centred up and down. Next and Previous Page step from group to group.
public struct PageLayout: Equatable, Sendable {
    public enum Arrangement: Equatable, Sendable {
        /// A page at a time.
        case singlePages
        /// Facing pages, book style: the cover alone on the right, then (1, 2), (3, 4)…, odd
        /// pages on the left.
        case spreads
    }

    public enum Direction: Equatable, Sendable {
        /// Pages run down the canvas.
        case vertical
        /// Pages run left to right.
        case horizontal
    }

    /// The gap between pages, and between groups down the canvas, at a zoom of 1.
    public static let pageGap: CGFloat = 16
    /// The gap between spreads across the canvas, wider than that between a spread's pages.
    public static let spreadGap: CGFloat = 48
    /// The smallest gap above and below the pages, in canvas points.
    public static let topMargin: CGFloat = 16
    /// The smallest gap left and right of the pages, in canvas points.
    public static let sideMargin: CGFloat = 32
    /// Canvas points added below the last group's gap, down the canvas.
    public static let bottomPadding: CGFloat = 48

    public let arrangement: Arrangement
    public let direction: Direction
    /// Each page's size on screen, at a zoom of 1: its bounds, turned with the view.
    public let pageSizes: [CGSize]
    /// Each page's top-left corner in its group.
    let originsInGroup: [CGPoint]
    /// The group each page is in.
    let groupOfPage: [Int]
    /// Each group's pages, in order.
    let groups: [ClosedRange<Int>]
    /// Each group's place at a zoom of 1: from the first group's start along the canvas, at 0 across it.
    let groupFrames: [CGRect]
    /// The gap after each group along the canvas.
    let gapAfterGroup: [CGFloat]
    /// How far the groups and the gaps after them reach along the canvas.
    let length: CGFloat
    /// The largest group across the canvas.
    let breadth: CGFloat

    public static let empty = PageLayout(pageBounds: [], rotation: 0, arrangement: .singlePages)

    public init(pageBounds: [CGRect], rotation: Int, arrangement: Arrangement, direction: Direction = .vertical) {
        let sideways = rotation == 90 || rotation == 270
        let sizes = pageBounds.map { sideways ? CGSize(width: $0.height, height: $0.width) : $0.size }
        self.arrangement = arrangement
        self.direction = direction
        self.pageSizes = sizes

        var groups: [ClosedRange<Int>] = []
        switch arrangement {
        case .singlePages:
            groups = sizes.indices.map { $0...$0 }
        case .spreads:
            if !sizes.isEmpty { groups.append(0...0) }
            var left = 1
            while left < sizes.count {
                groups.append(left...min(left + 1, sizes.count - 1))
                left += 2
            }
        }

        let gap = Self.pageGap
        let groupGap = direction == .horizontal && arrangement == .spreads ? Self.spreadGap : gap
        var origins = [CGPoint](repeating: .zero, count: sizes.count)
        var groupOfPage = [Int](repeating: 0, count: sizes.count)
        var frames: [CGRect] = []
        frames.reserveCapacity(groups.count)
        var position: CGFloat = 0
        for (index, group) in groups.enumerated() {
            let width: CGFloat
            switch arrangement {
            case .singlePages:
                width = sizes[group.lowerBound].width
            case .spreads where group.lowerBound == 0:
                // The cover sits where a right-hand page would, beside page 1's slot.
                let leftSlot = sizes.count > 1 ? sizes[1].width : sizes[0].width
                origins[0].x = leftSlot + gap
                width = leftSlot + gap + sizes[0].width
            case .spreads:
                let leftWidth = sizes[group.lowerBound].width
                // A last page with no partner keeps a right-hand slot as wide as itself.
                let rightSlot = group.count > 1 ? sizes[group.upperBound].width : leftWidth
                if group.count > 1 { origins[group.upperBound].x = leftWidth + gap }
                width = leftWidth + gap + rightSlot
            }
            var height: CGFloat = 0
            for page in group {
                groupOfPage[page] = index
                height = max(height, sizes[page].height)
            }
            switch direction {
            case .vertical:
                frames.append(CGRect(x: 0, y: position, width: width, height: height))
                position += height + gap
            case .horizontal:
                frames.append(CGRect(x: position, y: 0, width: width, height: height))
                position += width + groupGap
            }
        }
        self.originsInGroup = origins
        self.groupOfPage = groupOfPage
        self.groups = groups
        self.groupFrames = frames
        self.gapAfterGroup = groups.map { _ in direction == .vertical ? gap : groupGap }
        self.length = position
        self.breadth = frames.map { direction == .vertical ? $0.width : $0.height }.max() ?? 0
    }

    public var pageCount: Int { pageSizes.count }

    /// The pages' extent at a zoom of 1, leaving out the margins: down the canvas, the gap after
    /// each row is included.
    public var contentSize: CGSize {
        switch direction {
        case .vertical: CGSize(width: breadth, height: length)
        case .horizontal: CGSize(width: stripLength, height: breadth)
        }
    }

    /// The height of the pages at a zoom of 1: see `contentSize`.
    public var totalHeight: CGFloat { contentSize.height }

    /// Each page's top, at a zoom of 1 from the first group's top.
    public var pageYOffsets: [CGFloat] {
        originsInGroup.indices.map { groupFrames[groupOfPage[$0]].minY + originsInGroup[$0].y }
    }

    /// Across the canvas, the groups from the first's left edge to the last's right edge.
    private var stripLength: CGFloat { max(0, length - (gapAfterGroup.last ?? 0)) }

    // MARK: - On the canvas

    /// The canvas size that holds every page at `zoom`, at least as large as the view across the
    /// direction the pages run, and as wide as it either way.
    public func canvasSize(zoom: CGFloat, viewportSize: CGSize) -> CGSize {
        switch direction {
        case .vertical:
            CGSize(width: max(viewportSize.width, breadth * zoom + 2 * Self.sideMargin),
                   height: length * zoom + Self.bottomPadding)
        case .horizontal:
            CGSize(width: max(viewportSize.width, stripLength * zoom + 2 * Self.sideMargin),
                   height: max(viewportSize.height, breadth * zoom + 2 * Self.topMargin))
        }
    }

    /// Where group `group` sits on a canvas `canvasSize`, at `zoom`: its pages and any empty
    /// slot beside them.
    private func canvasFrame(ofGroup group: Int, zoom: CGFloat, canvasSize: CGSize) -> CGRect {
        let frame = groupFrames[group]
        let width = frame.width * zoom, height = frame.height * zoom
        switch direction {
        case .vertical:
            return CGRect(x: max(Self.sideMargin, (canvasSize.width - width) / 2),
                          y: Self.topMargin + frame.minY * zoom, width: width, height: height)
        case .horizontal:
            return CGRect(x: stripStart(zoom: zoom, canvasWidth: canvasSize.width) + frame.minX * zoom,
                          y: max(Self.topMargin, (canvasSize.height - height) / 2), width: width, height: height)
        }
    }

    /// Where the groups start along the canvas: the strip of pages is centred when it's narrower.
    private func stripStart(zoom: CGFloat, canvasWidth: CGFloat) -> CGFloat {
        max(Self.sideMargin, (canvasWidth - stripLength * zoom) / 2)
    }

    /// Where page `page` sits on a canvas `canvasSize`, at `zoom`.
    public func frame(for page: Int, zoom: CGFloat, canvasSize: CGSize) -> CGRect? {
        guard originsInGroup.indices.contains(page) else { return nil }
        let group = canvasFrame(ofGroup: groupOfPage[page], zoom: zoom, canvasSize: canvasSize)
        let origin = originsInGroup[page], size = pageSizes[page]
        return CGRect(x: group.minX + origin.x * zoom, y: group.minY + origin.y * zoom,
                      width: size.width * zoom, height: size.height * zoom)
    }

    /// The space page `page`'s group takes on the canvas: its pages and any empty slot beside them.
    public func groupFrame(containing page: Int, zoom: CGFloat, canvasSize: CGSize) -> CGRect? {
        guard groupOfPage.indices.contains(page) else { return nil }
        return canvasFrame(ofGroup: groupOfPage[page], zoom: zoom, canvasSize: canvasSize)
    }

    /// The group whose start is the last at or before canvas point `position` along the canvas,
    /// or the first group before them all.
    private func group(atCanvasPosition position: CGFloat, zoom: CGFloat, canvasSize: CGSize) -> Int {
        let start = direction == .vertical ? Self.topMargin : stripStart(zoom: zoom, canvasWidth: canvasSize.width)
        let offset = max(0, (position - start) / zoom)
        var low = 0, high = groupFrames.count - 1, result = 0
        while low <= high {
            let mid = (low + high) / 2
            let groupStart = direction == .vertical ? groupFrames[mid].minY : groupFrames[mid].minX
            if groupStart <= offset {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// The pages `rect` on the canvas may show, with one either side to spare.
    public func pages(in rect: CGRect, zoom: CGFloat, canvasSize: CGSize) -> ClosedRange<Int>? {
        guard !groups.isEmpty, zoom > 0 else { return nil }
        let (from, to) = direction == .vertical ? (rect.minY, rect.maxY) : (rect.minX, rect.maxX)
        let first = groups[group(atCanvasPosition: from, zoom: zoom, canvasSize: canvasSize)].lowerBound
        let last = groups[group(atCanvasPosition: to, zoom: zoom, canvasSize: canvasSize)].upperBound
        return max(0, first - 1)...min(pageCount - 1, last + 1)
    }

    /// The page at or nearest before `point` on the canvas: in a spread, the one on its side.
    public func page(at point: CGPoint, zoom: CGFloat, canvasSize: CGSize) -> Int {
        guard !groups.isEmpty else { return 0 }
        let position = direction == .vertical ? point.y : point.x
        let pages = groups[group(atCanvasPosition: position, zoom: zoom, canvasSize: canvasSize)]
        return pages.last { frame(for: $0, zoom: zoom, canvasSize: canvasSize)!.minX <= point.x } ?? pages.lowerBound
    }

    /// The group being read in `visible`, a view of the canvas: down the canvas, the one a little
    /// below the top; across it, the first more than half in view.
    public func leadingGroup(in visible: CGRect, zoom: CGFloat, canvasSize: CGSize) -> ClosedRange<Int>? {
        guard !groups.isEmpty else { return nil }
        switch direction {
        case .vertical:
            let readingLine = max(visible.minY, Self.topMargin) + 80 * zoom
            return groups[group(atCanvasPosition: readingLine, zoom: zoom, canvasSize: canvasSize)]
        case .horizontal:
            var index = group(atCanvasPosition: visible.minX, zoom: zoom, canvasSize: canvasSize)
            if canvasFrame(ofGroup: index, zoom: zoom, canvasSize: canvasSize).midX < visible.minX, index + 1 < groups.count {
                index += 1
            }
            return groups[index]
        }
    }

    /// Where to scroll a view `viewportSize` to show page `page`'s group from its start: at the
    /// top, centred across; or at the left, centred up and down. The first group shows the margin
    /// before it too.
    public func scrollOrigin(toShow page: Int, zoom: CGFloat, canvasSize: CGSize, viewportSize: CGSize) -> CGPoint? {
        guard groupOfPage.indices.contains(page) else { return nil }
        let index = groupOfPage[page]
        let frame = canvasFrame(ofGroup: index, zoom: zoom, canvasSize: canvasSize)
        let maxX = max(0, canvasSize.width - viewportSize.width), maxY = max(0, canvasSize.height - viewportSize.height)
        func clamp(_ value: CGFloat, _ upper: CGFloat) -> CGFloat { min(max(0, value), upper) }
        switch direction {
        case .vertical:
            return CGPoint(x: clamp(frame.midX - viewportSize.width / 2, maxX),
                           y: index == 0 ? 0 : clamp(frame.minY, maxY))
        case .horizontal:
            // The gap before the group shows, and none of the page before it.
            let gapBefore = index == 0 ? 0 : gapAfterGroup[index - 1] * zoom
            return CGPoint(x: index == 0 ? 0 : clamp(frame.minX - gapBefore, maxX),
                           y: clamp(frame.midY - viewportSize.height / 2, maxY))
        }
    }

    /// Across the canvas, the page to scroll to to show the next screenful after `visible`: the
    /// first group that isn't wholly in view. Nil when the last page is in view.
    public func pageAfterScreen(_ visible: CGRect, from page: Int, zoom: CGFloat, canvasSize: CGSize) -> Int? {
        guard groupOfPage.indices.contains(page) else { return nil }
        let current = groupOfPage[page]
        for index in (current + 1)..<max(current + 1, groups.count) {
            if canvasFrame(ofGroup: index, zoom: zoom, canvasSize: canvasSize).maxX > visible.maxX + 0.5 {
                return groups[index].lowerBound
            }
        }
        return nil
    }

    /// Across the canvas, the page to scroll to to show the screenful before the one starting at
    /// `page`'s group, in a view `viewportWidth` wide: as many groups as fit wholly, ending with
    /// the one before. Nil at the first page.
    public func pageBeforeScreen(from page: Int, viewportWidth: CGFloat, zoom: CGFloat, canvasSize: CGSize) -> Int? {
        guard groupOfPage.indices.contains(page), groupOfPage[page] > 0 else { return nil }
        let previous = groupOfPage[page] - 1
        let end = canvasFrame(ofGroup: previous, zoom: zoom, canvasSize: canvasSize).maxX
        var first = previous
        while first > 0 {
            let candidate = first - 1
            let start = canvasFrame(ofGroup: candidate, zoom: zoom, canvasSize: canvasSize).minX
            let gapBefore = candidate == 0 ? 0 : gapAfterGroup[candidate - 1] * zoom
            guard end - (start - gapBefore) <= viewportWidth else { break }
            first = candidate
        }
        return groups[first].lowerBound
    }

    /// About how many pages a view `viewportSize` can show at once at `zoom`, for the render cache.
    public func pagesInView(viewportSize: CGSize, zoom: CGFloat) -> Int {
        guard zoom > 0, !pageSizes.isEmpty else { return 1 }
        let smallest = direction == .vertical
            ? (pageSizes.map(\.height).min() ?? 1)
            : (pageSizes.map(\.width).min() ?? 1)
        let extent = direction == .vertical ? viewportSize.height : viewportSize.width
        let perGroup = arrangement == .spreads ? 2 : 1
        return min(pageCount, (Int(extent / max(1, (smallest + Self.pageGap) * zoom)) + 2) * perGroup)
    }

    // MARK: - Groups

    /// The pages in the same group as `page`: the spread it's in, or just itself.
    public func group(containing page: Int) -> ClosedRange<Int>? {
        groupOfPage.indices.contains(page) ? groups[groupOfPage[page]] : nil
    }

    /// The width of `page`'s group, at a zoom of 1: what Fit Width and Fit Page fit.
    public func groupWidth(containing page: Int) -> CGFloat? {
        groupOfPage.indices.contains(page) ? groupFrames[groupOfPage[page]].width : nil
    }

    /// The first page of the group after `page`'s, if there is one.
    public func firstPageOfNextGroup(after page: Int) -> Int? {
        guard groupOfPage.indices.contains(page) else { return nil }
        let next = groupOfPage[page] + 1
        return groups.indices.contains(next) ? groups[next].lowerBound : nil
    }

    /// The first page of the group before `page`'s, if there is one.
    public func firstPageOfPreviousGroup(before page: Int) -> Int? {
        guard groupOfPage.indices.contains(page) else { return nil }
        let previous = groupOfPage[page] - 1
        return previous >= 0 ? groups[previous].lowerBound : nil
    }
}
