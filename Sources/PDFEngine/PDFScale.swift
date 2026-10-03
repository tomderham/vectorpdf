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

/// Unit of measurement for linear distances.
public enum MeasurementUnit: String, Codable, CaseIterable, Sendable {
    case footInch = "ft-in"
    case decimalFeet = "ft"
    case inches = "in"
    case millimeters = "mm"
    case centimeters = "cm"
    case meters = "m"

    public var displayName: String {
        switch self {
        case .footInch: return "Feet & Inches (12'-4 1/2\")"
        case .decimalFeet: return "Decimal Feet (ft)"
        case .inches: return "Inches (in)"
        case .millimeters: return "Millimeters (mm)"
        case .centimeters: return "Centimeters (cm)"
        case .meters: return "Meters (m)"
        }
    }

    public var shortSymbol: String {
        switch self {
        case .footInch: return "ft-in"
        case .decimalFeet: return "ft"
        case .inches: return "in"
        case .millimeters: return "mm"
        case .centimeters: return "cm"
        case .meters: return "m"
        }
    }
}

/// Unit of measurement for surface area takeoffs.
public enum AreaUnit: String, Codable, CaseIterable, Sendable {
    case squareMeters = "sq m"
    case squareFeet = "sq ft"
    case squareYards = "sq yd"
    case squareInches = "sq in"

    public var displayName: String {
        switch self {
        case .squareMeters: return "Square Meters (sq m)"
        case .squareFeet: return "Square Feet (sq ft)"
        case .squareYards: return "Square Yards (sq yd)"
        case .squareInches: return "Square Inches (sq in)"
        }
    }

    public var shortSymbol: String {
        switch self {
        case .squareMeters: return "sq m"
        case .squareFeet: return "sq ft"
        case .squareYards: return "sq yd"
        case .squareInches: return "sq in"
        }
    }
}

/// Category grouping for standard drawing scales.
public enum ScaleCategory: String, CaseIterable, Sendable {
    case metric = "Metric (ISO)"
    case architectural = "Architectural (US)"
    case engineering = "Civil Engineering (US)"
    case custom = "Custom"
}

/// Predefined standard drawing scale presets.
public struct ScalePreset: Identifiable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let category: ScaleCategory
    public let ratioString: String
    /// PDF points (1/72 inch) per 1 unit of linearUnit.
    public let pointsPerUnit: Double
    public let linearUnit: MeasurementUnit
    public let areaUnit: AreaUnit

    public init(id: String, name: String, category: ScaleCategory, ratioString: String, pointsPerUnit: Double, linearUnit: MeasurementUnit, areaUnit: AreaUnit) {
        self.id = id
        self.name = name
        self.category = category
        self.ratioString = ratioString
        self.pointsPerUnit = pointsPerUnit
        self.linearUnit = linearUnit
        self.areaUnit = areaUnit
    }

    /// All standard AEC industry scales.
    public static let standardPresets: [ScalePreset] = [
        // Metric (ISO). `pointsPerUnit` is per one *real-world* unit of `linearUnit`, so it depends
        // on that unit as well as the ratio:
        // 1 meter on paper = 39.3700787 inches = 2834.64567 pt.
        // Scale 1:50 -> 1 real meter = 2834.64567 / 50 = 56.6929 pt.
        // Scale 1:1  -> 1 real millimeter = 2834.64567 / 1000 = 2.83465 pt.
        // Scale 1:10 -> 1 real centimeter = 2834.64567 / 10 / 100 = 2.83465 pt.
        ScalePreset(id: "met_1_1", name: "1:1", category: .metric, ratioString: "1:1", pointsPerUnit: 2834.64567 / 1000.0, linearUnit: .millimeters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_10", name: "1:10", category: .metric, ratioString: "1:10", pointsPerUnit: 2834.64567 / 10.0 / 100.0, linearUnit: .centimeters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_20", name: "1:20", category: .metric, ratioString: "1:20", pointsPerUnit: 2834.64567 / 20.0, linearUnit: .meters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_50", name: "1:50", category: .metric, ratioString: "1:50", pointsPerUnit: 2834.64567 / 50.0, linearUnit: .meters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_100", name: "1:100", category: .metric, ratioString: "1:100", pointsPerUnit: 2834.64567 / 100.0, linearUnit: .meters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_200", name: "1:200", category: .metric, ratioString: "1:200", pointsPerUnit: 2834.64567 / 200.0, linearUnit: .meters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_500", name: "1:500", category: .metric, ratioString: "1:500", pointsPerUnit: 2834.64567 / 500.0, linearUnit: .meters, areaUnit: .squareMeters),
        ScalePreset(id: "met_1_1000", name: "1:1000", category: .metric, ratioString: "1:1000", pointsPerUnit: 2834.64567 / 1000.0, linearUnit: .meters, areaUnit: .squareMeters),

        // Architectural (US Imperial): 1/72 pt per inch.
        // E.g. 1/4" = 1'-0": 1/4 in on paper = 18 pt. 1 ft in real world = 18 pt.
        // So 1 ft = 18.0 pt.
        ScalePreset(id: "arch_1_16", name: "1/16\" = 1'-0\"", category: .architectural, ratioString: "1/16\" = 1'-0\"", pointsPerUnit: 72.0 * (1.0 / 16.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_3_32", name: "3/32\" = 1'-0\"", category: .architectural, ratioString: "3/32\" = 1'-0\"", pointsPerUnit: 72.0 * (3.0 / 32.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_1_8", name: "1/8\" = 1'-0\"", category: .architectural, ratioString: "1/8\" = 1'-0\"", pointsPerUnit: 72.0 * (1.0 / 8.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_3_16", name: "3/16\" = 1'-0\"", category: .architectural, ratioString: "3/16\" = 1'-0\"", pointsPerUnit: 72.0 * (3.0 / 16.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_1_4", name: "1/4\" = 1'-0\"", category: .architectural, ratioString: "1/4\" = 1'-0\"", pointsPerUnit: 72.0 * (1.0 / 4.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_3_8", name: "3/8\" = 1'-0\"", category: .architectural, ratioString: "3/8\" = 1'-0\"", pointsPerUnit: 72.0 * (3.0 / 8.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_1_2", name: "1/2\" = 1'-0\"", category: .architectural, ratioString: "1/2\" = 1'-0\"", pointsPerUnit: 72.0 * (1.0 / 2.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_3_4", name: "3/4\" = 1'-0\"", category: .architectural, ratioString: "3/4\" = 1'-0\"", pointsPerUnit: 72.0 * (3.0 / 4.0), linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_1", name: "1\" = 1'-0\"", category: .architectural, ratioString: "1\" = 1'-0\"", pointsPerUnit: 72.0 * 1.0, linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_1_5", name: "1-1/2\" = 1'-0\"", category: .architectural, ratioString: "1-1/2\" = 1'-0\"", pointsPerUnit: 72.0 * 1.5, linearUnit: .footInch, areaUnit: .squareFeet),
        ScalePreset(id: "arch_3", name: "3\" = 1'-0\"", category: .architectural, ratioString: "3\" = 1'-0\"", pointsPerUnit: 72.0 * 3.0, linearUnit: .footInch, areaUnit: .squareFeet),

        // Civil Engineering (US):
        // 1 in = 10 ft -> 72 pt = 10 ft -> 1 ft = 7.2 pt.
        ScalePreset(id: "eng_10", name: "1\" = 10'", category: .engineering, ratioString: "1\" = 10'", pointsPerUnit: 72.0 / 10.0, linearUnit: .decimalFeet, areaUnit: .squareFeet),
        ScalePreset(id: "eng_20", name: "1\" = 20'", category: .engineering, ratioString: "1\" = 20'", pointsPerUnit: 72.0 / 20.0, linearUnit: .decimalFeet, areaUnit: .squareFeet),
        ScalePreset(id: "eng_30", name: "1\" = 30'", category: .engineering, ratioString: "1\" = 30'", pointsPerUnit: 72.0 / 30.0, linearUnit: .decimalFeet, areaUnit: .squareFeet),
        ScalePreset(id: "eng_40", name: "1\" = 40'", category: .engineering, ratioString: "1\" = 40'", pointsPerUnit: 72.0 / 40.0, linearUnit: .decimalFeet, areaUnit: .squareFeet),
        ScalePreset(id: "eng_50", name: "1\" = 50'", category: .engineering, ratioString: "1\" = 50'", pointsPerUnit: 72.0 / 50.0, linearUnit: .decimalFeet, areaUnit: .squareFeet),
        ScalePreset(id: "eng_60", name: "1\" = 60'", category: .engineering, ratioString: "1\" = 60'", pointsPerUnit: 72.0 / 60.0, linearUnit: .decimalFeet, areaUnit: .squareFeet),
        ScalePreset(id: "eng_100", name: "1\" = 100'", category: .engineering, ratioString: "1\" = 100'", pointsPerUnit: 72.0 / 100.0, linearUnit: .decimalFeet, areaUnit: .squareFeet)
    ]
}

/// Represents the active drawing scale configuration and unit format settings.
public struct PDFScaleConfiguration: Codable, Sendable, Equatable {
    public var name: String
    /// Number of PDF points (1/72") per 1 linear unit (e.g. 28.346 pt per meter for 1:100).
    public var pointsPerUnit: Double
    public var linearUnit: MeasurementUnit
    public var areaUnit: AreaUnit
    public var precisionFractionDenominator: Int
    public var ratioString: String

    public init(
        name: String = "1:100",
        pointsPerUnit: Double = 2834.64567 / 100.0,
        linearUnit: MeasurementUnit = .meters,
        areaUnit: AreaUnit = .squareMeters,
        precisionFractionDenominator: Int = 100,
        ratioString: String = "1:100"
    ) {
        self.name = name
        self.pointsPerUnit = max(0.000001, pointsPerUnit)
        self.linearUnit = linearUnit
        self.areaUnit = areaUnit
        self.precisionFractionDenominator = precisionFractionDenominator
        self.ratioString = ratioString
    }

    public init(preset: ScalePreset) {
        self.init(
            name: preset.name,
            pointsPerUnit: preset.pointsPerUnit,
            linearUnit: preset.linearUnit,
            areaUnit: preset.areaUnit,
            precisionFractionDenominator: 16,
            ratioString: preset.ratioString
        )
    }

    /// Standard default 1:100 metric scale (1 meter = 28.346 pt)
    public static let standardMetricOneToOneHundred = PDFScaleConfiguration(
        name: "1:100",
        pointsPerUnit: 2834.64567 / 100.0,
        linearUnit: .meters,
        areaUnit: .squareMeters,
        precisionFractionDenominator: 100,
        ratioString: "1:100"
    )

    /// Standard default 1/4" = 1'-0" architectural scale
    public static let standardArchitecturalQuarterInch = PDFScaleConfiguration(
        name: "1/4\" = 1'-0\"",
        pointsPerUnit: 18.0,
        linearUnit: .footInch,
        areaUnit: .squareFeet,
        precisionFractionDenominator: 16,
        ratioString: "1/4\" = 1'-0\""
    )

    /// Creates a calibrated configuration from a measured line on the PDF canvas.
    /// - Parameters:
    ///   - measuredPoints: The distance in PDF points between two points.
    ///   - knownRealWorldLength: The known distance in `unit`.
    ///   - unit: The measurement unit.
    ///   - areaUnit: The unit to use for area takeoffs.
    ///   - label: Optional custom name.
    public static func calibrated(
        measuredPoints: Double,
        knownRealWorldLength: Double,
        unit: MeasurementUnit,
        areaUnit: AreaUnit = .squareMeters,
        label: String? = nil
    ) -> PDFScaleConfiguration {
        let safeLength = max(0.0001, knownRealWorldLength)
        let ptsPerUnit = measuredPoints / safeLength
        let nameStr = label ?? "\(String(format: "%.1f", measuredPoints)) pt = \(String(format: "%.2f", knownRealWorldLength)) \(unit.shortSymbol)"
        return PDFScaleConfiguration(
            name: nameStr,
            pointsPerUnit: ptsPerUnit,
            linearUnit: unit,
            areaUnit: areaUnit,
            precisionFractionDenominator: 16,
            ratioString: nameStr
        )
    }

    /// Rebuilds a configuration from stored scale metadata.
    public static func restored(ratioString: String, unitSymbol: String, pointsPerUnit: Double) -> PDFScaleConfiguration? {
        guard let unit = MeasurementUnit.allCases.first(where: { $0.shortSymbol == unitSymbol }), pointsPerUnit > 0 else {
            return nil
        }
        if let preset = ScalePreset.standardPresets.first(where: {
            $0.ratioString == ratioString && $0.linearUnit == unit && abs($0.pointsPerUnit - pointsPerUnit) / $0.pointsPerUnit < 0.001
        }) {
            return PDFScaleConfiguration(preset: preset)
        }
        let area: AreaUnit
        switch unit {
        case .footInch, .decimalFeet: area = .squareFeet
        case .inches: area = .squareInches
        case .millimeters, .centimeters, .meters: area = .squareMeters
        }
        let label = ratioString.isEmpty ? "Custom" : ratioString
        return PDFScaleConfiguration(
            name: label,
            pointsPerUnit: pointsPerUnit,
            linearUnit: unit,
            areaUnit: area,
            precisionFractionDenominator: 16,
            ratioString: label
        )
    }

    /// User-facing label or name of the scale.
    public var label: String {
        get { name }
        set { name = newValue }
    }

    /// Converts PDF points distance to real-world units.
    public func convertPointsToReal(pointsDistance: Double) -> Double {
        return pointsDistance / pointsPerUnit
    }

    /// Real-world meters per one `linearUnit`.
    var metersPerLinearUnit: Double {
        switch linearUnit {
        case .footInch, .decimalFeet: return 0.3048
        case .inches: return 0.0254
        case .millimeters: return 0.001
        case .centimeters: return 0.01
        case .meters: return 1.0
        }
    }

    /// Converts a PDF-points-squared area into the configured `areaUnit`.
    private func areaInAreaUnit(pointsSquared: Double) -> Double {
        let realUnitsSquared = pointsSquared / (pointsPerUnit * pointsPerUnit)
        let squareMeters = realUnitsSquared * metersPerLinearUnit * metersPerLinearUnit
        switch areaUnit {
        case .squareMeters: return squareMeters
        case .squareFeet: return squareMeters / (0.3048 * 0.3048)
        case .squareYards: return squareMeters / (0.9144 * 0.9144)
        case .squareInches: return squareMeters / (0.0254 * 0.0254)
        }
    }

    /// Converts PDF points squared to real-world square meters.
    func squareMeters(pointsSquared: Double) -> Double {
        pointsSquared / (pointsPerUnit * pointsPerUnit) * metersPerLinearUnit * metersPerLinearUnit
    }

    /// Converts PDF points squared to real-world area in areaUnit.
    public func convertAreaPointsToReal(pointsArea: Double) -> Double {
        areaInAreaUnit(pointsSquared: pointsArea)
    }

    // MARK: - Formatting Helpers

    /// Formats a distance measured in PDF points into a human-readable calibrated string.
    public func formatLength(points: Double) -> String {
        let realVal = points / pointsPerUnit
        switch linearUnit {
        case .footInch:
            return formatFootInches(feet: realVal, denominator: precisionFractionDenominator)
        case .decimalFeet:
            return String(format: "%.2f ft", realVal)
        case .inches:
            return formatInchesFraction(inches: realVal, denominator: precisionFractionDenominator)
        case .millimeters:
            // If linear unit is mm, realVal is in mm
            return String(format: "%.0f mm", realVal)
        case .centimeters:
            return String(format: "%.1f cm", realVal)
        case .meters:
            return String(format: "%.2f m", realVal)
        }
    }

    /// Convenience alias taking pointsDistance.
    public func formatLength(pointsDistance: Double) -> String {
        return formatLength(points: pointsDistance)
    }

    /// Convenience alias taking pointsArea.
    public func formatArea(pointsArea: Double) -> String {
        return formatArea(pointsSquared: pointsArea)
    }

    /// Formats an area measured in PDF points squared (pt²) into a calibrated surface area string.
    public func formatArea(pointsSquared: Double) -> String {
        let value = areaInAreaUnit(pointsSquared: pointsSquared)
        switch areaUnit {
        case .squareFeet: return String(format: "%.1f sq ft", value)
        case .squareYards: return String(format: "%.2f sq yd", value)
        case .squareMeters: return String(format: "%.2f m²", value)
        case .squareInches: return String(format: "%.0f sq in", value)
        }
    }

    /// Formats an angle in degrees.
    public func formatAngle(degrees: Double) -> String {
        return String(format: "%.1f°", degrees)
    }

    // MARK: - Architectural Foot-Inch Calculation

    private func formatFootInches(feet: Double, denominator: Int) -> String {
        var totalInches = feet * 12.0
        if totalInches < 0 { totalInches = 0 }

        let denom = max(1, denominator)
        let totalFractionalUnits = Int(round(totalInches * Double(denom)))

        let wholeInchesTotal = totalFractionalUnits / denom
        let remainderFrac = totalFractionalUnits % denom

        let feetPart = wholeInchesTotal / 12
        let inchPart = wholeInchesTotal % 12

        if remainderFrac == 0 {
            return "\(feetPart)'-0\"" == "\(feetPart)'-\(inchPart)\"" ? "\(feetPart)'-0\"" : "\(feetPart)'-\(inchPart)\""
        }

        // Simplify fraction
        let gcdVal = gcd(remainderFrac, denom)
        let simpNum = remainderFrac / gcdVal
        let simpDenom = denom / gcdVal

        if inchPart == 0 {
            return "\(feetPart)'-\(simpNum)/\(simpDenom)\""
        } else {
            return "\(feetPart)'-\(inchPart) \(simpNum)/\(simpDenom)\""
        }
    }

    private func formatInchesFraction(inches: Double, denominator: Int) -> String {
        let denom = max(1, denominator)
        let totalFrac = Int(round(inches * Double(denom)))
        let whole = totalFrac / denom
        let rem = totalFrac % denom
        if rem == 0 {
            return "\(whole)\""
        }
        let g = gcd(rem, denom)
        let num = rem / g
        let den = denom / g
        if whole == 0 {
            return "\(num)/\(den)\""
        }
        return "\(whole) \(num)/\(den)\""
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var x = abs(a)
        var y = abs(b)
        while y != 0 {
            let t = y
            y = x % y
            x = t
        }
        return max(1, x)
    }
}

// MARK: - Geometric Helpers for Measurements

public struct PDFMeasurementGeometry {
    /// Computes the Shoelace area of a polygon defined by points in order.
    public static func shoelaceArea(points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0.0 }
        var area: Double = 0.0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += Double(points[i].x * points[j].y)
            area -= Double(points[j].x * points[i].y)
        }
        return abs(area) * 0.5
    }

    /// Computes the angle in degrees subtended at apex by r1 and r2.
    public static func angleDegrees(r1: CGPoint, apex: CGPoint, r2: CGPoint) -> Double {
        let v1 = CGPoint(x: r1.x - apex.x, y: r1.y - apex.y)
        let v2 = CGPoint(x: r2.x - apex.x, y: r2.y - apex.y)
        let dot = Double(v1.x * v2.x + v1.y * v2.y)
        let mag1 = Double(hypot(v1.x, v1.y))
        let mag2 = Double(hypot(v2.x, v2.y))
        if mag1 == 0 || mag2 == 0 { return 0.0 }
        let cosTheta = max(-1.0, min(1.0, dot / (mag1 * mag2)))
        return acos(cosTheta) * 180.0 / .pi
    }

    /// Computes the cumulative polyline length across sequential points.
    public static func polylineLength(points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0.0 }
        var total: Double = 0.0
        for i in 0..<(points.count - 1) {
            total += Double(hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y))
        }
        return total
    }

    /// Snaps target point to 0°, 45°, 90°, 135°, 180°, etc. from origin.
    public static func snapOrtho(origin: CGPoint, target: CGPoint) -> CGPoint {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        let dist = hypot(dx, dy)
        if dist < 1.0 { return target }
        let rawAngle = atan2(dy, dx)
        let step = CGFloat.pi / 4.0
        let snappedAngle = round(rawAngle / step) * step
        return CGPoint(
            x: origin.x + dist * cos(snappedAngle),
            y: origin.y + dist * sin(snappedAngle)
        )
    }

    /// Snaps candidate point to nearest vertex within magnetic snap radius.
    public static func snapVertex(candidate: CGPoint, vertices: [CGPoint], radius: CGFloat = 8.0) -> (point: CGPoint, snapped: Bool) {
        for v in vertices {
            if hypot(candidate.x - v.x, candidate.y - v.y) <= radius {
                return (v, true)
            }
        }
        return (candidate, false)
    }
}
