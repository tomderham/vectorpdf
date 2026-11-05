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

/// Changing measurements already on the page with the Select tool: dragging their points, moving
/// them, offsetting a dimension line, nudging and recoloring, with Undo, in saved files too.
@Suite(.serialized)
struct MeasurementEditingTests {

    /// A 200 pt length across page 0, from (100, 200) to (300, 200), in Select mode.
    @MainActor
    private func fixtureWithLength(view: RotatedAndTwoPageViewTests.View = .single, file: URL? = nil) async throws -> (CanvasFixture, PDFAnnotation) {
        let fixture = try await CanvasFixture(view: view, file: file)
        fixture.vm.isVertexSnapEnabled = false
        fixture.vm.isOrthoSnapEnabled = false
        let annot = try #require(addLength(to: fixture.vm))
        fixture.vm.canvasMode = .select
        return (fixture, annot)
    }

    @MainActor
    private func addLength(to vm: PDFViewerViewModel, from start: CGPoint = CGPoint(x: 100, y: 200), to end: CGPoint = CGPoint(x: 300, y: 200)) -> PDFAnnotation? {
        let (value, text) = vm.measured(.measureLength, points: [start, end], pageIndex: 0)
        return vm.addMeasurementAnnotation(pageIndex: 0, type: .measureLength, points: [start, end], value: value, formattedText: text, color: .red)
    }

    @MainActor
    private func onlyMeasurement(_ vm: PDFViewerViewModel) throws -> PDFAnnotation {
        let measurements = (vm.pageAnnotations[0] ?? []).filter(\.isMeasurement)
        #expect(measurements.count == 1)
        // The document holds just the one, too: an edit replaces it rather than adding another.
        #expect(vm.document?.measurementAnnotations(pageIndex: 0).count == 1)
        return try #require(measurements.first)
    }

    private func close(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 0.01) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    @MainActor
    @Test(arguments: [RotatedAndTwoPageViewTests.View.single, .rotated90])
    func draggingAnEndReshapesTheLengthAndWorksOutItsValueAgain(in view: RotatedAndTwoPageViewTests.View) async throws {
        let (fixture, original) = try await fixtureWithLength(view: view)
        defer { fixture.close() }
        fixture.drag(page: 0, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 350, y: 260))

        let edited = try onlyMeasurement(fixture.vm)
        #expect(close(edited.measurementPoints[0], CGPoint(x: 100, y: 200)), "\(view)")
        #expect(close(edited.measurementPoints[1], CGPoint(x: 350, y: 260)), "\(view): \(edited.measurementPoints)")
        #expect(abs(edited.measurementValue - (250.0 * 250.0 + 60.0 * 60.0).squareRoot()) < 0.01)
        #expect(edited.measurementText != original.measurementText)
        #expect(fixture.canvas.selectedAnnotation?.id == edited.id)
        let saved = try #require(fixture.vm.document?.measurementAnnotations(pageIndex: 0).first)
        #expect(close(saved.measurementPoints[1], CGPoint(x: 350, y: 260), within: 0.1))
        #expect(saved.measurementText == edited.measurementText)

        // One Undo puts it back as it was.
        fixture.vm.undoManager.undo()
        let restored = try onlyMeasurement(fixture.vm)
        #expect(close(restored.measurementPoints[1], CGPoint(x: 300, y: 200)))
        #expect(restored.measurementText == original.measurementText)
    }

    @MainActor
    @Test func aDraggedEndKeepsToOrthoLock() async throws {
        let (fixture, _) = try await fixtureWithLength()
        defer { fixture.close() }
        fixture.vm.isOrthoSnapEnabled = true
        // 13° off horizontal from the other end: it stays level.
        fixture.drag(page: 0, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 350, y: 260))
        let edited = try onlyMeasurement(fixture.vm)
        #expect(abs(edited.measurementPoints[1].y - 200) < 0.01, "\(edited.measurementPoints)")
        #expect(edited.measurementPoints[1].x > 340)
    }

    @MainActor
    @Test func draggingTheLineMovesAllOfIt() async throws {
        let (fixture, _) = try await fixtureWithLength()
        defer { fixture.close() }
        // Away from its ends and from its label in the middle.
        fixture.drag(page: 0, from: CGPoint(x: 130, y: 200), to: CGPoint(x: 150, y: 230))
        let edited = try onlyMeasurement(fixture.vm)
        #expect(close(edited.measurementPoints[0], CGPoint(x: 120, y: 230)), "\(edited.measurementPoints)")
        #expect(close(edited.measurementPoints[1], CGPoint(x: 320, y: 230)))
        #expect(abs(edited.measurementValue - 200) < 0.01)
    }

    @MainActor
    @Test func draggingTheLabelOffsetsTheDimensionLineAndTheOffsetIsSaved() async throws {
        let (fixture, _) = try await fixtureWithLength()
        defer { fixture.close() }
        // Only the part of the drag across the line counts.
        fixture.drag(page: 0, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 215, y: 230))
        let edited = try onlyMeasurement(fixture.vm)
        #expect(abs(edited.leaderOffset - 30) < 0.01, "\(edited.leaderOffset)")
        #expect(close(edited.measurementPoints[0], CGPoint(x: 100, y: 200)))
        #expect(abs(edited.measurementValue - 200) < 0.01)
        let saved = try #require(fixture.vm.document?.measurementAnnotations(pageIndex: 0).first)
        #expect(abs(saved.leaderOffset - 30) < 0.01, "\(saved.leaderOffset)")

        // Now offset, the dimension line itself drags it further.
        fixture.drag(page: 0, from: CGPoint(x: 140, y: 230), to: CGPoint(x: 140, y: 240))
        #expect(abs(try onlyMeasurement(fixture.vm).leaderOffset - 40) < 0.01)
    }

    @MainActor
    @Test func aPolygonCornerCanBeDraggedButItsInsideIsLeftForText() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        fixture.vm.isVertexSnapEnabled = false
        fixture.vm.isOrthoSnapEnabled = false
        let square = [CGPoint(x: 100, y: 300), CGPoint(x: 300, y: 300), CGPoint(x: 300, y: 500), CGPoint(x: 100, y: 500)]
        let (value, text) = fixture.vm.measured(.measureArea, points: square, pageIndex: 0)
        _ = try #require(fixture.vm.addMeasurementAnnotation(pageIndex: 0, type: .measureArea, points: square, value: value, formattedText: text))
        fixture.vm.canvasMode = .select

        fixture.click(page: 0, at: CGPoint(x: 200, y: 400))
        #expect(fixture.canvas.selectedAnnotation == nil)

        fixture.drag(page: 0, from: CGPoint(x: 300, y: 500), to: CGPoint(x: 400, y: 500))
        let edited = try onlyMeasurement(fixture.vm)
        #expect(close(edited.measurementPoints[2], CGPoint(x: 400, y: 500)))
        // 200 x 200 plus a 100 x 200 triangle.
        #expect(abs(edited.measurementValue - 50_000) < 0.5, "\(edited.measurementValue)")
    }

    @MainActor
    @Test func arrowKeysMoveASelectedMeasurement() async throws {
        let (fixture, original) = try await fixtureWithLength()
        defer { fixture.close() }
        fixture.canvas.nextResponder = KeySinkResponder()
        fixture.canvas.selectedAnnotation = (original.id, 0)
        fixture.canvas.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124)!)
        let moved = try onlyMeasurement(fixture.vm)
        #expect(close(moved.measurementPoints[0], CGPoint(x: 101, y: 200)))
        #expect(fixture.canvas.selectedAnnotation?.id == moved.id)
    }

    @MainActor
    @Test func theColorButtonRecolorsTheSelectedMeasurement() async throws {
        let (fixture, original) = try await fixtureWithLength()
        defer { fixture.close() }
        fixture.click(page: 0, at: CGPoint(x: 130, y: 200))
        #expect(fixture.canvas.selectedAnnotation?.id == original.id)
        fixture.vm.selectedAnnotationColor = .blue
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(try onlyMeasurement(fixture.vm).color == .blue)
    }

    @MainActor
    @Test func aMeasurementFromASavedFileCanBeChanged() async throws {
        // Measure, save, and open the file again.
        let src = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_measure_edit_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        makeLabelledPDF(at: src, labels: ["Alpha"])
        do {
            let vm = PDFViewerViewModel()
            vm.isTransientWindow = true
            await vm.loadDocument(from: src.path)
            _ = try #require(addLength(to: vm))
            vm.saveDocument()
        }
        let fixture = try await selectFixture(opening: src)
        defer { fixture.close() }
        let before = try #require(fixture.vm.document?.measurementAnnotations(pageIndex: 0).first?.documentObjectNumber)
        #expect(fixture.vm.pageAnnotations[0]?.isEmpty ?? true)

        fixture.drag(page: 0, from: CGPoint(x: 300, y: 200), to: CGPoint(x: 300, y: 260))
        let edited = try onlyMeasurement(fixture.vm)
        #expect(close(edited.measurementPoints[1], CGPoint(x: 300, y: 260)))
        // The page picture, made from the file as it was opened, leaves the old one out.
        #expect(fixture.vm.hiddenAnnotationNumbers[0]?.contains(before) == true)

        // Deleting it keeps it out of the picture, too.
        fixture.canvas.deleteSelectedAnnotation()
        #expect(fixture.vm.document?.measurementAnnotations(pageIndex: 0).isEmpty == true)
        #expect(fixture.vm.hiddenAnnotationNumbers[0]?.contains(before) == true)
    }

    @MainActor
    private func selectFixture(opening file: URL) async throws -> CanvasFixture {
        let fixture = try await CanvasFixture(view: .single, file: file)
        fixture.vm.isVertexSnapEnabled = false
        fixture.vm.isOrthoSnapEnabled = false
        fixture.vm.canvasMode = .select
        return fixture
    }

    @MainActor
    @Test func holdingShiftSwitchesOrthoLockForOneLine() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        fixture.vm.isVertexSnapEnabled = false
        let from = CGPoint(x: 100, y: 100)
        let skew = CGPoint(x: 200, y: 130)   // 17° off horizontal
        func snapped(shift: Bool) -> CGPoint {
            fixture.canvas.applySnapping(to: skew, fromPoint: from, inPage: 0, modifierFlags: shift ? .shift : [])
        }
        // Ortho Lock on: level, unless ⇧ frees it.
        fixture.vm.isOrthoSnapEnabled = true
        #expect(abs(snapped(shift: false).y - 100) < 0.01)
        #expect(snapped(shift: true) == skew)
        // Ortho Lock off: free, unless ⇧ keeps it level.
        fixture.vm.isOrthoSnapEnabled = false
        #expect(snapped(shift: false) == skew)
        #expect(abs(snapped(shift: true).y - 100) < 0.01)
    }

    @MainActor
    @Test func clickingTheActiveToolPutsItDown() {
        let vm = PDFViewerViewModel()
        vm.toggleTool(.measureArea)
        #expect(vm.canvasMode == .measureArea)
        vm.toggleTool(.measureLength)
        #expect(vm.canvasMode == .measureLength)
        vm.toggleTool(.measureLength)
        #expect(vm.canvasMode == .select)
        vm.toggleTool(.stamp)
        vm.pendingSignatureData = Data([1])
        vm.toggleTool(.stamp)
        #expect(vm.canvasMode == .select && vm.pendingSignatureData == nil)
    }
}
