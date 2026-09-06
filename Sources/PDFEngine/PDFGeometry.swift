import Foundation
import CoreGraphics
import MuPDFBridge

public struct PDFQuad: Sendable, Equatable, Codable {
    public var ul: CGPoint
    public var ur: CGPoint
    public var ll: CGPoint
    public var lr: CGPoint
    
    public init(ul: CGPoint, ur: CGPoint, ll: CGPoint, lr: CGPoint) {
        self.ul = ul
        self.ur = ur
        self.ll = ll
        self.lr = lr
    }
    
    public init(fzQuad q: fz_quad) {
        self.ul = CGPoint(x: CGFloat(q.ul.x), y: CGFloat(q.ul.y))
        self.ur = CGPoint(x: CGFloat(q.ur.x), y: CGFloat(q.ur.y))
        self.ll = CGPoint(x: CGFloat(q.ll.x), y: CGFloat(q.ll.y))
        self.lr = CGPoint(x: CGFloat(q.lr.x), y: CGFloat(q.lr.y))
    }
    
    public var boundingRect: CGRect {
        let minX = min(ul.x, ur.x, ll.x, lr.x)
        let maxX = max(ul.x, ur.x, ll.x, lr.x)
        let minY = min(ul.y, ur.y, ll.y, lr.y)
        let maxY = max(ul.y, ur.y, ll.y, lr.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    public func toFZQuad() -> fz_quad {
        var q = fz_quad()
        q.ul = fz_point(x: Float(ul.x), y: Float(ul.y))
        q.ur = fz_point(x: Float(ur.x), y: Float(ur.y))
        q.ll = fz_point(x: Float(ll.x), y: Float(ll.y))
        q.lr = fz_point(x: Float(lr.x), y: Float(lr.y))
        return q
    }
}

public struct PDFOutlineNode: Sendable, Identifiable {
    public let id = UUID()
    public let title: String
    public let uri: String?
    public let targetPage: Int?
    public let children: [PDFOutlineNode]
    
    public init(title: String, uri: String?, targetPage: Int?, children: [PDFOutlineNode] = []) {
        self.title = title
        self.uri = uri
        self.targetPage = targetPage
        self.children = children
    }
}

public extension Array where Element == PDFQuad {
    /// Merges contiguous character quads on the same line into unified highlight rectangles
    func mergedLineQuads() -> [PDFQuad] {
        guard !isEmpty else { return [] }
        var result: [PDFQuad] = []
        var currentGroup: [PDFQuad] = [self[0]]
        
        for quad in dropFirst() {
            let last = currentGroup.last!
            let lastBox = last.boundingRect
            let currBox = quad.boundingRect
            
            // Check vertical alignment (same text line) and horizontal adjacency
            let yOverlap = abs(lastBox.midY - currBox.midY) < Swift.max(lastBox.height, currBox.height) * 0.6
            let xClose = currBox.minX >= lastBox.minX - 2 && (currBox.minX - lastBox.maxX) < 20
            
            if yOverlap && xClose {
                currentGroup.append(quad)
            } else {
                result.append(Self.combine(currentGroup))
                currentGroup = [quad]
            }
        }
        if !currentGroup.isEmpty {
            result.append(Self.combine(currentGroup))
        }
        return result
    }
    
    private static func combine(_ quads: [PDFQuad]) -> PDFQuad {
        let minX = quads.map { $0.boundingRect.minX }.min() ?? 0
        let maxX = quads.map { $0.boundingRect.maxX }.max() ?? 0
        let minY = quads.map { $0.boundingRect.minY }.min() ?? 0
        let maxY = quads.map { $0.boundingRect.maxY }.max() ?? 0
        return PDFQuad(
            ul: CGPoint(x: minX, y: minY),
            ur: CGPoint(x: maxX, y: minY),
            ll: CGPoint(x: minX, y: maxY),
            lr: CGPoint(x: maxX, y: maxY)
        )
    }
}

