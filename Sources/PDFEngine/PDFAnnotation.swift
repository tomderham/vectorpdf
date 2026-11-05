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
    /// A revision cloud: a Polygon annotation round `inkPoints`, or, without them, a Square
    /// annotation filling `rect`; either with a cloudy border.
    case cloud
    /// A rectangle (a Square annotation).
    case square
    /// An oval (a Circle annotation).
    case circle
    /// A line or arrow (a Line annotation), from `inkPoints[0]` to `inkPoints[1]`.
    case line
    /// An annotation from another app of a kind VectorPDF doesn't make, such as a polygon or a
    /// file attachment. It can be moved as a whole.
    case other
    case measureLength
    case measurePerimeter
    case measureArea
    case measureAngle
}

/// What the Shapes tool draws.
public enum PDFShapeKind: String, CaseIterable, Sendable {
    case rectangle
    case oval
    /// A line, or an arrow: its end is `selectedShapeLineEnding`.
    case line
    /// A revision cloud around the outline dragged.
    case cloud

    public var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .oval: return "Oval"
        case .line: return "Line or Arrow"
        case .cloud: return "Revision Cloud"
        }
    }

    public var systemImage: String {
        switch self {
        case .rectangle: return "rectangle"
        case .oval: return "oval"
        case .line: return "arrow.up.right"
        case .cloud: return "cloud"
        }
    }

    /// Whether the shape fills the box dragged out, rather than running between its corners.
    public var isBoxed: Bool {
        self == .rectangle || self == .oval
    }
}

extension CGRect {
    /// The smallest rectangle holding all of `points`.
    init(enclosing points: [CGPoint]) {
        let xs = points.map(\.x), ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { self = .zero; return }
        self = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Outlines for revision clouds.
enum CloudOutline {
    /// `points`, a path dragged by hand, with the corners that matter kept and the jitter
    /// between them dropped (Ramer–Douglas–Peucker), so each side gets whole arcs.
    static func simplified(_ points: [CGPoint], tolerance: CGFloat = 4) -> [CGPoint] {
        guard points.count > 2 else { return points }
        func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = hypot(dx, dy)
            guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
            return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
        }
        var keep = Array(repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            var farthest = first
            var greatest: CGFloat = 0
            for i in (first + 1)..<last {
                let d = distance(points[i], points[first], points[last])
                if d > greatest { greatest = d; farthest = i }
            }
            if greatest > tolerance {
                keep[farthest] = true
                stack.append((first, farthest))
                stack.append((farthest, last))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// Twice the signed area of the polygon `points`: positive when they run the way the
    /// corners of a rectangle do from (minX, minY) to (maxX, minY).
    static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 2 else { return 0 }
        return points.indices.reduce(0) { sum, i in
            let a = points[i], b = points[(i + 1) % points.count]
            return sum + a.x * b.y - b.x * a.y
        }
    }

    /// The outline for a cloud dragged along `path`: the path itself, simplified, if it goes
    /// round an area; otherwise, for a drag across, an oval filling the box it crosses.
    static func outline(for path: [CGPoint]) -> [CGPoint] {
        let box = CGRect(enclosing: path)
        let simple = simplified(path)
        if simple.count >= 3, abs(signedArea(simple)) / 2 > box.width * box.height * 0.25 {
            return simple
        }
        return (0..<16).map { i in
            let angle = CGFloat(i) / 16 * 2 * .pi
            return CGPoint(x: box.midX + cos(angle) * box.width / 2, y: box.midY + sin(angle) * box.height / 2)
        }
    }
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
    /// The sizes match `ap_line_ending` in the bridge so saved and on-screen callouts agree;
    /// `scale` enlarges it, for a thicker line or a zoomed page.
    func path(tip: NSPoint, dx: CGFloat, dy: CGFloat, scale: CGFloat = 1) -> (path: NSBezierPath, filled: Bool)? {
        let len = hypot(dx, dy)
        guard len > 0.1 else { return nil }
        let u = NSPoint(x: dx / len, y: dy / len)
        let p = NSPoint(x: -u.y, y: u.x)
        let l: CGFloat = 8.0 * scale
        let w: CGFloat = 4.0 * scale
        func at(_ along: CGFloat, _ across: CGFloat) -> NSPoint {
            NSPoint(x: tip.x + u.x * along + p.x * across, y: tip.y + u.y * along + p.y * across)
        }
        let path = NSBezierPath()
        path.lineWidth = 1.5 * scale
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
    /// Rectangles, ovals, lines, arrows and revision clouds; `selectedShape` says which.
    case shape
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
    /// The ending of a callout's leader or of a line (at `inkPoints[1]`); nil for anything else.
    public let lineEnding: PDFLineEnding?
    /// The revision cloud's /BE /I; nil for anything else.
    public let cloudIntensity: CGFloat?
    public let dateCreated: Date
    /// The PDF object number for in-session annotations.
    public var documentObjectNumber: Int?
    /// For an annotation that came with the file, picked up to move or restyle: its PDF subtype,
    /// such as "Square". The canvas draws it as the document does, not from the fields above,
    /// which only say where it is for selecting and dragging.
    public var fileSubtype: String?
    /// Bumped whenever an annotation from the file changes, so its picture is drawn again.
    public var appearanceRevision = 0
    /// The object number of the layer it's on (its /OC), or nil when it isn't on one.
    public var layerObjectNumber: Int?

    public var isFromFile: Bool { fileSubtype != nil }

    /// For a measurement that was in the file when it was opened, picked up to be changed: the
    /// renderer's copy of the document still has it, so it has to keep being left out once it's
    /// replaced or deleted.
    public var cameWithFile = false

    /// Whether an annotation from the file can be resized by its corners: one MuPDF can draw
    /// again from its entries at the new size.
    public var isResizableFromFile: Bool {
        isFromFile && (type == .square || type == .circle || (type == .cloud && (inkPoints.count >= 3 || fileSubtype == "Square")))
    }

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

    /// A revision cloud, rectangle, oval or line: drawn from `rect`, which moving or resizing
    /// changes. A line's `rect` is the box its ends are corners of.
    public var isShape: Bool {
        type == .cloud || type == .square || type == .circle || type == .line
    }

    /// `inkPoints` moved and scaled as `rect` is to become `newRect`, as a line's ends are when
    /// it's dragged.
    public func inkPoints(fittedTo newRect: CGRect) -> [CGPoint] {
        let old = rect ?? newRect
        return inkPoints.map { p in
            CGPoint(x: newRect.minX + (p.x - old.minX) * (old.width > 0 ? newRect.width / old.width : 1),
                    y: newRect.minY + (p.y - old.minY) * (old.height > 0 ? newRect.height / old.height : 1))
        }
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
        if type == .freeText || type == .stamp || type == .note || type == .other {
            return rect ?? .zero
        }
        if type == .cloud {
            // A polygon cloud's arcs bulge past its corners.
            return inkPoints.count >= 3 ? (rect ?? .zero).insetBy(dx: -8, dy: -8) : rect ?? .zero
        }
        if type == .square || type == .circle || type == .line {
            // Room for the stroke, and for an arrowhead past the end of a line.
            let pad = strokeWidth / 2 + (type == .line && lineEnding != nil && lineEnding != PDFLineEnding.none ? 4.5 * max(1, strokeWidth) : 0)
            return (rect ?? .zero).insetBy(dx: -pad, dy: -pad)
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
        if type == .freeText || type == .stamp || type == .note || type == .other {
            guard let r = rect else { return false }
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(pagePoint)
        }
        if type == .cloud, inkPoints.count >= 3 {
            // Only the outline, arcs and all.
            return inkPoints.indices.contains { i in
                distanceToSegment(p: pagePoint, a: inkPoints[i], b: inkPoints[(i + 1) % inkPoints.count]) <= tolerance + 8.0
            }
        }
        if type == .cloud || type == .square {
            // Only the outline: a cloud rings content that people still need to select.
            guard let r = rect else { return false }
            let margin = tolerance + 6.0
            return r.insetBy(dx: -margin, dy: -margin).contains(pagePoint)
                && !r.insetBy(dx: margin, dy: margin).contains(pagePoint)
        }
        if type == .circle {
            // Only the outline, as for a cloud: how far the point is from the ellipse, roughly.
            guard let r = rect, r.width > 0, r.height > 0 else { return false }
            let nx = (pagePoint.x - r.midX) / (r.width / 2)
            let ny = (pagePoint.y - r.midY) / (r.height / 2)
            let distance = abs(hypot(nx, ny) - 1) * min(r.width, r.height) / 2
            return distance <= tolerance + 6.0
        }
        if type == .line {
            guard inkPoints.count >= 2 else { return false }
            return distanceToSegment(p: pagePoint, a: inkPoints[0], b: inkPoints[1]) <= tolerance + strokeWidth / 2 + 3.0
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
