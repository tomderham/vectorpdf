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

// Redaction must remove content from the saved file, not just hide it. These tests build PDFs by
// hand (Type1 Helvetica, literal strings) so redacted text would be visible in the raw bytes, and
// they search every stream in the output after decompressing it.

// MARK: - Fixtures

private func scratchURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_redaction_\(UUID().uuidString)_\(name)")
}

/// Writes a PDF from object bodies; `objects[i]` becomes object `i + 1`. Object 1 must be the catalog.
private func writeRawPDF(at url: URL, objects: [String]) {
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for (i, body) in objects.enumerated() {
        offsets.append(pdf.utf8.count)
        pdf += "\(i + 1) 0 obj\n\(body)\nendobj\n"
    }
    let xrefOffset = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        pdf += String(format: "%010d 00000 n \n", offset)
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    try! Data(pdf.utf8).write(to: url)
}

private func stream(_ content: String, dict: String = "") -> String {
    "<< \(dict) /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
}

private let helvetica = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

/// One page per entry, each showing its lines in 12 pt Helvetica from y = 700 (PDF space) down,
/// 30 pt apart. Objects: 1 catalog, 2 pages, 3 font, then a page and content stream per page.
private func writeTextPDF(at url: URL, pages: [[String]]) {
    let firstPage = 4
    let kids = pages.indices.map { "\(firstPage + 2 * $0) 0 R" }.joined(separator: " ")
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>",
        helvetica,
    ]
    for (i, lines) in pages.enumerated() {
        let content = lines.enumerated()
            .map { "BT /F1 12 Tf 72 \(700 - 30 * $0.offset) Td (\($0.element)) Tj ET" }
            .joined(separator: "\n")
        objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents \(firstPage + 2 * i + 1) 0 R /Resources << /Font << /F1 3 0 R >> >> >>")
        objects.append(stream(content))
    }
    writeRawPDF(at: url, objects: objects)
}

/// The whole file as Latin-1 text, followed by the decoded contents of every stream, so a search
/// finds strings whether they were written plain, Flate-compressed, or hex-encoded.
private func decodedFileText(_ url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    var text = String(decoding: data, as: Unicode.ASCII.self)
    if let latin1 = String(data: data, encoding: .isoLatin1) { text = latin1 }
    for s in decodedStreams(data) {
        text += "\n" + (String(data: s.payload, encoding: .isoLatin1) ?? "")
    }
    return text
}

private struct DecodedStream {
    let dict: String
    let payload: Data
}

private func decodedStreams(_ data: Data) -> [DecodedStream] {
    let bytes = [UInt8](data)
    let streamKey = Array("stream".utf8)
    let endKey = Array("endstream".utf8)
    let objKey = Array(" obj".utf8)
    var result: [DecodedStream] = []
    var i = 0
    func matches(_ key: [UInt8], at p: Int) -> Bool {
        p >= 0 && p + key.count <= bytes.count && Array(bytes[p..<p + key.count]) == key
    }
    while i < bytes.count {
        guard matches(streamKey, at: i), !matches(endKey, at: i - 3) else { i += 1; continue }
        var start = i + streamKey.count
        if start < bytes.count, bytes[start] == 0x0D { start += 1 }
        if start < bytes.count, bytes[start] == 0x0A { start += 1 }
        var end = start
        while end < bytes.count, !matches(endKey, at: end) { end += 1 }
        var dictStart = i
        while dictStart > 0, !matches(objKey, at: dictStart) { dictStart -= 1 }
        let dict = String(decoding: bytes[dictStart..<i], as: UTF8.self)
        var payload = Data(bytes[start..<end])
        if dict.contains("FlateDecode"), payload.count > 2,
           let inflated = try? (Data(payload.dropFirst(2)) as NSData).decompressed(using: .zlib) as Data {
            payload = inflated
        } else if dict.contains("ASCIIHexDecode") {
            payload = hexDecoded(payload)
        }
        result.append(DecodedStream(dict: dict, payload: payload))
        i = end + endKey.count
    }
    return result
}

private func hexDecoded(_ data: Data) -> Data {
    var out = Data()
    var high: UInt8?
    for byte in data {
        if byte == UInt8(ascii: ">") { break }
        guard let nibble = UInt8(String(UnicodeScalar(byte)), radix: 16) else { continue }
        if let h = high { out.append(h << 4 | nibble); high = nil } else { high = nibble }
    }
    if let h = high { out.append(h << 4) }
    return out
}

/// Counts pixels equal to `rgb` in an 8-bit RGB image payload.
private func pixelCount(_ payload: Data, rgb: (UInt8, UInt8, UInt8)) -> Int {
    let b = [UInt8](payload)
    return stride(from: 0, to: b.count - 2, by: 3).filter { b[$0] == rgb.0 && b[$0 + 1] == rgb.1 && b[$0 + 2] == rgb.2 }.count
}

/// RGB of the pixel at the center of `rect` (page coordinates, origin top-left) when rendered.
private func renderedColor(_ doc: PDFDocumentCore, pageIndex: Int, rect: CGRect) throws -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    let png = try #require(doc.renderPageRect(pageIndex: pageIndex, rect: rect, scale: 1.0))
    let rep = try #require(NSBitmapImageRep(data: png))
    let color = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
    return (color.redComponent, color.greenComponent, color.blueComponent)
}

/// Waits for the view model's background redaction search to finish.
@MainActor
private func awaitRedactionSearch(_ vm: PDFViewerViewModel, expecting count: Int) async {
    for _ in 0..<60 {
        if !vm.isRedactionSearching && vm.redactionMatches.count >= count { return }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

// MARK: - Tests

@Suite(.serialized)
struct RedactionSafetyTests {

    @Test @MainActor func findAndRedactRemovesOnlyTheMatchedWordFromALine() async throws {
        let url = scratchURL("partial.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        writeTextPDF(at: url, pages: [["KEEPME SECRETWORD TAILTEXT"]])

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        vm.editRedactTab = .findAndRedact
        vm.replaceAction = .redact
        vm.redactionPreset = .customText
        vm.redactionSearchQuery = "SECRETWORD"
        vm.performRedactionSearch()
        await awaitRedactionSearch(vm, expecting: 1)
        #expect(vm.redactionMatches.count == 1)
        vm.applySelectedMatches()
        vm.saveDocument()

        let text = try PDFDocumentCore(filePath: url.path).extractText(pageIndex: 0) ?? ""
        #expect(text.contains("KEEPME"))
        #expect(text.contains("TAILTEXT"))
        #expect(!text.contains("SECRET"))
        #expect(!(try decodedFileText(url)).contains("SECRETWORD"))
    }

    @Test @MainActor func findAndRedactCoversEveryPageAndSurvivesSave() async throws {
        let url = scratchURL("multipage.pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        writeTextPDF(at: url, pages: [
            ["Applicant SSN 123-45-6789", "Page one body"],
            ["Page two body", "Spouse SSN 987-65-4321"],
            ["Page three has no identifiers"],
        ])

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        vm.editRedactTab = .findAndRedact
        vm.replaceAction = .redact
        vm.redactionPreset = .ssn
        vm.performRedactionSearch()
        await awaitRedactionSearch(vm, expecting: 2)
        #expect(Set(vm.redactionMatches.map(\.result.pageIndex)) == [0, 1])
        vm.applySelectedMatches()
        vm.saveDocument()

        let saved = try PDFDocumentCore(filePath: url.path)
        let allText = (0..<saved.pageCount).compactMap { saved.extractText(pageIndex: $0) }.joined(separator: "\n")
        #expect(!allText.contains("123-45-6789"))
        #expect(!allText.contains("987-65-4321"))
        #expect(allText.contains("Page one body"))
        #expect(allText.contains("Page three has no identifiers"))

        let raw = try decodedFileText(url)
        #expect(!raw.contains("123-45-6789"))
        #expect(!raw.contains("987-65-4321"))
    }

    /// A 10×10 red image drawn at (100, 300)–(300, 500) in PDF space, i.e. y 292–492 from the top.
    private func writeImagePDF(at url: URL) {
        let hex = String(repeating: "FF0000", count: 100) + ">"
        writeRawPDF(at: url, objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /XObject << /Im1 5 0 R >> >> >>",
            stream("q 200 0 0 200 100 300 cm /Im1 Do Q"),
            stream(hex, dict: "/Type /XObject /Subtype /Image /Width 10 /Height 10 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /ASCIIHexDecode"),
        ])
    }

    @Test(arguments: [Int32(1), Int32(2)])
    func regionRedactionErasesImagePixelsUnderTheRegion(mode: Int32) throws {
        let src = scratchURL("image_src.pdf")
        let out = scratchURL("image_out.pdf")
        defer { for u in [src, out] { try? FileManager.default.removeItem(at: u) } }
        writeImagePDF(at: src)

        let doc = try PDFDocumentCore(filePath: src.path)
        // Left half of the image (columns 0–4).
        try doc.applyRedactions(pageIndex: 0, rects: [CGRect(x: 90, y: 280, width: 110, height: 230)], mode: mode)
        try doc.save(to: out.path)

        let images = decodedStreams(try Data(contentsOf: out)).filter { $0.dict.contains("/Image") }
        #expect(!images.isEmpty)
        // No copy of the original image may survive; the one left keeps only the right half red.
        for image in images {
            let red = pixelCount(image.payload, rgb: (255, 0, 0))
            #expect(red == 50, "image stream still holds \(red) of 100 original pixels")
        }
    }

    @Test func textOnlyRedactionLeavesImagesIntact() throws {
        let src = scratchURL("image_textonly_src.pdf")
        let out = scratchURL("image_textonly_out.pdf")
        defer { for u in [src, out] { try? FileManager.default.removeItem(at: u) } }
        writeImagePDF(at: src)

        let doc = try PDFDocumentCore(filePath: src.path)
        try doc.applyRedactions(pageIndex: 0, rects: [CGRect(x: 90, y: 280, width: 110, height: 230)], mode: 0)
        try doc.save(to: out.path)

        let images = decodedStreams(try Data(contentsOf: out)).filter { $0.dict.contains("/Image") }
        #expect(images.map { pixelCount($0.payload, rgb: (255, 0, 0)) } == [100])
    }

    @Test func regionRedactionRemovesVectorArtItTouches() throws {
        let src = scratchURL("vector_src.pdf")
        let out = scratchURL("vector_out.pdf")
        defer { for u in [src, out] { try? FileManager.default.removeItem(at: u) } }
        // A blue bar from x 100–300 at PDF y 600–620 (y 172–192 from the top).
        writeRawPDF(at: src, objects: [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>",
            stream("0 0 1 rg 100 600 200 20 re f"),
        ])
        let barSample = CGRect(x: 260, y: 177, width: 10, height: 10)
        let before = try renderedColor(try PDFDocumentCore(filePath: src.path), pageIndex: 0, rect: barSample)
        #expect(before.b > 0.9 && before.r < 0.1)

        let doc = try PDFDocumentCore(filePath: src.path)
        // Touch only the bar's left end; line art that a region touches is removed entirely.
        try doc.applyRedactions(pageIndex: 0, rects: [CGRect(x: 90, y: 165, width: 40, height: 35)], mode: 1)
        try doc.save(to: out.path)

        let after = try renderedColor(try PDFDocumentCore(filePath: out.path), pageIndex: 0, rect: barSample)
        #expect(after.r > 0.9 && after.g > 0.9 && after.b > 0.9, "blue bar still drawn outside the region: \(after)")
    }

    // MARK: Annotations and form fields under a region

    /// A page with "ACCOUNT 99887766" at PDF y 700 (y ≈ 80–95 from the top), plus annotations
    /// over it that carry the same number, and a note elsewhere that must survive.
    private func writeAnnotatedPDF(at url: URL) {
        writeRawPDF(at: url, objects: [
            "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [8 0 R] /DA (/Helv 0 Tf 0 g) >> >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> /Annots [6 0 R 7 0 R 8 0 R 9 0 R] >>",
            stream("BT /F1 12 Tf 72 700 Td (ACCOUNT 99887766) Tj ET"),
            helvetica,
            // Highlight whose comment repeats the highlighted text, as Acrobat and Preview write it.
            "<< /Type /Annot /Subtype /Highlight /Rect [70 696 200 714] /QuadPoints [70 714 200 714 70 696 200 696] /C [1 1 0] /Contents (HIGHLIGHTED 99887766) /T (Reviewer) >>",
            // Sticky note anchored on the line.
            "<< /Type /Annot /Subtype /Text /Rect [180 696 198 714] /Contents (NOTE 99887766) /T (Reviewer) >>",
            // Form field over the line with the number as its value.
            "<< /Type /Annot /Subtype /Widget /FT /Tx /T (acct) /V (FIELD99887766) /Rect [210 696 330 714] /DA (/Helv 10 Tf 0 g) /F 4 >>",
            // Unrelated note far from the region.
            "<< /Type /Annot /Subtype /Text /Rect [500 100 518 118] /Contents (KEEPNOTE) /T (Reviewer) >>",
        ])
    }

    @Test(arguments: [Int32(1), Int32(2), Int32(0)])
    func regionRedactionRemovesAnnotationsAndFieldsCarryingTheText(mode: Int32) throws {
        let src = scratchURL("annots_src.pdf")
        let out = scratchURL("annots_out.pdf")
        defer { for u in [src, out] { try? FileManager.default.removeItem(at: u) } }
        writeAnnotatedPDF(at: src)

        let doc = try PDFDocumentCore(filePath: src.path)
        #expect(doc.extractText(pageIndex: 0)?.contains("99887766") == true)
        try doc.applyRedactions(pageIndex: 0, rects: [CGRect(x: 60, y: 70, width: 290, height: 35)], mode: mode)
        try doc.save(to: out.path)

        let raw = try decodedFileText(out)
        #expect(!raw.contains("99887766"))
        #expect(raw.contains("KEEPNOTE"))
        #expect(try PDFDocumentCore(filePath: out.path).extractText(pageIndex: 0)?.contains("99887766") == false)
    }

    @Test func savedRedactionHasNoRecoverableEarlierRevision() throws {
        // An incrementally updated file: the original revision's content stream (object 5) is
        // superseded but still in the bytes, and both revisions carry the number.
        let src = scratchURL("incremental_src.pdf")
        let out = scratchURL("incremental_out.pdf")
        defer { for u in [src, out] { try? FileManager.default.removeItem(at: u) } }
        writeTextPDF(at: src, pages: [["OLDREVISION 55443322", "Public line"]])
        var bytes = try String(contentsOf: src, encoding: .isoLatin1)
        let prevXref = try #require(bytes.components(separatedBy: "startxref\n").last?.split(separator: "\n").first)
        let objectOffset = bytes.utf8.count
        bytes += "5 0 obj\n" + stream("BT /F1 12 Tf 72 700 Td (CURRENT 55443322) Tj ET\nBT /F1 12 Tf 72 670 Td (Public line) Tj ET") + "\nendobj\n"
        let xrefOffset = bytes.utf8.count
        bytes += "xref\n5 1\n" + String(format: "%010d 00000 n \n", objectOffset)
        bytes += "trailer\n<< /Size 6 /Root 1 0 R /Prev \(prevXref) >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        try Data(bytes.utf8).write(to: src)
        #expect(try decodedFileText(src).contains("OLDREVISION 55443322"))

        let doc = try PDFDocumentCore(filePath: src.path)
        let line = try #require(doc.loadStructuredPage(for: 0)?.allLines.first { $0.text.contains("55443322") })
        try doc.applyRedactions(pageIndex: 0, rects: [line.bbox.insetBy(dx: -2, dy: -2)], mode: 1)
        try doc.save(to: out.path)

        let raw = try decodedFileText(out)
        #expect(!raw.contains("55443322"))
        #expect(!raw.contains("OLDREVISION"))
        #expect(raw.contains("Public line"))
        // A single revision: nothing to roll back to.
        #expect(raw.components(separatedBy: "%%EOF").count - 1 == 1)
    }
}
