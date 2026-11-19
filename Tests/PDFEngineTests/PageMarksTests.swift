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
import Testing
@testable import PDFEngine

/// Headers, footers, Bates numbers and watermarks are drawn into pages, and can be changed or
/// taken off again.
@Suite(.serialized) struct PageMarksTests {
    private func document(_ labels: [String] = ["Alpha", "Bravo", "Charlie"]) throws -> (PDFDocumentCore, URL) {
        let dir = try makeScratchDirectory()
        let url = dir.appendingPathComponent("Contract.pdf")
        makeLabelledPDF(at: url, labels: labels)
        return (try PDFDocumentCore(filePath: url.path), dir)
    }

    /// Where `text` is on `page`, in page (top-down) coordinates, after saving to `url`.
    private func find(_ text: String, in url: URL) async throws -> [SearchResult] {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: url.path)
        return try await actor.search(query: text, options: SearchOptions(smartSearch: false))
    }

    @Test func pageAndBatesNumbersAreFilledInForEachPage() async throws {
        let (doc, dir) = try document()
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = PageMarkSettings()
        settings.header.texts[2] = "<<file>>"
        settings.header.texts[4] = "Page <<page>> of <<pages>>"
        settings.header.texts[5] = "<<bates>>"
        settings.bates.prefix = "ACME-"
        settings.bates.start = 7
        settings.bates.digits = 4
        try doc.applyPageMarks(settings)
        let saved = dir.appendingPathComponent("Marked.pdf")
        try doc.save(to: saved.path)

        let marked = try PDFDocumentCore(filePath: saved.path)
        for page in 0..<3 {
            let text = try #require(marked.extractText(pageIndex: page))
            #expect(text.contains("Page \(page + 1) of 3"))
            #expect(text.contains("ACME-000\(7 + page)"))
            #expect(text.contains("Contract.pdf"))
        }
        // At the foot of the page, centred; the file name at the top right.
        let footer = try #require(try await find("Page 2 of 3", in: saved).first)
        #expect(footer.pageIndex == 1)
        #expect(footer.rect.minY > 792 - 50 && abs(footer.rect.midX - 306) < 2)
        let header = try #require(try await find("Contract.pdf", in: saved).first)
        #expect(header.rect.maxY < 60 && abs(header.rect.maxX - (612 - 72)) < 2)
        #expect(marked.pageMarkSettings() == settings)
        #expect(marked.pageMarkKinds() == (true, false))
    }

    /// The preview is of a copy of one page, numbered as that page would be; the document isn't
    /// changed.
    @Test func thePreviewNumbersThePageAsTheDocumentWould() throws {
        let (doc, dir) = try document()
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = PageMarkSettings()
        settings.header.texts[4] = "Page <<page>> of <<pages>> <<bates>>"
        settings.pages.which = .odd
        settings.firstPageNumber = 5
        settings.bates.start = 100
        // Pages 1 and 3 are marked; page 3 is the second of them.
        let third = PageMarksPreview.settings(settings, forPage: 2, of: 3)
        #expect(third.expand(third.header.texts[4], index: 0, pageCount: 3, date: Date(), fileName: "") == "Page 6 of 3 000101")
        #expect(PageMarksPreview.settings(settings, forPage: 1, of: 3).isEmpty)

        let preview = try PageMarksPreview(document: doc, pageIndex: 2)
        let image = try #require(try preview.image(settings, width: 200))
        #expect(image.width == 200)
        #expect(doc.pageMarkKinds() == (false, false))
    }

    /// A picture watermark is in the file once, drawn on every page marked, and comes back with
    /// its settings; settings saved before pictures could be used still read.
    @Test func aPictureWatermarkIsAddedOnce() throws {
        let (doc, dir) = try document()
        defer { try? FileManager.default.removeItem(at: dir) }
        let logo = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        var settings = PageMarkSettings()
        settings.watermark.image = try #require(PageMarksSheet.watermarkPNG(logo))
        settings.watermark.imageScale = 0.4
        #expect(!settings.isEmpty)
        try doc.applyPageMarks(settings)
        let saved = dir.appendingPathComponent("Logo.pdf")
        try doc.save(to: saved.path)

        let bytes = try Data(contentsOf: saved)
        let text = String(decoding: bytes, as: UTF8.self)
        // The picture and its transparency (an /SMask), once each.
        #expect(text.components(separatedBy: "/Subtype/Image").count - 1 == 2)
        #expect(text.components(separatedBy: "/SMask").count - 1 == 1)
        #expect(text.components(separatedBy: "/VPMarkIm").count - 1 >= 3)
        let marked = try PDFDocumentCore(filePath: saved.path)
        #expect(marked.pageMarkKinds() == (false, true))
        #expect(marked.pageMarkSettings()?.watermark.image == settings.watermark.image)
        // The picture is drawn: the middle of the page isn't white any more.
        let middle = try #require(marked.renderPageRect(pageIndex: 0, rect: CGRect(x: 300, y: 390, width: 12, height: 12), scale: 1))
        let image = try #require(NSBitmapImageRep(data: middle))
        let color = try #require(image.colorAt(x: 6, y: 6))
        #expect(color.blueComponent > color.redComponent + 0.1)

        let old = #"{"header":{"texts":["","","","","",""],"font":0,"size":10,"color":{"red":0,"green":0,"blue":0},"marginTop":36,"marginBottom":30,"marginLeft":72,"marginRight":72},"watermark":{"text":"DRAFT","font":3,"size":0,"color":{"red":0.6,"green":0.6,"blue":0.6},"opacity":0.3,"rotation":45,"behindContent":false},"pages":{"which":"all"},"firstPageNumber":1,"bates":{"prefix":"","suffix":"","digits":6,"start":1}}"#
        let decoded = try JSONDecoder().decode(PageMarkSettings.self, from: Data(old.utf8))
        #expect(decoded.watermark.text == "DRAFT" && decoded.watermark.image == nil)
    }

    @Test func changingThemReplacesTheOldOnes() throws {
        let (doc, dir) = try document()
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = PageMarkSettings()
        settings.header.texts[1] = "DRAFT ONE"
        try doc.applyPageMarks(settings)
        settings.header.texts[1] = "FINAL"
        try doc.applyPageMarks(settings)
        let text = try #require(doc.extractText(pageIndex: 0))
        #expect(text.contains("FINAL") && !text.contains("DRAFT ONE"))
        #expect(text.contains("Alpha"))

        // Taking them off leaves the page as it was.
        try doc.applyPageMarks(PageMarkSettings())
        let plain = try #require(doc.extractText(pageIndex: 0))
        #expect(!plain.contains("FINAL") && plain.contains("Alpha"))
        #expect(doc.pageMarkSettings() == nil)
        #expect(doc.pageMarkKinds() == (false, false))
    }

    @Test func aWatermarkGoesOnTheChosenPagesOnly() throws {
        let (doc, dir) = try document(["Alpha", "Bravo", "Charlie", "Delta"])
        defer { try? FileManager.default.removeItem(at: dir) }
        var settings = PageMarkSettings()
        settings.watermark.text = "CONFIDENTIAL"
        settings.pages.which = .even
        try doc.applyPageMarks(settings)
        let marked = (0..<4).map { doc.extractText(pageIndex: $0)?.contains("CONFIDENTIAL") == true }
        #expect(marked == [false, true, false, true])
        #expect(doc.pageMarkKinds() == (false, true))

        settings.pages = PageMarkSettings.PageChoice()
        settings.pages.from = 2
        settings.pages.to = 3
        #expect(settings.pages.indices(pageCount: 4) == [1, 2])
    }

    /// On a page turned a quarter, the header is still at the top of the page as it's shown.
    @Test func aHeaderIsAtTheTopOfARotatedPage() async throws {
        let (doc, dir) = try document(["Alpha"])
        defer { try? FileManager.default.removeItem(at: dir) }
        try doc.rotatePage(0, by: 90)
        var settings = PageMarkSettings()
        settings.header.texts[0] = "TOPLEFT"
        try doc.applyPageMarks(settings)
        let saved = dir.appendingPathComponent("Rotated.pdf")
        try doc.save(to: saved.path)
        let result = try #require(try await find("TOPLEFT", in: saved).first)
        // Shown 792 wide by 612 high.
        #expect(result.rect.maxY < 60 && abs(result.rect.minX - 72) < 2)
        #expect(result.rect.width > result.rect.height)
    }

    @Test func batesNumbersArePadded() {
        var bates = PageMarkSettings.Bates()
        bates.prefix = "X"
        bates.suffix = "-A"
        #expect(bates.number(0) == "X000001-A")
        bates.digits = 2
        bates.start = 123
        #expect(bates.number(1) == "X124-A")
    }
}

/// The window's Headers, Footers and Watermark sheet: added, saved, changed and removed.
@MainActor
@Suite(.serialized) struct PageMarksViewModelTests {
    @Test func marksAreSavedAndCanBeChangedLater() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Report.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        #expect(!vm.hasPageMarks)

        var settings = PageMarkSettings()
        settings.header.texts[4] = "Page <<page>>"
        settings.watermark.text = "DRAFT"
        vm.applyPageMarks(settings)
        #expect(vm.isDocumentEdited)
        #expect(vm.hasPageMarks)
        #expect(vm.document?.extractText(pageIndex: 1)?.contains("Page 2") == true)
        vm.saveDocument()

        // Opened again, the sheet starts from what the document has.
        let again = PDFViewerViewModel()
        await again.loadDocument(from: url.path)
        #expect(again.hasPageMarks)
        #expect(again.initialPageMarkSettings() == settings)

        again.applyPageMarks(PageMarkSettings())
        #expect(!again.hasPageMarks)
        #expect(again.document?.extractText(pageIndex: 1)?.contains("DRAFT") == false)
        #expect(again.document?.extractText(pageIndex: 1)?.contains("Bravo") == true)
    }
}
