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
import Vision

/// Represents a single recognized line of text from Vision OCR with its PDF-space bounding geometry.
public struct PDFOCRLine: Sendable, Codable, Equatable {
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect // In native PDF point coordinates (top-down or matching pageBounds)
    /// The line's outline in the same coordinates; follows the text when it's slanted.
    public let quad: PDFQuad

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.quad = PDFQuad(rect: boundingBox)
    }

    public init(text: String, confidence: Float, quad: PDFQuad) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = quad.boundingRect
        self.quad = quad
    }
}

/// Results of running OCR on a single scanned PDF page.
public struct PDFOCRPageResult: Sendable, Codable, Equatable {
    public let pageIndex: Int
    public let lines: [PDFOCRLine]
    public let fullText: String

    public init(pageIndex: Int, lines: [PDFOCRLine], fullText: String) {
        self.pageIndex = pageIndex
        self.lines = lines
        self.fullText = fullText
    }
}

/// High-performance on-device OCR pipeline leveraging Apple's Vision framework and Apple Silicon Neural Engine.
public actor PDFOCREngine {
    public static let shared = PDFOCREngine()

    public init() {}

    /// Performs on-device text recognition on a rendered page image, mapping Vision's normalized
    /// coordinates to the page's native point bounds.
    public func recognizeText(
        in image: CGImage,
        pageIndex: Int,
        pageBounds: CGRect,
        languages: [String] = ["en-US"]
    ) async throws -> PDFOCRPageResult {
        // Read results directly from the synchronous Vision request.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let observations = request.results ?? []

        var ocrLines: [PDFOCRLine] = []
        var fullTextParts: [String] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let str = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !str.isEmpty else { continue }

            // Corners rather than boundingBox, which is upright even for slanted text.
            let quad = Self.pageQuad(
                topLeft: obs.topLeft, topRight: obs.topRight,
                bottomLeft: obs.bottomLeft, bottomRight: obs.bottomRight,
                pageBounds: pageBounds
            )
            ocrLines.append(PDFOCRLine(text: str, confidence: candidate.confidence, quad: quad))
            fullTextParts.append(str)
        }

        let fullText = fullTextParts.joined(separator: "\n")
        return PDFOCRPageResult(pageIndex: pageIndex, lines: ocrLines, fullText: fullText)
    }

    /// Maps Vision's normalized, bottom-left-origin corners to top-left page coordinates.
    static func pageQuad(topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint, pageBounds: CGRect) -> PDFQuad {
        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: pageBounds.minX + p.x * pageBounds.width, y: pageBounds.minY + (1.0 - p.y) * pageBounds.height)
        }
        return PDFQuad(ul: map(topLeft), ur: map(topRight), ll: map(bottomLeft), lr: map(bottomRight))
    }

    /// Merges multiple OCR results for the same page (e.g. from high-resolution tiled passes),
    /// deduplicating overlapping line observations and ordering in natural reading order.
    public func mergeOCRResults(pageIndex: Int, results: [PDFOCRPageResult]) -> PDFOCRPageResult {
        var allLines: [PDFOCRLine] = []
        for r in results {
            for line in r.lines {
                let isDuplicate = allLines.contains { existing in
                    if existing.text.caseInsensitiveCompare(line.text) == .orderedSame {
                        let inter = existing.boundingBox.intersection(line.boundingBox)
                        if !inter.isNull {
                            let minArea = min(existing.boundingBox.width * existing.boundingBox.height, line.boundingBox.width * line.boundingBox.height)
                            if minArea > 0 && (inter.width * inter.height) / minArea > 0.3 {
                                return true
                            }
                        }
                        let c1 = CGPoint(x: existing.boundingBox.midX, y: existing.boundingBox.midY)
                        let c2 = CGPoint(x: line.boundingBox.midX, y: line.boundingBox.midY)
                        if hypot(c1.x - c2.x, c1.y - c2.y) < 15.0 {
                            return true
                        }
                    }
                    return false
                }
                if !isDuplicate {
                    allLines.append(line)
                }
            }
        }

        allLines.sort { a, b in
            let rowA = Int(a.boundingBox.minY / 15.0)
            let rowB = Int(b.boundingBox.minY / 15.0)
            if rowA != rowB {
                return rowA < rowB
            }
            return a.boundingBox.minX < b.boundingBox.minX
        }

        let fullText = allLines.map { $0.text }.joined(separator: "\n")
        return PDFOCRPageResult(pageIndex: pageIndex, lines: allLines, fullText: fullText)
    }
}
