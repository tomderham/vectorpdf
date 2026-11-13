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
import Testing
@testable import PDFEngine

/// The status bar's figures: paper sizes, units, the size of a selection and a measurement's
/// figures while it's drawn.
struct CanvasReadoutTests {
    @Test func pagesAreNamedForThePaperTheyMatchEitherWayRound() {
        #expect(PaperSize.name(for: CGSize(width: 595.28, height: 841.89)) == "A4")
        #expect(PaperSize.name(for: CGSize(width: 842, height: 595)) == "A4")
        #expect(PaperSize.name(for: CGSize(width: 612, height: 792)) == "Letter")
        #expect(PaperSize.name(for: CGSize(width: 1224, height: 792)) == "Tabloid")
        #expect(PaperSize.name(for: CGSize(width: 2592, height: 1728)) == "ARCH D")
        #expect(PaperSize.name(for: CGSize(width: 2384, height: 3370)) == "A0")
        #expect(PaperSize.name(for: CGSize(width: 500, height: 500)) == nil)
    }

    @Test func positionsAndSizesAreGivenInTheChosenUnits() {
        #expect(ReadoutUnit.millimeters.format(72) == "25.4")
        #expect(ReadoutUnit.inches.format(36) == "0.50")
        #expect(ReadoutUnit.points.format(12.345) == "12.3")
        #expect(ReadoutUnit.millimeters.formatSize(CGSize(width: 595.28, height: 841.89)) == "210 × 297 mm")
        #expect(ReadoutUnit.inches.formatSize(CGSize(width: 612, height: 792)) == "8.5 × 11 in")
        #expect(ReadoutUnit.points.formatSize(CGSize(width: 612, height: 792)) == "612 × 792 pt")
        #expect(abs(ReadoutUnit.millimeters.points(fromValue: 25.4) - 72) < 0.0001)
    }

    @Test func aSelectionsWordsAndCharactersAreCounted() {
        let counts = CanvasReadout.counts(of: "The quick brown fox\njumps over it.")
        #expect(counts.words == 7)
        #expect(counts.characters == 33)
        #expect(CanvasReadout.counts(of: "").words == 0)
    }

    @Test func aLengthBeingDrawnGivesItsLengthAngleAndRun() {
        // 1:1 in millimetres: 72 pt is 25.4 mm.
        let scale = PDFScaleConfiguration.calibrated(measuredPoints: 72, knownRealWorldLength: 25.4, unit: .millimeters)
        let items = CanvasReadout.measurementItems(
            mode: .measureLength,
            points: [CGPoint(x: 100, y: 500)],
            // Up and to the right on the page, which is top-down.
            candidate: CGPoint(x: 172, y: 428),
            scale: scale
        )
        #expect(items.map(\.label) == ["Length", "Angle", "ΔX", "ΔY"])
        #expect(items[1].value == "45.0°")
        #expect(items[2].value == "25 mm" && items[3].value == "25 mm")
        #expect(items[0].value == "36 mm")
    }

    @Test func anAreaBeingDrawnGivesItsAreaAndPerimeterSoFar() {
        let scale = PDFScaleConfiguration.calibrated(measuredPoints: 72, knownRealWorldLength: 25.4, unit: .millimeters)
        let items = CanvasReadout.measurementItems(
            mode: .measureArea,
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 72, y: 0)],
            candidate: CGPoint(x: 72, y: 72),
            scale: scale
        )
        #expect(items.map(\.label) == ["Area", "Perimeter", "Segment"])
        // A right triangle with 25.4 mm legs: perimeter 25.4 + 25.4 + 35.9.
        #expect(items[1].value == "87 mm")
        #expect(items[2].value == "25 mm")
        // Nothing to show before the first point.
        #expect(CanvasReadout.measurementItems(mode: .measureArea, points: [], candidate: .zero, scale: scale).isEmpty)
    }
}
