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
