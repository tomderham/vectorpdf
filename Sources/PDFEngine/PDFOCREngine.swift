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
    /// One outline per whitespace-separated word of `text`, or empty if Vision gave none.
    public let wordQuads: [PDFQuad]

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.quad = PDFQuad(rect: boundingBox)
        self.wordQuads = []
    }

    public init(text: String, confidence: Float, quad: PDFQuad, wordQuads: [PDFQuad] = []) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = quad.boundingRect
        self.quad = quad
        self.wordQuads = wordQuads
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

    /// The recognized text in the form text selection reads. On a skewed scan, a long line's upright
    /// box overlaps those of the lines around it, so the lines are held turned upright by the
    /// page's skew, and `pageTransform` turns selections back onto the page.
    func structuredPage(bounds: CGRect) -> StructuredPage {
        let toPage = Self.deskewTransform(for: lines, bounds: bounds)
        let toUpright = toPage.inverted()
        let textLines = lines.compactMap { line -> TextLine? in
            let characters = Self.characters(of: line, toUpright: toUpright)
            guard !characters.isEmpty else { return nil }
            return TextLine(bbox: line.quad.applying(toUpright).boundingRect, characters: characters)
        }
        return StructuredPage(pageIndex: pageIndex, bounds: bounds, blocks: Self.blocks(of: textLines), pageTransform: toPage)
    }

    /// Rotation about the page's centre by the slant of its typical line, which a sideways label
    /// on a drawing doesn't disturb. Identity for a straight page.
    private static func deskewTransform(for lines: [PDFOCRLine], bounds: CGRect) -> CGAffineTransform {
        let long = lines.filter { $0.text.count >= 4 }
        let angles = (long.isEmpty ? lines : long).map { atan2($0.quad.ur.y - $0.quad.ul.y, $0.quad.ur.x - $0.quad.ul.x) }.sorted()
        guard !angles.isEmpty else { return .identity }
        let angle = angles[angles.count / 2]
        guard abs(angle) > 0.0005 else { return .identity }
        return CGAffineTransform(translationX: bounds.midX, y: bounds.midY)
            .rotated(by: angle)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
    }

    /// A line's characters. Vision places words, not letters: asked for a letter it answers with
    /// its whole word. So words sit where Vision saw them and letters share their word's width.
    private static func characters(of line: PDFOCRLine, toUpright: CGAffineTransform) -> [TextCharacter] {
        var characters: [TextCharacter] = []
        let size = hypot(line.quad.ll.x - line.quad.ul.x, line.quad.ll.y - line.quad.ul.y)
        func append(_ text: some Collection<Character>, spread over: PDFQuad) {
            let count = CGFloat(text.count)
            for (i, char) in text.enumerated() {
                let quad = over.slice(from: CGFloat(i) / count, to: CGFloat(i + 1) / count)
                characters.append(TextCharacter(char: char, quad: quad, origin: quad.ll, size: Float(size)))
            }
        }

        let words = line.text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, words.count == line.wordQuads.count else {
            append(line.text, spread: line.quad.applying(toUpright))
            return characters
        }
        let quads = line.wordQuads.map { $0.applying(toUpright) }
        for (i, word) in words.enumerated() {
            if i > 0 {
                append(" ", spread: PDFQuad(ul: quads[i - 1].ur, ur: quads[i].ul, ll: quads[i - 1].lr, lr: quads[i].ll))
            }
            append(word, spread: quads[i])
        }
        return characters
    }

    /// Groups upright lines into blocks: runs of close lines of about the same width. Vision reports
    /// each column's lines separately, and a heading wider than the column under it stays out, so
    /// that blocks keep to their column as the selector expects.
    private static func blocks(of lines: [TextLine]) -> [TextBlock] {
        var groups: [[TextLine]] = []
        for line in lines.sorted(by: { $0.bbox.minY < $1.bbox.minY }) {
            let group = groups.lastIndex { group in
                let last = group[group.count - 1].bbox
                let gap = line.bbox.minY - last.maxY
                let overlap = min(line.bbox.maxX, last.maxX) - max(line.bbox.minX, last.minX)
                let narrower = min(line.bbox.width, last.width), wider = max(line.bbox.width, last.width)
                return abs(gap) <= line.bbox.height && overlap >= narrower * 0.5 && narrower >= wider * 0.6
            }
            if let group {
                groups[group].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            TextBlock(type: .text, bbox: group.reduce(CGRect.null) { $0.union($1.bbox) }, lines: group)
        }
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
            let wordQuads = Self.wordQuads(of: candidate, pageBounds: pageBounds)
            ocrLines.append(PDFOCRLine(text: str, confidence: candidate.confidence, quad: quad, wordQuads: wordQuads))
            fullTextParts.append(str)
        }

        let fullText = fullTextParts.joined(separator: "\n")
        return PDFOCRPageResult(pageIndex: pageIndex, lines: ocrLines, fullText: fullText)
    }

    /// Where Vision saw each word of a line, or nothing if it can't place one of them.
    private static func wordQuads(of candidate: VNRecognizedText, pageBounds: CGRect) -> [PDFQuad] {
        var quads: [PDFQuad] = []
        for word in candidate.string.split(whereSeparator: \.isWhitespace) {
            guard let box = try? candidate.boundingBox(for: word.startIndex..<word.endIndex) else { return [] }
            quads.append(pageQuad(
                topLeft: box.topLeft, topRight: box.topRight,
                bottomLeft: box.bottomLeft, bottomRight: box.bottomRight,
                pageBounds: pageBounds
            ))
        }
        return quads
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

        // Rows by line height rather than fixed bands, so close rows of small text stay apart and
        // a row straddling a band boundary stays together.
        let heights = allLines.map(\.boundingBox.height).sorted()
        let rowTolerance = heights.isEmpty ? 3 : max(1, heights[heights.count / 2] * 0.5)
        allLines = readingOrder(allLines, rowTolerance: rowTolerance) { $0.boundingBox }

        let fullText = allLines.map { $0.text }.joined(separator: "\n")
        return PDFOCRPageResult(pageIndex: pageIndex, lines: allLines, fullText: fullText)
    }
}
