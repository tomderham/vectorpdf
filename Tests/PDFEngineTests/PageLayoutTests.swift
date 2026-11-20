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
        #expect(layout.contentSize.width == 612)
        // Each page is centred on its own, at least the side margin from the edge.
        #expect(layout.frame(for: 1, zoom: 1, canvasSize: CGSize(width: 1000, height: 4000)) == CGRect(x: 300, y: 824, width: 400, height: 300))
        #expect(layout.frame(for: 0, zoom: 2, canvasSize: CGSize(width: 1000, height: 4000)) == CGRect(x: 32, y: 16, width: 1224, height: 1584))
        #expect(layout.frame(for: 3, zoom: 1, canvasSize: CGSize(width: 1000, height: 4000)) == nil)
        #expect(layout.canvasSize(zoom: 1, viewportSize: CGSize(width: 500, height: 500)) == CGSize(width: 676, height: 1932 + 48))
        #expect(layout.canvasSize(zoom: 1, viewportSize: CGSize(width: 900, height: 500)).width == 900)
    }

    @Test func spreadsPutTheCoverOnTheRightThenPairPages() {
        let layout = PageLayout(pageBounds: Array(repeating: letter, count: 4), rotation: 0, arrangement: .spreads)
        #expect(layout.pageYOffsets == [0, 808, 808, 1616])
        let canvasWidth: CGFloat = 1400, pairX = (canvasWidth - (612 * 2 + 16)) / 2
        #expect(layout.frame(for: 0, zoom: 1, canvasSize: CGSize(width: canvasWidth, height: 4000))?.minX == pairX + 628)
        #expect(layout.frame(for: 1, zoom: 1, canvasSize: CGSize(width: canvasWidth, height: 4000))?.minX == pairX)
        #expect(layout.frame(for: 2, zoom: 1, canvasSize: CGSize(width: canvasWidth, height: 4000))?.minX == pairX + 628)
        // A last page with no partner stays on the left.
        #expect(layout.frame(for: 3, zoom: 1, canvasSize: CGSize(width: canvasWidth, height: 4000))?.minX == pairX)
        #expect(layout.group(containing: 2) == 1...2)
        #expect(layout.groupWidth(containing: 0) == CGFloat(1240))
        #expect(layout.groupFrame(containing: 0, zoom: 1, canvasSize: CGSize(width: canvasWidth, height: 4000))?.midX == canvasWidth / 2)
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
        #expect(layout.contentSize.width == 792)
    }

    @Test func nextAndPreviousStepByRow() {
        let single = PageLayout(pageBounds: Array(repeating: letter, count: 3), rotation: 0, arrangement: .singlePages)
        #expect(single.firstPageOfNextGroup(after: 1) == 2)
        #expect(single.firstPageOfNextGroup(after: 2) == nil)
        #expect(single.firstPageOfPreviousGroup(before: 1) == 0)

        let spreads = PageLayout(pageBounds: Array(repeating: letter, count: 6), rotation: 0, arrangement: .spreads)
        #expect(spreads.firstPageOfNextGroup(after: 0) == 1)
        #expect(spreads.firstPageOfNextGroup(after: 2) == 3)
        #expect(spreads.firstPageOfNextGroup(after: 4) == 5)
        #expect(spreads.firstPageOfNextGroup(after: 5) == nil)
        #expect(spreads.firstPageOfPreviousGroup(before: 4) == 1)
        #expect(spreads.firstPageOfPreviousGroup(before: 2) == 0)
        #expect(spreads.firstPageOfPreviousGroup(before: 0) == nil)
    }

    @Test func pagesInABandIncludeWholeSpreadsAndOneToSpare() {
        let spreads = PageLayout(pageBounds: Array(repeating: letter, count: 7), rotation: 0, arrangement: .spreads)
        let canvas = CGSize(width: 1400, height: 4000)
        // A band inside the second spread (pages 3 and 4) reaches one page either side.
        #expect(spreads.pages(in: CGRect(x: 0, y: 16 + 1700, width: 1400, height: 100), zoom: 1, canvasSize: canvas) == 2...5)
        #expect(spreads.pages(in: CGRect(x: 0, y: 0, width: 1400, height: 10), zoom: 1, canvasSize: canvas) == 0...1)
        #expect(PageLayout.empty.pages(in: CGRect(x: 0, y: 0, width: 100, height: 100), zoom: 1, canvasSize: canvas) == nil)
    }

    // MARK: - Across the window

    let across = PageLayout(pageBounds: Array(repeating: CGRect(x: 0, y: 0, width: 612, height: 792), count: 5),
                            rotation: 0, arrangement: .singlePages, direction: .horizontal)

    @Test func acrossTheWindowPagesRunLeftToRightCentredUpAndDown() {
        let canvas = across.canvasSize(zoom: 1, viewportSize: CGSize(width: 1000, height: 1000))
        // Five pages and four gaps, and the side margins.
        #expect(canvas == CGSize(width: 5 * 612 + 4 * 16 + 64, height: 1000))
        #expect(across.contentSize == CGSize(width: 5 * 612 + 4 * 16, height: 792))
        #expect(across.frame(for: 0, zoom: 1, canvasSize: canvas) == CGRect(x: 32, y: 104, width: 612, height: 792))
        #expect(across.frame(for: 2, zoom: 1, canvasSize: canvas) == CGRect(x: 32 + 2 * 628, y: 104, width: 612, height: 792))
        // Too short for the view, the pages are as far from the top as they need, no further.
        let short = across.canvasSize(zoom: 1, viewportSize: CGSize(width: 1000, height: 400))
        #expect(short.height == CGFloat(792 + 32))
        #expect(across.frame(for: 0, zoom: 1, canvasSize: short)?.minY == 16)
    }

    @Test func acrossTheWindowAFewPagesAreCentred() {
        let two = PageLayout(pageBounds: [letter, letter], rotation: 0, arrangement: .singlePages, direction: .horizontal)
        let canvas = two.canvasSize(zoom: 1, viewportSize: CGSize(width: 2000, height: 1000))
        #expect(canvas.width == 2000)
        #expect(two.frame(for: 0, zoom: 1, canvasSize: canvas)?.minX == CGFloat((2000 - 1240) / 2))
    }

    @Test func acrossTheWindowSpreadsHaveAWiderGapBetweenThem() {
        let spreads = PageLayout(pageBounds: Array(repeating: letter, count: 5), rotation: 0, arrangement: .spreads, direction: .horizontal)
        let canvas = spreads.canvasSize(zoom: 1, viewportSize: CGSize(width: 800, height: 1000))
        let x = (0..<5).map { spreads.frame(for: $0, zoom: 1, canvasSize: canvas)!.minX }
        // The cover in a right-hand slot, then (1, 2) and (3, 4), 48 apart.
        #expect(x[0] == CGFloat(32 + 628))
        #expect(x[1] == CGFloat(32 + 1240 + 48))
        #expect(x[2] == x[1] + 628)
        #expect(x[3] == x[1] + 1240 + 48)
        #expect(spreads.group(containing: 4) == 3...4)
    }

    @Test func acrossTheWindowLookupsUseTheHorizontalPosition() {
        let canvas = across.canvasSize(zoom: 1, viewportSize: CGSize(width: 1000, height: 1000))
        // A view over pages 1 and 2 may show pages 0…3.
        #expect(across.pages(in: CGRect(x: 32 + 628 + 10, y: 0, width: 1000, height: 1000), zoom: 1, canvasSize: canvas) == 0...3)
        #expect(across.page(at: CGPoint(x: 32 + 2 * 628 + 5, y: 500), zoom: 1, canvasSize: canvas) == 2)
        // The page being read is the first more than half in view.
        #expect(across.leadingGroup(in: CGRect(x: 32 + 628 + 200, y: 0, width: 1000, height: 1000), zoom: 1, canvasSize: canvas) == 1...1)
        #expect(across.leadingGroup(in: CGRect(x: 32 + 628 + 400, y: 0, width: 1000, height: 1000), zoom: 1, canvasSize: canvas) == 2...2)
    }

    @Test func acrossTheWindowTurningToAPageBringsItToTheLeft() {
        let viewport = CGSize(width: 1000, height: 1000)
        let canvas = across.canvasSize(zoom: 1, viewportSize: viewport)
        #expect(across.scrollOrigin(toShow: 0, zoom: 1, canvasSize: canvas, viewportSize: viewport) == CGPoint(x: 0, y: 0))
        // The gap before page 2 shows, and none of page 1.
        #expect(across.scrollOrigin(toShow: 2, zoom: 1, canvasSize: canvas, viewportSize: viewport) == CGPoint(x: 32 + 2 * 628 - 16, y: 0))
        // The last page can't come to the left: the view stops at the end.
        #expect(across.scrollOrigin(toShow: 4, zoom: 1, canvasSize: canvas, viewportSize: viewport)?.x == canvas.width - 1000)
    }

    @Test func acrossTheWindowAScreenfulMovesToTheFirstPageNotWhollyShown() {
        let viewport = CGSize(width: 1400, height: 1000)
        let canvas = across.canvasSize(zoom: 1, viewportSize: viewport)
        // From the start, pages 0 and 1 show whole, and page 2 only in part.
        let start = CGRect(origin: .zero, size: viewport)
        #expect(across.pageAfterScreen(start, from: 0, zoom: 1, canvasSize: canvas) == 2)
        // From page 2, back a screenful: pages 0 and 1 fit before it.
        #expect(across.pageBeforeScreen(from: 2, viewportWidth: 1400, zoom: 1, canvasSize: canvas) == 0)
        #expect(across.pageBeforeScreen(from: 4, viewportWidth: 1400, zoom: 1, canvasSize: canvas) == 2)
        #expect(across.pageBeforeScreen(from: 0, viewportWidth: 1400, zoom: 1, canvasSize: canvas) == nil)
        // With the last page in view, there's no further to go.
        let end = CGRect(x: canvas.width - 1400, y: 0, width: 1400, height: 1000)
        #expect(across.pageAfterScreen(end, from: 3, zoom: 1, canvasSize: canvas) == nil)
    }
}
