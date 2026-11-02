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

/// Files from the PDF Association's test suite: unusual but valid PDFs, and PDFs "from the future"
/// that a reader should get as far through as it can.
@Suite struct PDFDifferencesTests {
    private func open(_ name: String) throws -> PDFDocumentCore {
        try PDFDocumentCore(filePath: Fixture.pdfDifferences(name).path)
    }

    /// Without the line breaks MuPDF puts between vertical or separately placed glyphs.
    private func text(of doc: PDFDocumentCore) -> String {
        (doc.extractText(pageIndex: 0) ?? "").filter { !$0.isNewline }
    }

    @Test func extractsTextOfEveryOrientation() throws {
        #expect(text(of: try open("NegativeFontSize.pdf")).contains("Helvetica -20 font size"))
        #expect(text(of: try open("VerticalText.pdf")).contains("縦書きのテスト"))
        #expect(text(of: try open("Type3Test.pdf")).contains("□△△□"))
    }

    @Test(arguments: ["PDF-versions1.pdf", "PDF-versions2.pdf", "PDF-versions3.pdf"])
    func reportsTheVersionAfterIncrementalUpdates(file: String) throws {
        #expect(try open(file).getMetadata().pdfVersion == "PDF 1.6")
    }

    /// Everything but the broken stream survives.
    @Test(arguments: [
        "UnknownFilter-Font.pdf", "UnknownFilter-FormXObject.pdf", "UnknownFilter-ICC.pdf",
        "UnknownFilter-ImageXObject.pdf", "UnknownFilter-OutlineObjStm.pdf", "UnknownFilter-objstm.pdf"
    ])
    func unknownFiltersLeaveTheRestOfThePageReadable(file: String) throws {
        let doc = try open(file)
        #expect(doc.pageCount == 1)
        #expect(text(of: doc).contains("Hello!"))
        #expect(doc.renderPageRect(pageIndex: 0, rect: doc.pageBounds[0], scale: 1) != nil)
    }

    @Test func anUnreadableContentStreamLeavesABlankPage() throws {
        let doc = try open("UnknownFilter-PageContentStream.pdf")
        #expect(doc.pageCount == 1)
        #expect(text(of: doc).isEmpty)
        #expect(doc.renderPageRect(pageIndex: 0, rect: doc.pageBounds[0], scale: 1) != nil)
    }

    @Test func aFileWithNoReadablePagesFailsToOpen() {
        #expect(throws: PDFError.self) { try open("UnknownFilter-xrefstm.pdf") }
    }

    /// Linearization data is optional, so a reader could ignore it, but MuPDF finds no pages.
    @Test func unreadableLinearizationDataIsIgnored() {
        withKnownIssue("MuPDF finds no pages") {
            let doc = try open("UnknownFilter-Linearized.pdf")
            #expect(doc.pageCount == 1)
        }
    }
}
