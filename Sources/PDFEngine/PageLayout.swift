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

/// Where every page sits in the document view: one page per row, or facing pages in spreads,
/// upright or rotated. Positions are at a zoom of 1, with the canvas's margins left out;
/// `frame(for:zoom:canvasWidth:)` places a page on the canvas.
///
/// Pages are grouped into rows (a single page, or the two pages of a spread). Each row is centred
/// across the canvas on its own, and the pages in a row sit side by side in it. Next and Previous
/// Page step from row to row.
public struct PageLayout: Equatable, Sendable {
    public enum Arrangement: Equatable, Sendable {
        /// One page per row.
        case singlePages
        /// Facing pages, book style: the cover alone on the right, then (1, 2), (3, 4)…, odd
        /// pages on the left.
        case spreads
    }

    /// The gap between rows and between the pages of a spread, at a zoom of 1.
    public static let pageGap: CGFloat = 16
    /// Canvas points above the first row.
    public static let topMargin: CGFloat = 16
    /// The smallest gap left and right of a row, in canvas points.
    public static let sideMargin: CGFloat = 32
    /// Canvas points added below the last row's gap.
    public static let bottomPadding: CGFloat = 48

    public let arrangement: Arrangement
    /// Each page's size on screen, at a zoom of 1: its bounds, turned with the view.
    public let pageSizes: [CGSize]
    /// Each page's top-left corner in its row: x from the row's left edge, y from the first row's top.
    let origins: [CGPoint]
    /// The row each page is in.
    let rowOfPage: [Int]
    /// Each row's pages, in order.
    let rows: [ClosedRange<Int>]
    /// Each row's width, at a zoom of 1, which centres it.
    let rowWidths: [CGFloat]
    /// The height of all the rows and the gaps after them, at a zoom of 1.
    public let totalHeight: CGFloat
    /// The widest row, at a zoom of 1.
    public let widestRow: CGFloat

    public static let empty = PageLayout(pageBounds: [], rotation: 0, arrangement: .singlePages)

    public init(pageBounds: [CGRect], rotation: Int, arrangement: Arrangement) {
        let sideways = rotation == 90 || rotation == 270
        let sizes = pageBounds.map { sideways ? CGSize(width: $0.height, height: $0.width) : $0.size }
        self.arrangement = arrangement
        self.pageSizes = sizes

        var rows: [ClosedRange<Int>] = []
        switch arrangement {
        case .singlePages:
            rows = sizes.indices.map { $0...$0 }
        case .spreads:
            if !sizes.isEmpty { rows.append(0...0) }
            var left = 1
            while left < sizes.count {
                rows.append(left...min(left + 1, sizes.count - 1))
                left += 2
            }
        }

        let gap = Self.pageGap
        var origins = [CGPoint](repeating: .zero, count: sizes.count)
        var rowOfPage = [Int](repeating: 0, count: sizes.count)
        var rowWidths: [CGFloat] = []
        rowWidths.reserveCapacity(rows.count)
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let width: CGFloat
            switch arrangement {
            case .singlePages:
                width = sizes[row.lowerBound].width
            case .spreads where row.lowerBound == 0:
                // The cover sits where a right-hand page would, beside page 1's slot.
                let leftSlot = sizes.count > 1 ? sizes[1].width : sizes[0].width
                origins[0].x = leftSlot + gap
                width = leftSlot + gap + sizes[0].width
            case .spreads:
                let leftWidth = sizes[row.lowerBound].width
                // A last page with no partner keeps a right-hand slot as wide as itself.
                let rightSlot = row.count > 1 ? sizes[row.upperBound].width : leftWidth
                if row.count > 1 { origins[row.upperBound].x = leftWidth + gap }
                width = leftWidth + gap + rightSlot
            }
            var height: CGFloat = 0
            for page in row {
                origins[page].y = y
                rowOfPage[page] = rowIndex
                height = max(height, sizes[page].height)
            }
            rowWidths.append(width)
            y += height + gap
        }
        self.origins = origins
        self.rowOfPage = rowOfPage
        self.rows = rows
        self.rowWidths = rowWidths
        self.totalHeight = y
        self.widestRow = rowWidths.max() ?? 0
    }

    public var pageCount: Int { pageSizes.count }

    /// Each page's top, at a zoom of 1 from the first row's top.
    public var pageYOffsets: [CGFloat] { origins.map(\.y) }

    /// Where page `page` sits on a canvas `canvasWidth` wide, at `zoom`.
    public func frame(for page: Int, zoom: CGFloat, canvasWidth: CGFloat) -> CGRect? {
        guard origins.indices.contains(page) else { return nil }
        let origin = origins[page], size = pageSizes[page]
        let rowX = max(Self.sideMargin, (canvasWidth - rowWidths[rowOfPage[page]] * zoom) / 2)
        return CGRect(x: rowX + origin.x * zoom, y: Self.topMargin + origin.y * zoom,
                      width: size.width * zoom, height: size.height * zoom)
    }

    /// The space page `page`'s row takes on a canvas `canvasWidth` wide, at `zoom`: its pages
    /// and any empty slot beside them.
    public func rowFrame(containing page: Int, zoom: CGFloat, canvasWidth: CGFloat) -> CGRect? {
        guard rowOfPage.indices.contains(page) else { return nil }
        let row = rows[rowOfPage[page]], width = rowWidths[rowOfPage[page]] * zoom
        let height = row.map { pageSizes[$0].height }.max()! * zoom
        return CGRect(x: max(Self.sideMargin, (canvasWidth - width) / 2), y: Self.topMargin + origins[page].y * zoom,
                      width: width, height: height)
    }

    /// The canvas size that holds every page at `zoom`, at least as wide as the view.
    public func canvasSize(zoom: CGFloat, viewportWidth: CGFloat) -> CGSize {
        CGSize(width: max(viewportWidth, widestRow * zoom + 2 * Self.sideMargin),
               height: totalHeight * zoom + Self.bottomPadding)
    }

    /// The pages in the same row as `page`.
    public func row(containing page: Int) -> ClosedRange<Int>? {
        rowOfPage.indices.contains(page) ? rows[rowOfPage[page]] : nil
    }

    /// The width of `page`'s row, at a zoom of 1: what Fit Width and Fit Page fit.
    public func rowWidth(containing page: Int) -> CGFloat? {
        rowOfPage.indices.contains(page) ? rowWidths[rowOfPage[page]] : nil
    }

    /// The first page of the row after `page`'s, if there is one.
    public func firstPageOfNextRow(after page: Int) -> Int? {
        guard rowOfPage.indices.contains(page) else { return nil }
        let next = rowOfPage[page] + 1
        return rows.indices.contains(next) ? rows[next].lowerBound : nil
    }

    /// The first page of the row before `page`'s, if there is one.
    public func firstPageOfPreviousRow(before page: Int) -> Int? {
        guard rowOfPage.indices.contains(page) else { return nil }
        let previous = rowOfPage[page] - 1
        return previous >= 0 ? rows[previous].lowerBound : nil
    }

    /// The last page whose row starts at or above `y` (at a zoom of 1), or 0 above the first.
    public func lastPage(atOrAboveY y: CGFloat) -> Int {
        var low = 0, high = origins.count - 1, result = 0
        while low <= high {
            let mid = (low + high) / 2
            if origins[mid].y <= y {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    /// The pages whose rows a band of the canvas, from `minY` to `maxY` in canvas points at
    /// `zoom`, may cross, with a page either side to spare.
    public func pages(fromCanvasY minY: CGFloat, to maxY: CGFloat, zoom: CGFloat) -> ClosedRange<Int>? {
        guard !origins.isEmpty, zoom > 0 else { return nil }
        let first = row(containing: lastPage(atOrAboveY: max(0, (minY - Self.topMargin) / zoom)))!.lowerBound
        let last = lastPage(atOrAboveY: max(0, (maxY - Self.topMargin) / zoom))
        let start = max(0, first - 1), end = min(origins.count - 1, last + 1)
        return start <= end ? start...end : nil
    }
}
