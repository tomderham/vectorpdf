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

/// A measurement drawn as a shape: an area as a rectangle or circle, a length as an arc. In the
/// file it's an ordinary area (polygon) or length (polyline) through `outline`, which other apps
/// measure; `points` define the shape, so VectorPDF can edit it as one.
public struct MeasuredShape: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case rectangle = "Rectangle", circle = "Circle", arc = "Arc"
    }

    public var kind: Kind
    /// A rectangle's opposite corners; a circle's centre and a point on it; an arc's start, a
    /// point along it and its end.
    public var points: [CGPoint]

    public init?(kind: Kind, points: [CGPoint]) {
        guard points.count == (kind == .arc ? 3 : 2) else { return nil }
        self.kind = kind
        self.points = points
    }

    /// The type of measurement it's saved as.
    public var measurementType: PDFAnnotationType { kind == .arc ? .measurePerimeter : .measureArea }

    /// How finely a circle or arc is traced: a point every 2°. The area or length of the traced
    /// outline is within 0.05% of the shape's.
    static let stepRadians = 2.0 * .pi / 180

    /// The vertices it's saved through.
    public var outline: [CGPoint] {
        switch kind {
        case .rectangle:
            let a = points[0], b = points[1]
            return [a, CGPoint(x: b.x, y: a.y), b, CGPoint(x: a.x, y: b.y)]
        case .circle:
            let c = points[0], r = radius
            let start = atan2(Double(points[1].y - c.y), Double(points[1].x - c.x))
            let n = Int((2 * .pi / Self.stepRadians).rounded())
            return (0..<n).map { i in
                let t = start + Double(i) * 2 * .pi / Double(n)
                return CGPoint(x: c.x + r * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t)))
            }
        case .arc:
            guard let (c, r, start, sweep) = arcCircle else { return [points[0], points[2]] }
            let n = max(2, Int((abs(sweep) / Self.stepRadians).rounded(.up)))
            return (0...n).map { i in
                let t = start + sweep * Double(i) / Double(n)
                return CGPoint(x: c.x + r * CGFloat(cos(t)), y: c.y + r * CGFloat(sin(t)))
            }
        }
    }

    public var radius: CGFloat {
        switch kind {
        case .circle: return hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        case .arc: return arcCircle?.radius ?? 0
        case .rectangle: return 0
        }
    }

    /// The circle through an arc's three points, the angle of its start and how far it turns to
    /// its end through its middle point (signed); nil when they're in a line.
    var arcCircle: (center: CGPoint, radius: CGFloat, start: Double, sweep: Double)? {
        guard kind == .arc else { return nil }
        let a = points[0], b = points[1], e = points[2]
        let d = 2 * (a.x * (b.y - e.y) + b.x * (e.y - a.y) + e.x * (a.y - b.y))
        guard abs(d) > 1e-6 else { return nil }
        let a2 = a.x * a.x + a.y * a.y, b2 = b.x * b.x + b.y * b.y, e2 = e.x * e.x + e.y * e.y
        let c = CGPoint(x: (a2 * (b.y - e.y) + b2 * (e.y - a.y) + e2 * (a.y - b.y)) / d,
                        y: (a2 * (e.x - b.x) + b2 * (a.x - e.x) + e2 * (b.x - a.x)) / d)
        let r = hypot(a.x - c.x, a.y - c.y)
        // A huge circle is a straight line drawn not quite straight.
        guard r < 1e6 else { return nil }
        func angle(_ p: CGPoint) -> Double { atan2(Double(p.y - c.y), Double(p.x - c.x)) }
        func ccw(_ from: Double, _ to: Double) -> Double {  // 0 ..< 2π
            let t = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
            return t < 0 ? t + 2 * .pi : t
        }
        let start = angle(a), toMid = ccw(start, angle(b)), toEnd = ccw(start, angle(e))
        // Through the middle point: anticlockwise if it comes before the end that way.
        let sweep = toMid <= toEnd ? toEnd : toEnd - 2 * .pi
        return (c, r, start, sweep)
    }

    /// Its area (rectangle, circle) or length (arc), in page points.
    public var value: Double {
        switch kind {
        case .rectangle: return Double(abs((points[1].x - points[0].x) * (points[1].y - points[0].y)))
        case .circle: return .pi * Double(radius * radius)
        case .arc:
            guard let (_, r, _, sweep) = arcCircle else {
                return Double(hypot(points[2].x - points[0].x, points[2].y - points[0].y))
            }
            return Double(r) * abs(sweep)
        }
    }

    /// Its label: the area or length, with a circle's diameter and an arc's radius.
    public func label(scale: PDFScaleConfiguration) -> String {
        switch kind {
        case .rectangle:
            return scale.formatArea(pointsSquared: value)
        case .circle:
            return "\(scale.formatArea(pointsSquared: value)) (Ø \(scale.formatLength(points: Double(radius) * 2)))"
        case .arc:
            guard arcCircle != nil else { return scale.formatLength(points: value) }
            return "\(scale.formatLength(points: value)) (R \(scale.formatLength(points: Double(radius))))"
        }
    }

    /// The shape moved by `delta`.
    public func offset(by delta: CGSize) -> MeasuredShape {
        var moved = self
        moved.points = points.map { CGPoint(x: $0.x + delta.width, y: $0.y + delta.height) }
        return moved
    }

    /// Whether `vertices` are its outline, so it still describes the measurement (another app
    /// may have changed the vertices and left the shape as it was).
    func matches(_ vertices: [CGPoint]) -> Bool {
        let expected = outline
        guard expected.count == vertices.count else { return false }
        return zip(expected, vertices).allSatisfy { abs($0.x - $1.x) < 0.5 && abs($0.y - $1.y) < 0.5 }
    }
}
