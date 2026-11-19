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
import Foundation
import Testing
@testable import PDFEngine

/// Areas measured as rectangles and circles, and lengths along arcs: their geometry, drawing them
/// on the page, editing them by the points that define them, and how they're saved.
@Suite(.serialized)
struct MeasuredShapeTests {
    private func close(_ a: CGPoint, _ b: CGPoint, within tolerance: CGFloat = 0.01) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
    }

    @Test func rectanglesAndCircles() throws {
        let rect = try #require(MeasuredShape(kind: .rectangle, points: [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 70)]))
        #expect(rect.value == 5000)
        #expect(rect.outline == [CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 20), CGPoint(x: 110, y: 70), CGPoint(x: 10, y: 70)])
        #expect(rect.measurementType == .measureArea)

        let circle = try #require(MeasuredShape(kind: .circle, points: [CGPoint(x: 200, y: 200), CGPoint(x: 250, y: 200)]))
        #expect(circle.radius == 50)
        #expect(abs(circle.value - .pi * 2500) < 1e-9)
        // Traced closely enough that other apps measuring the outline get nearly the same.
        #expect(circle.outline.count == 180)
        let traced = PDFMeasurementGeometry.shoelaceArea(points: circle.outline)
        #expect(abs(traced - circle.value) / circle.value < 0.0005)
        #expect(circle.outline.allSatisfy { abs(hypot($0.x - 200, $0.y - 200) - 50) < 1e-6 })
        #expect(MeasuredShape(kind: .circle, points: [CGPoint.zero]) == nil)
    }

    @Test func arcs() throws {
        // A quarter of a circle of radius 100 round the origin, either way round.
        let diagonal: CGFloat = 100 * CGFloat(cos(Double.pi / 4))
        let quarter: [CGPoint] = [CGPoint(x: 100, y: 0), CGPoint(x: diagonal, y: diagonal), CGPoint(x: 0, y: 100)]
        let quarterLength: Double = Double.pi / 2 * 100
        for points in [quarter, Array(quarter.reversed())] {
            let arc = try #require(MeasuredShape(kind: .arc, points: points))
            #expect(abs(arc.value - quarterLength) < 1e-6)
            #expect(abs(arc.radius - 100) < 1e-6)
            #expect(close(arc.outline.first!, points.first!) && close(arc.outline.last!, points.last!))
            // Through the middle point, not the other way round the circle.
            #expect(arc.outline.allSatisfy { $0.x >= -1e-6 && $0.y >= -1e-6 })
            let traced = PDFMeasurementGeometry.polylineLength(points: arc.outline)
            #expect(abs(traced - arc.value) / arc.value < 0.0005)
        }
        // Three-quarters of the circle: the middle point is on the far side.
        let long = try #require(MeasuredShape(kind: .arc, points: [CGPoint(x: 100, y: 0), CGPoint(x: -100, y: 0), CGPoint(x: 0, y: 100)]))
        #expect(abs(long.value - 1.5 * Double.pi * 100) < 1e-6)
        // In a line: the straight distance.
        let straight = try #require(MeasuredShape(kind: .arc, points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)]))
        #expect(straight.value == 100)
        #expect(straight.outline.count == 2)
    }

    /// A circle drawn on the page is saved as an area other apps can read, and comes back as a
    /// circle, valued exactly, edited by its centre and edge.
    @MainActor
    @Test func aCircleDrawnOnThePageIsSavedAndEditedAsOne() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let vm = fixture.vm
        vm.isVertexSnapEnabled = false
        vm.isOrthoSnapEnabled = false
        vm.canvasMode = .measureCircle
        fixture.drag(page: 0, from: CGPoint(x: 200, y: 300), to: CGPoint(x: 260, y: 300))

        let drawn = try #require(vm.pageAnnotations[0]?.first(where: { $0.isMeasurement }))
        #expect(drawn.type == .measureArea && drawn.measuredShape?.kind == .circle)
        #expect(abs(drawn.measurementValue - .pi * 3600) < 0.5)
        #expect(drawn.measurementText.contains("Ø"))

        // In the file: a polygon area through 180 points, with the circle beside it.
        let saved = try #require(vm.document?.measurementAnnotations(pageIndex: 0).first)
        #expect(saved.measurementPoints.count == 180)
        #expect(saved.measuredShape?.kind == .circle)
        #expect(close(saved.measuredShape!.points[0], CGPoint(x: 200, y: 300), within: 0.1))
        #expect(abs(saved.measurementValue - .pi * 3600) < 0.5)

        // Dragging its edge handle changes the radius.
        vm.canvasMode = .select
        fixture.click(page: 0, at: CGPoint(x: 260, y: 300))
        fixture.drag(page: 0, from: CGPoint(x: 260, y: 300), to: CGPoint(x: 280, y: 300))
        let edited = try #require(vm.pageAnnotations[0]?.first(where: { $0.isMeasurement }))
        #expect(edited.measuredShape?.kind == .circle)
        #expect(abs(edited.measuredShape!.radius - 80) < 0.5, "\(String(describing: edited.measuredShape))")
        #expect(abs(edited.measurementValue - .pi * 6400) < 2)
        #expect(vm.document?.measurementAnnotations(pageIndex: 0).count == 1)
        #expect(abs((vm.document?.measurementAnnotations(pageIndex: 0).first?.measuredShape?.radius ?? 0) - 80) < 0.5)

        // Undo puts the first circle back, as a circle.
        vm.undoManager.undo()
        let restored = try #require(vm.pageAnnotations[0]?.first(where: { $0.isMeasurement }))
        #expect(abs((restored.measuredShape?.radius ?? 0) - 60) < 0.5)
        #expect(PDFViewerViewModel.takeoffTypeName(restored) == "Circle Area")
    }

    @MainActor
    @Test func rectanglesAreDraggedAndArcsClicked() async throws {
        let fixture = try await CanvasFixture(view: .single)
        defer { fixture.close() }
        let vm = fixture.vm
        vm.isVertexSnapEnabled = false
        vm.isOrthoSnapEnabled = false
        vm.canvasMode = .measureRectangle
        fixture.drag(page: 0, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150))
        vm.canvasMode = .measureArc
        fixture.click(page: 0, at: CGPoint(x: 400, y: 300))
        let diagonal: CGFloat = 100 * CGFloat(cos(Double.pi / 4))
        fixture.click(page: 0, at: CGPoint(x: 300 + diagonal, y: 300 + diagonal))
        fixture.click(page: 0, at: CGPoint(x: 300, y: 400))

        let measurements = (vm.pageAnnotations[0] ?? []).filter(\.isMeasurement)
        let rect = try #require(measurements.first { $0.measuredShape?.kind == .rectangle })
        #expect(abs(rect.measurementValue - 5000) < 1)
        let arc = try #require(measurements.first { $0.measuredShape?.kind == .arc })
        #expect(arc.type == .measurePerimeter)
        #expect(abs(arc.measurementValue - .pi / 2 * 100) < 1)
        #expect(PDFViewerViewModel.takeoffTypeName(arc) == "Arc Length")
        let entries = vm.takeoffEntries()
        #expect(entries.count == 2)
    }

    /// A shape whose outline another app has changed isn't that shape any more: the measurement
    /// is read as the polygon it is.
    @Test func aShapeTheVerticesNoLongerFollowIsDropped() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: ["Plan"])
        let doc = try PDFDocumentCore(filePath: url.path)
        let rect = try #require(MeasuredShape(kind: .rectangle, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 40)]))
        try doc.addPolygonDimension(pageIndex: 0, vertices: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 10), CGPoint(x: 70, y: 40)],
                                    text: "Area", red: 1, green: 0, blue: 0)
        let number = try #require(doc.lastAnnotationObjectNumber(pageIndex: 0))
        try doc.setMeasurementShape(pageIndex: 0, objectNumber: number, shape: rect)
        let read = try #require(doc.measurementAnnotations(pageIndex: 0).first)
        #expect(read.measuredShape == nil)
        #expect(read.measurementPoints.count == 3)
    }
}
