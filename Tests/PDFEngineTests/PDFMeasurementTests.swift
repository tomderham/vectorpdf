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

import Foundation
import CoreGraphics
import Testing
@testable import PDFEngine

@Suite("PDF Measurement Suite Tests")
struct PDFMeasurementTests {

    // MARK: - Architectural Foot-Inch Formatting Tests

    @Test("Architectural 1/4\" = 1'-0\" Preset Conversion")
    func testArchitecturalScalePresets() {
        guard let archQuarter = ScalePreset.standardPresets.first(where: { $0.id == "arch_1_4" }) else {
            Issue.record("arch_1_4 preset not found")
            return
        }
        
        let config = PDFScaleConfiguration(preset: archQuarter)
        #expect(config.linearUnit == .footInch)
        #expect(config.areaUnit == .squareFeet)
        
        // 1/4" on paper is 18 PDF points (72 / 4 = 18).
        // That represents 1 real foot.
        // Therefore, 72 points on paper represents exactly 4.0 feet (48 inches).
        let feet = config.convertPointsToReal(pointsDistance: 72.0)
        #expect(abs(feet - 4.0) < 0.001)
        
        let formatted = config.formatLength(pointsDistance: 72.0)
        #expect(formatted == "4'-0\"")
    }

    @Test("Architectural Fractional Inch Formatting")
    func testArchitecturalFractionalInches() {
        guard let archQuarter = ScalePreset.standardPresets.first(where: { $0.id == "arch_1_4" }) else {
            Issue.record("arch_1_4 preset not found")
            return
        }
        
        let config = PDFScaleConfiguration(preset: archQuarter)
        
        // 1 foot = 18 points.
        // 1 inch = 18 / 12 = 1.5 points.
        // Let's test 14 feet, 6.5 inches = 14 * 18 + 6.5 * 1.5 = 252 + 9.75 = 261.75 points.
        let formattedHalf = config.formatLength(pointsDistance: 261.75)
        #expect(formattedHalf == "14'-6 1/2\"")
        
        // Test 1/4 fraction: 10 feet, 3.25 inches = 10 * 18 + 3.25 * 1.5 = 180 + 4.875 = 184.875 points.
        let formattedQuarter = config.formatLength(pointsDistance: 184.875)
        #expect(formattedQuarter == "10'-3 1/4\"")
        
        // Test 0 inches with 1/2 fraction: 5 feet, 0.5 inches = 5 * 18 + 0.5 * 1.5 = 90 + 0.75 = 90.75 points.
        let formattedZeroInchFrac = config.formatLength(pointsDistance: 90.75)
        #expect(formattedZeroInchFrac == "5'-1/2\"")
        
        // Test exact inches without fraction: 2 feet, 7 inches = 2 * 18 + 7 * 1.5 = 36 + 10.5 = 46.5 points.
        let formattedWholeInches = config.formatLength(pointsDistance: 46.5)
        #expect(formattedWholeInches == "2'-7\"")
    }

    // MARK: - Metric & Engineering Scale Tests

    @Test("Metric 1:50 Scale Formatting")
    func testMetricScale() {
        guard let metric50 = ScalePreset.standardPresets.first(where: { $0.id == "met_1_50" }) else {
            Issue.record("met_1_50 preset not found")
            return
        }
        
        let config = PDFScaleConfiguration(preset: metric50)
        #expect(config.linearUnit == .meters)
        #expect(config.areaUnit == .squareMeters)
        
        // At 1:50, 1 meter = 1000 mm.
        // 1 mm in PDF points = 72 / 25.4 points ≈ 2.8346 points.
        // At 1:50, 1 meter on paper is 1000 / 50 = 20 mm = 20 * (72 / 25.4) ≈ 56.6929 points.
        let ptsPerMeter = config.pointsPerUnit
        let measuredMeters = config.convertPointsToReal(pointsDistance: ptsPerMeter * 2.5)
        #expect(abs(measuredMeters - 2.5) < 0.001)
        
        let formatted = config.formatLength(pointsDistance: ptsPerMeter * 2.5)
        #expect(formatted == "2.50 m")
    }

    @Test("Civil Engineering 1 in = 10 ft Scale")
    func testCivilEngineeringScale() {
        guard let civil10 = ScalePreset.standardPresets.first(where: { $0.id == "eng_10" }) else {
            Issue.record("eng_10 preset not found")
            return
        }
        
        let config = PDFScaleConfiguration(preset: civil10)
        #expect(config.linearUnit == .decimalFeet)
        
        // 1 inch on drawing (72 points) = 10 feet.
        // 72 / 10 = 7.2 points per foot.
        let ptsFor25Feet = 25.0 * 7.2
        let formatted = config.formatLength(pointsDistance: ptsFor25Feet)
        #expect(formatted == "25.00 ft")
    }

    // MARK: - Interactive 2-Point Calibration

    @Test("Two-Point Interactive Calibration")
    func testInteractiveCalibration() {
        // Suppose user measures a dimension line of 144 points (2 inches on page)
        // and enters that it equals 12.0 feet.
        let config = PDFScaleConfiguration.calibrated(
            measuredPoints: 144.0,
            knownRealWorldLength: 12.0,
            unit: .footInch,
            label: "Custom 144pt = 12ft"
        )
        
        #expect(config.pointsPerUnit == 12.0) // 144 / 12 = 12 points per foot
        #expect(config.label == "Custom 144pt = 12ft")
        
        let formatted = config.formatLength(pointsDistance: 120.0) // 10 feet
        #expect(formatted == "10'-0\"")
    }

    // MARK: - Area Calculation Tests

    @Test("Area Calculation and Formatting")
    func testAreaCalculations() {
        guard let archQuarter = ScalePreset.standardPresets.first(where: { $0.id == "arch_1_4" }) else {
            Issue.record("arch_1_4 preset not found")
            return
        }
        
        let config = PDFScaleConfiguration(preset: archQuarter)
        // 1 foot = 18 points.
        // A room of 10 ft by 20 ft = 200 sq ft.
        // Points area = (10 * 18) * (20 * 18) = 180 * 360 = 64,800 points^2.
        let pointsArea = 180.0 * 360.0
        let realArea = config.convertAreaPointsToReal(pointsArea: pointsArea)
        #expect(abs(realArea - 200.0) < 0.001)
        
        let formattedArea = config.formatArea(pointsArea: pointsArea)
        #expect(formattedArea == "200.0 sq ft")
    }

    // MARK: - Geometry Engine Tests

    @Test("Shoelace Polygon Area Algorithm")
    func testShoelaceArea() {
        // Rectangle 100 x 50
        let rectPoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 50),
            CGPoint(x: 0, y: 50)
        ]
        let rectArea = PDFMeasurementGeometry.shoelaceArea(points: rectPoints)
        #expect(rectArea == 5000.0)
        
        // Right triangle base 60, height 40 -> area 1200
        let triPoints = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 60, y: 0),
            CGPoint(x: 0, y: 40)
        ]
        let triArea = PDFMeasurementGeometry.shoelaceArea(points: triPoints)
        #expect(triArea == 1200.0)
        
        // Degenerate polygon (< 3 points)
        #expect(PDFMeasurementGeometry.shoelaceArea(points: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]) == 0.0)
    }

    @Test("Angular Trigonometry Angle Calculation")
    func testAngleCalculation() {
        // 90 degree angle
        let r1_90 = CGPoint(x: 100, y: 0)
        let apex_90 = CGPoint(x: 0, y: 0)
        let r2_90 = CGPoint(x: 0, y: 100)
        let angle90 = PDFMeasurementGeometry.angleDegrees(r1: r1_90, apex: apex_90, r2: r2_90)
        #expect(abs(angle90 - 90.0) < 0.001)
        
        // 45 degree angle
        let r1_45 = CGPoint(x: 100, y: 0)
        let apex_45 = CGPoint(x: 0, y: 0)
        let r2_45 = CGPoint(x: 100, y: 100)
        let angle45 = PDFMeasurementGeometry.angleDegrees(r1: r1_45, apex: apex_45, r2: r2_45)
        #expect(abs(angle45 - 45.0) < 0.001)
        
        // 180 degree straight line
        let r1_180 = CGPoint(x: 100, y: 0)
        let apex_180 = CGPoint(x: 0, y: 0)
        let r2_180 = CGPoint(x: -100, y: 0)
        let angle180 = PDFMeasurementGeometry.angleDegrees(r1: r1_180, apex: apex_180, r2: r2_180)
        #expect(abs(angle180 - 180.0) < 0.001)
    }

    @Test("Cumulative Polyline Length")
    func testPolylineLength() {
        let pts = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 30, y: 40),  // dist = 50
            CGPoint(x: 30, y: 140)  // dist = 100
        ]
        let total = PDFMeasurementGeometry.polylineLength(points: pts)
        #expect(abs(total - 150.0) < 0.001)
    }

    // MARK: - Snapping Engine Tests

    @Test("Orthogonal Snapping (0°, 45°, 90°)")
    func testOrthoSnapping() {
        let origin = CGPoint(x: 50, y: 50)
        
        // Horizontal constraint near 0°: (150, 52) should snap to (150, 50)
        let nearHoriz = CGPoint(x: 150, y: 52)
        let snappedHoriz = PDFMeasurementGeometry.snapOrtho(origin: origin, target: nearHoriz)
        #expect(abs(snappedHoriz.y - 50.0) < 0.01)
        #expect(abs(snappedHoriz.x - 150.0) < 0.1)
        
        // Vertical constraint near 90°: (53, 150) should snap to (50, 150)
        let nearVert = CGPoint(x: 53, y: 150)
        let snappedVert = PDFMeasurementGeometry.snapOrtho(origin: origin, target: nearVert)
        #expect(abs(snappedVert.x - 50.0) < 0.01)
        #expect(abs(snappedVert.y - 150.0) < 0.1)
        
        // 45 degree constraint near (150, 153)
        let near45 = CGPoint(x: 150, y: 153)
        let snapped45 = PDFMeasurementGeometry.snapOrtho(origin: origin, target: near45)
        let dx = snapped45.x - origin.x
        let dy = snapped45.y - origin.y
        #expect(abs(dx - dy) < 0.01)
    }

    @Test("Magnetic Vertex Snapping")
    func testVertexSnapping() {
        let vertices = [
            CGPoint(x: 100, y: 100),
            CGPoint(x: 200, y: 200)
        ]
        
        // Candidate within snap radius (distance = hypot(3, 4) = 5 <= 8)
        let candidateNear = CGPoint(x: 103, y: 104)
        let resultNear = PDFMeasurementGeometry.snapVertex(candidate: candidateNear, vertices: vertices, radius: 8.0)
        #expect(resultNear.snapped == true)
        #expect(resultNear.point == CGPoint(x: 100, y: 100))
        
        // Candidate outside snap radius (distance = hypot(10, 10) ≈ 14.14 > 8)
        let candidateFar = CGPoint(x: 110, y: 110)
        let resultFar = PDFMeasurementGeometry.snapVertex(candidate: candidateFar, vertices: vertices, radius: 8.0)
        #expect(resultFar.snapped == false)
        #expect(resultFar.point == candidateFar)
    }

    // MARK: - Annotation Data Model & Hit Testing Tests

    @Test("Measurement Annotation Properties and Bounding Box")
    func testAnnotationDataModel() {
        let annot = PDFAnnotation(
            id: UUID(),
            pageIndex: 0,
            type: PDFAnnotationType.measureLength,
            strokeWidth: 2.0,
            color: AnnotationColor.blue,
            measurementPoints: [CGPoint(x: 20, y: 30), CGPoint(x: 120, y: 150)],
            measurementValue: 10.0,
            measurementText: "10'-0\""
        )
        
        #expect(annot.isMeasurement == true)
        #expect(annot.measurementFormattedText == "10'-0\"")
        #expect(annot.points.count == 2)
        
        let bbox = annot.boundingBox
        #expect(bbox.minX <= 20)
        #expect(bbox.maxX >= 120)
        #expect(bbox.minY <= 30)
        #expect(bbox.maxY >= 150)
        
        // Hit test near the midpoint of the line: (70, 90)
        #expect(annot.contains(point: CGPoint(x: 70, y: 90), tolerance: 6.0) == true)
        // Far point should miss
        #expect(annot.contains(point: CGPoint(x: 0, y: 0), tolerance: 4.0) == false)
    }

    // MARK: - Takeoff Schedule Export Tests

    private static func scale(fromPreset id: String, areaUnit: AreaUnit) -> PDFScaleConfiguration {
        let preset = ScalePreset.standardPresets.first { $0.id == id }!
        return PDFScaleConfiguration(
            name: preset.name,
            pointsPerUnit: preset.pointsPerUnit,
            linearUnit: preset.linearUnit,
            areaUnit: areaUnit,
            precisionFractionDenominator: 16,
            ratioString: preset.name
        )
    }

    @Test("Takeoff Schedule Markdown and CSV Generation")
    @MainActor
    func testTakeoffExports() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takeoff_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        createSamplePDF(at: url)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        // 1/4" = 1'-0": 18 pt per foot.
        vm.setScaleConfig(Self.scale(fromPreset: "arch_1_4", areaUnit: .squareFeet), for: 0, applyToAll: true)

        #expect(vm.addMeasurementAnnotation(
            pageIndex: 0, type: .measureLength,
            points: [CGPoint(x: 100, y: 100), CGPoint(x: 172, y: 100)],
            value: 72, formattedText: "4'-0\"", color: .blue
        ) != nil)
        #expect(vm.addMeasurementAnnotation(
            pageIndex: 0, type: .measureArea,
            points: [CGPoint(x: 100, y: 200), CGPoint(x: 190, y: 200), CGPoint(x: 190, y: 254), CGPoint(x: 100, y: 254)],
            value: 90 * 54, formattedText: "15.0 sq ft", color: .green
        ) != nil)

        let csv = vm.generateTakeoffSummaryCSV()
        #expect(csv.contains("Linear Dimension"))
        #expect(csv.contains("Area Takeoff"))
        #expect(csv.contains("4'-0"))
        // 90 × 54 pt at 18 pt/ft is 5 × 3 ft = 15 sq ft; the value column is real-world, not points.
        #expect(csv.contains("15.0 sq ft"))
        #expect(csv.contains("4.000,\"ft\""))
        #expect(csv.contains("15.000,\"sq ft\""))

        let md = vm.generateTakeoffSummaryMarkdown()
        #expect(md.contains("# Measurement Takeoff Summary"))
        #expect(md.contains("Linear Dimension"))
        #expect(md.contains("Area Takeoff"))
        #expect(md.contains("Total Linear Footage / Perimeter:** 4'-0\""))
        #expect(md.contains("Total Calculated Surface Area:** 15.0 sq ft"))

        // Measurements are read from the document, so they're still there after saving and reopening.
        vm.saveDocument()
        let reopened = PDFViewerViewModel()
        reopened.isTransientWindow = true
        await reopened.loadDocument(from: url.path)
        let entries = reopened.takeoffEntries()
        #expect(entries.map(\.annotation.type) == [.measureLength, .measureArea])
        #expect(entries.first?.formattedValue == "4'-0\"")
    }

    @Test("Takeoff totals convert each page with its own scale")
    @MainActor
    func testTakeoffTotalsAcrossScales() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("takeoff_scales_\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        createSamplePDF(at: url)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        vm.setScaleConfig(Self.scale(fromPreset: "met_1_100", areaUnit: .squareMeters), for: 0)
        vm.setScaleConfig(Self.scale(fromPreset: "met_1_50", areaUnit: .squareMeters), for: 1)

        // 10 m on page 1 at 1:100, and 5 m on page 2 at 1:50 — the same length on paper.
        let tenMetersAt100 = 2834.64567 / 100.0 * 10.0
        _ = vm.addMeasurementAnnotation(pageIndex: 0, type: .measureLength, points: [CGPoint(x: 50, y: 50), CGPoint(x: 50 + tenMetersAt100, y: 50)], value: tenMetersAt100, formattedText: "10.00 m")
        _ = vm.addMeasurementAnnotation(pageIndex: 1, type: .measureLength, points: [CGPoint(x: 50, y: 50), CGPoint(x: 50 + tenMetersAt100, y: 50)], value: tenMetersAt100, formattedText: "5.00 m")

        let entries = vm.takeoffEntries()
        #expect(entries.map(\.formattedValue) == ["10.00 m", "5.00 m"])
        #expect(vm.takeoffTotals(entries).linear == "15.00 m")
    }

    @Test("Metric 1:100 Default Scale and Print Measurement Detection")
    @MainActor
    func testMetricDefaultScale() {
        let defaultConfig = PDFScaleConfiguration()
        #expect(defaultConfig.name == "1:100")
        #expect(defaultConfig.linearUnit == .meters)
        #expect(defaultConfig.areaUnit == .squareMeters)
        #expect(abs(defaultConfig.pointsPerUnit - (2834.64567 / 100.0)) < 0.001)

        #expect(ScaleCategory.allCases.first == .metric)
        
        let vm = PDFViewerViewModel()
        #expect(vm.currentScaleConfig.name == "1:100")
        #expect(vm.currentScaleConfig.linearUnit == .meters)
        #expect(vm.hasMeasurementAnnotations == false)

        vm.pageAnnotations[0] = [
            PDFAnnotation(
                pageIndex: 0,
                type: .measureLength,
                measurementPoints: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0)]
            )
        ]
        #expect(vm.hasMeasurementAnnotations == true)
    }

    @Test("Area Takeoff Defaults to Square Meters")
    func testAreaTakeoffDefaults() {
        #expect(AreaUnit.allCases.first == .squareMeters)
        let calibrated = PDFScaleConfiguration.calibrated(
            measuredPoints: 100.0,
            knownRealWorldLength: 10.0,
            unit: .meters
        )
        #expect(calibrated.areaUnit == .squareMeters)
    }

    @Test("Measurement Annotations Save to PDF Core Without DA Error")
    @MainActor
    func testMeasurementAnnotationsPDFCoreIntegration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let pdfURL = tempDir.appendingPathComponent("test_measurements_\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
            Issue.record("Failed to create CGContext")
            return
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: pdfURL.path)
        guard let doc = vm.document else {
            Issue.record("Document failed to load")
            return
        }

        // Test 1: Line dimension
        try doc.addLineDimension(
            pageIndex: 0,
            startPoint: CGPoint(x: 100, y: 200),
            endPoint: CGPoint(x: 300, y: 200),
            leaderOffset: 15.0,
            text: "2.00 m",
            red: 0.0,
            green: 0.5,
            blue: 1.0
        )

        // Test 2: Polyline dimension
        try doc.addPolylineDimension(
            pageIndex: 0,
            vertices: [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150), CGPoint(x: 300, y: 100)],
            text: "3.50 m",
            red: 0.2,
            green: 0.8,
            blue: 0.2
        )

        // Test 3: Polygon dimension
        try doc.addPolygonDimension(
            pageIndex: 0,
            vertices: [CGPoint(x: 100, y: 300), CGPoint(x: 200, y: 300), CGPoint(x: 200, y: 400), CGPoint(x: 100, y: 400)],
            text: "10.00 sq m",
            red: 1.0,
            green: 0.4,
            blue: 0.0
        )

        // Test 4: via ViewModel
        let annot1 = vm.addMeasurementAnnotation(
            pageIndex: 0,
            type: .measureLength,
            points: [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50)],
            value: 100.0,
            formattedText: "1.00 m",
            leaderOffset: 0.0,
            color: .blue,
            strokeWidth: 1.5
        )
        #expect(annot1 != nil)

        let annot2 = vm.addMeasurementAnnotation(
            pageIndex: 0,
            type: .measureArea,
            points: [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50), CGPoint(x: 150, y: 150), CGPoint(x: 50, y: 150)],
            value: 10000.0,
            formattedText: "12.50 sq m",
            color: .green,
            strokeWidth: 1.5
        )
        #expect(annot2 != nil)
        #expect(vm.pageAnnotations[0]?.count == 2)
    }
}
