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
        }
    }

    /// Normalized RGB values (0.0 - 1.0) passed to MuPDF for PDF standard annotation storage.
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
    case redact
    case stamp
}

/// Canvas interaction modes for the markup toolbar
public enum CanvasMode: String, CaseIterable, Sendable {
    case select
    case draw
    case text
    case callout
    case redact
    case eraser
    case stamp
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
    public let text: String
    public let stampImageData: Data?
    public let dateCreated: Date

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
        self.dateCreated = dateCreated
    }

    /// Union bounding rect across quads, ink points, or freeText rect in page coordinates.
    public var boundingRect: CGRect {
        if type == .freeText || type == .redact || type == .stamp {
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
        guard !quads.isEmpty else { return .zero }
        return quads.reduce(into: CGRect.null) { union, q in
            union = union.isNull ? q.boundingRect : union.union(q.boundingRect)
        }
    }

    /// Checks whether a given page-space point hits this annotation (with a small hit-test margin).
    public func contains(pagePoint: CGPoint, tolerance: CGFloat = 3.0) -> Bool {
        if type == .freeText || type == .redact || type == .stamp {
            guard let r = rect else { return false }
            return r.insetBy(dx: -tolerance, dy: -tolerance).contains(pagePoint)
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
}
