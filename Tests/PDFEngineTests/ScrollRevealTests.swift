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

/// Going to a search result, anchor or annotation moves the view only as far as it needs to.
@Suite(.serialized)
struct ScrollRevealTests {
    private let canvas = CGSize(width: 2000, height: 10_000)
    private let view = CGRect(x: 600, y: 2000, width: 800, height: 600)

    /// On screen, even close to an edge: the page doesn't move.
    @Test func aResultOnScreenDoesntMoveThePage() {
        for result in [CGRect(x: 900, y: 2300, width: 80, height: 16),
                       CGRect(x: 602, y: 2002, width: 80, height: 16),
                       CGRect(x: 1318, y: 2582, width: 80, height: 16)] {
            #expect(ScrollReveal.origin(toShow: result, in: view, canvasSize: canvas) == view.origin, "\(result)")
        }
    }

    /// Below the view but across from it: the view scrolls down and stays across.
    @Test func aResultBelowScrollsDownWithoutMovingAcross() {
        let result = CGRect(x: 1300, y: 3000, width: 80, height: 16)
        #expect(ScrollReveal.origin(toShow: result, in: view, canvasSize: canvas) == CGPoint(x: 600, y: 2708))
    }

    /// Off to the side but level with the view: it moves across only, centring the result.
    @Test func aResultToTheSideMovesAcrossOnly() {
        let result = CGRect(x: 100, y: 2300, width: 80, height: 16)
        #expect(ScrollReveal.origin(toShow: result, in: view, canvasSize: canvas) == CGPoint(x: 0, y: 2000))
        let farRight = CGRect(x: 1800, y: 2300, width: 80, height: 16)
        #expect(ScrollReveal.origin(toShow: farRight, in: view, canvasSize: canvas) == CGPoint(x: 1200, y: 2000))
    }

    /// Cut off at an edge, it's moved in, at least the margin from the edge.
    @Test func aResultCutOffAtAnEdgeIsBroughtIn() {
        let atBottom = CGRect(x: 900, y: 2590, width: 80, height: 16)
        let origin = ScrollReveal.origin(toShow: atBottom, in: view, canvasSize: canvas)
        #expect(origin.x == 600)
        #expect(atBottom.minY - origin.y >= ScrollReveal.margin.height && origin.y + view.height - atBottom.maxY >= ScrollReveal.margin.height)
    }

    /// Bigger than the view: its start shows, just inside the view's.
    @Test func aTargetBiggerThanTheViewShowsFromItsStart() {
        let tall = CGRect(x: 700, y: 4000, width: 200, height: 900)
        #expect(ScrollReveal.origin(toShow: tall, in: view, canvasSize: canvas) == CGPoint(x: 600, y: 3976))
        let tallShowing = CGRect(x: 700, y: 2100, width: 200, height: 900)
        #expect(ScrollReveal.origin(toShow: tallShowing, in: view, canvasSize: canvas) == view.origin)
    }

    @Test func staysWithinTheCanvas() {
        let nearEnd = CGRect(x: 1950, y: 9990, width: 40, height: 8)
        #expect(ScrollReveal.origin(toShow: nearEnd, in: view, canvasSize: canvas) == CGPoint(x: 1200, y: 9400))
    }

    // MARK: - On screen

    /// Zoomed in past the window's width, stepping between results on one screen leaves the
    /// page where it is.
    @Test(.showsWindows) @MainActor func steppingBetweenResultsOnScreenLeavesThePage() async throws {
        _ = NSApplication.shared
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: Fixture.url("rfc9457.pdf").path)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PDFVirtualizedScrollView(viewModel: vm))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        vm.setZoom(1.5)
        try await Task.sleep(for: .milliseconds(300))
        let scrollView = try #require(vm.hostScrollView)
        let canvas = try #require(scrollView.documentView as? PDFCanvasView)
        let clip = scrollView.contentView
        #expect(canvas.frame.width > clip.bounds.width, "zoomed in past the window's width")

        vm.searchQuery = "problem"
        vm.performSearch(autoNavigate: true)
        #expect(try await eventually { !vm.searchResults.isEmpty && !vm.isSearching })
        try await Task.sleep(for: .milliseconds(200))

        func onScreen(_ result: SearchResult) throws -> Bool {
            let rect = result.highlightQuads.first?.boundingRect ?? result.boundingRect
            let target = try #require(canvas.pageGeometry(for: result.pageIndex)).canvasRect(forPageRect: rect)
            return clip.bounds.contains(target)
        }
        var stepped = 0
        for index in vm.searchResults.indices.prefix(40) {
            vm.navigateToMatch(at: index)
            try await Task.sleep(for: .milliseconds(60))
            #expect(try onScreen(vm.searchResults[index]), "result \(index)")
            // The next result, if it's on screen already, is gone to without the page moving.
            let next = index + 1
            guard next < vm.searchResults.count, try onScreen(vm.searchResults[next]) else { continue }
            let before = clip.bounds.origin
            vm.navigateToMatch(at: next)
            try await Task.sleep(for: .milliseconds(60))
            #expect(clip.bounds.origin == before, "result \(next)")
            stepped += 1
        }
        #expect(stepped >= 3, "Only \(stepped) steps between results on one screen")
    }

    @MainActor private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }
}
