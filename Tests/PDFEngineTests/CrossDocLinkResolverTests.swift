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

/// Writes a PDF from object bodies; `objects[i]` becomes object `i + 1`. Object 1 is the catalog.
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

private func textStream(_ lines: [String]) -> String {
    let content = lines.enumerated()
        .map { "BT /F1 14 Tf 72 \(720 - 30 * $0.offset) Td (\($0.element)) Tj ET" }
        .joined(separator: "\n")
    return "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream"
}

private let helvetica = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
private let pageDict = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents"

/// Two pages, RFC-style: page 1 opens with "RFC 9999", page 2 has §2.1, reachable through the
/// named destination "section-2.1".
private func writeNamedDestinationRFC(at url: URL) {
    writeRawPDF(at: url, objects: [
        "<< /Type /Catalog /Pages 2 0 R /Dests << /section-2.1 [6 0 R /XYZ 72 720 0] >> >>",
        "<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>",
        helvetica,
        "\(pageDict) 5 0 R >>",
        textStream(["RFC 9999", "Widget Exchange Protocol"]),
        "\(pageDict) 7 0 R >>",
        textStream(["2.1. Widget Format", "Widgets are exchanged as octets."]),
    ])
}

/// Two pages with no named destinations; page 2's §2.1 is reachable only through the outline.
private func writeOutlineOnlyRFC(at url: URL) {
    writeRawPDF(at: url, objects: [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 8 0 R >>",
        "<< /Type /Pages /Kids [4 0 R 6 0 R] /Count 2 >>",
        helvetica,
        "\(pageDict) 5 0 R >>",
        textStream(["Gadget Protocol"]),
        "\(pageDict) 7 0 R >>",
        textStream(["2.1. Gadget Format", "Gadgets are exchanged as octets."]),
        "<< /Type /Outlines /First 9 0 R /Last 9 0 R /Count 1 >>",
        "<< /Title (2.1. Gadget Format) /Parent 8 0 R /Dest [6 0 R /XYZ 72 720 0] >>",
    ])
}

private func scratchURL(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_crossdoc_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

@MainActor
private func loadedViewModel(_ url: URL) async -> PDFViewerViewModel {
    let vm = PDFViewerViewModel()
    vm.isTransientWindow = true
    await vm.loadDocument(from: url.path)
    return vm
}

private func webLink(_ uri: String) -> SnapshotTarget {
    SnapshotTarget(label: "Section 2.1", targetPage: -1, sourceRect: CGRect(x: 72, y: 100, width: 60, height: 12), sourcePage: 3, uri: uri)
}

@Suite(.serialized)
struct CrossDocLinkResolverTests {

    @Test func parsesRFCURLs() {
        let cases: [(String, Int?, String?)] = [
            ("https://www.rfc-editor.org/rfc/rfc9110#section-5.6.1", 9110, "section-5.6.1"),
            ("https://www.rfc-editor.org/rfc/rfc9110.html#appendix-B.1", 9110, "appendix-B.1"),
            ("https://www.rfc-editor.org/info/rfc9110", 9110, nil),
            ("https://datatracker.ietf.org/doc/html/rfc7234#section-4", 7234, "section-4"),
            ("https://tools.ietf.org/html/rfc2616", 2616, nil),
            ("https://www.ietf.org/rfc/rfc793.txt", 793, nil),
            ("https://www.rfc-editor.org/rfc/rfc9110#", 9110, nil),
        ]
        for (uri, number, fragment) in cases {
            let parsed = CrossDocLinkResolver.rfcReference(in: uri)
            #expect(parsed?.number == number, "\(uri)")
            #expect(parsed?.fragment == fragment, "\(uri)")
        }
        for uri in ["https://example.com/rfc9110", "https://www.rfc-editor.org/info/", "https://www.iana.org/assignments/http-fields", "mailto:user@example.com", "#section-2"] {
            #expect(CrossDocLinkResolver.rfcReference(in: uri) == nil, "\(uri)")
        }
    }

    @Test func identifiesRFCsByFileNameAndFirstPage() {
        #expect(CrossDocLinkResolver.rfcNumber(fileName: "rfc9110.pdf") == 9110)
        #expect(CrossDocLinkResolver.rfcNumber(fileName: "RFC 9110 HTTP Semantics.pdf") == 9110)
        #expect(CrossDocLinkResolver.rfcNumber(fileName: "RFC-0793.pdf") == 793)
        #expect(CrossDocLinkResolver.rfcNumber(fileName: "draft-ietf-httpbis-rfc9110bis.pdf") == 9110)
        #expect(CrossDocLinkResolver.rfcNumber(fileName: "Specification.pdf") == nil)
        #expect(CrossDocLinkResolver.rfcNumber(fileName: "surfconditions12.pdf") == nil)

        #expect(CrossDocLinkResolver.rfcNumber(firstPageText: "RFC 9111\nHTTP Caching\n\nAbstract") == 9111)
        #expect(CrossDocLinkResolver.rfcNumber(firstPageText: "Internet Engineering Task Force (IETF)   R. Fielding, Ed.\nRequest for Comments: 9110   Adobe\nObsoletes: 2818, 7230") == 9110)
        // A mention further down is not the document's own number.
        #expect(CrossDocLinkResolver.rfcNumber(firstPageText: "Gadget Protocol\nThis updates RFC 9110.") == nil)
    }

    @Test @MainActor func resolvesNamedDestinationInOpenTab() async throws {
        // Named neutrally: the RFC number comes from its first page.
        let url = scratchURL("spec.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        writeNamedDestinationRFC(at: url)
        let other = await loadedViewModel(url)

        let link = webLink("https://www.rfc-editor.org/rfc/rfc9999#section-2.1")
        let (vm, target) = try #require(CrossDocLinkResolver.target(for: link, in: [other]))
        #expect(vm === other)
        #expect(target.targetPage == 1)
        #expect(target.uri == "#nameddest=section-2.1")
        // It stands in for the link: same id (so hovering doesn't restart the peek) and source.
        #expect(target.id == link.id)
        #expect(target.sourcePage == 3)
        #expect(target.sourceRect == link.sourceRect)

        // The document itself ("[HTTP]" citations): its first page.
        let whole = try #require(CrossDocLinkResolver.target(for: webLink("https://www.rfc-editor.org/info/rfc9999"), in: [other]))
        #expect(whole.target.targetPage == 0)

        // Unknown section, a different RFC, or an internal link: nothing to show.
        #expect(CrossDocLinkResolver.target(for: webLink("https://www.rfc-editor.org/rfc/rfc9999#section-77"), in: [other]) == nil)
        #expect(CrossDocLinkResolver.target(for: webLink("https://www.rfc-editor.org/rfc/rfc9110#section-2.1"), in: [other]) == nil)
        let sameDocumentLink = SnapshotTarget(label: "x", targetPage: 0, uri: "https://www.rfc-editor.org/rfc/rfc9999#section-2.1")
        #expect(CrossDocLinkResolver.target(for: sameDocumentLink, in: [other]) == nil)
    }

    @Test @MainActor func fallsBackToOutlineWithoutNamedDestinations() async throws {
        let url = scratchURL("RFC 4242 Gadgets.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        writeOutlineOnlyRFC(at: url)
        let other = await loadedViewModel(url)

        let (_, target) = try #require(CrossDocLinkResolver.target(for: webLink("https://datatracker.ietf.org/doc/html/rfc4242#section-2.1"), in: [other]))
        #expect(target.targetPage == 1)
        #expect(CrossDocLinkResolver.target(for: webLink("https://datatracker.ietf.org/doc/html/rfc4242#section-9"), in: [other]) == nil)
    }

    @Test @MainActor func peekRendersFromTheOtherTabAtTheGivenZoom() async throws {
        let url = scratchURL("rfc9999.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        writeNamedDestinationRFC(at: url)
        let other = await loadedViewModel(url)
        let (_, target) = try #require(CrossDocLinkResolver.target(for: webLink("https://www.rfc-editor.org/rfc/rfc9999#section-2.1"), in: [other]))

        other.loadPageMetadata(target.targetPage)
        let rect = other.linkPeekRect(for: target)
        let image = try #require(await other.renderRegion(pageIndex: target.targetPage, rect: rect, zoom: 2))
        #expect(abs(image.size.width - rect.width * 2) < 0.5)
    }

    @Test @MainActor func captionAddsAHeaderAboveTheImage() {
        let image = NSImage(size: NSSize(width: 300, height: 120))
        let plain = LinkPeekController.makeContentView(image: image, size: image.size, isTruncated: false)
        let captioned = LinkPeekController.makeContentView(image: image, size: image.size, isTruncated: false, caption: "RFC 9110 HTTP Semantics")
        #expect(plain.frame.height == 120)
        #expect(captioned.frame.height == 120 + LinkPeekController.captionHeight)
        #expect(captioned.subviews.contains { ($0 as? NSTextField)?.stringValue == "RFC 9110 HTTP Semantics" })
    }

    @Test func webLinkIsNotResolvedAgainstThisDocumentsOwnDestinations() throws {
        // This document has its own "section-2", and a web link to section 2 of another RFC.
        let url = scratchURL("rfc1111.pdf")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        writeRawPDF(at: url, objects: [
            "<< /Type /Catalog /Pages 2 0 R /Dests << /section-2 [4 0 R /XYZ 72 720 0] >> >>",
            "<< /Type /Pages /Kids [4 0 R] /Count 1 >>",
            helvetica,
            "\(pageDict) 5 0 R /Annots [6 0 R 7 0 R] >>",
            textStream(["See Section 2 of [HTTP] and Section 2 here."]),
            "<< /Type /Annot /Subtype /Link /Rect [72 715 160 735] /A << /S /URI /URI (https://www.rfc-editor.org/rfc/rfc9999#section-2) >> >>",
            "<< /Type /Annot /Subtype /Link /Rect [240 715 300 735] /A << /S /GoTo /D /section-2 >> >>",
        ])
        let links = try PDFDocumentCore(filePath: url.path).loadLinks(for: 0).sorted { ($0.sourceRect?.minX ?? 0) < ($1.sourceRect?.minX ?? 0) }
        #expect(links.count == 2)
        #expect(links.first?.targetPage == -1)
        #expect(links.first?.uri == "https://www.rfc-editor.org/rfc/rfc9999#section-2")
        #expect(links.last?.targetPage == 0)
    }
}
