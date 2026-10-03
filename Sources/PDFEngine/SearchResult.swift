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

    public var boundingRect: CGRect {
        guard let first = highlightQuads.first else { return .zero }
        return highlightQuads.dropFirst().reduce(first.boundingRect) { $0.union($1.boundingRect) }
    }

    public var rect: CGRect {
        boundingRect
    }
}
