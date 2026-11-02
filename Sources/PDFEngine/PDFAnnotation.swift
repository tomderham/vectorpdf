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
import AppKit

/// Color options for PDF annotations with accurate visual representation in both light and dark modes.
public enum AnnotationColor: String, CaseIterable, Codable, Sendable {
    case yellow
    case green
    case cyan
    case blue
    case purple
    case pink
    case red
    case orange
    case gray
    case black
    case white

    public static var allCases: [AnnotationColor] {
        [.yellow, .green, .cyan, .blue, .purple, .pink, .red, .orange, .gray, .black]
    }

    public var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .cyan:   return "Cyan"
        case .blue:   return "Blue"
        case .purple: return "Purple"
        case .pink:   return "Pink"
        case .red:    return "Red"
        case .orange: return "Orange"
        case .gray:   return "Gray"
        case .black:  return "Black"
        case .white:  return "White"
        }
    }

    /// Normalized RGB values (0.0 - 1.0) passed to MuPDF for PDF standard annotation storage.
    /// The palette colour closest to an arbitrary RGB colour (e.g. one read back from a PDF).
    public static func nearest(red: Float, green: Float, blue: Float) -> AnnotationColor {
        allCases.min { a, b in
            let da = (a.rgb.red - red) * (a.rgb.red - red) + (a.rgb.green - green) * (a.rgb.green - green) + (a.rgb.blue - blue) * (a.rgb.blue - blue)
            let db = (b.rgb.red - red) * (b.rgb.red - red) + (b.rgb.green - green) * (b.rgb.green - green) + (b.rgb.blue - blue) * (b.rgb.blue - blue)
            return da < db
        } ?? .black
    }

    public var rgb: (red: Float, green: Float, blue: Float) {
        switch self {
        case .yellow: return (1.00, 0.92, 0.23)
        case .green:  return (0.30, 0.85, 0.39)
        case .cyan:   return (0.20, 0.78, 0.95)
        case .blue:   return (0.00, 0.48, 1.00)
        case .purple: return (0.69, 0.32, 0.87)
        case .pink:   return (1.00, 0.42, 0.62)
        case .red:    return (1.00, 0.23, 0.19)
        case .orange: return (1.00, 0.62, 0.15)
        case .gray:   return (0.55, 0.55, 0.58)
        case .black:  return (0.12, 0.12, 0.12)
        case .white:  return (1.00, 1.00, 1.00)
        }
    }

    /// Native AppKit color for UI controls and menus.
    public var nsColor: NSColor {
        let (r, g, b) = rgb
        return NSColor(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
    }

    /// Semi-transparent highlight fill color for Quartz 2D canvas overlay.
    public var highlightFillColor: NSColor {
        let (r, g, b) = rgb
        let alpha: CGFloat = (self == .black || self == .gray) ? 0.20 : 0.38
        return NSColor(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: alpha)
    }

    /// A circular colored icon rendered as an image with isTemplate = false so macOS menus display the actual color.
    public var menuIcon: NSImage {
        let size = NSSize(width: 13, height: 13)
        let image = NSImage(size: size, flipped: false) { bounds in
            let circleRect = bounds.insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(ovalIn: circleRect)
            self.nsColor.setFill()
            path.fill()

            // Subtle outline so light colors like yellow and dark colors like black remain visible
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 0.75
            path.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}

public enum PDFAnnotationType: String, Codable, Sendable {
    case highlight
    case underline
    case strikeout
    case ink
    case freeText
    case callout
    case stamp
    case note
    case cloud
    case measureLength
    case measurePerimeter
    case measureArea
    case measureAngle
}

/// The shape at the end of a callout's leader line. Raw values are MuPDF's `pdf_line_ending`.
public enum PDFLineEnding: Int32, Codable, CaseIterable, Sendable {
    case closedArrow = 5
    case openArrow = 4
    case diamond = 3
    case circle = 2
    case square = 1
    case butt = 6
    case slash = 9
    case none = 0

    public var displayName: String {
        switch self {
        case .closedArrow: return "Closed Arrow"
        case .openArrow: return "Open Arrow"
        case .diamond: return "Diamond"
        case .circle: return "Circle"
        case .square: return "Square"
        case .butt: return "Butt"
        case .slash: return "Slash"
        case .none: return "None"
        }
    }

    /// The ending for a tip at `tip` on a line running along (dx, dy), and whether to fill it.
    /// The sizes match `ap_line_ending` in the bridge so saved and on-screen callouts agree.
    func path(tip: NSPoint, dx: CGFloat, dy: CGFloat) -> (path: NSBezierPath, filled: Bool)? {
        let len = hypot(dx, dy)
        guard len > 0.1 else { return nil }
        let u = NSPoint(x: dx / len, y: dy / len)
        let p = NSPoint(x: -u.y, y: u.x)
        let l: CGFloat = 8.0
        let w: CGFloat = 4.0
        func at(_ along: CGFloat, _ across: CGFloat) -> NSPoint {
            NSPoint(x: tip.x + u.x * along + p.x * across, y: tip.y + u.y * along + p.y * across)
        }
        let path = NSBezierPath()
        path.lineWidth = 1.5
        func polygon(_ points: [NSPoint]) {
            path.move(to: points[0])
            points.dropFirst().forEach { path.line(to: $0) }
        }
        switch self {
        case .none:
            return nil
        case .openArrow:
            polygon([at(l, w), tip, at(l, -w)])
            return (path, false)
        case .closedArrow:
            polygon([tip, at(l, w), at(l, -w)])
        case .butt:
            polygon([at(0, w), at(0, -w)])
            return (path, false)
        case .slash:
            polygon([at(w * 0.5, w), at(-w * 0.5, -w)])
            return (path, false)
        case .diamond:
            polygon([at(w, 0), at(0, w), at(-w, 0), at(0, -w)])
        case .square:
            let s = w * 0.75
            polygon([at(s, s), at(s, -s), at(-s, -s), at(-s, s)])
        case .circle:
            path.appendOval(in: NSRect(x: tip.x - w, y: tip.y - w, width: w * 2, height: w * 2))
            return (path, true)
        }
        path.close()
        return (path, true)
    }
}

/// How big a revision cloud's arcs are. Raw values are the PDF border effect intensity (/BE /I),
/// which ISO 32000 limits to 0–2 and which viewers turn into the arc radius.
public enum PDFCloudArcSize: CGFloat, CaseIterable, Sendable {
    case small = 1.0
    case medium = 1.5
    case large = 2.0

    public var displayName: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

/// Canvas interaction modes for the markup and measurement toolbars
public enum CanvasMode: String, CaseIterable, Sendable {
    case select
    case draw
    case text
    case callout
    case redact
    case eraser
    case stamp
    case note
    case cloud
    case measureLength
    case measurePerimeter
    case measureArea
    case measureAngle
    case calibrateScale
}

/// Represents a user or document annotation in VectorPDF
public struct PDFAnnotation: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let pageIndex: Int
    public let type: PDFAnnotationType
    public let quads: [PDFQuad]
    public let inkPoints: [CGPoint]
    public let rect: CGRect?
    public let targetPoint: CGPoint?
    public let kneePoint: CGPoint?
    public let strokeWidth: CGFloat
    public let fontSize: CGFloat?
    public let color: AnnotationColor
    public var text: String
    public let stampImageData: Data?
    public let measurementPoints: [CGPoint]
    public let measurementValue: Double
    public let measurementText: String
    public let leaderOffset: CGFloat
    /// The callout's line ending; nil for anything else.
    public let lineEnding: PDFLineEnding?
    /// The revision cloud's /BE /I; nil for anything else.
    public let cloudIntensity: CGFloat?
    public let dateCreated: Date
    /// The PDF object number for in-session annotations.
    public var documentObjectNumber: Int?

    public init(
        id: UUID = UUID(),
        pageIndex: Int,
        type: PDFAnnotationType = .highlight,
        quads: [PDFQuad] = [],
        inkPoints: [CGPoint] = [],
        rect: CGRect? = nil,
        targetPoint: CGPoint? = nil,
        kneePoint: CGPoint? = nil,
        strokeWidth: CGFloat = 2.0,
        fontSize: CGFloat? = nil,
        color: AnnotationColor = .yellow,
        text: String = "",
        stampImageData: Data? = nil,
        measurementPoints: [CGPoint] = [],
        measurementValue: Double = 0.0,
        measurementText: String = "",
        leaderOffset: CGFloat = 0.0,
        lineEnding: PDFLineEnding? = nil,
        cloudIntensity: CGFloat? = nil,
        dateCreated: Date = Date()
    ) {
        self.id = id
        self.pageIndex = pageIndex
        self.type = type
        self.quads = quads
        self.inkPoints = inkPoints
        self.rect = rect
        self.targetPoint = targetPoint
        self.kneePoint = kneePoint
        self.strokeWidth = strokeWidth
        self.fontSize = fontSize
        self.color = color
        self.text = text
        self.stampImageData = stampImageData
        self.measurementPoints = measurementPoints
        self.measurementValue = measurementValue
        self.measurementText = measurementText
        self.leaderOffset = leaderOffset
        self.lineEnding = lineEnding
        self.cloudIntensity = cloudIntensity
        self.dateCreated = dateCreated
    }

    /// Whether this annotation is an architectural or engineering measurement.
    public var isMeasurement: Bool {
        return type == .measureLength || type == .measurePerimeter || type == .measureArea || type == .measureAngle
    }

    /// Bounding box alias for boundingRect.
    public var boundingBox: CGRect {
        return boundingRect
    }

    /// Points alias for measurementPoints.
    public var points: [CGPoint] {
        return measurementPoints
    }

    /// Measurement text alias for measurementText.
    public var measurementFormattedText: String {
        return measurementText
    }

    /// Contains alias taking `point`.
    public func contains(point: CGPoint, tolerance: CGFloat = 3.0) -> Bool {
        return contains(pagePoint: point, tolerance: tolerance)
    }

    /// Union bounding rect across quads, ink points, or freeText rect in page coordinates.
    public var boundingRect: CGRect {
        if type == .freeText || type == .stamp || type == .note || type == .cloud {
            return rect ?? .zero
        }
        if type == .callout {
            var union = rect ?? .zero
            if let tp = targetPoint {
                union = union.union(CGRect(origin: tp, size: .zero))
            }
            if let kp = kneePoint {
                union = union.union(CGRect(origin: kp, size: .zero))
            }
            return union.insetBy(dx: -4.0, dy: -4.0)
        }
        if type == .ink {
            guard !inkPoints.isEmpty else { return .zero }
            var minX = inkPoints[0].x
            var maxX = inkPoints[0].x
            var minY = inkPoints[0].y
            var maxY = inkPoints[0].y
            for p in inkPoints.dropFirst() {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
            let halfW = strokeWidth / 2.0
            return CGRect(x: minX - halfW, y: minY - halfW, width: (maxX - minX) + strokeWidth, height: (maxY - minY) + strokeWidth)
        }
        if type == .measureLength || type == .measurePerimeter || type == .measureArea || type == .measureAngle {
            guard !measurementPoints.isEmpty else { return .zero }
            var minX = measurementPoints[0].x
            var maxX = measurementPoints[0].x
            var minY = measurementPoints[0].y
            var maxY = measurementPoints[0].y
            for p in measurementPoints.dropFirst() {
                minX = min(minX, p.x)
                maxX = max(maxX, p.x)
                minY = min(minY, p.y)
                maxY = max(maxY, p.y)
            }
            let pad = max(24.0, abs(leaderOffset) + 12.0)
            return CGRect(x: minX - pad, y: minY - pad, width: (maxX - minX) + (pad * 2.0), height: (maxY - minY) + (pad * 2.0))
        }
        guard !quads.isEmpty else { return .zero }
        return quads.reduce(into: CGRect.null) { union, q in
            union = union.isNull ? q.boundingRect : union.union(q.boundingRect)
        }
    }

    /// Checks whether a given page-space point hits this annotation (with a small hit-test margin).
    public func contains(pagePoint: CGPoint, tolerance: CGFloat = 3.0) -> Bool {
        if type == .freeText || type == .stamp || type == .note {
            guard let r = rect else { return false }
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(pagePoint)
        }
        if type == .cloud {
            // Only the outline: a cloud rings content that people still need to select.
            guard let r = rect else { return false }
            let margin = tolerance + 6.0
            return r.insetBy(dx: -margin, dy: -margin).contains(pagePoint)
                && !r.insetBy(dx: margin, dy: margin).contains(pagePoint)
        }
        if type == .callout {
            if let r = rect, r.insetBy(dx: -tolerance, dy: -tolerance).contains(pagePoint) {
                return true
            }
            // Check line segments: targetPoint -> kneePoint, kneePoint -> rect attachment
            if let tp = targetPoint, let kp = kneePoint {
                var segments = [(tp, kp)]
                if let r = rect {
                    let attachX = (kp.x <= r.minX) ? r.minX : ((kp.x >= r.maxX) ? r.maxX : kp.x)
                    let attachY = (kp.y <= r.minY) ? r.minY : ((kp.y >= r.maxY) ? r.maxY : (r.minY + r.maxY) * 0.5)
                    segments.append((kp, CGPoint(x: attachX, y: attachY)))
                }
                for (a, b) in segments {
                    let dx = b.x - a.x
                    let dy = b.y - a.y
                    let l2 = dx * dx + dy * dy
                    if l2 > 0 {
                        let t = max(0, min(1, ((pagePoint.x - a.x) * dx + (pagePoint.y - a.y) * dy) / l2))
                        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
                        if hypot(pagePoint.x - proj.x, pagePoint.y - proj.y) <= tolerance + 3.0 {
                            return true
                        }
                    }
                }
            }
            return false
        }
        if type == .measureLength {
            guard measurementPoints.count >= 2 else { return false }
            let p0 = measurementPoints[0]
            let p1 = measurementPoints[1]
            let effectiveTol = tolerance + 4.0

            // Direct line or offset dimension line
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let len = hypot(dx, dy)
            if len > 0 {
                // Perpendicular vector for leader offset
                let nx = -dy / len * leaderOffset
                let ny = dx / len * leaderOffset
                let off0 = CGPoint(x: p0.x + nx, y: p0.y + ny)
                let off1 = CGPoint(x: p1.x + nx, y: p1.y + ny)

                // Check dimension line
                if distanceToSegment(p: pagePoint, a: off0, b: off1) <= effectiveTol {
                    return true
                }
                // If there are leader lines, check them too
                if abs(leaderOffset) > 1.0 {
                    if distanceToSegment(p: pagePoint, a: p0, b: off0) <= effectiveTol ||
                       distanceToSegment(p: pagePoint, a: p1, b: off1) <= effectiveTol {
                        return true
                    }
                }
            }
            return false
        }
        if type == .measurePerimeter {
            let effectiveTol = tolerance + strokeWidth / 2.0 + 3.0
            guard measurementPoints.count >= 2 else { return false }
            for i in 1..<measurementPoints.count {
                if distanceToSegment(p: pagePoint, a: measurementPoints[i - 1], b: measurementPoints[i]) <= effectiveTol {
                    return true
                }
            }
            return false
        }
        if type == .measureArea {
            guard measurementPoints.count >= 3 else { return false }
            // Check polygon interior containment
            let path = CGMutablePath()
            path.addLines(between: measurementPoints)
            path.closeSubpath()
            if path.contains(pagePoint) {
                return true
            }
            // Check boundary edges
            let effectiveTol = tolerance + strokeWidth / 2.0 + 3.0
            for i in 0..<measurementPoints.count {
                let nextIdx = (i + 1) % measurementPoints.count
                if distanceToSegment(p: pagePoint, a: measurementPoints[i], b: measurementPoints[nextIdx]) <= effectiveTol {
                    return true
                }
            }
            return false
        }
        if type == .measureAngle {
            guard measurementPoints.count >= 3 else { return false }
            let r1 = measurementPoints[0]
            let apex = measurementPoints[1]
            let r2 = measurementPoints[2]
            let effectiveTol = tolerance + 4.0
            if distanceToSegment(p: pagePoint, a: apex, b: r1) <= effectiveTol ||
               distanceToSegment(p: pagePoint, a: apex, b: r2) <= effectiveTol {
                return true
            }
            return false
        }
        if type == .ink {
            let effectiveTol = tolerance + strokeWidth / 2.0
            guard !inkPoints.isEmpty else { return false }
            if inkPoints.count == 1 {
                return hypot(pagePoint.x - inkPoints[0].x, pagePoint.y - inkPoints[0].y) <= effectiveTol
            }
            for i in 1..<inkPoints.count {
                let a = inkPoints[i - 1]
                let b = inkPoints[i]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let l2 = dx * dx + dy * dy
                if l2 == 0 {
                    if hypot(pagePoint.x - a.x, pagePoint.y - a.y) <= effectiveTol { return true }
                    continue
                }
                let t = max(0, min(1, ((pagePoint.x - a.x) * dx + (pagePoint.y - a.y) * dy) / l2))
                let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
                if hypot(pagePoint.x - proj.x, pagePoint.y - proj.y) <= effectiveTol {
                    return true
                }
            }
            return false
        }
        for q in quads {
            let hitBox = q.boundingRect.insetBy(dx: -tolerance, dy: -tolerance)
            if hitBox.contains(pagePoint) {
                return true
            }
        }
        return false
    }

    private func distanceToSegment(p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        if l2 == 0 { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
