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
import Testing
@testable import PDFEngine

/// `PageLayout`: where pages sit one to a row, in spreads, and turned.
struct PageLayoutTests {
    let letter = CGRect(x: 0, y: 0, width: 612, height: 792)

    @Test func singlePagesStackWithAGapBetween() {
        let layout = PageLayout(pageBounds: [letter, CGRect(x: 0, y: 0, width: 400, height: 300), letter],
                                rotation: 0, arrangement: .singlePages)
        #expect(layout.pageYOffsets == [0, 808, 1124])
        #expect(layout.totalHeight == CGFloat(1932))
        #expect(layout.widestRow == 612)
        // Each page is centred on its own, at least the side margin from the edge.
        #expect(layout.frame(for: 1, zoom: 1, canvasWidth: 1000) == CGRect(x: 300, y: 824, width: 400, height: 300))
        #expect(layout.frame(for: 0, zoom: 2, canvasWidth: 1000) == CGRect(x: 32, y: 16, width: 1224, height: 1584))
        #expect(layout.frame(for: 3, zoom: 1, canvasWidth: 1000) == nil)
        #expect(layout.canvasSize(zoom: 1, viewportWidth: 500) == CGSize(width: 676, height: 1932 + 48))
        #expect(layout.canvasSize(zoom: 1, viewportWidth: 900).width == 900)
    }

    @Test func spreadsPutTheCoverOnTheRightThenPairPages() {
        let layout = PageLayout(pageBounds: Array(repeating: letter, count: 4), rotation: 0, arrangement: .spreads)
        #expect(layout.pageYOffsets == [0, 808, 808, 1616])
        let canvasWidth: CGFloat = 1400, pairX = (canvasWidth - (612 * 2 + 16)) / 2
        #expect(layout.frame(for: 0, zoom: 1, canvasWidth: canvasWidth)?.minX == pairX + 628)
        #expect(layout.frame(for: 1, zoom: 1, canvasWidth: canvasWidth)?.minX == pairX)
        #expect(layout.frame(for: 2, zoom: 1, canvasWidth: canvasWidth)?.minX == pairX + 628)
        // A last page with no partner stays on the left.
        #expect(layout.frame(for: 3, zoom: 1, canvasWidth: canvasWidth)?.minX == pairX)
        #expect(layout.row(containing: 2) == 1...2)
        #expect(layout.rowWidth(containing: 0) == CGFloat(1240))
        #expect(layout.rowFrame(containing: 0, zoom: 1, canvasWidth: canvasWidth)?.midX == canvasWidth / 2)
    }

    @Test func spreadRowsAreAsTallAsTheirTallerPage() {
        let tall = CGRect(x: 0, y: 0, width: 612, height: 1008)
        let layout = PageLayout(pageBounds: [letter, letter, tall, letter], rotation: 0, arrangement: .spreads)
        #expect(layout.pageYOffsets == [0, 808, 808, 808 + 1024])
    }

    @Test func turningSidewaysSwapsEachPagesWidthAndHeight() {
        let layout = PageLayout(pageBounds: [letter, letter], rotation: 90, arrangement: .singlePages)
        #expect(layout.pageSizes == [CGSize(width: 792, height: 612), CGSize(width: 792, height: 612)])
        #expect(layout.pageYOffsets == [0, 628])
        #expect(layout.widestRow == 792)
    }

    @Test func nextAndPreviousStepByRow() {
        let single = PageLayout(pageBounds: Array(repeating: letter, count: 3), rotation: 0, arrangement: .singlePages)
        #expect(single.firstPageOfNextRow(after: 1) == 2)
        #expect(single.firstPageOfNextRow(after: 2) == nil)
        #expect(single.firstPageOfPreviousRow(before: 1) == 0)

        let spreads = PageLayout(pageBounds: Array(repeating: letter, count: 6), rotation: 0, arrangement: .spreads)
        #expect(spreads.firstPageOfNextRow(after: 0) == 1)
        #expect(spreads.firstPageOfNextRow(after: 2) == 3)
        #expect(spreads.firstPageOfNextRow(after: 4) == 5)
        #expect(spreads.firstPageOfNextRow(after: 5) == nil)
        #expect(spreads.firstPageOfPreviousRow(before: 4) == 1)
        #expect(spreads.firstPageOfPreviousRow(before: 2) == 0)
        #expect(spreads.firstPageOfPreviousRow(before: 0) == nil)
    }

    @Test func pagesInABandIncludeWholeSpreadsAndOneToSpare() {
        let spreads = PageLayout(pageBounds: Array(repeating: letter, count: 7), rotation: 0, arrangement: .spreads)
        // A band inside the second spread (pages 3 and 4) reaches one page either side.
        #expect(spreads.pages(fromCanvasY: 16 + 1700, to: 16 + 1800, zoom: 1) == 2...5)
        #expect(spreads.pages(fromCanvasY: 0, to: 10, zoom: 1) == 0...1)
        #expect(PageLayout.empty.pages(fromCanvasY: 0, to: 100, zoom: 1) == nil)
    }
}
