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

/// Object 3 of the PDF `makePDF` writes, which is the `/PageLabels` tree, so a tree can refer to itself.
private let labelTreeObject = 3

/// Writes a PDF with one page per string in `pages`, each showing only that string, and with
/// `tree` as its `/PageLabels`.
private func makePDF(at url: URL, pages: [String], tree: String?) throws {
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R\(tree == nil ? "" : " /PageLabels \(labelTreeObject) 0 R") >>",
        "<< /Type /Pages /Count \(pages.count) /Kids [\(pages.indices.map { "\(5 + 2 * $0) 0 R" }.joined(separator: " "))] >>",
        tree ?? "null",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]
    for (index, text) in pages.enumerated() {
        let content = "BT /F1 24 Tf 72 700 Td (\(text)) Tj ET"
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents \(6 + 2 * index) 0 R >>")
        objects.append("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")
    }
    var file = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(file.utf8.count)
        file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let xref = file.utf8.count
    file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
    file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    try Data(file.utf8).write(to: url)
}

private let sheets = ["Alpha", "Bravo", "Charlie", "Delta"]
private let sheetTree = "<< /Nums [0 << /P (A-101) >> 1 << /P (S-201) >> 2 << /P (M-301) >> 3 << /S /D /P (E-) /St 401 >>] >>"
/// i, ii, 1, 2, 3, 4
private let bookTree = "<< /Nums [0 << /S /r >> 2 << /S /D >>] >>"
private let bookPages = Array(natoLabels.prefix(6))

/// Labels as another PDF reader sees them, without the spaces the reference file's labels start with.
private func labelsReadByPDFKit(at url: URL) -> [String]? {
    guard let doc = PDFKit.PDFDocument(url: url) else { return nil }
    return (0..<doc.pageCount).map { (doc.page(at: $0)?.label ?? "").trimmingCharacters(in: .whitespaces) }
}

@Suite(.serialized)
struct PageLabelTests {
    private func open(pages: [String], tree: String?, in dir: URL) throws -> PDFDocumentCore {
        let url = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        try makePDF(at: url, pages: pages, tree: tree)
        return try PDFDocumentCore(filePath: url.path)
    }

    /// Labels as a fresh open of the saved file sees them.
    private func savedLabels(of doc: PDFDocumentCore, in dir: URL) throws -> [String]? {
        let url = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        try doc.save(to: url.path)
        return try PDFDocumentCore(filePath: url.path).pageLabels
    }

    // MARK: - Reading

    @Test func readsSheetCodesAndRomanNumerals() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try open(pages: sheets, tree: sheetTree, in: dir).pageLabels == ["A-101", "S-201", "M-301", "E-401"])
        #expect(try open(pages: bookPages, tree: bookTree, in: dir).pageLabels == ["i", "ii", "1", "2", "3", "4"])
    }

    @Test func labelsThatMatchThePositionCountAsNone() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(try open(pages: sheets, tree: nil, in: dir).pageLabels == nil)
        #expect(try open(pages: sheets, tree: "<< /Nums [0 << /S /D >>] >>", in: dir).pageLabels == nil)
    }

    @Test func pagesWithoutALabelShowTheirPosition() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: "<< /Nums [1 << /P (X) >> 2 << >>] >>", in: dir)
        #expect(doc.pageLabels == ["1", "X", "3", "4"])
        #expect(doc.displayLabel(forPage: 1) == "X")
    }

    @Test(arguments: [
        "<< /Kids [\(labelTreeObject) 0 R] >>",
        "<< /Kids [\(labelTreeObject) 0 R \(labelTreeObject) 0 R] >>",
        "<< /Nums [0 << /S /R /St 2000000000 >>] >>"
    ])
    func hostileTreesLeavePagesUnlabelledAndEditable(tree: String) throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: tree, in: dir)
        #expect(doc.pageLabels == nil)
        try doc.reorderPage(from: 2, to: 0)
        #expect(pageLabels(of: doc, among: sheets) == ["Charlie", "Alpha", "Bravo", "Delta"])
        #expect(doc.pageLabels == nil)
    }

    @Test func readsTheReferenceFileLikePDFKit() throws {
        let url = Fixture.pdfDifferences("PageLabelsTest.pdf")
        let doc = try PDFDocumentCore(filePath: url.path)
        #expect(doc.pageLabels == [
            "i", "ii", "iii", "iv", "1", "2", "3", "4", "٤", "٥", "٦", "٧",
            "Long Label - 11", "Long Label - 12", "Long Label - 13", "Long Label - 14"
        ])
        #expect(doc.pageLabels == labelsReadByPDFKit(at: url))
    }

    @Test func jumpsToEveryLabelInTheReferenceFile() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.pdfDifferences("PageLabelsTest.pdf").path)
        for (index, label) in try #require(doc.pageLabels).enumerated() {
            #expect(doc.pageIndex(forJumpTo: label, from: 0) == index)
        }
    }

    @Test func editedLabelsReadTheSameInPDFKit() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try PDFDocumentCore(filePath: Fixture.pdfDifferences("PageLabelsTest.pdf").path)
        try doc.reorderPage(from: 15, to: 0)
        try doc.deletePage(8)
        _ = try doc.insertBlankPage(atSlot: 0)
        let saved = dir.appendingPathComponent("edited.pdf")
        try doc.save(to: saved.path)
        #expect(doc.pageLabels == labelsReadByPDFKit(at: saved))
    }

    // MARK: - Page edits

    @Test func editsGiveAnUnlabelledDocumentNoLabels() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: nil, in: dir)
        try doc.reorderPage(from: 2, to: 0)
        #expect(doc.pageLabels == nil)
        _ = try doc.insertBlankPage(atSlot: 0)
        #expect(doc.pageLabels == nil)
        try doc.reorderPages(from: [3, 4], toSlot: 0)
        #expect(doc.pageLabels == nil)
        #expect(try savedLabels(of: doc, in: dir) == nil)
    }

    @Test func sheetCodesMoveWithTheirPages() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: sheetTree, in: dir)
        try doc.reorderPage(from: 0, to: 2)
        #expect(pageLabels(of: doc, among: sheets) == ["Bravo", "Charlie", "Alpha", "Delta"])
        #expect(doc.pageLabels == ["S-201", "M-301", "A-101", "E-401"])
        try doc.reorderPages(from: [3, 0], toSlot: 2)
        #expect(pageLabels(of: doc, among: sheets) == ["Charlie", "Delta", "Bravo", "Alpha"])
        #expect(doc.pageLabels == ["M-301", "E-401", "S-201", "A-101"])
        #expect(try savedLabels(of: doc, in: dir) == ["M-301", "E-401", "S-201", "A-101"])
    }

    @Test func deletingASheetKeepsTheOthersCodes() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: sheetTree, in: dir)
        try doc.deletePage(0)
        #expect(doc.pageLabels == ["S-201", "M-301", "E-401"])
        try doc.deletePages([1])
        #expect(try savedLabels(of: doc, in: dir) == ["S-201", "E-401"])
    }

    @Test func numberingStaysInOrderWhenPagesMove() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: bookPages, tree: bookTree, in: dir)
        try doc.reorderPage(from: 4, to: 0)
        #expect(doc.pageLabels == ["i", "ii", "1", "2", "3", "4"])
        #expect(try savedLabels(of: doc, in: dir) == ["i", "ii", "1", "2", "3", "4"])
    }

    @Test func deletingShortensItsRange() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: bookPages, tree: bookTree, in: dir)
        try doc.deletePage(0)
        #expect(doc.pageLabels == ["i", "1", "2", "3", "4"])
        try doc.deletePage(0)
        #expect(doc.pageLabels == nil, "1, 2, 3, 4 is just the pages' positions")
    }

    @Test func addedPagesCarryOnTheNumbering() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: bookPages, tree: bookTree, in: dir)
        _ = try doc.insertBlankPage(atSlot: 0)
        #expect(doc.pageLabels == ["i", "ii", "iii", "1", "2", "3", "4"])
        _ = try doc.insertBlankPage(atSlot: 5)
        #expect(doc.pageLabels == ["i", "ii", "iii", "1", "2", "3", "4", "5"])
    }

    @Test func aPageAddedAmongSheetsIsNumberedByPosition() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: sheetTree, in: dir)
        _ = try doc.insertBlankPage(atSlot: 2)
        #expect(doc.pageLabels == ["A-101", "S-201", "3", "M-301", "E-401"])
        let (slot, count) = try doc.duplicatePages([0])
        #expect((slot, count) == (1, 1))
        #expect(doc.pageLabels == ["A-101", "2", "S-201", "3", "M-301", "E-401"])
    }

    @Test func splittingANumberedRangeContinuesItsNumbers() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tree = "<< /Nums [0 << /P (Cover) >> 1 << /S /D >>] >>"
        let doc = try open(pages: sheets, tree: tree, in: dir)
        try doc.reorderPage(from: 0, to: 2)
        #expect(doc.pageLabels == ["1", "2", "Cover", "3"])
    }

    @Test func aFailedEditLeavesTheLabelsAlone() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: sheetTree, in: dir)
        #expect(throws: PDFError.self) { try doc.reorderPage(from: 0, to: 99) }
        #expect(throws: PDFError.self) { try doc.deletePages([0, 1, 2, 3]) }
        #expect(try savedLabels(of: doc, in: dir) == ["A-101", "S-201", "M-301", "E-401"])
    }

    @Test func repeatedKeysAreRepairedByAnEdit() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: "<< /Nums [0 << /P (A) >> 0 << /P (B) >> 1 << /P (C) >> 2 << /P (D) >>] >>", in: dir)
        #expect(doc.pageLabels == ["B", "C", "D", "D"])
        try doc.reorderPage(from: 0, to: 1)
        #expect(doc.pageLabels == ["C", "B", "D", "D"])
    }

    // MARK: - Jumping

    @Test func jumpsByLabelAndPosition() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let book = try open(pages: bookPages, tree: bookTree, in: dir)
        #expect(book.pageIndex(forJumpTo: "ii", from: 0) == 1)
        #expect(book.pageIndex(forJumpTo: " II ", from: 0) == 1)
        #expect(book.pageIndex(forJumpTo: "1", from: 0) == 2, "A label wins over a position")
        #expect(book.pageIndex(forJumpTo: "#1", from: 3) == 0)
        #expect(book.pageIndex(forJumpTo: "6", from: 0) == 5, "No such label, so a position")
        #expect(book.pageIndex(forJumpTo: "99", from: 0) == 5)
        #expect(book.pageIndex(forJumpTo: "nope", from: 0) == nil)
        #expect(book.pageIndex(forJumpTo: "", from: 0) == nil)

        let sheetSet = try open(pages: sheets, tree: sheetTree, in: dir)
        #expect(sheetSet.pageIndex(forJumpTo: "m-301", from: 0) == 2)
        #expect(sheetSet.pageIndex(forJumpTo: "E-401", from: 0) == 3)
    }

    @Test func aRepeatedLabelFindsTheNextOne() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: "<< /Nums [0 << /S /D >> 2 << /S /D >>] >>", in: dir)
        #expect(doc.pageLabels == ["1", "2", "1", "2"])
        #expect(doc.pageIndex(forJumpTo: "2", from: 0) == 1)
        #expect(doc.pageIndex(forJumpTo: "2", from: 1) == 3)
        #expect(doc.pageIndex(forJumpTo: "2", from: 3) == 1)
    }

    @Test func withoutLabelsAJumpIsAClampedPosition() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let doc = try open(pages: sheets, tree: nil, in: dir)
        #expect(doc.pageIndex(forJumpTo: "3", from: 0) == 2)
        #expect(doc.pageIndex(forJumpTo: "0", from: 3) == 0)
        #expect(doc.pageIndex(forJumpTo: "99", from: 0) == 3)
    }
}
