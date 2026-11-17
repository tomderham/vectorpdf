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
@testable import PDFEngine

/// Several annotations selected at once (⇧-click), and changed together.
@MainActor
@Suite struct GroupSelectionTests {
    /// Three rectangles side by side on the first page, the first selected and the others added.
    private func threeSelected(_ fixture: CanvasFixture, colors: [AnnotationColor] = [.red, .red, .red]) throws -> [PDFAnnotation] {
        var made: [PDFAnnotation] = []
        for (i, x) in [100, 250, 400].enumerated() {
            let rect = try #require(fixture.vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: x, y: 300 + i * 20), to: CGPoint(x: x + 80, y: 360 + i * 20), color: colors[i]))
            made.append(rect)
        }
        fixture.canvas.selectedAnnotation = (made[0].id, 0)
        fixture.canvas.toggleInSelection(made[1], pageIndex: 0)
        fixture.canvas.toggleInSelection(made[2], pageIndex: 0)
        return made
    }

    private func rectangles(_ vm: PDFViewerViewModel) -> [PDFAnnotation] {
        (vm.pageAnnotations[0] ?? []).filter { $0.type == .square }.sorted { ($0.rect?.minX ?? 0) < ($1.rect?.minX ?? 0) }
    }

    @Test func shiftClickAddsAndRemoves() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let made = try threeSelected(fixture)
        #expect(fixture.canvas.allSelectedAnnotationIDs == made.map(\.id))
        fixture.canvas.toggleInSelection(made[1], pageIndex: 0)
        #expect(fixture.canvas.allSelectedAnnotationIDs == [made[0].id, made[2].id])
        // Taking out the first leaves the next as the one selected.
        fixture.canvas.toggleInSelection(made[0], pageIndex: 0)
        #expect(fixture.canvas.selectedAnnotation?.id == made[2].id && fixture.canvas.groupSelection.isEmpty)
    }

    @Test func draggingOneMovesThemAll() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        _ = try threeSelected(fixture)
        fixture.vm.undoManager.removeAllActions()
        let before = rectangles(fixture.vm).map { $0.rect!.minX }
        // Drag the middle one by its outline, 30 points right and 10 down.
        fixture.drag(page: 0, from: CGPoint(x: 250, y: 340), to: CGPoint(x: 280, y: 350))
        let after = rectangles(fixture.vm)
        #expect(after.count == 3)
        #expect(zip(before, after.map { $0.rect!.minX }).allSatisfy { abs($1 - $0 - 30) < 0.5 })
        // Still all selected, under their new IDs.
        #expect(Set(fixture.canvas.allSelectedAnnotationIDs) == Set(after.map(\.id)))
        // One Undo puts them all back.
        fixture.vm.undoManager.undo()
        #expect(rectangles(fixture.vm).map { $0.rect!.minX } == before)
    }

    @Test func deleteRemovesThemAllInOneUndoStep() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        _ = try threeSelected(fixture)
        // Making them is its own Undo step in the app; here it's in the same turn of the run loop.
        fixture.vm.undoManager.removeAllActions()
        fixture.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!)
        #expect(rectangles(fixture.vm).isEmpty)
        #expect(fixture.canvas.selectedAnnotation == nil)
        fixture.vm.undoManager.undo()
        #expect(rectangles(fixture.vm).count == 3)
    }

    @Test func alignAndDistribute() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        _ = try threeSelected(fixture)
        fixture.canvas.alignSelectedAnnotations(.top)
        let tops = rectangles(fixture.vm).map { $0.boundingRect.minY }
        #expect(tops.allSatisfy { abs($0 - tops[0]) < 0.5 })

        // Move the middle one off-centre, then space them evenly again.
        let ids = fixture.canvas.allSelectedAnnotationIDs
        fixture.canvas.alignSelectedAnnotations(.distributeX)
        let mids = rectangles(fixture.vm).map { $0.boundingRect.midX }
        #expect(abs((mids[1] - mids[0]) - (mids[2] - mids[1])) < 0.5)
        #expect(fixture.canvas.allSelectedAnnotationIDs.count == ids.count)
    }

    @Test func aColorChosenRecolorsThemAll() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        _ = try threeSelected(fixture, colors: [.red, .blue, .green])
        fixture.vm.selectedAnnotationColor = .purple
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(rectangles(fixture.vm).allSatisfy { $0.color == .purple })
    }

    @Test func clickingOneOfThemDoesntRecolorTheOthers() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        _ = try threeSelected(fixture, colors: [.red, .blue, .green])
        // A click (no drag) on the blue one's outline keeps the group and its colors.
        fixture.click(page: 0, at: CGPoint(x: 250, y: 340))
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(rectangles(fixture.vm).map(\.color) == [.red, .blue, .green])
        #expect(fixture.canvas.allSelectedAnnotationIDs.count == 3)
    }
}

/// Finding annotations to select: hover outlines, an area, or all on the page.
@MainActor
@Suite struct FindingAnnotationsToSelectTests {
    @Test func theAnnotationUnderThePointerIsOutlined() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let rect = try #require(fixture.vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 200, y: 380)))
        fixture.canvas.scheduleHoverOutline(at: fixture.canvasPoint(page: 0, CGPoint(x: 100, y: 340)))
        try await Task.sleep(nanoseconds: 150_000_000)
        let hover = try #require(fixture.canvas.hoverOutline)
        #expect(hover.pageIndex == 0 && hover.rect.contains(rect.rect!))
        // Inside a rectangle there's nothing to pick up: clicks there select text.
        fixture.canvas.scheduleHoverOutline(at: fixture.canvasPoint(page: 0, CGPoint(x: 150, y: 340)))
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(fixture.canvas.hoverOutline == nil)
        // A measurement in Select mode too.
        let count = try #require(fixture.vm.addCountMarker(pageIndex: 0, at: CGPoint(x: 400, y: 400)))
        fixture.canvas.scheduleHoverOutline(at: fixture.canvasPoint(page: 0, CGPoint(x: 400, y: 400)))
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(fixture.canvas.hoverOutline?.rect.contains(count.measurementPoints[0]) == true)
    }

    @Test func anAreaSelectsWhatsEntirelyInsideIt() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha"])
        // Saved in the file, so they're picked up from it.
        do {
            let vm = PDFViewerViewModel()
            await vm.loadDocument(from: url.path)
            _ = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 160, y: 340))
            _ = vm.addShapeAnnotation(pageIndex: 0, shape: .oval, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 260, y: 340))
            _ = vm.addCountMarker(pageIndex: 0, at: CGPoint(x: 300, y: 320))
            // Partly outside the area: left alone.
            _ = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 380, y: 300), to: CGPoint(x: 600, y: 340))
            try vm.document?.save(to: url.path)
        }
        let fixture = try await CanvasFixture(view: .single, file: url)
        defer { fixture.close() }
        let count = fixture.canvas.selectAnnotations(in: CGRect(x: 80, y: 280, width: 400, height: 80), pageIndex: 0)
        #expect(count == 3)
        #expect(fixture.canvas.allSelectedAnnotationIDs.count == 3)
        let types = fixture.canvas.selectedAnnotationsNow.map(\.type)
        #expect(Set(types) == [.square, .circle, .measureCount])
    }

    @Test func selectAllAnnotationsOnThePage() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        _ = fixture.vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 300), to: CGPoint(x: 160, y: 340))
        _ = fixture.vm.addShapeAnnotation(pageIndex: 0, shape: .oval, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 260, y: 340))
        _ = fixture.vm.addShapeAnnotation(pageIndex: 1, shape: .oval, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 260, y: 340))
        fixture.vm.canvasMode = .draw
        NotificationCenter.default.post(name: .selectAllAnnotationsCommand, object: fixture.vm)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(fixture.vm.canvasMode == .select)
        #expect(fixture.canvas.allSelectedAnnotationIDs.count == 2)
    }
}

/// Freehand drawings are selected with Select like other annotations.
@MainActor
@Suite struct SelectingDrawingsTests {
    private let stroke = [CGPoint(x: 100, y: 300), CGPoint(x: 150, y: 330), CGPoint(x: 200, y: 310)]

    private func drawings(_ vm: PDFViewerViewModel) -> [PDFAnnotation] {
        (vm.pageAnnotations[0] ?? []).filter { $0.type == .ink }
    }

    @Test func clickingAStrokeSelectsItToMoveRestyleAndDelete() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        try #require(fixture.vm.addInkAnnotation(pageIndex: 0, points: stroke, strokeWidth: 2, color: .red) != nil)
        // Away from the stroke, nothing; on it, the drawing.
        fixture.click(page: 0, at: CGPoint(x: 150, y: 380))
        #expect(fixture.canvas.selectedAnnotation == nil)
        fixture.click(page: 0, at: CGPoint(x: 125, y: 315))
        let selected = try #require(fixture.canvas.selectedAnnotation)
        #expect(drawings(fixture.vm).first?.id == selected.id)

        fixture.drag(page: 0, from: CGPoint(x: 125, y: 315), to: CGPoint(x: 165, y: 335))
        let moved = try #require(drawings(fixture.vm).first)
        #expect(abs(moved.inkPoints[0].x - 140) < 0.5 && abs(moved.inkPoints[0].y - 320) < 0.5)
        #expect(drawings(fixture.vm).count == 1)

        fixture.vm.selectedAnnotationColor = .blue
        fixture.vm.drawStrokeWidth = 6
        try await Task.sleep(nanoseconds: 100_000_000)
        let restyled = try #require(drawings(fixture.vm).first)
        #expect(restyled.color == .blue && restyled.strokeWidth == 6)

        fixture.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!)
        #expect(drawings(fixture.vm).isEmpty)
    }

    @Test func thePenDrawsOverAStrokeRatherThanSelectingIt() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        try #require(fixture.vm.addInkAnnotation(pageIndex: 0, points: stroke, strokeWidth: 2, color: .red) != nil)
        fixture.vm.canvasMode = .draw
        fixture.drag(page: 0, from: CGPoint(x: 125, y: 315), to: CGPoint(x: 180, y: 360))
        #expect(fixture.canvas.selectedAnnotation == nil)
        #expect(drawings(fixture.vm).count == 2)
    }

    @Test func aDrawingSavedInTheFileCanBeSelectedAndMoved() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha"])
        do {
            let vm = PDFViewerViewModel()
            await vm.loadDocument(from: url.path)
            _ = vm.addInkAnnotation(pageIndex: 0, points: stroke, strokeWidth: 2, color: .red)
            try vm.document?.save(to: url.path)
        }
        let fixture = try await CanvasFixture(view: .single, file: url)
        defer { fixture.close() }
        fixture.click(page: 0, at: CGPoint(x: 125, y: 315))
        let selected = try #require(fixture.canvas.selectedAnnotationsNow.first)
        #expect(selected.isFromFile && selected.fileSubtype == "Ink")
        let before = try #require(selected.rect)
        fixture.drag(page: 0, from: CGPoint(x: 125, y: 315), to: CGPoint(x: 145, y: 315))
        let after = try #require(fixture.canvas.selectedAnnotationsNow.first?.rect)
        #expect(abs(after.minX - before.minX - 20) < 1)
        // An area selects it too.
        fixture.canvas.selectedAnnotation = nil
        #expect(fixture.canvas.selectAnnotations(in: CGRect(x: 50, y: 250, width: 250, height: 150), pageIndex: 0) == 1)
    }
}
