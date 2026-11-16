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
import Foundation
import AppKit
import PDFKit
@testable import PDFEngine

/// Polygons and polylines clicked out point by point, area highlights, and typewriter text.
@MainActor
@Suite struct PolyShapeTests {
    private func shapes(_ vm: PDFViewerViewModel, _ type: PDFAnnotationType) -> [PDFEngine.PDFAnnotation] {
        vm.pageAnnotations[0]?.filter { $0.type == type } ?? []
    }

    @Test func aPolygonClosesOnItsFirstPoint() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        fixture.vm.canvasMode = .shape
        fixture.vm.selectedShape = .polygon
        for point in [CGPoint(x: 100, y: 300), CGPoint(x: 250, y: 300), CGPoint(x: 180, y: 420)] {
            fixture.click(page: 0, at: point)
        }
        #expect(shapes(fixture.vm, .polygon).isEmpty)
        fixture.click(page: 0, at: CGPoint(x: 101, y: 301))
        let polygon = try #require(shapes(fixture.vm, .polygon).first)
        #expect(polygon.inkPoints.count == 3)
        #expect(polygon.color == .red && polygon.strokeWidth == 2.5)
        #expect(fixture.canvas.selectedAnnotation?.id == polygon.id)
        // Its outline is hit, not the inside.
        #expect(polygon.contains(pagePoint: CGPoint(x: 175, y: 300)))
        #expect(!polygon.contains(pagePoint: CGPoint(x: 180, y: 340)))
    }

    @Test func aPolylineEndsOnADoubleClickOrReturn() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        fixture.vm.canvasMode = .shape
        fixture.vm.selectedShape = .polyline
        fixture.vm.selectedShapeLineEnding = .closedArrow
        fixture.click(page: 0, at: CGPoint(x: 100, y: 300))
        fixture.click(page: 0, at: CGPoint(x: 200, y: 320))
        fixture.click(page: 0, at: CGPoint(x: 260, y: 400))
        fixture.click(page: 0, at: CGPoint(x: 260, y: 400), clickCount: 2)
        let line = try #require(shapes(fixture.vm, .polyline).first)
        #expect(line.inkPoints.count == 3)
        #expect(line.lineEnding == .closedArrow)

        // Return finishes too; Escape throws a half-drawn one away.
        fixture.click(page: 0, at: CGPoint(x: 100, y: 500))
        fixture.click(page: 0, at: CGPoint(x: 200, y: 520))
        fixture.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
        #expect(shapes(fixture.vm, .polyline).count == 2)
        fixture.click(page: 0, at: CGPoint(x: 100, y: 600))
        fixture.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        #expect(fixture.canvas.currentPolyPage == nil)
        #expect(shapes(fixture.vm, .polyline).count == 2)
    }

    @Test func theyAreSavedAsPolygonAndPolyLineAndReadBack() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        try #require(vm.addPolyShape(pageIndex: 0, closed: true, points: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100), CGPoint(x: 150, y: 200)], strokeWidth: 1, color: .blue) != nil)
        try #require(vm.addPolyShape(pageIndex: 0, closed: false, points: [CGPoint(x: 300, y: 100), CGPoint(x: 400, y: 150)], strokeWidth: 3, lineEnding: .openArrow, color: .green) != nil)
        try vm.document?.save(to: url.path)

        let opened: PDFKit.PDFDocument? = PDFKit.PDFDocument(url: url)
        let types = try #require(opened).page(at: 0)?.annotations.map(\.type) ?? []
        #expect(types.contains("Polygon") && types.contains("PolyLine"))

        // Opened again, they're picked up as polygons and polylines, to move and restyle.
        let reopened = PDFViewerViewModel()
        await reopened.loadDocument(from: url.path)
        let doc = try #require(reopened.document)
        let numbers = [CGPoint(x: 150, y: 100), CGPoint(x: 350, y: 125)].compactMap { doc.annotationObjectNumber(pageIndex: 0, at: $0) }
        let picked = numbers.compactMap { reopened.pickUpFileAnnotation(pageIndex: 0, objectNumber: $0) }
        #expect(Set(picked.map(\.type)) == [.polygon, .polyline])
        #expect(picked.first { $0.type == .polyline }?.lineEnding == .openArrow)
    }

    @Test func changingTheWidthRestylesASelectedPolygon() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let polygon = try #require(fixture.vm.addPolyShape(pageIndex: 0, closed: true, points: [CGPoint(x: 100, y: 300), CGPoint(x: 250, y: 300), CGPoint(x: 180, y: 420)]))
        fixture.canvas.selectedAnnotation = (polygon.id, 0)
        fixture.canvas.restyleSelectedShape(strokeWidth: 6)
        #expect(shapes(fixture.vm, .polygon).first?.strokeWidth == 6)
        #expect(shapes(fixture.vm, .polygon).first?.inkPoints.count == 3)
    }

    @Test func anAreaSelectionIsHighlightedAsAnArea() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        fixture.vm.handleDragSelect(pageIndex: 0, startPagePoint: CGPoint(x: 300, y: 300), currentPagePoint: CGPoint(x: 400, y: 380), forceMode: .rectangularArea)
        let created = fixture.vm.highlightSelection(color: fixture.vm.toolColor(.highlight))
        let highlight = try #require(created.first)
        #expect(highlight.type == .highlight && highlight.color == .yellow)
        let box = try #require(highlight.quads.first).boundingRect
        #expect(abs(box.minX - 300) < 1 && abs(box.maxY - 380) < 1)
    }

    @Test func textBoxesAreStillTextBoxesWhenReadBack() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        try #require(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 500, width: 120, height: 20), text: "Typed", fontSize: 13, color: .black) != nil)
        try vm.document?.save(to: url.path)
        let reopened = PDFViewerViewModel()
        await reopened.loadDocument(from: url.path)
        let number = try #require(reopened.document?.annotationObjectNumber(pageIndex: 0, at: CGPoint(x: 110, y: 510)))
        #expect(reopened.pickUpFileAnnotation(pageIndex: 0, objectNumber: number)?.type == .freeText)
    }
}
