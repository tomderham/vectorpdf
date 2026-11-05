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

/// Selection, links, search highlights, markup and forms in two-page spreads and rotated views,
/// which map page points to the canvas through `PageGeometry`.
@Suite(.serialized)
struct RotatedAndTwoPageViewTests {

    /// The views a page can be shown in.
    enum View: CaseIterable, CustomStringConvertible {
        case single, twoPage, rotated90, rotated180, rotated270
        var description: String {
            switch self {
            case .single: "single page"
            case .twoPage: "two pages"
            case .rotated90: "rotated 90°"
            case .rotated180: "rotated 180°"
            case .rotated270: "rotated 270°"
            }
        }
    }

    // MARK: - Geometry

    @Test func pageGeometryRoundTripsAndTurnsClockwise() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        for rotation in [0, 90, 180, 270] {
            let sideways = rotation == 90 || rotation == 270
            let frame = NSRect(x: 40, y: 16, width: (sideways ? 400 : 600) * 2, height: (sideways ? 600 : 400) * 2)
            let geometry = PageGeometry(frame: frame, pageBounds: bounds, zoom: 2, rotation: rotation)
            // The whole page lands exactly on its footprint.
            let pageOnCanvas = geometry.canvasRect(forPageRect: bounds)
            #expect(abs(pageOnCanvas.minX - frame.minX) < 0.001 && abs(pageOnCanvas.maxY - frame.maxY) < 0.001, "\(rotation)°")
            #expect(abs(pageOnCanvas.width - frame.width) < 0.001 && abs(pageOnCanvas.height - frame.height) < 0.001, "\(rotation)°")
            for point in [CGPoint(x: 10, y: 20), CGPoint(x: 599, y: 1), CGPoint(x: 300, y: 399)] {
                let back = geometry.pagePoint(forCanvasPoint: geometry.canvasPoint(forPagePoint: point))
                #expect(abs(back.x - point.x) < 0.001 && abs(back.y - point.y) < 0.001, "\(rotation)°")
            }
        }
        // Turned clockwise, the page's top-left corner is at the footprint's top-right, and its
        // top edge runs down the right-hand side.
        let turned = PageGeometry(frame: NSRect(x: 40, y: 16, width: 800, height: 1200), pageBounds: bounds, zoom: 2, rotation: 90)
        let topLeft = turned.canvasPoint(forPagePoint: .zero)
        #expect(abs(topLeft.x - 840) < 0.001 && abs(topLeft.y - 16) < 0.001)
        let alongTop = turned.pageVector(forCanvasVector: CGSize(width: 0, height: 2))
        #expect(abs(alongTop.width - 1) < 0.001 && abs(alongTop.height) < 0.001)
    }

    // MARK: - Interaction in each view

    @MainActor
    @Test(arguments: View.allCases)
    func dragSelectsTheTextUnderIt(in view: View) async throws {
        let fixture = try await CanvasFixture(view: view)
        defer { fixture.close() }
        // Page 2 (the right-hand page of a spread) shows "Charlie" at about x 72…160, y 96…125.
        fixture.drag(page: 2, from: CGPoint(x: 66, y: 112), to: CGPoint(x: 200, y: 113))
        let selection = try #require(fixture.vm.activeSelection, "\(view)")
        #expect(selection.pageIndex == 2, "\(view)")
        #expect(selection.result.text.contains("Charlie"), "\(view): \(selection.result.text)")
    }

    @MainActor
    @Test(arguments: View.allCases)
    func clickFollowsALink(in view: View) async throws {
        let fixture = try await CanvasFixture(view: view)
        defer { fixture.close() }
        let link = SnapshotTarget(label: "To cover", targetPage: 0, targetPoint: CGPoint(x: 72, y: 100), sourceRect: CGRect(x: 300, y: 400, width: 80, height: 20), sourcePage: 2)
        fixture.vm.pageLinks[2] = [link]
        #expect(fixture.canvas.internalLinkInfo(at: fixture.canvasPoint(page: 2, CGPoint(x: 340, y: 410)))?.id == link.id, "\(view)")
        fixture.click(page: 2, at: CGPoint(x: 340, y: 410))
        #expect(fixture.vm.activeSnapshotTarget?.id == link.id, "\(view)")
    }

    @MainActor
    @Test(arguments: View.allCases)
    func searchHitIsDrawnOverItsText(in view: View) async throws {
        let fixture = try await CanvasFixture(view: view)
        defer { fixture.close() }
        let hitRect = CGRect(x: 300, y: 300, width: 120, height: 40)
        fixture.vm.searchResultsByPage[2] = [SearchResult(pageIndex: 2, matchedText: "x", snippet: "x", highlightQuads: [PDFQuad(rect: hitRect)])]

        let geometry = try #require(fixture.canvas.pageGeometry(for: 2))
        let rep = try #require(fixture.canvas.bitmapImageRepForCachingDisplay(in: geometry.frame))
        fixture.canvas.cacheDisplay(in: geometry.frame, to: rep)
        func color(atPage point: CGPoint) -> NSColor? {
            let p = geometry.canvasPoint(forPagePoint: point)
            let scale = CGFloat(rep.pixelsWide) / geometry.frame.width
            return rep.colorAt(x: Int((p.x - geometry.frame.minX) * scale), y: Int((p.y - geometry.frame.minY) * scale))?.usingColorSpace(.deviceRGB)
        }
        let onHit = try #require(color(atPage: CGPoint(x: hitRect.midX, y: hitRect.midY)))
        let offHit = try #require(color(atPage: CGPoint(x: 500, y: 700)))
        // The hit is drawn yellow over the page, where its text is.
        #expect(onHit.blueComponent < offHit.blueComponent - 0.1, "\(view): \(onHit) vs \(offHit)")
    }

    @MainActor
    @Test(arguments: [View.rotated90, .rotated180, .rotated270, .twoPage])
    func shapeLandsWhereItWasDragged(in view: View) async throws {
        let fixture = try await CanvasFixture(view: view)
        defer { fixture.close() }
        fixture.vm.canvasMode = .shape
        fixture.vm.selectedShape = .rectangle
        fixture.drag(page: 2, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 250, y: 380))
        let shape = try #require(fixture.vm.pageAnnotations[2]?.first(where: { $0.type == .square }), "\(view)")
        let rect = try #require(shape.rect)
        // Allow for the stroke the annotation's rect includes.
        #expect(rect.insetBy(dx: -6, dy: -6).contains(CGRect(x: 100, y: 300, width: 150, height: 80)), "\(view): \(rect)")
        #expect(CGRect(x: 100, y: 300, width: 150, height: 80).insetBy(dx: -6, dy: -6).contains(rect), "\(view): \(rect)")
    }

    @MainActor
    @Test func arrowKeysMoveTheSelectedAnnotationThatWayOnScreen() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let canvas = fixture.canvas
        canvas.nextResponder = KeySinkResponder()
        func nudge(keyCode: UInt16, character: String) throws -> CGRect {
            let annot = try #require(fixture.vm.pageAnnotations[0]?.last)
            canvas.selectedAnnotation = (annot.id, 0)
            let before = try #require(annot.rect)
            canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: keyCode)!)
            let after = try #require(fixture.vm.pageAnnotations[0]?.last?.rect)
            return CGRect(x: after.minX - before.minX, y: after.minY - before.minY, width: 0, height: 0)
        }
        _ = try #require(fixture.vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 200, y: 200, width: 80, height: 20), text: "nudge", fontSize: 12))

        // Unrotated: Up moves it up the page (page space runs down, as the screen does).
        let up = try nudge(keyCode: 126, character: "\u{F700}")
        #expect(up.minX == 0 && up.minY == -1)

        // Turned clockwise, Right on screen is up the page.
        fixture.vm.rotateClockwise()
        fixture.layOut()
        let right = try nudge(keyCode: 124, character: "\u{F703}")
        #expect(right.minX == 0 && right.minY == -1, "\(right)")
    }

    @MainActor
    @Test func formFieldsTurnWithARotatedView() async throws {
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_rotated_form_\(UUID().uuidString).pdf")
        PDFEngineTests().createFormSamplePDF(at: src)
        defer { try? FileManager.default.removeItem(at: src) }
        let fixture = try await CanvasFixture(view: .rotated90, file: src)
        defer { fixture.close() }
        let canvas = fixture.canvas
        fixture.vm.loadPageMetadata(0)
        canvas.syncFormControls()

        let widget = try #require(fixture.vm.pageFormWidgets[0]?.first(where: { $0.type == .text }))
        let control = try #require(canvas.activeFormControls[widget.id])
        #expect(control.frameCenterRotation == 90)
        // Its centre is the widget's centre, turned with the page.
        let geometry = try #require(canvas.pageGeometry(for: 0))
        let layoutRect = canvas.layoutRect(of: control)
        let expected = geometry.canvasPoint(forLayoutPoint: CGPoint(x: layoutRect.midX, y: layoutRect.midY))
        let widgetCenter = geometry.canvasPoint(forPagePoint: CGPoint(x: widget.rect.midX, y: widget.rect.midY))
        // Where AppKit really shows it: the centre of its bounds, in the canvas.
        let actual = canvas.convert(NSPoint(x: control.bounds.midX, y: control.bounds.midY), from: control)
        // Turned clockwise, as the page is: the middle of its left edge is straight above its centre.
        let leftMiddle = canvas.convert(NSPoint(x: control.bounds.minX, y: control.bounds.midY), from: control)
        #expect(abs(leftMiddle.x - actual.x) < 1 && leftMiddle.y < actual.y - 10, "\(leftMiddle) vs \(actual)")
        #expect(abs(actual.x - expected.x) < 1 && abs(actual.y - expected.y) < 1, "\(actual) vs \(expected)")
        #expect(geometry.frame.contains(widgetCenter))
        // A click there reaches it: AppKit alone would hit-test it by its frame, which isn't
        // where a turned view is shown.
        let hit = canvas.hitTest(canvas.convert(widgetCenter, to: canvas.superview))
        #expect(hit.map { $0 === control || $0.isDescendant(of: control) } == true, "\(String(describing: hit))")

        // Back to unrotated, it's unturned again.
        for _ in 0..<3 { fixture.vm.rotateClockwise() }
        fixture.layOut()
        canvas.syncFormControls()
        #expect(canvas.activeFormControls[widget.id]?.frameCenterRotation == 0)
    }
}

/// A canvas in an offscreen window showing a document (by default three pages labelled Alpha,
/// Bravo and Charlie) in `view`, with mouse events sent at page points.
@MainActor
final class CanvasFixture {
    let vm = PDFViewerViewModel()
    let canvas: PDFCanvasView
    let window: NSWindow
    private let ownedFile: URL?

    init(view: RotatedAndTwoPageViewTests.View, file: URL? = nil) async throws {
        let url: URL
        if let file {
            url = file
            ownedFile = nil
        } else {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_views_\(UUID().uuidString).pdf")
            makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])
            ownedFile = url
        }
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 1400), styleMask: [.titled], backing: .buffered, defer: true)
        canvas = PDFCanvasView(viewModel: vm)
        window.contentView = canvas
        switch view {
        case .single: break
        case .twoPage: vm.toggleTwoPageMode()
        case .rotated90: vm.rotateClockwise()
        case .rotated180: vm.rotateClockwise(); vm.rotateClockwise()
        case .rotated270: vm.rotateCounterclockwise()
        }
        vm.setZoom(1)
        layOut()
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    /// Sizes the canvas to hold every page, as the scroll view does.
    func layOut() {
        canvas.frame = NSRect(x: 0, y: 0, width: 1400, height: max(1400, vm.effectiveTotalHeight * vm.effectiveZoom + 64))
    }

    func close() {
        if let ownedFile { try? FileManager.default.removeItem(at: ownedFile) }
    }

    func canvasPoint(page: Int, _ point: CGPoint) -> CGPoint {
        canvas.pageGeometry(for: page)!.canvasPoint(forPagePoint: point)
    }

    private func event(_ type: NSEvent.EventType, page: Int, _ point: CGPoint, clickCount: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: canvas.convert(canvasPoint(page: page, point), to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)!
    }

    func click(page: Int, at point: CGPoint, clickCount: Int = 1) {
        canvas.mouseDown(with: event(.leftMouseDown, page: page, point, clickCount: clickCount))
        canvas.mouseUp(with: event(.leftMouseUp, page: page, point, clickCount: clickCount))
    }

    func drag(page: Int, from start: CGPoint, to end: CGPoint) {
        canvas.mouseDown(with: event(.leftMouseDown, page: page, start))
        for step in 1...4 {
            let t = CGFloat(step) / 4
            canvas.mouseDragged(with: event(.leftMouseDragged, page: page, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)))
        }
        canvas.mouseUp(with: event(.leftMouseUp, page: page, end))
    }
}
