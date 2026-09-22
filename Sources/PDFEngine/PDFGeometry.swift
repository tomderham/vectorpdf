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
    public let id: UUID
    public let title: String
    public let uri: String?
    public let targetPage: Int?
    public let children: [PDFOutlineNode]
    
    public init(id: UUID = UUID(), title: String, uri: String? = nil, targetPage: Int? = nil, children: [PDFOutlineNode] = []) {
        self.id = id
        self.title = title
        self.uri = uri
        self.targetPage = targetPage
        self.children = children
    }
    
    /// Recursively filters outline nodes by title matching `query` (case-insensitive).
    /// Keeps nodes whose title matches `query`, or parent nodes necessary to display matching descendants.
    /// Non-matching child sections are excluded.
    public static func filter(nodes: [PDFOutlineNode], query: String) -> [PDFOutlineNode] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nodes }
        let lowercasedQuery = trimmed.lowercased()
        return filterInternal(nodes: nodes, lowercasedQuery: lowercasedQuery)
    }
    
    private static func filterInternal(nodes: [PDFOutlineNode], lowercasedQuery: String) -> [PDFOutlineNode] {
        var result: [PDFOutlineNode] = []
        for node in nodes {
            let matchesSelf = node.title.lowercased().contains(lowercasedQuery)
            let filteredChildren = filterInternal(nodes: node.children, lowercasedQuery: lowercasedQuery)
            
            if matchesSelf || !filteredChildren.isEmpty {
                result.append(PDFOutlineNode(
                    id: node.id,
                    title: node.title,
                    uri: node.uri,
                    targetPage: node.targetPage,
                    children: filteredChildren
                ))
            }
        }
        return result
    }
    
    /// Finds the outline node ID corresponding to `page` (0-indexed).
    /// - If any section headings start on `page`, the FIRST heading on `page` is returned (representing the top of the page).
    /// - If no headings start on `page`, the LAST heading before `page` is returned (representing the continuing section).
    public static func findActiveNodeId(in nodes: [PDFOutlineNode], for page: Int) -> UUID? {
        guard page >= 0 else { return nil }
        
        var flatList: [PDFOutlineNode] = []
        func flatten(_ list: [PDFOutlineNode]) {
            for node in list {
                flatList.append(node)
                flatten(node.children)
            }
        }
        flatten(nodes)
        
        // If any heading starts on this exact page, the first one on the page represents the page start
        if let firstOnPage = flatList.first(where: { $0.targetPage == page }) {
            return firstOnPage.id
        }
        
        // Otherwise, find the last heading that started before this page
        var lastPreceding: PDFOutlineNode? = nil
        for node in flatList {
            if let target = node.targetPage, target < page {
                lastPreceding = node
            }
        }
        return lastPreceding?.id
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

