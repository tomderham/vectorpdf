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

import Testing
import AppKit
@testable import PDFEngine

/// Dragging past the edge of the view scrolls it, and ⇧-click extends a selection.
@Suite struct DragAutoscrollTests {
    @Test func scrollsOnlyPastTheEdgeAndFasterFurtherPast() {
        let visible = CGRect(x: 0, y: 100, width: 600, height: 400)
        #expect(PDFCanvasView.autoscrollStep(for: CGPoint(x: 300, y: 300), visible: visible) == .zero)
        // Just past the bottom: a few points down.
        #expect(PDFCanvasView.autoscrollStep(for: CGPoint(x: 300, y: 502), visible: visible) == CGVector(dx: 0, dy: 4))
        #expect(PDFCanvasView.autoscrollStep(for: CGPoint(x: 300, y: 540), visible: visible) == CGVector(dx: 0, dy: 20))
        // Far past the top: up, at most 120 a step.
        #expect(PDFCanvasView.autoscrollStep(for: CGPoint(x: 300, y: -900), visible: visible) == CGVector(dx: 0, dy: -120))
        // Past a corner: both ways.
        let corner = PDFCanvasView.autoscrollStep(for: CGPoint(x: 640, y: 560), visible: visible)
        #expect(corner.dx > 0 && corner.dy > 0)
    }
}

/// A canvas in a scroll view in an offscreen window, showing three labelled pages.
@MainActor
private final class ScrollingCanvasFixture {
    let vm = PDFViewerViewModel()
    let canvas: PDFCanvasView
    let scrollView: NSScrollView
    let window: NSWindow
    private let file: URL

    init() async {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_autoscroll_\(UUID().uuidString).pdf")
        makeLabelledPDF(at: file, labels: ["Alpha", "Bravo", "Charlie"])
        vm.isTransientWindow = true
        await vm.loadDocument(from: file.path)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        canvas = PDFCanvasView(viewModel: vm)
        vm.setZoom(1)
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: vm.effectiveTotalHeight * vm.effectiveZoom + 64)
        scrollView.documentView = canvas
        window.contentView = scrollView
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func close() {
        canvas.stopAutoscroll()
        // The canvas holds its view model unowned: nothing may reach it after the test.
        scrollView.documentView = nil
        window.contentView = nil
        try? FileManager.default.removeItem(at: file)
    }

    func windowPoint(page: Int, _ point: CGPoint) -> CGPoint {
        canvas.convert(canvas.pageGeometry(for: page)!.canvasPoint(forPagePoint: point), to: nil)
    }

    func event(_ type: NSEvent.EventType, at location: CGPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
}

@MainActor
@Suite struct DragSelectionAcrossPagesTests {
    @Test func draggingPastTheBottomScrollsAndSelectsOnToLaterPages() async throws {
        let fixture = await ScrollingCanvasFixture()
        defer { fixture.close() }
        let canvas = fixture.canvas
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: fixture.windowPoint(page: 0, CGPoint(x: 60, y: 100))))
        // Below the window's bottom edge (window space is bottom-up).
        let below = CGPoint(x: 300, y: -200)
        canvas.mouseDragged(with: fixture.event(.leftMouseDragged, at: below))
        defer { canvas.mouseUp(with: fixture.event(.leftMouseUp, at: below)) }
        #expect(canvas.autoscrollTimer != nil)

        let startY = fixture.scrollView.contentView.bounds.minY
        for _ in 0..<40 { canvas.autoscroll(towards: below) }
        #expect(fixture.scrollView.contentView.bounds.minY > startY + 1000)

        // The selection runs from Alpha on the first page to the page now under the pointer.
        let selection = try #require(fixture.vm.activeSelection)
        #expect(selection.pageIndex == 0)
        #expect(selection.result.text.contains("Alpha"))
        let pages = fixture.vm.additionalSelectionPages.map(\.pageIndex)
        #expect(pages.contains(1))
        #expect(pages.last ?? 0 >= 2, "\(pages)")
    }

    @Test func releasingTheButtonStopsScrolling() async {
        let fixture = await ScrollingCanvasFixture()
        defer { fixture.close() }
        let canvas = fixture.canvas
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: fixture.windowPoint(page: 0, CGPoint(x: 60, y: 100))))
        canvas.mouseDragged(with: fixture.event(.leftMouseDragged, at: CGPoint(x: 300, y: -50)))
        canvas.mouseUp(with: fixture.event(.leftMouseUp, at: CGPoint(x: 300, y: -50)))
        #expect(canvas.autoscrollTimer == nil)
        #expect(!canvas.autoscroll(towards: CGPoint(x: 300, y: -50)))
    }

    @Test func aDragInsideTheViewDoesntScroll() async {
        let fixture = await ScrollingCanvasFixture()
        defer { fixture.close() }
        let canvas = fixture.canvas
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: fixture.windowPoint(page: 0, CGPoint(x: 60, y: 100))))
        canvas.mouseDragged(with: fixture.event(.leftMouseDragged, at: fixture.windowPoint(page: 0, CGPoint(x: 300, y: 120))))
        #expect(canvas.autoscrollTimer == nil)
        canvas.mouseUp(with: fixture.event(.leftMouseUp, at: fixture.windowPoint(page: 0, CGPoint(x: 300, y: 120))))
    }

    @Test func shiftClickExtendsTheSelectionToAnotherPage() async throws {
        let fixture = await ScrollingCanvasFixture()
        defer { fixture.close() }
        let canvas = fixture.canvas
        // Select Alpha, then ⇧-click past Charlie on the third page.
        let start = fixture.windowPoint(page: 0, CGPoint(x: 60, y: 110))
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: start))
        canvas.mouseDragged(with: fixture.event(.leftMouseDragged, at: fixture.windowPoint(page: 0, CGPoint(x: 200, y: 112))))
        canvas.mouseUp(with: fixture.event(.leftMouseUp, at: fixture.windowPoint(page: 0, CGPoint(x: 200, y: 112))))
        #expect(fixture.vm.activeSelection?.result.text.contains("Alpha") == true)

        let end = fixture.windowPoint(page: 2, CGPoint(x: 200, y: 112))
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: end, modifiers: .shift))
        canvas.mouseUp(with: fixture.event(.leftMouseUp, at: end, modifiers: .shift))
        let selection = try #require(fixture.vm.activeSelection)
        #expect(selection.pageIndex == 0 && selection.result.text.contains("Alpha"))
        let rest = fixture.vm.additionalSelectionPages
        #expect(rest.map(\.pageIndex) == [1, 2])
        #expect(rest.last?.result.text.contains("Charlie") == true)

        // ⇧-click back on the first page shortens it again, from the same start.
        let back = fixture.windowPoint(page: 0, CGPoint(x: 200, y: 112))
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: back, modifiers: .shift))
        canvas.mouseUp(with: fixture.event(.leftMouseUp, at: back, modifiers: .shift))
        #expect(fixture.vm.activeSelection?.result.text.contains("Alpha") == true)
        #expect(fixture.vm.additionalSelectionPages.isEmpty)
    }

    @Test func shiftClickWithoutASelectionStartsOne() async {
        let fixture = await ScrollingCanvasFixture()
        defer { fixture.close() }
        let canvas = fixture.canvas
        let point = fixture.windowPoint(page: 1, CGPoint(x: 60, y: 110))
        canvas.mouseDown(with: fixture.event(.leftMouseDown, at: point, modifiers: .shift))
        #expect(fixture.vm.activeSelection == nil)
        #expect(fixture.vm.selectionAnchor?.pageIndex == 1)
        canvas.mouseUp(with: fixture.event(.leftMouseUp, at: point, modifiers: .shift))
    }
}

/// A canvas can outlive its view model briefly, as when a tab closes with a change still queued.
@MainActor
@Suite struct CanvasOutlivingItsViewModelTests {
    @Test func queuedChangesAfterTheViewModelIsGoneDoNothing() async throws {
        var vm: PDFViewerViewModel? = PDFViewerViewModel()
        weak var gone = vm
        let canvas = PDFCanvasView(viewModel: vm!)
        canvas.frame = NSRect(x: 0, y: 0, width: 400, height: 400)
        // Each change queues a delivery to the canvas on the main queue…
        vm!.selectedFontSize += 1
        vm!.canvasMode = .draw
        vm!.searchQuery = "queued"
        // …which runs after the view model is freed.
        vm = nil
        #expect(gone == nil, "something else kept the view model; the test needs it freed")
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(!canvas.hasLiveViewModel)
        canvas.syncFormControls()
        canvas.layout()
        canvas.display()
        #expect(!canvas.autoscroll(towards: CGPoint(x: 0, y: -100)))
    }
}
