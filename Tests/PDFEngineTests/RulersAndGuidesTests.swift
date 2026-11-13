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
import Testing
@testable import PDFEngine

/// Rulers' marks, guides, the grid and snapping to them.
@Suite(.serialized)
struct RulersAndGuidesTests {
    @Test func pointsSnapToTheNearestGuideOrGridLineWithinReach() {
        // Guides win over a grid line as near.
        #expect(GuideSnapping.snap(103, guides: [100], gridSpacing: 10, gridOrigin: 0, threshold: 4) == 100)
        #expect(GuideSnapping.snap(108, guides: [100], gridSpacing: 10, gridOrigin: 0, threshold: 4) == 110)
        #expect(GuideSnapping.snap(105, guides: [], gridSpacing: 10, gridOrigin: 0, threshold: 4) == nil)
        // The grid is drawn from the page's corner.
        #expect(GuideSnapping.snap(13, guides: [], gridSpacing: 10, gridOrigin: 2, threshold: 2) == 12)
        let snapped = GuideSnapping.snap(CGPoint(x: 51, y: 77), guides: [PageGuide(isVertical: true, position: 50)], gridSpacing: nil, pageOrigin: .zero, threshold: 3)
        #expect(snapped.didSnap && snapped.point == CGPoint(x: 50, y: 77))
    }

    @Test func rulerMarksAreSpacedForTheZoom() {
        // At 100%, a millimetre is 2.83 pixels: numbers every 50 mm would crowd less than 20.
        let mm = RulerSteps.choose(unit: .millimeters, pixelsPerUnit: 72 / 25.4)
        #expect(mm.major == 50 && mm.minorCount == 5)
        let zoomed = RulerSteps.choose(unit: .millimeters, pixelsPerUnit: 72 / 25.4 * 8)
        #expect(zoomed.major == 5 && zoomed.minorCount == 5)
        let inches = RulerSteps.choose(unit: .inches, pixelsPerUnit: 72)
        #expect(inches.major == 1 && inches.minorCount == 8)
        // Never more minor marks than fit.
        let far = RulerSteps.choose(unit: .inches, pixelsPerUnit: 4)
        #expect(far.major * 4 >= 60)
        #expect(far.major / Double(far.minorCount) * 4 >= 4)
        #expect(PageRulerView.label(0.5) == "0.5" && PageRulerView.label(20) == "20")
    }

    @Test func gridSpacingsAreOfferedInTheChosenUnits() {
        let mm = GridSpacingChoice.choices(for: .millimeters)
        #expect(mm.contains { $0.title == "10 mm" && abs($0.points - 72 / 25.4 * 10) < 0.0001 })
        #expect(GridSpacingChoice.choices(for: .inches).contains { $0.title == "1/4 in" && $0.points == 18 })
    }

    @MainActor
    @Test func guidesAreKeptPerPageAndMeasurementsSnapToThem() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_guides_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        makeLabelledPDF(at: url, labels: ["One", "Two"])
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let coordinator = PDFViewerAppCoordinator.shared
        let saved = (coordinator.snapsToGuidesAndGrid, coordinator.showsGrid)
        defer { (coordinator.snapsToGuidesAndGrid, coordinator.showsGrid) = saved }
        coordinator.snapsToGuidesAndGrid = true
        coordinator.showsGrid = false

        let guide = vm.addGuide(onPage: 0, isVertical: false, position: 200)
        #expect(vm.guides(onPage: 0) == [guide])
        #expect(vm.guides(onPage: 1).isEmpty)
        let reach = 6 / vm.effectiveZoom
        #expect(vm.snapToGuidesAndGrid(CGPoint(x: 80, y: 200 + reach / 2), onPage: 0) == CGPoint(x: 80, y: 200))
        #expect(vm.snapToGuidesAndGrid(CGPoint(x: 80, y: 200 + reach * 2), onPage: 0) == nil)
        #expect(vm.snapToGuidesAndGrid(CGPoint(x: 80, y: 201), onPage: 1) == nil)

        coordinator.snapsToGuidesAndGrid = false
        #expect(vm.snapToGuidesAndGrid(CGPoint(x: 80, y: 201), onPage: 0) == nil)
        coordinator.snapsToGuidesAndGrid = true

        vm.moveGuide(guide.id, onPage: 0, to: 300)
        #expect(vm.guides(onPage: 0).first?.position == 300)
        vm.removeGuide(guide.id, onPage: 0)
        #expect(vm.pageGuides.isEmpty)
        vm.addGuide(onPage: 1, isVertical: true, position: 10)
        vm.clearGuides()
        #expect(vm.pageGuides.isEmpty)
    }
}
