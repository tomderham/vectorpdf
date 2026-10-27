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

import AppKit
import Foundation
import PDFKit
import Testing
@testable import PDFEngine

/// Two pages, each with one sentence on its own line, so a selection can pick out exact words.
private func makeSentencePDF(at url: URL) {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create CGPDFContext")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 18)
    for sentence in ["Measured drawings need careful review", "Second page sentence for markup"] {
        context.beginPDFPage(nil)
        (sentence as NSString).draw(at: NSPoint(x: 72, y: 680), withAttributes: [.font: font])
        ("Unrelated footer line" as NSString).draw(at: NSPoint(x: 72, y: 400), withAttributes: [.font: font])
        context.endPDFPage()
    }
    context.closePDF()
}

/// Selects the first line of `pageIndex` the way a drag across it would.
@MainActor
private func selectFirstLine(in vm: PDFViewerViewModel, pageIndex: Int) throws -> SelectionResult {
    let page = try #require(vm.document?.loadStructuredPage(for: pageIndex))
    let result = SpatialTextSelector().selectText(on: page, from: CGPoint(x: 60, y: 90), to: CGPoint(x: 560, y: 120))
    try #require(!result.highlightQuads.isEmpty)
    return result
}

private func pdfKitDocument(at url: URL) throws -> PDFKit.PDFDocument {
    let doc = PDFKit.PDFDocument(url: url)
    return try #require(doc)
}

/// The page text PDFKit finds under an annotation's bounds.
private func textUnder(_ annotation: PDFKit.PDFAnnotation, on page: PDFPage) -> String {
    (page.selection(for: annotation.bounds)?.string ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func rgb(_ color: NSColor) -> (Float, Float, Float) {
    let c = color.usingColorSpace(.deviceRGB) ?? color
    return (Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
}

@MainActor
@Suite(.serialized)
struct MarkupTests {

    private func openSentenceDocument(in dir: URL) async throws -> (PDFViewerViewModel, URL) {
        let url = dir.appendingPathComponent("markup.pdf")
        makeSentencePDF(at: url)
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true   // keep this test out of the stored reading state
        await vm.loadDocument(from: url.path)
        return (vm, url)
    }

    @Test(arguments: [
        (PDFAnnotationType.highlight, "Highlight", AnnotationColor.yellow),
        (PDFAnnotationType.underline, "Underline", AnnotationColor.blue),
        (PDFAnnotationType.strikeout, "StrikeOut", AnnotationColor.red),
    ])
    func textMarkupCoversTheSelectedWordsInTheSavedFile(type: PDFAnnotationType, subtype: String, color: AnnotationColor) async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openSentenceDocument(in: dir)

        let selection = try selectFirstLine(in: vm, pageIndex: 0)
        #expect(selection.text.contains("Measured drawings"))
        vm.activeSelection = (pageIndex: 0, result: selection)

        let created = vm.addTextMarkupSelection(type: type, color: color)
        #expect(created.count == 1)
        #expect(created.first?.type == type)
        #expect(vm.activeSelection == nil)   // the selection is consumed
        #expect(vm.isDocumentEdited)

        vm.saveDocument()
        let saved = try pdfKitDocument(at: url)
        let page = try #require(saved.page(at: 0))
        let annotations = page.annotations.filter { $0.type == subtype }
        try #require(annotations.count == 1)
        let annotation = annotations[0]
        #expect(textUnder(annotation, on: page).contains("Measured drawings need careful review"))
        #expect(!textUnder(annotation, on: page).contains("footer"))
        let (r, g, b) = rgb(annotation.color)
        #expect(abs(r - color.rgb.red) < 0.02 && abs(g - color.rgb.green) < 0.02 && abs(b - color.rgb.blue) < 0.02)
        #expect(saved.page(at: 1)?.annotations.isEmpty == true)
    }

    @Test func selectionAcrossPagesMarksUpEachPage() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openSentenceDocument(in: dir)

        vm.activeSelection = (pageIndex: 0, result: try selectFirstLine(in: vm, pageIndex: 0))
        vm.additionalSelectionPages = [PageSelectionResult(pageIndex: 1, result: try selectFirstLine(in: vm, pageIndex: 1))]
        let created = vm.highlightSelection(color: .green)
        #expect(created.map(\.pageIndex) == [0, 1])

        vm.saveDocument()
        let saved = try pdfKitDocument(at: url)
        let second = try #require(saved.page(at: 1))
        let highlight = try #require(second.annotations.first { $0.type == "Highlight" })
        #expect(textUnder(highlight, on: second).contains("Second page sentence"))
        #expect(saved.page(at: 0)?.annotations.filter { $0.type == "Highlight" }.count == 1)
    }

    @Test func markupWithoutASelectionDoesNothing() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openSentenceDocument(in: dir)

        #expect(vm.highlightSelection().isEmpty)
        #expect(vm.underlineSelection().isEmpty)
        #expect(vm.strikethroughSelection().isEmpty)
        #expect(!vm.isDocumentEdited)
        #expect(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 72, y: 300, width: 100, height: 20), text: "") == nil)
        #expect(vm.addInkAnnotation(pageIndex: 5, points: [CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]) == nil)
    }

    /// Ink, a text box and a stamp go through save into the file, where another reader sees them
    /// with the text and roughly the place they were given.
    @Test func inkTextBoxAndStampAreSavedWhereTheyWerePlaced() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openSentenceDocument(in: dir)

        // Ink and text box take MuPDF page space (origin top left).
        #expect(vm.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 100, y: 500), CGPoint(x: 160, y: 540), CGPoint(x: 220, y: 500)], strokeWidth: 3, color: .purple) != nil)
        #expect(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 300, y: 500, width: 200, height: 30), text: "Check dimension", fontSize: 14, color: .red) != nil)
        let stampImage = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(stampImage.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        #expect(vm.addStampAnnotation(pageIndex: 1, rect: CGRect(x: 72, y: 72, width: 120, height: 60), imageData: png) != nil)
        #expect(vm.pageAnnotations[0]?.count == 2)

        vm.saveDocument()
        let saved = try pdfKitDocument(at: url)
        let first = try #require(saved.page(at: 0))
        let ink = try #require(first.annotations.first { $0.type == "Ink" })
        let freeText = try #require(first.annotations.first { $0.type == "FreeText" })
        #expect(freeText.contents == "Check dimension")
        // PDFKit bounds are in PDF space (origin bottom left): y = 792 − MuPDF y.
        #expect(ink.bounds.insetBy(dx: -5, dy: -5).contains(CGPoint(x: 160, y: 792 - 540)))
        #expect(ink.bounds.minX < 105 && ink.bounds.maxX > 215)
        #expect(abs(freeText.bounds.minX - 300) < 2 && abs(freeText.bounds.maxY - (792 - 500)) < 2)

        let second = try #require(saved.page(at: 1))
        #expect(second.annotations.contains { $0.type == "Stamp" })
    }

    /// Removing one annotation removes it from the saved file and leaves the rest.
    @Test func removedAnnotationIsGoneFromTheSavedFile() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openSentenceDocument(in: dir)

        vm.activeSelection = (pageIndex: 0, result: try selectFirstLine(in: vm, pageIndex: 0))
        let highlight = try #require(vm.highlightSelection().first)
        let ink = try #require(vm.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 100, y: 500), CGPoint(x: 200, y: 520)]))
        let note = try #require(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 300, y: 600, width: 150, height: 24), text: "Remove me"))

        vm.removeAnnotation(note)
        vm.removeAnnotation(highlight)
        #expect(vm.pageAnnotations[0]?.map(\.id) == [ink.id])

        vm.saveDocument()
        let saved = try pdfKitDocument(at: url)
        #expect(saved.page(at: 0)?.annotations.compactMap(\.type) == ["Ink"])
    }

    /// Markup added in one session is still there, unchanged, after the file is reopened and
    /// saved again by a second session.
    @Test func markupSurvivesReopenAndResave() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openSentenceDocument(in: dir)
        vm.activeSelection = (pageIndex: 0, result: try selectFirstLine(in: vm, pageIndex: 0))
        vm.underlineSelection(color: .cyan)
        vm.saveDocument()

        let second = PDFViewerViewModel()
        second.isTransientWindow = true
        await second.loadDocument(from: url.path)
        _ = second.addInkAnnotation(pageIndex: 1, points: [CGPoint(x: 100, y: 500), CGPoint(x: 200, y: 520)])
        second.saveDocument()

        let saved = try pdfKitDocument(at: url)
        let page = try #require(saved.page(at: 0))
        let underline = try #require(page.annotations.first { $0.type == "Underline" })
        #expect(textUnder(underline, on: page).contains("Measured drawings"))
        #expect(saved.page(at: 1)?.annotations.compactMap(\.type) == ["Ink"])
    }
}
