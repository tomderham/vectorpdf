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

import Testing
import Foundation
import AppKit
import CoreGraphics
import PDFKit
@testable import PDFEngine

/// A picture of `lines` of text, as a scanner makes: black text on white, at `dpi`.
func makeTextImage(lines: [String], pageSize: CGSize, dpi: CGFloat = 200, fontSize: CGFloat = 22) -> CGImage {
    let scale = dpi / 72
    let width = Int(pageSize.width * scale), height = Int(pageSize.height * scale)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (i, line) in lines.enumerated() {
        (line as NSString).draw(at: NSPoint(x: 72, y: pageSize.height - 110 - CGFloat(i) * fontSize * 2),
                                withAttributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.black])
    }
    NSGraphicsContext.restoreGraphicsState()
    return context.makeImage()!
}

/// A PDF whose pages are only `images`, each filling its page: no text, as a scan.
func makeScannedPDF(at url: URL, images: [CGImage], pageSize: CGSize = CGSize(width: 612, height: 792)) {
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil)!
    for image in images {
        context.beginPDFPage(nil)
        context.draw(image, in: mediaBox)
        context.endPDFPage()
    }
    context.closePDF()
}

@Suite struct RecognizedTextLayerTests {
    private static let pageSize = CGSize(width: 612, height: 792)

    /// One line of words laid out left to right at `y` (top-down page space), each `wordWidth` wide.
    private static func line(_ words: [String], x: CGFloat = 72, y: CGFloat, height: CGFloat = 20, wordWidth: CGFloat = 80, gap: CGFloat = 12) -> PDFOCRLine {
        var quads: [PDFQuad] = []
        var left = x
        for _ in words {
            quads.append(PDFQuad(rect: CGRect(x: left, y: y, width: wordWidth, height: height)))
            left += wordWidth + gap
        }
        let lineRect = CGRect(x: x, y: y, width: left - gap - x, height: height)
        return PDFOCRLine(text: words.joined(separator: " "), confidence: 1, quad: PDFQuad(rect: lineRect), wordQuads: quads)
    }

    private func scannedDocument(pages: Int = 1, in dir: URL) -> URL {
        let url = dir.appendingPathComponent("Scan.pdf")
        let image = makeTextImage(lines: [], pageSize: Self.pageSize)
        makeScannedPDF(at: url, images: Array(repeating: image, count: pages), pageSize: Self.pageSize)
        return url
    }

    @Test func writtenTextIsFoundWhereItWasRecognized() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = scannedDocument(in: dir)
        let doc = try PDFDocumentCore(filePath: source.path)
        #expect(doc.isScannedPage(pageIndex: 0))

        let result = PDFOCRPageResult(pageIndex: 0, lines: [
            Self.line(["Quarterly", "report"], y: 100),
            Self.line(["Ünïcödé", "日本語", "naïve"], y: 200),
        ], fullText: "")
        let output = dir.appendingPathComponent("Searchable.pdf")
        let written = try doc.saveWithRecognizedText(to: output.path, results: [result])
        #expect(written == 1)
        // The open document isn't changed.
        #expect(doc.isScannedPage(pageIndex: 0))

        let saved = try PDFDocumentCore(filePath: output.path)
        let text = saved.extractText(pageIndex: 0) ?? ""
        #expect(text.contains("Quarterly report"))
        #expect(text.contains("Ünïcödé"))
        #expect(text.contains("日本語"))
        #expect(!saved.isScannedPage(pageIndex: 0))

        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: output.path)
        let hits = try await actor.search(query: "report")
        #expect(hits.count == 1)
        let box = try #require(hits.first).boundingRect
        // Within a point of the box it was recognized in: x 164–244, y 100–120.
        #expect(abs(box.minX - 164) < 1 && abs(box.maxX - 244) < 1)
        #expect(abs(box.minY - 100) < 1 && abs(box.maxY - 120) < 1)
    }

    @Test func textGoesOnTheRightPlaceOfARotatedPage() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let unrotated = scannedDocument(in: dir)
        let rotatedURL = dir.appendingPathComponent("Rotated.pdf")
        do {
            let doc = try PDFDocumentCore(filePath: unrotated.path)
            try doc.rotatePage(0, by: 90)
            try doc.save(to: rotatedURL.path)
        }
        let doc = try PDFDocumentCore(filePath: rotatedURL.path)
        let bounds = doc.pageBounds[0]
        #expect(bounds.width > bounds.height)

        // Upright on screen, so upright in page space too.
        let result = PDFOCRPageResult(pageIndex: 0, lines: [Self.line(["Sideways", "sheet"], x: bounds.minX + 300, y: bounds.minY + 50)], fullText: "")
        let output = dir.appendingPathComponent("Searchable.pdf")
        try doc.saveWithRecognizedText(to: output.path, results: [result])

        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: output.path)
        let hits = try await actor.search(query: "sheet")
        let box = try #require(hits.first).boundingRect
        #expect(abs(box.minX - (bounds.minX + 392)) < 1 && abs(box.maxX - (bounds.minX + 472)) < 1)
        #expect(abs(box.minY - (bounds.minY + 50)) < 1 && abs(box.maxY - (bounds.minY + 70)) < 1)
    }

    @Test func pagesWithTextOfTheirOwnAreLeftAlone() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Text.pdf")
        makeLabelledPDF(at: source, labels: ["Alpha"])
        let doc = try PDFDocumentCore(filePath: source.path)
        let result = PDFOCRPageResult(pageIndex: 0, lines: [Self.line(["Bravo"], y: 300)], fullText: "")
        let output = dir.appendingPathComponent("Out.pdf")
        #expect(try doc.saveWithRecognizedText(to: output.path, results: [result]) == 0)
        #expect(try PDFDocumentCore(filePath: output.path).extractText(pageIndex: 0)?.contains("Bravo") == false)
    }

    @Test func everyPageSharesOneFontAndTheFileStaysSmall() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = scannedDocument(pages: 3, in: dir)
        let doc = try PDFDocumentCore(filePath: source.path)
        let results = (0..<3).map { PDFOCRPageResult(pageIndex: $0, lines: [Self.line(["Page", "\($0 + 1)"], y: 100)], fullText: "") }
        let output = dir.appendingPathComponent("Out.pdf")
        #expect(try doc.saveWithRecognizedText(to: output.path, results: results) == 3)

        let saved = try PDFDocumentCore(filePath: output.path)
        for page in 0..<3 {
            #expect(saved.extractText(pageIndex: page)?.contains("Page \(page + 1)") == true)
        }
        let before = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as! Int
        let after = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as! Int
        #expect(after - before < 6_000, "grew by \(after - before) bytes")
    }

    /// From a picture of text through Vision to a searchable page.
    @Test func recognizedScanBecomesSearchable() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = makeTextImage(lines: ["The quick brown fox jumps", "over the lazy dog"], pageSize: Self.pageSize)
        let source = dir.appendingPathComponent("Scan.pdf")
        makeScannedPDF(at: source, images: [image], pageSize: Self.pageSize)
        let doc = try PDFDocumentCore(filePath: source.path)

        let result = try await PDFOCREngine.shared.recognizeText(in: image, pageIndex: 0, pageBounds: doc.pageBounds[0])
        try #require(result.fullText.localizedCaseInsensitiveContains("lazy dog"))
        let output = dir.appendingPathComponent("Searchable.pdf")
        try doc.saveWithRecognizedText(to: output.path, results: [result])

        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: output.path)
        let hits = try await actor.search(query: "brown fox")
        #expect(try PDFDocumentCore(filePath: output.path).extractText(pageIndex: 0)?.contains("over the lazy dog") == true)
        // As Preview, Spotlight and Safari read it.
        let opened: PDFKit.PDFDocument? = PDFKit.PDFDocument(url: output)
        let pdfKit = try #require(opened)
        #expect(pdfKit.string?.contains("brown fox") == true)
        let found = pdfKit.findString("lazy dog", withOptions: .caseInsensitive)
        #expect(found.count == 1)
        if let selection = found.first, let page = selection.pages.first {
            // PDFKit's space is bottom-up.
            let rect = selection.bounds(for: page)
            let lazy = try #require(result.lines.first { $0.text.contains("lazy") }).boundingBox
            #expect(abs(rect.minY - (Self.pageSize.height - lazy.maxY)) < 3)
        }
        #expect(hits.count == 1)
        // Where the OCR saw it.
        let line = try #require(result.lines.first { $0.text.contains("brown") })
        let hit = try #require(hits.first)
        #expect(hit.boundingRect.intersects(line.boundingBox))
    }
}

@MainActor
@Suite struct SaveWithRecognizedTextTests {
    @Test func savingRecognizesEveryScannedPageAndWritesItsText() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let size = CGSize(width: 612, height: 792)
        let source = dir.appendingPathComponent("Scan.pdf")
        makeScannedPDF(at: source, images: [
            makeTextImage(lines: ["Invoice number 4471"], pageSize: size),
            makeTextImage(lines: ["Payment due within thirty days"], pageSize: size),
        ], pageSize: size)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: source.path)
        // Recognition on open may still be running; saving recognizes whatever it hasn't.
        #expect(vm.document?.isScannedPage(pageIndex: 1) == true)
        vm.detectedScannedPages = [0, 1]
        #expect(vm.canSaveRecognizedText)

        await vm.saveWithRecognizedText()

        let saved = try PDFDocumentCore(filePath: source.path)
        #expect(saved.extractText(pageIndex: 0)?.contains("4471") == true)
        #expect(saved.extractText(pageIndex: 1)?.localizedCaseInsensitiveContains("thirty days") == true)
        // The document was opened again from the file: nothing is left unsaved or to recognize.
        #expect(!vm.isDocumentEdited)
        #expect(vm.document?.isScannedPage(pageIndex: 0) == false)
        #expect(!vm.canSaveRecognizedText)
    }

    @Test func aDocumentWithoutScannedPagesHasNothingToSave() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("Text.pdf")
        makeLabelledPDF(at: source, labels: ["Alpha"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: source.path)
        #expect(!vm.canSaveRecognizedText)
    }
}
