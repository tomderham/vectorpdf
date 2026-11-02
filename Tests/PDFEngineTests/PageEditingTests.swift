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
import PDFKit
import Testing
@testable import PDFEngine

/// Annotation subtypes ("Highlight", "Ink", …) on each page of a saved file, read with PDFKit so
/// the check doesn't depend on MuPDF reading back what it wrote.
private func annotationTypesByPage(ofFileAt url: URL) -> [[String]] {
    guard let doc = PDFKit.PDFDocument(url: url) else { return [] }
    return (0..<doc.pageCount).map { index in
        (doc.page(at: index)?.annotations ?? []).compactMap(\.type).filter { $0 != "Widget" && $0 != "Link" }
    }
}

/// Writes a one-page PDF with a single text field named "Applicant". The widget is either the
/// field itself (merged, as most simple forms have it) or a kid of a separate field object.
private func writeOneFieldForm(at url: URL, widgetIsItsOwnField: Bool) {
    let widgetField = widgetIsItsOwnField ? "/FT /Tx /T (Applicant) " : "/Parent 6 0 R "
    var objects = [
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [\(widgetIsItsOwnField ? 4 : 6) 0 R] /DA (/Helv 12 Tf 0 g) /DR << /Font << /Helv 5 0 R >> >> >> >>\nendobj\n",
        "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [4 0 R] >>\nendobj\n",
        "4 0 obj\n<< /Type /Annot /Subtype /Widget \(widgetField)/Rect [72 600 300 624] /P 3 0 R /DA (/Helv 12 Tf 0 g) /F 4 >>\nendobj\n",
        "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n",
    ]
    if !widgetIsItsOwnField {
        objects.append("6 0 obj\n<< /FT /Tx /T (Applicant) /Kids [4 0 R] >>\nendobj\n")
    }
    var pdf = "%PDF-1.7\n"
    var offsets: [Int] = []
    for object in objects {
        offsets.append(pdf.utf8.count)
        pdf += object
    }
    let xrefOffset = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        pdf += String(format: "%010d 00000 n \n", offset)
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    try! Data(pdf.utf8).write(to: url)
}

private let highlightQuad = PDFQuad(
    ul: CGPoint(x: 72, y: 90), ur: CGPoint(x: 200, y: 90),
    ll: CGPoint(x: 72, y: 120), lr: CGPoint(x: 200, y: 120)
)

/// Page operations are checked by which page ends up where, not just the page count: each test
/// PDF labels its pages, so a reorder that does nothing or a duplicate of the wrong page fails.
@Suite(.serialized)
struct PageEditingTests {

    // MARK: - Reorder

    @Test func movingOnePageLandsItAtTheTargetIndex() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("reorder.pdf")
        let labels = Array(natoLabels.prefix(4))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.reorderPage(from: 0, to: 2)
        #expect(pageLabels(of: doc, among: labels) == ["Bravo", "Charlie", "Alpha", "Delta"])
        try doc.reorderPage(from: 3, to: 0)
        #expect(pageLabels(of: doc, among: labels) == ["Delta", "Bravo", "Charlie", "Alpha"])

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(try pageLabels(ofFileAt: saved, among: labels) == ["Delta", "Bravo", "Charlie", "Alpha"])
    }

    @Test(arguments: [
        // Pages, destination slot (an index into the original order), expected result.
        ([1, 2], 0, ["Bravo", "Charlie", "Alpha", "Delta", "Echo"]),
        ([0, 1], 5, ["Charlie", "Delta", "Echo", "Alpha", "Bravo"]),
        ([0, 4], 2, ["Bravo", "Alpha", "Echo", "Charlie", "Delta"]),
        // Selection order is kept, so dragging pages picked last-first drops them that way.
        ([3, 1], 0, ["Delta", "Bravo", "Alpha", "Charlie", "Echo"]),
    ])
    func movingSeveralPagesKeepsThemTogetherAtTheSlot(pages: [Int], slot: Int, expected: [String]) throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("multi_reorder.pdf")
        let labels = Array(natoLabels.prefix(5))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.reorderPages(from: pages, toSlot: slot)
        #expect(pageLabels(of: doc, among: labels) == expected)
    }

    @Test func outOfRangeMovesThrowAndLeaveTheDocumentAlone() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("bounds.pdf")
        let labels = Array(natoLabels.prefix(3))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        #expect(throws: Error.self) { try doc.reorderPage(from: 0, to: 3) }
        #expect(throws: Error.self) { try doc.reorderPages(from: [5], toSlot: 0) }
        #expect(throws: Error.self) { try doc.reorderPages(from: [0], toSlot: 4) }
        #expect(throws: Error.self) { try doc.deletePage(3) }
        #expect(pageLabels(of: doc, among: labels) == labels)
    }

    // MARK: - Delete

    @Test func deletingPagesRemovesExactlyThosePages() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("delete.pdf")
        let labels = Array(natoLabels.prefix(5))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.deletePage(1)
        #expect(pageLabels(of: doc, among: labels) == ["Alpha", "Charlie", "Delta", "Echo"])
        // Unsorted indices, as a thumbnail selection can produce.
        try doc.deletePages([3, 0])
        #expect(pageLabels(of: doc, among: labels) == ["Charlie", "Delta"])
        // A document can't be left with no pages.
        #expect(throws: Error.self) { try doc.deletePages([0, 1]) }
        #expect(doc.pageCount == 2)
    }

    @Test func deletingAPageDropsItsAnnotationsAndKeepsTheOthers() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("delete_annots.pdf")
        let labels = Array(natoLabels.prefix(3))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.addHighlight(pageIndex: 0, quad: highlightQuad, red: 1, green: 0.9, blue: 0.2)
        try doc.addInkStroke(pageIndex: 1, points: [CGPoint(x: 100, y: 300), CGPoint(x: 200, y: 350)], strokeWidth: 2, red: 0, green: 0, blue: 1)
        try doc.addFreeText(pageIndex: 2, rect: CGRect(x: 72, y: 400, width: 200, height: 30), text: "Note", fontSize: 12, red: 0, green: 0, blue: 0)
        try doc.deletePage(1)

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(try pageLabels(ofFileAt: saved, among: labels) == ["Alpha", "Charlie"])
        #expect(annotationTypesByPage(ofFileAt: saved) == [["Highlight"], ["FreeText"]])
    }

    // MARK: - Rotate

    @Test func rotationAccumulatesAndSurvivesSave() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("rotate.pdf")
        let labels = Array(natoLabels.prefix(3))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.rotatePage(0, by: 90)
        try doc.rotatePages([1, 2], by: 90)
        try doc.rotatePage(1, by: 90)      // 180 in total: portrait again
        try doc.rotatePage(2, by: -90)     // back to 0
        #expect(doc.pageBounds.map(\.size) == [CGSize(width: 792, height: 612), CGSize(width: 612, height: 792), CGSize(width: 612, height: 792)])

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        let reopened = PDFKit.PDFDocument(url: saved)
        let pdfKit = try #require(reopened)
        #expect((0..<3).map { pdfKit.page(at: $0)?.rotation } == [90, 180, 0])
        // Rotating doesn't change which page is which.
        #expect(try pageLabels(ofFileAt: saved, among: labels) == labels)
    }

    // MARK: - Duplicate

    @Test func duplicatesAreInsertedAfterTheLastSelectedPageInOrder() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("duplicate.pdf")
        let labels = Array(natoLabels.prefix(4))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        let single = try doc.duplicatePages([1])
        #expect(single.insertedSlot == 2 && single.count == 1)
        #expect(pageLabels(of: doc, among: labels) == ["Alpha", "Bravo", "Bravo", "Charlie", "Delta"])

        // Indices are into the document as it now stands: Alpha and Delta.
        let several = try doc.duplicatePages([0, 4])
        #expect(several.insertedSlot == 5 && several.count == 2)
        #expect(pageLabels(of: doc, among: labels) == ["Alpha", "Bravo", "Bravo", "Charlie", "Delta", "Alpha", "Delta"])

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(try pageLabels(ofFileAt: saved, among: labels) == ["Alpha", "Bravo", "Bravo", "Charlie", "Delta", "Alpha", "Delta"])
    }

    @MainActor @Test func duplicateCommandIgnoresASelectionWithoutTheCurrentPage() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("duplicate_command.pdf")
        let labels = Array(natoLabels.prefix(4))
        makeLabelledPDF(at: url, labels: labels)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        let doc = try #require(vm.document)

        // Left over from earlier: the reader has since moved to the first page.
        vm.selectedThumbnailPageIndices = [3]
        vm.currentPageIndex = 0
        vm.duplicateCurrentPages()
        #expect(pageLabels(of: doc, among: labels) == ["Alpha", "Alpha", "Bravo", "Charlie", "Delta"])

        // A selection including the current page is used whole.
        vm.selectedThumbnailPageIndices = [0, 2]
        vm.currentPageIndex = 2
        vm.duplicateCurrentPages()
        #expect(pageLabels(of: doc, among: labels) == ["Alpha", "Alpha", "Bravo", "Alpha", "Bravo", "Charlie", "Delta"])
    }

    @Test func duplicateCarriesTheOriginalsAnnotations() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("duplicate_annots.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.addHighlight(pageIndex: 0, quad: highlightQuad, red: 1, green: 0.9, blue: 0.2)
        _ = try doc.duplicatePages([0])

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(annotationTypesByPage(ofFileAt: saved) == [["Highlight"], ["Highlight"], []])
    }

    /// A duplicated page has to be a page of its own: marking up the copy must not change the
    /// original (and vice versa), as it would if both shared one /Annots array.
    @Test func markupOnADuplicateStaysOnTheDuplicate() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("duplicate_independent.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo"])

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.addHighlight(pageIndex: 0, quad: highlightQuad, red: 1, green: 0.9, blue: 0.2)
        _ = try doc.duplicatePages([0])
        try doc.addInkStroke(pageIndex: 1, points: [CGPoint(x: 100, y: 300), CGPoint(x: 200, y: 350)], strokeWidth: 2, red: 0, green: 0, blue: 1)
        let saved = dir.appendingPathComponent("saved.pdf")
        // Remove the copied highlight from the duplicate only.
        #expect(try doc.deleteHighlight(pageIndex: 1, at: CGPoint(x: 120, y: 105)))
        try doc.save(to: saved.path)
        #expect(annotationTypesByPage(ofFileAt: saved) == [["Highlight"], ["Ink"], []])
    }

    @Test func duplicateKeepsItsLinks() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("duplicate_links.pdf")
        try FileManager.default.copyItem(at: Fixture.lcmsTutorial, to: url)

        let doc = try PDFDocumentCore(filePath: url.path)
        let original = doc.loadLinks(for: 1).map(\.targetPage)
        #expect(original.count > 5)
        _ = try doc.duplicatePages([1])
        // The copy links to the same pages as the original (which haven't moved).
        #expect(doc.loadLinks(for: 2).map(\.targetPage) == original.map { $0 >= 2 ? $0 + 1 : $0 })
    }

    /// A widget on a duplicated page joins the original's field, as in Acrobat and Preview:
    /// filling in either shows the same value in both.
    @Test(arguments: [true, false])
    func duplicatedFormFieldIsLinkedToTheOriginal(widgetIsItsOwnField: Bool) throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("form.pdf")
        writeOneFieldForm(at: url, widgetIsItsOwnField: widgetIsItsOwnField)

        let doc = try PDFDocumentCore(filePath: url.path)
        #expect(doc.loadFormWidgets(for: 0).map(\.name) == ["Applicant"])
        _ = try doc.duplicatePages([0])
        let copy = try #require(doc.loadFormWidgets(for: 1).first)
        #expect(copy.name == "Applicant")

        try doc.setFormWidgetValue(pageIndex: 1, widgetIndex: copy.widgetIndex, value: "Jane Example")
        #expect(doc.loadFormWidgets(for: 0).first?.value == "Jane Example")

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        let reopened = PDFKit.PDFDocument(url: saved)
        let pdfKit = try #require(reopened)
        #expect((0..<2).map { pdfKit.page(at: $0)?.annotations.first?.widgetStringValue } == ["Jane Example", "Jane Example"])
    }

    /// Imported form fields come across fillable. Importing a form a second time gives separate
    /// fields (renamed), not a second view of the first copy's.
    @Test func importedFormFieldsAreFillableAndKeptApartFromExistingOnes() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let primary = dir.appendingPathComponent("primary.pdf")
        let form = dir.appendingPathComponent("form.pdf")
        makeLabelledPDF(at: primary, labels: ["Alpha"])
        writeOneFieldForm(at: form, widgetIsItsOwnField: true)

        let doc = try PDFDocumentCore(filePath: primary.path)
        _ = try doc.importPages(from: form, atSlot: 1)
        _ = try doc.importPages(from: form, atSlot: 2)
        let first = try #require(doc.loadFormWidgets(for: 1).first)
        let second = try #require(doc.loadFormWidgets(for: 2).first)
        #expect(first.name == "Applicant")
        #expect(second.name == "Applicant_2")

        try doc.setFormWidgetValue(pageIndex: 1, widgetIndex: first.widgetIndex, value: "First copy")
        #expect(doc.loadFormWidgets(for: 1).first?.value == "First copy")
        #expect(doc.loadFormWidgets(for: 2).first?.value.isEmpty == true)

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(try PDFDocumentCore(filePath: saved.path).loadFormWidgets(for: 1).first?.value == "First copy")
    }

    /// Imports the IRS 1040 (fields nested under a form hierarchy) behind another page.
    @Test func importingARealWorldFormKeepsEveryField() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let primary = dir.appendingPathComponent("primary.pdf")
        makeLabelledPDF(at: primary, labels: ["Alpha"])

        let source = try PDFDocumentCore(filePath: Fixture.form1040.path)
        let sourceNames = (0..<source.pageCount).map { source.loadFormWidgets(for: $0).map(\.name) }
        #expect(sourceNames[0].count > 20)

        let doc = try PDFDocumentCore(filePath: primary.path)
        _ = try doc.importPages(from: Fixture.form1040, atSlot: 1)
        #expect((0..<source.pageCount).map { doc.loadFormWidgets(for: $0 + 1).map(\.name) } == sourceNames)
    }

    // MARK: - Insert blank page

    @Test func blankPagesTakeTheSizeOfThePageBeforeThemOrTheSizeGiven() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("blank.pdf")
        let labels = ["Alpha", "Bravo"]
        makeLabelledPDF(at: url, labels: labels, pageSize: CGSize(width: 842, height: 595))   // A4 landscape

        let doc = try PDFDocumentCore(filePath: url.path)
        #expect(try doc.insertBlankPage(atSlot: 1) == 1)
        #expect(try doc.insertBlankPage(atSlot: 0) == 0)
        #expect(try doc.insertBlankPage(atSlot: doc.pageCount, width: 300, height: 400) == 4)
        #expect(pageLabels(of: doc, among: labels) == ["", "Alpha", "", "Bravo", ""])
        #expect(doc.getPageBoxes(for: 0).mediaBox.size == CGSize(width: 842, height: 595))
        #expect(doc.getPageBoxes(for: 2).mediaBox.size == CGSize(width: 842, height: 595))
        #expect(doc.getPageBoxes(for: 4).mediaBox.size == CGSize(width: 300, height: 400))
        #expect((doc.extractText(pageIndex: 2) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(throws: Error.self) { _ = try doc.insertBlankPage(atSlot: 99) }
    }

    // MARK: - Import

    @Test(arguments: [0, 1, 2])
    func importedPagesLandAtTheSlotInTheirOwnOrder(slot: Int) throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let primary = dir.appendingPathComponent("primary.pdf")
        let external = dir.appendingPathComponent("external.pdf")
        makeLabelledPDF(at: primary, labels: ["Alpha", "Bravo"])
        makeLabelledPDF(at: external, labels: ["Xray", "Yankee", "Zulu"], pageSize: CGSize(width: 400, height: 300))

        let doc = try PDFDocumentCore(filePath: primary.path)
        let result = try doc.importPages(from: external, atSlot: slot)
        #expect(result.insertedSlot == slot && result.count == 3)

        var expected = ["Alpha", "Bravo"]
        expected.insert(contentsOf: ["Xray", "Yankee", "Zulu"], at: slot)
        let all = ["Alpha", "Bravo", "Xray", "Yankee", "Zulu"]
        #expect(pageLabels(of: doc, among: all) == expected)
        // Imported pages keep their own size rather than taking the host document's.
        #expect(doc.pageBounds[slot].size == CGSize(width: 400, height: 300))
        #expect(doc.pageBounds[(slot + 3) % 5].size == CGSize(width: 612, height: 792))

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(try pageLabels(ofFileAt: saved, among: all) == expected)
    }

    @Test func importRejectsBadSlotsAndNonPDFFiles() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let primary = dir.appendingPathComponent("primary.pdf")
        makeLabelledPDF(at: primary, labels: ["Alpha", "Bravo"])
        let notAPDF = dir.appendingPathComponent("notes.pdf")
        try Data("just some text".utf8).write(to: notAPDF)

        let doc = try PDFDocumentCore(filePath: primary.path)
        #expect(throws: Error.self) { _ = try doc.importPages(from: primary, atSlot: 3) }
        #expect(throws: Error.self) { _ = try doc.importPages(from: notAPDF, atSlot: 0) }
        #expect(throws: Error.self) { _ = try doc.importPages(from: dir.appendingPathComponent("missing.pdf"), atSlot: 0) }
        #expect(pageLabels(of: doc, among: ["Alpha", "Bravo"]) == ["Alpha", "Bravo"])
    }

    /// Imports a real-world document with embedded fonts: every page's text has to come across
    /// (fonts and other resources grafted with it), and the result has to save and reopen.
    @Test func importingARealWorldDocumentKeepsItsText() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let primary = dir.appendingPathComponent("primary.pdf")
        makeLabelledPDF(at: primary, labels: ["Alpha"])

        let source = try PDFDocumentCore(filePath: Fixture.lcmsTutorial.path)
        let sourceTexts = (0..<source.pageCount).map { source.extractText(pageIndex: $0) ?? "" }
        #expect(sourceTexts[0].contains("How to use the engine"))

        let doc = try PDFDocumentCore(filePath: primary.path)
        let result = try doc.importPages(from: Fixture.lcmsTutorial, atSlot: 1)
        #expect(result.count == source.pageCount)

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        let reopened = try PDFDocumentCore(filePath: saved.path)
        #expect(reopened.pageCount == source.pageCount + 1)
        #expect(reopened.extractText(pageIndex: 0)?.contains("Alpha") == true)
        for (index, text) in sourceTexts.enumerated() {
            #expect(reopened.extractText(pageIndex: index + 1) == text, "page \(index + 1)")
        }
    }

    /// The tutorial's table of contents links to its own pages. After importing it behind another
    /// page, those links must still lead to the imported pages (one page further on), not to
    /// pages of the file they came from or nowhere.
    @Test func importedInternalLinksStillPointAtTheImportedPages() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let primary = dir.appendingPathComponent("primary.pdf")
        makeLabelledPDF(at: primary, labels: ["Alpha"])

        let source = try PDFDocumentCore(filePath: Fixture.lcmsTutorial.path)
        let sourceTargets = source.loadLinks(for: 1).filter { $0.uri == nil || $0.uri?.hasPrefix("#") == true }.map(\.targetPage)
        #expect(sourceTargets.count > 5)

        let doc = try PDFDocumentCore(filePath: primary.path)
        _ = try doc.importPages(from: Fixture.lcmsTutorial, atSlot: 1)
        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        let reopened = try PDFDocumentCore(filePath: saved.path)
        let importedTargets = reopened.loadLinks(for: 2).filter { $0.uri == nil || $0.uri?.hasPrefix("#") == true }.map(\.targetPage)
        #expect(importedTargets == sourceTargets.map { $0 + 1 })
    }

    // MARK: - Measurements

    /// A drawing's scale and its measurements belong to the page they were made on, so they
    /// have to move with it when pages are reordered or others are deleted.
    @Test func scaleAndMeasurementsMoveWithTheirPage() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("drawings.pdf")
        let labels = ["Alpha", "Bravo", "Charlie"]
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.setPageScale(pageIndex: 0, ratioString: "1/4\" = 1'-0\"", unitString: "ft", pointsPerUnit: 18)
        try doc.addLineDimension(pageIndex: 0, startPoint: CGPoint(x: 100, y: 300), endPoint: CGPoint(x: 172, y: 300), text: "4'-0\"", red: 0, green: 0, blue: 1)
        try doc.reorderPage(from: 0, to: 2)    // Bravo Charlie Alpha
        try doc.deletePage(0)                  // Charlie Alpha

        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        let reopened = try PDFDocumentCore(filePath: saved.path)
        #expect(pageLabels(of: reopened, among: labels) == ["Charlie", "Alpha"])
        #expect(reopened.loadPageScale(pageIndex: 0) == nil)
        #expect(reopened.loadPageScale(pageIndex: 1).map { abs($0.pointsPerUnit - 18) < 0.01 } == true)
        #expect(reopened.measurementAnnotations(pageIndex: 0).isEmpty)
        #expect(reopened.measurementAnnotations(pageIndex: 1).map(\.measurementText) == ["4'-0\""])
    }

    /// A duplicated sheet should measure the same as the original.
    @Test func duplicateKeepsThePagesScale() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("scaled.pdf")
        makeLabelledPDF(at: url, labels: ["Alpha"])

        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.setPageScale(pageIndex: 0, ratioString: "1:100", unitString: "m", pointsPerUnit: 28.3465)
        _ = try doc.duplicatePages([0])
        #expect(doc.loadPageScale(pageIndex: 1).map { abs($0.pointsPerUnit - 28.3465) < 0.01 } == true)
    }

    // MARK: - Extract & split

    @Test func extractAndSplitWriteTheChosenPagesInOrder() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("split.pdf")
        let labels = Array(natoLabels.prefix(5))
        makeLabelledPDF(at: url, labels: labels)

        let doc = try PDFDocumentCore(filePath: url.path)
        let extracted = dir.appendingPathComponent("extracted.pdf")
        try doc.extractPages([3, 1], to: extracted)
        #expect(try pageLabels(ofFileAt: extracted, among: labels) == ["Delta", "Bravo"])

        let parts = try doc.split(pageRanges: [[0, 1], [], [2, 3, 4]], outputDirectory: dir,
                                  fileNames: ["part1.pdf", "unused.pdf", "part2.pdf"])
        #expect(parts.map(\.lastPathComponent) == ["part1.pdf", "part2.pdf"])
        #expect(try pageLabels(ofFileAt: parts[0], among: labels) == ["Alpha", "Bravo"])
        #expect(try pageLabels(ofFileAt: parts[1], among: labels) == ["Charlie", "Delta", "Echo"])
        // Extracting leaves the source as it was.
        #expect(pageLabels(of: doc, among: labels) == labels)
    }

    // MARK: - Through the view model

    /// The editing commands the thumbnail sidebar and menus use, end to end: each edit is made
    /// on a working copy, the original file is untouched until Save, and Save writes the result.
    @MainActor
    @Test func viewModelEditsReachTheFileOnlyOnSave() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("vm_edits.pdf")
        let external = dir.appendingPathComponent("external.pdf")
        let labels = ["Alpha", "Bravo", "Charlie", "Xray"]
        makeLabelledPDF(at: url, labels: ["Alpha", "Bravo", "Charlie"])
        makeLabelledPDF(at: external, labels: ["Xray"])
        let original = try Data(contentsOf: url)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true   // keep this test out of the stored reading state
        await vm.loadDocument(from: url.path)
        let doc = try #require(vm.document)

        vm.rotatePage(1, by: 90)                  // Alpha Bravo(landscape) Charlie
        vm.duplicatePage(0)                       // Alpha Alpha Bravo Charlie
        vm.reorderPage(from: 3, to: 0)            // Charlie Alpha Alpha Bravo
        vm.deletePage(2)                          // Charlie Alpha Bravo
        vm.insertBlankPage(after: 0)              // Charlie _ Alpha Bravo
        vm.importPages(from: external, toSlot: 4) // Charlie _ Alpha Bravo Xray
        let expected = ["Charlie", "", "Alpha", "Bravo", "Xray"]
        #expect(pageLabels(of: doc, among: labels) == expected)
        #expect(vm.isDocumentEdited)
        #expect(try Data(contentsOf: url) == original)

        let workingCopy = try #require(vm.workingCopyPath)
        vm.saveDocument()
        #expect(!vm.isDocumentEdited)
        #expect(try pageLabels(ofFileAt: url, among: labels) == expected)
        // Reopens the edits queued for the working copy, which the save has just deleted, are
        // skipped; the actors follow the saved file instead.
        #expect(vm.workingCopyPath == nil && !FileManager.default.fileExists(atPath: workingCopy))
        #expect(await vm.reopenActors(at: workingCopy) == false)
        #expect(await vm.reopenActors(at: url.path))
        #expect(PDFKit.PDFDocument(url: url)?.page(at: 3)?.rotation == 90)   // Bravo
    }
}
