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

/// Writes a PDF from numbered object bodies (object 1 is the catalog), with its xref table.
func writeRawPDF(_ objects: [String], to url: URL) throws {
    var out = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (index, body) in objects.enumerated() {
        offsets.append(out.utf8.count)
        out += "\(index + 1) 0 obj\n\(body)\nendobj\n"
    }
    let xref = out.utf8.count
    out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets { out += String(format: "%010d 00000 n \n", offset) }
    out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    try Data(out.utf8).write(to: url)
}

/// Two pages: page 1 has a text field, a group of two radio buttons, a signed signature field,
/// a web link and a link to the named destination "results"; page 2 is where "results" and
/// "appendix" point.
func makeDocumentContentsPDF(at url: URL) throws {
    let content = "BT /F1 12 Tf 72 700 Td (Example site) Tj ET"
    try writeRawPDF([
        // 1 catalog
        "<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [5 0 R 6 0 R 9 0 R] >> /Names << /Dests << /Names [(appendix) [4 0 R /XYZ 0 500 0] (results) [4 0 R /XYZ 0 700 0]] >> >> >>",
        // 2 pages
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        // 3 page 1
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> /Contents 12 0 R /Annots [5 0 R 7 0 R 8 0 R 9 0 R 10 0 R 11 0 R] >>",
        // 4 page 2
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
        // 5 text field
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (city) /TU (City of birth) /V (Lisbon) /Ff 2 /Rect [72 600 272 620] /P 3 0 R /DA (/Helv 10 Tf 0 g) >>",
        // 6 radio group
        "<< /FT /Btn /Ff 49152 /T (size) /V /Large /Kids [7 0 R 8 0 R] >>",
        // 7, 8 radio buttons
        "<< /Type /Annot /Subtype /Widget /Parent 6 0 R /Rect [72 560 86 574] /P 3 0 R /AS /Off /AP << /N << /Small 13 0 R /Off 13 0 R >> >> >>",
        "<< /Type /Annot /Subtype /Widget /Parent 6 0 R /Rect [100 560 114 574] /P 3 0 R /AS /Large /AP << /N << /Large 13 0 R /Off 13 0 R >> >> >>",
        // 9 signature field, signed
        "<< /Type /Annot /Subtype /Widget /FT /Sig /T (approval) /Rect [72 480 272 520] /P 3 0 R /V << /Type /Sig /Filter /Adobe.PPKLite /SubFilter /adbe.pkcs7.detached /ByteRange [0 10 20 10] /Contents <00> /Name (Jane Example) /M (D:20260301120000Z) /Reason (Approved) /Location (Lisbon) >> >>",
        // 10 web link
        "<< /Type /Annot /Subtype /Link /Rect [70 695 160 712] /Border [0 0 0] /A << /S /URI /URI (https://example.com/) >> >>",
        // 11 link to a named destination
        "<< /Type /Annot /Subtype /Link /Rect [72 400 200 420] /Border [0 0 0] /Dest (results) >>",
        // 12 page 1 content
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        // 13 appearance
        "<< /Type /XObject /Subtype /Form /BBox [0 0 14 14] /Length 0 >>\nstream\n\nendstream",
    ], to: url)
}

@Suite(.serialized)
struct DocumentContentsTests {
    @Test func summaryFindsFieldsLinksAndDestinations() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("contents.pdf")
        try makeDocumentContentsPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        #expect(doc.contentsSummary() == DocumentContentsSummary(hasFormFields: true, hasLinks: true, hasNamedDestinations: true, signatureCount: 1))

        let plain = dir.appendingPathComponent("plain.pdf")
        makeLabelledPDF(at: plain, labels: ["One"])
        #expect(try PDFDocumentCore(filePath: plain.path).contentsSummary() == DocumentContentsSummary())
    }

    @Test func formFieldsListOneRowPerFieldWithTheirValuesAndSignatures() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("contents.pdf")
        try makeDocumentContentsPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        let fields = doc.formFieldEntries(pageIndex: 0)
        #expect(fields.map(\.type) == [.text, .radiobutton, .signature])
        #expect(doc.formFieldEntries(pageIndex: 1).isEmpty)

        let city = fields[0]
        #expect(city.name == "city")
        #expect(city.displayName == "City of birth")
        #expect(city.value == "Lisbon")
        #expect(city.isRequired && !city.isReadOnly)
        // Top-down page coordinates, as the canvas uses.
        #expect(abs(city.rect.minY - (792 - 620)) < 0.5 && abs(city.rect.width - 200) < 0.5)

        // Two radio buttons, one field.
        #expect(fields[1].name == "size" && fields[1].value == "Large")

        let signature = try #require(fields[2].signature)
        #expect(signature.isSigned)
        #expect(signature.signer == "Jane Example")
        #expect(signature.reason == "Approved" && signature.location == "Lisbon")
        #expect(signature.date == ISO8601DateFormatter().date(from: "2026-03-01T12:00:00Z"))
        #expect(signature.certification == nil)
        #expect(fields[2].displayValue == "")
    }

    @Test func linksListTheirTextAndWhereTheyGo() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("contents.pdf")
        try makeDocumentContentsPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        let links = doc.documentLinks(pageIndex: 0)
        let web = try #require(links.first { $0.isExternal })
        #expect(web.uri == "https://example.com/")
        // The text under a link is read separately, as the list shows its page.
        #expect(web.text == "")
        #expect(doc.linkTexts(pageIndex: 0, rects: links.map(\.rect)) == links.map { $0.isExternal ? "Example site" : "" })
        #expect(web.destinationDescription == "https://example.com/")
        let inside = try #require(links.first { !$0.isExternal })
        #expect(inside.targetPage == 1)
        #expect(inside.text == "")
        #expect(inside.destinationDescription == "Page 2")
    }

    @Test func namedDestinationsAreListedByNameWithTheirPages() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("contents.pdf")
        try makeDocumentContentsPDF(at: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        let destinations = doc.namedDestinations()
        #expect(destinations.map(\.name) == ["appendix", "results"])
        #expect(destinations.map(\.pageIndex) == [1, 1])
        // Top-down: y 700 from the bottom is 92 from the top.
        #expect(abs((destinations[1].point?.y ?? 0) - 92) < 0.5)
    }

    @Test func aRealFormListsItsFields() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.form1040.path)
        #expect(doc.contentsSummary().hasFormFields)
        let fields = (0..<doc.pageCount).flatMap { doc.formFieldEntries(pageIndex: $0) }
        #expect(fields.count > 50)
        #expect(fields.contains { $0.type == .text } && fields.contains { $0.type == .checkbox })
        // Names are fully qualified.
        #expect(fields.contains { $0.name.contains(".") })
    }

    @MainActor
    @Test func theDocumentTabOffersOnlyWhatTheDocumentHas() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("contents.pdf")
        try makeDocumentContentsPDF(at: url)
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let coordinator = PDFViewerAppCoordinator.shared
        let saved = coordinator.showsDocumentStructureInSidebar
        defer { coordinator.showsDocumentStructureInSidebar = saved }
        // Off by default: a form being filled in, or a paper with links, gets no Document tab;
        // but its signatures are listed whatever the setting.
        coordinator.showsDocumentStructureInSidebar = false
        #expect(vm.documentSidebarSections == [.signatures])
        coordinator.showsDocumentStructureInSidebar = true
        #expect(vm.documentSidebarSections == [.signatures, .fields, .links, .destinations])
        // Layers was chosen last, but this document has none.
        vm.documentSidebarSection = .layers
        #expect(vm.shownDocumentSidebarSection == .signatures)

        vm.loadDocumentSection(.fields)
        vm.loadDocumentSection(.links)
        vm.loadDocumentSection(.destinations)
        for _ in 0..<100 where vm.formFieldEntries == nil || vm.documentLinks == nil || vm.namedDestinations == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(vm.formFieldEntries?.count == 3)
        #expect(vm.documentLinks?.count == 2)
        #expect(vm.namedDestinations?.count == 2)
        #expect(vm.documentLinksProgress == nil)
        vm.loadLinkTexts(onPage: 0)
        let web = try #require(vm.documentLinks?.first { $0.isExternal })
        for _ in 0..<100 where vm.documentLinkTexts[web.id] == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(vm.documentLinkTexts[web.id] == "Example site")

        // Filling in a field shows its new value in the list.
        let widget = try #require(vm.document?.loadFormWidgets(for: 0).first { $0.type == .text })
        vm.loadPageMetadata(0)
        vm.updateWidgetValue(pageIndex: 0, widgetIndex: widget.widgetIndex, value: "Porto")
        #expect(vm.formFieldEntries?.first?.value == "Porto")

        let attachments = PDFViewerViewModel()
        attachments.isTransientWindow = true
        await attachments.loadDocument(from: Fixture.attachmentSample.path)
        #expect(attachments.documentSidebarSections.first == .attachments)
    }
}
