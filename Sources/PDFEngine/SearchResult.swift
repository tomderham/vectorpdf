import Foundation
import CoreGraphics

public struct SearchResult: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let pageIndex: Int
    public let matchedText: String
    public let snippet: String
    public let highlightQuads: [PDFQuad]
    
    public init(pageIndex: Int, matchedText: String, snippet: String, highlightQuads: [PDFQuad]) {
        self.pageIndex = pageIndex
        self.matchedText = matchedText
        self.snippet = snippet
        self.highlightQuads = highlightQuads
    }
}
