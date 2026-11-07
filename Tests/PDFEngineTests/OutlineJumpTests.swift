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
import SwiftUI
import Testing
@testable import PDFEngine

/// Choosing an outline entry shows its heading, scrolling only when it isn't already on screen.
@Suite(.serialized)
struct OutlineJumpTests {

    // MARK: - Whether to scroll, and where

    private let canvas = CGSize(width: 1000, height: 10_000)

    @Test func aHeadingOnScreenStaysPut() {
        let view = CGRect(x: 0, y: 2000, width: 800, height: 600)
        #expect(OutlineJump.scrollOrigin(toShow: CGRect(x: 100, y: 2300, width: 300, height: 60), in: view, canvasSize: canvas) == nil)
    }

    @Test func aHeadingBelowOrAboveGoesNearTheTop() {
        let view = CGRect(x: 0, y: 2000, width: 800, height: 600)
        let below = CGRect(x: 100, y: 3000, width: 300, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: below, in: view, canvasSize: canvas) == CGPoint(x: 0, y: 2976))
        let above = CGRect(x: 100, y: 1000, width: 300, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: above, in: view, canvasSize: canvas) == CGPoint(x: 0, y: 976))
    }

    /// A heading at the very bottom, with none of its section showing, counts as off screen.
    @Test func aHeadingCutOffAtAnEdgeIsMoved() {
        let view = CGRect(x: 0, y: 2000, width: 800, height: 600)
        let atBottom = CGRect(x: 100, y: 2570, width: 300, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: atBottom, in: view, canvasSize: canvas)?.y == 2546)
        let atTop = CGRect(x: 100, y: 1990, width: 300, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: atTop, in: view, canvasSize: canvas)?.y == 1966)
    }

    /// Zoomed in past the page's width, the view moves across only if the heading is off to
    /// the side, and down only if it's above or below.
    @Test func movesAcrossOnlyWhenTheHeadingIsOffToTheSide() {
        let view = CGRect(x: 0, y: 2000, width: 400, height: 600)
        let offRight = CGRect(x: 600, y: 2200, width: 200, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: offRight, in: view, canvasSize: canvas) == CGPoint(x: 568, y: 2000))
        // A band wider than the view shows if any of it does.
        let wide = CGRect(x: 0, y: 2200, width: 1000, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: wide, in: view, canvasSize: canvas) == nil)
        let wideBelow = CGRect(x: 0, y: 4000, width: 1000, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: wideBelow, in: view, canvasSize: canvas) == CGPoint(x: 0, y: 3976))
    }

    /// A heading wider than the view, scrolled to from elsewhere, shows from its start; one
    /// already showing in part is left as it is.
    @Test func aWideHeadingIsScrolledToFromItsStart() {
        let view = CGRect(x: 500, y: 2000, width: 400, height: 600)
        let wideBelow = CGRect(x: 100, y: 4000, width: 600, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: wideBelow, in: view, canvasSize: canvas) == CGPoint(x: 68, y: 3976))
        let wideShowing = CGRect(x: 100, y: 2200, width: 600, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: wideShowing, in: view, canvasSize: canvas) == nil)
    }

    @Test func staysWithinTheCanvas() {
        let view = CGRect(x: 0, y: 2000, width: 800, height: 600)
        let nearEnd = CGRect(x: 100, y: 9900, width: 300, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: nearEnd, in: view, canvasSize: canvas) == CGPoint(x: 0, y: 9400))
        let nearStart = CGRect(x: 100, y: 10, width: 300, height: 60)
        #expect(OutlineJump.scrollOrigin(toShow: nearStart, in: view, canvasSize: canvas) == CGPoint(x: 0, y: 0))
    }

    /// In each view (side by side, turned), wherever the view starts, after the scroll the
    /// heading shows, and a second request leaves it where it is.
    @Test(arguments: [0, 90, 180, 270], [false, true])
    func headingShowsAfterScrollingInEveryView(rotation: Int, rightHandPage: Bool) {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let sideways = rotation == 90 || rotation == 270
        let zoom: CGFloat = 2
        let size = CGSize(width: (sideways ? bounds.height : bounds.width) * zoom, height: (sideways ? bounds.width : bounds.height) * zoom)
        // The page's footprint: alone, or the right-hand page of a spread.
        let frame = NSRect(x: rightHandPage ? 32 + size.width + 16 : 32, y: 5000, width: size.width, height: size.height)
        let canvasSize = CGSize(width: rightHandPage ? 2 * size.width + 96 : size.width + 64, height: 20_000)
        let geometry = PageGeometry(frame: frame, pageBounds: bounds, zoom: zoom, rotation: rotation)
        let heading = OutlineJump.headingRect(y: 600, pageBounds: bounds, page: nil)
        let target = geometry.canvasRect(forPageRect: heading)
        for start in [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 5000), CGPoint(x: canvasSize.width, y: 6200), CGPoint(x: 900, y: 19_000)] {
            let viewSize = CGSize(width: 700, height: 500)
            let origin = CGPoint(x: min(start.x, canvasSize.width - viewSize.width), y: min(start.y, canvasSize.height - viewSize.height))
            let view = CGRect(origin: origin, size: viewSize)
            let scrolled = OutlineJump.scrollOrigin(toShow: target, in: view, canvasSize: canvasSize) ?? view.origin
            let after = CGRect(origin: scrolled, size: viewSize)
            #expect(OutlineJump.scrollOrigin(toShow: target, in: after, canvasSize: canvasSize) == nil, "\(rotation)° from \(start)")
            #expect(after.intersects(target), "\(rotation)° from \(start)")
        }
    }

    // MARK: - Finding the heading

    @Test func withoutTextTheHeadingIsABandAcrossThePage() {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        #expect(OutlineJump.headingRect(y: 300, pageBounds: bounds, page: nil) == CGRect(x: 0, y: 300, width: 612, height: OutlineJump.roomBelow))
    }

    /// A line of text 5 pt per character and 12 pt tall, starting at (`x`, `y`).
    private func line(_ text: String, x: CGFloat = 72, y: CGFloat) -> TextLine {
        let chars = text.enumerated().map { i, ch in
            TextCharacter(char: ch, quad: PDFQuad(rect: CGRect(x: x + CGFloat(i) * 5, y: y, width: 5, height: 12)),
                          origin: CGPoint(x: x + CGFloat(i) * 5, y: y + 10), size: 10, isBold: false, fontName: "Helvetica")
        }
        return TextLine(bbox: CGRect(x: x, y: y, width: CGFloat(text.count) * 5, height: 12), characters: chars)
    }

    private func page(_ lines: [TextLine]) -> StructuredPage {
        let bbox = lines.dropFirst().reduce(lines[0].bbox) { $0.union($1.bbox) }
        let block = TextBlock(type: .text, bbox: bbox, lines: lines)
        return StructuredPage(pageIndex: 0, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), blocks: [block])
    }

    /// Destinations point above their heading (into the line before, even), or at its
    /// baseline: either way the heading is the line reading like the entry's title.
    @Test func findsTheHeadingWhereverItsDestinationPoints() {
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let text = page([
            line("the end of the section before.", y: 300),
            line("4.2.", y: 330), line("Wind Loads", x: 100, y: 330),
            line("Wind loads act on the structure.", y: 346),
        ])
        for y: CGFloat in [305, 320, 342] {
            let rect = OutlineJump.headingRect(y: y, title: "4.2. Wind Loads", pageBounds: bounds, page: text)
            #expect(rect.minY == min(y, 330) && rect.maxY == 342 + OutlineJump.roomBelow, "y \(y)")
            // The number and words beside it, together.
            #expect(rect.minX == 72 && rect.maxX == 150, "y \(y)")
        }
        // Without a line reading like the title, the first line starting below the destination.
        let untitled = OutlineJump.headingRect(y: 320, title: "Something else", pageBounds: bounds, page: text)
        #expect(untitled.minY == 320 && untitled.maxY == 342 + OutlineJump.roomBelow)
    }

    /// On a real document, the line found below each entry's position is its heading.
    @Test func findsEachHeadingInARealDocument() async throws {
        let url = Fixture.url("rfc9457.pdf")
        let doc = try PDFDocumentCore(filePath: url.path)
        var entries: [PDFOutlineNode] = []
        func visit(_ nodes: [PDFOutlineNode]) {
            for node in nodes {
                if node.targetPage != nil, node.targetY != nil { entries.append(node) }
                visit(node.children)
            }
        }
        visit(doc.outline)
        try #require(entries.count >= 10)

        var checked = 0
        for entry in entries {
            let page = try #require(entry.targetPage)
            let y = try #require(entry.targetY)
            let stext = try #require(doc.loadStructuredPage(for: page))
            let rect = OutlineJump.headingRect(y: y, title: entry.title, pageBounds: doc.pageBounds[page], page: stext)
            // The heading's text is the lines at the top of the rect, above the room below it.
            let headingBand = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - OutlineJump.roomBelow)
            let text = stext.blocks.flatMap(\.lines)
                .filter { headingBand.insetBy(dx: -1, dy: -1).contains($0.bbox) }
                .map(\.text).joined(separator: " ")
            // "3.1. Members of a Problem Details Object" starts with its number.
            let number = try #require(entry.title.split(separator: " ").first)
            #expect(text.contains(number), "\(entry.title): found “\(text)”")
            checked += 1
        }
        #expect(checked >= 10)
    }

    // MARK: - The request

    @Test @MainActor func eachChoiceIsANewRequestEvenOnTheSamePage() async throws {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: Fixture.url("rfc9457.pdf").path)
        let doc = try #require(vm.document)
        let node = try #require(doc.outline.flatMap { [$0] + $0.children }.first { ($0.targetPage ?? 0) > 1 && $0.targetY != nil })
        vm.jumpToOutlineEntry(node)
        let first = try #require(vm.outlineJump)
        #expect(first.pageIndex == node.targetPage && vm.currentPageIndex == node.targetPage)
        vm.jumpToOutlineEntry(node)
        let second = try #require(vm.outlineJump)
        #expect(second.token != first.token)

        // An entry pointing at a page but no place on it goes to the top of the page.
        vm.jumpToOutlineEntry(PDFOutlineNode(title: "Whole page", targetPage: 0))
        #expect(vm.currentPageIndex == 0)
        #expect(vm.outlineJump == second)
    }

    // MARK: - On screen

    @Test(.showsWindows) @MainActor func scrollsToAHeadingOnlyWhenItIsOffScreen() async throws {
        _ = NSApplication.shared
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: Fixture.url("rfc9457.pdf").path)
        let doc = try #require(vm.document)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 450), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PDFVirtualizedScrollView(viewModel: vm))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))

        func entries(_ nodes: [PDFOutlineNode]) -> [PDFOutlineNode] { nodes.flatMap { [$0] + entries($0.children) } }
        // A heading well down its page, so the top of the page doesn't show it.
        let node = try #require(entries(doc.outline).first { ($0.targetPage ?? 0) > 0 && ($0.targetY ?? 0) > 400 })
        let scrollView = try #require(vm.hostScrollView)
        let canvas = try #require(scrollView.documentView as? PDFCanvasView)
        // Shown, and from its start: zoomed in, the heading can be wider than the view.
        func headingShows() throws -> Bool {
            let jump = try #require(vm.outlineJump)
            let target = try #require(canvas.pageGeometry(for: jump.pageIndex)).canvasRect(forPageRect: jump.rect)
            let view = scrollView.contentView.bounds
            return OutlineJump.scrollOrigin(toShow: target, in: view, canvasSize: canvas.frame.size) == nil
                && view.minX <= target.minX && target.minX < view.maxX
        }

        for twoPage in [false, true] {
            if vm.isTwoPageMode != twoPage { vm.toggleTwoPageMode() }
            vm.setZoom(2)
            try await Task.sleep(for: .milliseconds(200))
            #expect(canvas.frame.width > scrollView.contentView.bounds.width, "zoomed in past the view's width")
            vm.jumpToPage(0)
            try await Task.sleep(for: .milliseconds(200))
            vm.jumpToOutlineEntry(node)
            try await Task.sleep(for: .milliseconds(200))
            #expect(try headingShows(), "two pages: \(twoPage)")

            // Scrolled a little, with the heading still showing: choosing it again leaves the view.
            let clip = scrollView.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY - 60))
            scrollView.reflectScrolledClipView(clip)
            try await Task.sleep(for: .milliseconds(100))
            #expect(try headingShows())
            let before = clip.bounds.origin
            vm.jumpToOutlineEntry(node)
            try await Task.sleep(for: .milliseconds(200))
            #expect(clip.bounds.origin == before, "two pages: \(twoPage)")
        }
    }
}
