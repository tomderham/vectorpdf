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

/// The Count tool: a marker per click, in named groups, saved in the PDF and totalled.
@MainActor
@Suite struct CountToolTests {
    private func plan(in dir: URL, pages: [String] = ["Alpha", "Bravo"]) -> URL {
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: pages)
        return url
    }

    @Test func markersAreSavedWithTheirGroupAndReadBack() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try PDFDocumentCore(filePath: plan(in: dir).path)
        try doc.addCountMarker(pageIndex: 0, center: CGPoint(x: 100, y: 200), group: "Outlets", red: 1, green: 0, blue: 0)
        try doc.addCountMarker(pageIndex: 0, center: CGPoint(x: 150, y: 220), group: "Outlets", red: 1, green: 0, blue: 0)
        try doc.addCountMarker(pageIndex: 0, center: CGPoint(x: 300, y: 400), group: "Type A Doors", red: 0, green: 0, blue: 1)
        let saved = dir.appendingPathComponent("Saved.pdf")
        try doc.save(to: saved.path)

        let markers = try PDFDocumentCore(filePath: saved.path).measurementAnnotations(pageIndex: 0)
        #expect(markers.count == 3)
        #expect(markers.allSatisfy { $0.type == .measureCount && $0.isMeasurement })
        #expect(markers.filter { $0.text == "Outlets" }.count == 2)
        let door = try #require(markers.first { $0.text == "Type A Doors" })
        #expect(abs(door.measurementPoints[0].x - 300) < 0.5 && abs(door.measurementPoints[0].y - 400) < 0.5)
        #expect(door.color == .blue)

        // Other apps see a circle, with the group as its text.
        let opened: PDFKit.PDFDocument? = PDFKit.PDFDocument(url: saved)
        let pdfKit = try #require(opened)
        let circles = pdfKit.page(at: 0)?.annotations.filter { $0.type == "Circle" } ?? []
        #expect(circles.count == 3)
        #expect(circles.contains { $0.contents == "Type A Doors" })
    }

    @Test func eachClickCountsOneInTheCurrentGroup() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try await CanvasFixture(view: .single, file: plan(in: dir))
        defer { fixture.close() }
        fixture.vm.canvasMode = .measureCount
        fixture.vm.countGroup = "Outlets"
        fixture.click(page: 0, at: CGPoint(x: 100, y: 300))
        fixture.click(page: 0, at: CGPoint(x: 200, y: 300))
        fixture.vm.countGroup = "Lights"
        fixture.click(page: 0, at: CGPoint(x: 300, y: 300))
        #expect(fixture.vm.countMarkers(onPage: 0, group: "Outlets") == 2)
        #expect(fixture.vm.countMarkers(onPage: 0, group: "Lights") == 1)
        #expect(fixture.vm.countGroupsInDocument() == ["Lights", "Outlets"])
        // Gray, as measurements are by default.
        #expect(fixture.vm.pageAnnotations[0]?.filter { $0.type == .measureCount }.allSatisfy { $0.color == .gray } == true)
        // Nothing is left selected, so the next click counts again.
        #expect(fixture.canvas.selectedAnnotation == nil)
    }

    @Test func takeoffRowsAndTotals() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: plan(in: dir).path)
        vm.countGroup = "Outlets"
        for x in [100, 150, 200] { vm.addCountMarker(pageIndex: 0, at: CGPoint(x: x, y: 200)) }
        vm.addCountMarker(pageIndex: 1, at: CGPoint(x: 100, y: 200))
        vm.countGroup = "Doors"
        vm.addCountMarker(pageIndex: 1, at: CGPoint(x: 200, y: 200))

        let entries = vm.takeoffEntries().filter { $0.annotation.type == .measureCount }
        #expect(entries.map(\.formattedValue) == ["3 Outlets", "1 Doors", "1 Outlets"])
        let totals = vm.takeoffCounts(entries)
        #expect(totals.map(\.group) == ["Doors", "Outlets"])
        #expect(totals.map(\.count) == [1, 4])
        let csv = vm.generateTakeoffSummaryCSV()
        #expect(csv.contains(",Count,") && csv.contains("\"3 Outlets\""))
        #expect(vm.generateTakeoffSummaryMarkdown().contains("**Count, Outlets:** 4"))
    }

    @Test func movingAMarkerKeepsItsGroup() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: plan(in: dir).path)
        vm.countGroup = "Outlets"
        let marker = try #require(vm.addCountMarker(pageIndex: 0, at: CGPoint(x: 100, y: 200)))
        let moved = vm.editedMeasurement(marker, points: [CGPoint(x: 140, y: 260)])
        let replaced = try #require(vm.replaceMeasurement(marker, with: moved))
        #expect(replaced.text == "Outlets")
        #expect(vm.countMarkers(onPage: 0, group: "Outlets") == 1)
        let point = try #require(vm.document?.measurementAnnotations(pageIndex: 0).first { $0.type == .measureCount }?.measurementPoints.first)
        #expect(abs(point.x - 140) < 0.5 && abs(point.y - 260) < 0.5)
    }

    @Test func aBlankGroupCountsAsCount() {
        let vm = PDFViewerViewModel()
        vm.countGroup = "   "
        #expect(vm.effectiveCountGroup == "Count")
    }
}

@MainActor
@Suite struct CountMarkerSelectionTests {
    @Test func aSavedMarkerCanBeSelectedAndDeleted() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha"])
        do {
            let doc = try PDFDocumentCore(filePath: url.path)
            try doc.addCountMarker(pageIndex: 0, center: CGPoint(x: 300, y: 400), group: "Outlets", red: 0.5, green: 0.5, blue: 0.5)
            try doc.save(to: url.path)
        }
        let fixture = try await CanvasFixture(view: .single, file: url)
        defer { fixture.close() }
        fixture.click(page: 0, at: CGPoint(x: 301, y: 401))
        let selected = try #require(fixture.canvas.selectedAnnotation)
        let marker = try #require(fixture.vm.pageAnnotations[0]?.first { $0.id == selected.id })
        #expect(marker.type == .measureCount && marker.text == "Outlets")
        fixture.vm.removeAnnotation(marker)
        #expect(fixture.vm.countMarkers(onPage: 0, group: "Outlets") == 0)
    }
}
