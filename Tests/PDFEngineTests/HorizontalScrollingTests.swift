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
import CoreGraphics
import Testing
@testable import PDFEngine

/// Horizontal Scrolling: pages laid out left to right, as many as fit the window.
@MainActor
@Suite(.serialized) struct HorizontalScrollingTests {
    private func open(pages: Int) async -> (PDFViewerViewModel, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_across_\(UUID().uuidString).pdf")
        makeLabelledPDF(at: url, labels: (1...pages).map { "Page \($0)" })
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        return (vm, url)
    }

    @Test func turningItOnKeepsThePageAndFitsTheHeight() async {
        let (vm, url) = await open(pages: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.currentViewportSize = CGSize(width: 1600, height: 900)
        vm.jumpToPage(3)
        vm.toggleHorizontalScrolling()
        #expect(vm.isHorizontalScrolling)
        #expect(vm.pageLayout.direction == .horizontal)
        #expect(vm.currentPageIndex == 3)
        // The pages and their margins fit the view's height, to within the zoom's last step.
        let pagesHeight = 792 * vm.effectiveZoom + 2 * PageLayout.topMargin
        #expect(pagesHeight <= 900)
        #expect(pagesHeight > 900 - 792 * 0.01 * max(1, vm.displayScale) - 1)

        vm.toggleHorizontalScrolling()
        #expect(!vm.isHorizontalScrolling && vm.pageLayout.direction == .vertical)
        #expect(vm.currentPageIndex == 3)
    }

    @Test func itAndTwoPageModeReplaceEachOther() async {
        let (vm, url) = await open(pages: 6)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(vm.isSidebarVisible)
        vm.toggleTwoPageMode()
        #expect(!vm.isSidebarVisible)
        // Turning it on ends Two-Page Mode, bringing the sidebar back.
        vm.toggleHorizontalScrolling()
        #expect(vm.isHorizontalScrolling && !vm.isTwoPageMode)
        #expect(vm.isSidebarVisible)
        #expect(vm.pageLayout.arrangement == .singlePages && vm.pageLayout.direction == .horizontal)
        // And Two-Page Mode ends it.
        vm.toggleTwoPageMode()
        #expect(vm.isTwoPageMode && !vm.isHorizontalScrolling)
        #expect(vm.pageLayout.arrangement == .spreads && vm.pageLayout.direction == .vertical)
    }

    /// The View menu's items are named from this, which the app coordinator keeps for the active
    /// document. (The coordinator is shared with tests running alongside, so it isn't checked here.)
    @Test func theViewMenuIsNamedForTheDocumentsLayout() async {
        let (vm, url) = await open(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ActiveViewState(vm) == ActiveViewState())
        vm.toggleHorizontalScrolling()
        vm.isMarkupBarVisible = true
        var expected = ActiveViewState()
        expected.isHorizontalScrolling = true
        expected.isMarkupBarVisible = true
        #expect(ActiveViewState(vm) == expected)
    }

    @Test func rotatingKeepsThePagesAcross() async {
        let (vm, url) = await open(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.toggleHorizontalScrolling()
        vm.rotateClockwise()
        #expect(vm.isHorizontalScrolling)
        #expect(vm.pageLayout.pageSizes.first == CGSize(width: 792, height: 612))
    }

    @Test func reloadingKeepsItAndANewDocumentDoesnt() async {
        let (vm, url) = await open(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.toggleHorizontalScrolling()
        await vm.loadDocument(from: url.path)
        #expect(vm.isHorizontalScrolling && vm.pageLayout.direction == .horizontal)

        let other = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_across_other_\(UUID().uuidString).pdf")
        makeLabelledPDF(at: other, labels: ["One"])
        defer { try? FileManager.default.removeItem(at: other) }
        await vm.loadDocument(from: other.path)
        #expect(!vm.isHorizontalScrolling && vm.pageLayout.direction == .vertical)
    }

    @Test func aComparePaneStaysVertical() async {
        let (vm, url) = await open(pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }
        vm.isComparePane = true
        vm.toggleHorizontalScrolling()
        #expect(!vm.isHorizontalScrolling)
    }

    // MARK: - In the scroll view

    private func scrollView(for vm: PDFViewerViewModel) -> (PDFScrollView, PDFCanvasView, PDFVirtualizedScrollView.Coordinator) {
        let scrollView = PDFScrollView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        let canvas = PDFCanvasView(viewModel: vm)
        scrollView.documentView = canvas
        let coordinator = PDFVirtualizedScrollView.Coordinator(viewModel: vm)
        coordinator.scrollView = scrollView
        coordinator.canvasView = canvas
        scrollView.coordinator = coordinator
        return (scrollView, canvas, coordinator)
    }

    @Test func theViewFollowsThePageAndThePageFollowsTheView() async {
        let (vm, url) = await open(pages: 8)
        defer { try? FileManager.default.removeItem(at: url) }
        let (scrollView, canvas, coordinator) = scrollView(for: vm)
        defer { scrollView.documentView = nil }
        vm.setZoom(1)
        coordinator.update(viewModel: vm, scrollView: scrollView)
        vm.jumpToPage(4)
        coordinator.update(viewModel: vm, scrollView: scrollView)

        // Turning it on brings the current page to the left, right away.
        vm.toggleHorizontalScrolling()
        vm.setZoom(1)
        coordinator.update(viewModel: vm, scrollView: scrollView)
        let clip = scrollView.contentView
        #expect(canvas.frame.size == vm.pageLayout.canvasSize(zoom: vm.effectiveZoom, viewportSize: clip.bounds.size))
        let expected = vm.pageLayout.scrollOrigin(toShow: 4, zoom: vm.effectiveZoom, canvasSize: canvas.bounds.size, viewportSize: clip.bounds.size)!
        #expect(abs(clip.bounds.origin.x - expected.x) < 1)
        #expect(canvas.pageFrame(for: 4)!.minX > clip.bounds.minX)

        // Scrolling across makes the first page more than half in view current.
        let page6 = canvas.pageFrame(for: 6)!
        clip.scroll(to: CGPoint(x: page6.minX - 10, y: 0))
        coordinator.clipViewBoundsDidChange(Notification(name: NSView.boundsDidChangeNotification))
        #expect(vm.currentPageIndex == 6)
    }

    @Test func aPageTurnSlidesToThePageWithoutPassingThroughOthers() async throws {
        let (vm, url) = await open(pages: 8)
        defer { try? FileManager.default.removeItem(at: url) }
        let (scrollView, canvas, coordinator) = scrollView(for: vm)
        defer { scrollView.documentView = nil }
        vm.toggleHorizontalScrolling()
        vm.setZoom(1)
        coordinator.update(viewModel: vm, scrollView: scrollView)
        let clip = scrollView.contentView
        #expect(clip.bounds.minX == 0)

        vm.nextPage()
        vm.nextPage()
        coordinator.update(viewModel: vm, scrollView: scrollView)
        let expected = vm.pageLayout.scrollOrigin(toShow: 2, zoom: vm.effectiveZoom, canvasSize: canvas.bounds.size, viewportSize: clip.bounds.size)!
        for _ in 0..<40 where abs(clip.bounds.minX - expected.x) > 0.5 {
            // Mid-slide, page 1 shows first, but page 2 stays current.
            coordinator.clipViewBoundsDidChange(Notification(name: NSView.boundsDidChangeNotification))
            #expect(vm.currentPageIndex == 2)
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(abs(clip.bounds.minX - expected.x) <= 0.5)
    }

    @Test func aMouseWheelScrollsAcrossButATrackpadIsLeftAlone() throws {
        let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0))
        let event = try #require(NSEvent(cgEvent: wheel))
        #expect(event.scrollingDeltaY != 0 && event.scrollingDeltaX == 0)
        let turned = PDFScrollView.wheelTurnedSideways(event, pagesRunAcross: true, fitsTheHeight: true)
        #expect(turned.scrollingDeltaY == 0)
        #expect(turned.scrollingDeltaX == event.scrollingDeltaY)
        // Not when the pages run down the window, or there's height to scroll.
        #expect(PDFScrollView.wheelTurnedSideways(event, pagesRunAcross: false, fitsTheHeight: true) === event)
        #expect(PDFScrollView.wheelTurnedSideways(event, pagesRunAcross: true, fitsTheHeight: false) === event)

        let swipe = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -30, wheel2: 0, wheel3: 0))
        let swipeEvent = try #require(NSEvent(cgEvent: swipe))
        if swipeEvent.hasPreciseScrollingDeltas {
            #expect(PDFScrollView.wheelTurnedSideways(swipeEvent, pagesRunAcross: true, fitsTheHeight: true) === swipeEvent)
        }
    }
}
