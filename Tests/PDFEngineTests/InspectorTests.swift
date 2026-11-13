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
import Testing
@testable import PDFEngine

/// The Inspector: what a page draws at a point, and an annotation's place and size typed in.
@Suite(.serialized)
struct InspectorTests {
    /// One US Letter page: "Hello" in 24 pt red Helvetica at (72, 700) from the bottom; a blue
    /// rectangle stroked 3 pt wide from (100, 400) to (300, 500); and a 4 × 2 pixel image drawn
    /// 1 inch by half an inch at (400, 100).
    private func makeContentPDF(at url: URL) throws {
        let content = """
        BT /F1 24 Tf 1 0 0 rg 72 700 Td (Hello) Tj ET
        q 3 w 0 0 1 RG 100 400 200 100 re S Q
        q 72 0 0 36 400 100 cm /Im1 Do Q
        """
        let pixels = String(repeating: "00FF00", count: 8)
        try writeRawPDF([
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> /XObject << /Im1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
            "<< /Type /XObject /Subtype /Image /Width 4 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode /Length \(pixels.count + 1) >>\nstream\n\(pixels)>\nendstream",
        ], to: url)
    }

    @Test func textShowsItsFontSizeAndColor() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("content.pdf")
        try makeContentPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        // Top-down: 700 from the bottom is 92 from the top; the H's middle is a little above.
        let found = try #require(doc.inspectContent(pageIndex: 0, at: CGPoint(x: 78, y: 85)))
        let text = try #require(found.text)
        #expect(text.fontName.contains("Helvetica") || text.fontName.contains("Nimbus"))
        #expect(abs(text.fontSize - 24) < 0.01)
        #expect(text.character == "H")
        #expect(text.color.hex == "#FF0000")
        #expect(found.image == nil && found.path == nil)
    }

    @Test func aStrokedPathShowsItsLineWidthOnlyNearTheLine() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("content.pdf")
        try makeContentPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        // The rectangle's left side, at x 100, y 292 to 392 top-down.
        let onLine = try #require(doc.inspectContent(pageIndex: 0, at: CGPoint(x: 101, y: 340), tolerance: 1)?.path)
        #expect(abs((onLine.strokeWidth ?? 0) - 3) < 0.01)
        #expect(onLine.strokeColor?.hex == "#0000FF")
        #expect(onLine.fillColor == nil)
        #expect(onLine.colorSpace == "DeviceRGB")
        // Inside the rectangle, away from its sides: it's only stroked, so nothing's there.
        #expect(doc.inspectContent(pageIndex: 0, at: CGPoint(x: 200, y: 340), tolerance: 1)?.path == nil)
    }

    @Test func anImageShowsItsPixelsAndResolutionAsPlaced() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("content.pdf")
        try makeContentPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        // 100 to 136 from the bottom is 656 to 692 top-down.
        let image = try #require(doc.inspectContent(pageIndex: 0, at: CGPoint(x: 430, y: 670))?.image)
        #expect(image.pixelWidth == 4 && image.pixelHeight == 2)
        // 4 pixels across an inch, 2 down half an inch.
        #expect(abs(image.dpi.width - 4) < 0.01 && abs(image.dpi.height - 4) < 0.01)
        #expect(image.colorSpace == "DeviceRGB" && image.bitsPerComponent == 8)
        #expect(abs(image.rect.width - 72) < 0.01 && abs(image.rect.minY - 656) < 0.01)
        #expect(try #require(doc.inspectContent(pageIndex: 0, at: CGPoint(x: 300, y: 700))).isEmpty)
    }

    @Test func subsetFontNamesLoseTheirPrefix() {
        #expect(PageContentInspection.fontName("ABCDEF+Calibri-Bold") == ("Calibri-Bold", true))
        #expect(PageContentInspection.fontName("Helvetica") == ("Helvetica", false))
        #expect(PageContentInspection.fontName("AB+Odd") == ("AB+Odd", false))
    }

    @MainActor
    @Test func typingAPositionAndSizeMovesAndResizesTheAnnotation() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("content.pdf")
        try makeContentPDF(at: url)
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let canvas = PDFCanvasView(viewModel: vm)
        let shape = try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 150)))
        canvas.selectedAnnotation = (id: shape.id, pageIndex: 0)
        #expect(vm.inspectedAnnotation == InspectedAnnotation(id: shape.id, pageIndex: 0))
        let before = try #require(vm.inspectorAnnotation?.inspectorBounds)
        #expect(vm.inspectorAnnotation?.canResizeInInspector == true)

        vm.setInspectorAnnotationBounds(CGRect(x: before.minX + 20, y: before.minY + 10, width: before.width + 30, height: before.height))
        for _ in 0..<50 where vm.inspectorAnnotation?.inspectorBounds == before { try await Task.sleep(for: .milliseconds(20)) }
        let after = try #require(vm.inspectorAnnotation?.inspectorBounds)
        #expect(abs(after.minX - (before.minX + 20)) < 0.5)
        #expect(abs(after.minY - (before.minY + 10)) < 0.5)
        #expect(abs(after.width - (before.width + 30)) < 0.5)
        #expect(abs(after.height - before.height) < 0.5)
        // The canvas holds its view model unowned: both stay until work it queued has run.
        try await Task.sleep(for: .milliseconds(50))
        withExtendedLifetime((vm, canvas)) {}
    }
}
