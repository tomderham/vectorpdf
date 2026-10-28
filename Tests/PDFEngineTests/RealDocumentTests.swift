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

// Rendering, search and selection on real technical documents (see Resources/test-files/README.md).
// Where possible the expected answer comes from PDFKit — Apple's own, independent PDF stack — so
// the engine isn't checked against itself.

private let federalRegister = "federal-register-2024-00301.pdf"   // three narrow columns, footnotes
private let bill = "hr1968-ih.pdf"                                // line-numbered, justified
private let rfc = "rfc9457.pdf"                                   // outline, named destinations
private let nistNote = "nist-tn-2255.pdf"                         // vector plots, Greek and subscripts
private let ieeeDraft = "ieee-802.11-draft-layout.pdf"            // 802.11 draft layout, scrambled words

/// Page 7 of the bill: 24 numbered lines, body text from x = 178.
private let billPage = 6

private func pdfKitDocument(_ name: String) throws -> PDFKit.PDFDocument {
    let doc = PDFKit.PDFDocument(url: Fixture.url(name))
    return try #require(doc)
}

/// Converts a rect in MuPDF page space (origin top left) to PDF space (origin bottom left).
private func pdfSpace(_ rect: CGRect, pageHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: pageHeight - rect.maxY, width: rect.width, height: rect.height)
}

private func collapsed(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

/// The body lines of a page — left to right, top to bottom — excluding margin line numbers.
private func bodyLines(of page: StructuredPage) -> [TextLine] {
    let lines = page.blocks.filter { $0.type == .text }.flatMap(\.lines)
    let edge = SpatialTextSelector.bodyLeftEdge(of: lines) ?? 0
    return lines
        .filter { !SpatialTextSelector.isLineNumberGutter(line: $0, bodyLeftMargin: edge) }
        .sorted { abs($0.bbox.midY - $1.bbox.midY) > 3 ? $0.bbox.midY < $1.bbox.midY : $0.bbox.minX < $1.bbox.minX }
}

// MARK: - Search

@Suite(.serialized)
struct RealDocumentSearchTests {

    /// Each hit's highlight sits on exactly the text that matched: PDFKit, reading the page
    /// under each highlight, finds the query (split across lines where it wraps, and where a
    /// word is hyphenated across them).
    @Test(arguments: [
        (federalRegister, "Inflation Adjustment Act"),
        (federalRegister, "civil money penalt"),
        (bill, "Budget and Emergency Deficit Control Act"),
        (bill, "substituting"),
        (nistNote, "multiline TRL calibration"),
        (nistNote, "conductivity"),
        (rfc, "application/problem+json"),
    ])
    func highlightsCoverExactlyTheMatchedText(file: String, query: String) async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url(file).path)
        let kit = try pdfKitDocument(file)
        let results = try await actor.search(query: query)
        try #require(!results.isEmpty)

        for result in results {
            let page = try #require(kit.page(at: result.pageIndex))
            let height = page.bounds(for: .mediaBox).height
            let pieces = result.highlightQuads.map {
                collapsed(page.selection(for: pdfSpace($0.boundingRect, pageHeight: height))?.string ?? "")
            }
            // A word hyphenated across lines ("substi-" / "tuting") is in pieces with no space.
            let matches = [pieces.joined(separator: " "), pieces.joined()].contains { $0.lowercased() == query.lowercased() }
            #expect(matches, "page \(result.pageIndex + 1): highlight covers \(pieces)")
        }
    }

    /// Everything PDFKit finds, the engine finds too (it also finds phrases that wrap onto the
    /// next line, which PDFKit doesn't), and at the same place.
    @Test(arguments: [(federalRegister, "Inflation Adjustment Act"), (bill, "Health Administration"),
                      (nistNote, "Fig. 9"), (rfc, "problem details")])
    func findsEverythingPDFKitFinds(file: String, query: String) async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url(file).path)
        let kit = try pdfKitDocument(file)
        let results = try await actor.search(query: query)

        for selection in kit.findString(query, withOptions: .caseInsensitive) {
            let page = try #require(selection.pages.first)
            let index = kit.index(for: page)
            let height = page.bounds(for: .mediaBox).height
            let bounds = selection.bounds(for: page)
            let found = results.contains { result in
                result.pageIndex == index && result.highlightQuads.contains {
                    pdfSpace($0.boundingRect, pageHeight: height).insetBy(dx: -1, dy: -1).intersects(bounds)
                }
            }
            #expect(found, "missed the hit at \(bounds) on page \(index + 1)")
        }
    }

    /// In a narrow column, a phrase that wraps is found, highlighted on both lines, and the
    /// highlight never strays into the next column.
    @Test func highlightsInNarrowColumnsStayInTheirColumn() async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url(federalRegister).path)
        let results = try await actor.search(query: "Inflation Adjustment Act")
        let wrapped = results.filter { $0.highlightQuads.count == 2 }
        #expect(wrapped.count >= 3)
        for result in results {
            for quad in result.highlightQuads {
                #expect(quad.boundingRect.width < 175, "a column is ~170pt wide: \(quad.boundingRect)")
            }
        }
    }

    /// Every pair of adjacent lines on a line-numbered page: the last word of one line and the
    /// first word of the next are found together, though a line number sits between them.
    @Test(arguments: [(bill, billPage), (ieeeDraft, 1)])
    func phrasesWrappingPastALineNumberAreFound(file: String, pageIndex: Int) async throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url(file).path)
        let page = try #require(doc.loadStructuredPage(for: pageIndex))
        let lines = bodyLines(of: page).filter { $0.bbox.width > 150 }   // full-width body lines
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url(file).path)

        var checked = 0
        for (line, next) in zip(lines, lines.dropFirst()) where next.bbox.minY - line.bbox.maxY < 20 {
            let last = String(line.characters.map(\.char)).split(separator: " ").last.map(String.init) ?? ""
            let first = String(next.characters.map(\.char)).split(separator: " ").first.map(String.init) ?? ""
            guard last.count >= 3, first.count >= 3, last.allSatisfy(\.isLetter), first.allSatisfy(\.isLetter) else { continue }
            let hits = try await actor.search(query: "\(last) \(first)").filter { $0.pageIndex == pageIndex }
            let spans = hits.contains { hit in
                hit.highlightQuads.count == 2
                    && abs(hit.highlightQuads[0].boundingRect.midY - line.bbox.midY) < 4
                    && abs(hit.highlightQuads[1].boundingRect.midY - next.bbox.midY) < 4
            }
            #expect(spans, "\"\(last) \(first)\" across lines at y=\(Int(line.bbox.minY))")
            checked += 1
        }
        #expect(checked >= 3)
    }

    /// Line numbers stay searchable after being moved out of the way of the text.
    @Test func lineNumbersAreStillSearchable() async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url(ieeeDraft).path)
        let hits = try await actor.search(query: "47", options: SearchOptions(wholeWord: true))
        #expect(hits.contains { $0.pageIndex == 0 && $0.boundingRect.minX < 80 })
    }
}

// MARK: - Selection

@Suite(.serialized)
struct RealDocumentSelectionTests {
    private let selector = SpatialTextSelector()

    private func page(_ file: String, _ index: Int) throws -> StructuredPage {
        let doc = try PDFDocumentCore(filePath: Fixture.url(file).path)
        return try #require(doc.loadStructuredPage(for: index))
    }

    /// Dragging over a line-numbered page selects the text without its line numbers, and keeps
    /// single spaces across the wide gaps of fully justified lines.
    @Test func selectionLeavesOutLineNumbers() throws {
        let page = try page(bill, billPage)
        let selection = selector.selectText(on: page, from: CGPoint(x: 179, y: 81), to: CGPoint(x: 490, y: 382))
        let text = collapsed(selection.text)
        #expect(text.hasPrefix("that no amounts may be rescinded"))
        #expect(text.contains("Budget and Emergency Deficit Control Act of 1985’’"))
        #expect(text.contains("528 shall be applied by substituting"))
        #expect(text.contains("except the amount included in section 529"))   // "ex-" + "cept"
        #expect(!selection.highlightQuads.isEmpty)
        #expect(selection.highlightQuads.allSatisfy { $0.boundingRect.minX >= 175 }, "no highlight in the gutter")
        let words = Set(text.split(separator: " ").map(String.init))
        #expect(words.isDisjoint(with: (1...14).map(String.init)), "line numbers leaked into \(text)")
    }

    /// The same on the 802.11 draft layout — and its tables' numeric Order column, which starts
    /// right of the body margin, is kept.
    @Test func ieeeDraftSelectionKeepsTableNumbersButNotLineNumbers() throws {
        let page = try page(ieeeDraft, 0)
        let table = selector.selectText(on: page, from: CGPoint(x: 100, y: 330), to: CGPoint(x: 540, y: 470))
        for order in ["103", "104", "105", "106"] {
            #expect(table.text.contains(order), "Order \(order) missing from the table selection")
        }
        #expect(table.highlightQuads.allSatisfy { $0.boundingRect.minX > 80 }, "no highlight on the line numbers")

        // The editing instruction above the table: the body line mentioning 9-78 that starts at
        // the margin (the table's caption, also mentioning it, is centred), and the line after it.
        let lines = bodyLines(of: page)
        let first = try #require(lines.firstIndex { String($0.characters.map(\.char)).contains("9-78") && $0.bbox.minX < 100 })
        let second = lines[first + 1]
        let instruction = selector.selectText(on: page, from: CGPoint(x: lines[first].bbox.minX + 1, y: lines[first].bbox.midY),
                                              to: CGPoint(x: second.bbox.maxX, y: second.bbox.midY))
        #expect(instruction.text.contains("9-78"))
        #expect(instruction.highlightQuads.allSatisfy { $0.boundingRect.minX > 80 })
        #expect(!instruction.text.split(whereSeparator: \.isWhitespace).contains { ["16", "17", "18"].contains(String($0)) })
    }

    /// A bit-field figure's "Bits 1 1 1 …" rows are part of the drawing, not line numbers.
    @Test func ieeeDraftFigureKeepsItsBitRows() throws {
        let page = try page(ieeeDraft, 1)
        let figure = selector.selectText(on: page, from: CGPoint(x: 100, y: 195), to: CGPoint(x: 540, y: 290))
        #expect(collapsed(figure.text).contains("1 1 1 1 1 1 1 1"))
        #expect(figure.highlightQuads.allSatisfy { $0.boundingRect.minX > 80 })
    }

    /// Dragging the end point down a page grows the selection one line at a time: each step's
    /// text extends the last one, so the selection never jumps, shrinks or picks up stray text.
    @Test(arguments: [
        (bill, billPage, CGPoint(x: 179, y: 81), CGFloat(490), 90.0...700.0, ["\n1\n", " 1 ", " 12 "]),
        (federalRegister, 0, CGPoint(x: 44, y: 302), CGFloat(195), 312.0...640.0, ["FCSIC must enact", "required by the 2015 Act"]),
        (ieeeDraft, 1, CGPoint(x: 90, y: 346), CGFloat(540), 356.0...420.0, [" 29 ", " 33 "]),
    ])
    func selectionGrowsSmoothlyWhileDragging(file: String, pageIndex: Int, start: CGPoint, endX: CGFloat,
                                             endYs: ClosedRange<Double>, mustNotContain: [String]) throws {
        let page = try page(file, pageIndex)
        var previous = ""
        var steps = 0
        for y in stride(from: endYs.lowerBound, through: endYs.upperBound, by: 3) {
            let text = collapsed(selector.selectText(on: page, from: start, to: CGPoint(x: endX, y: y)).text)
            for stray in mustNotContain {
                #expect(!" \(text) ".contains(stray), "\"\(stray)\" in the selection at y=\(y)")
            }
            // A line ending "ex-" becomes "except" once the next line joins.
            let stem = previous.hasSuffix("-") ? String(previous.dropLast()) : previous
            #expect(text.hasPrefix(stem), "selection jumped at y=\(y):\n  \(previous)\n→ \(text)")
            if text != previous { steps += 1 }
            previous = text
        }
        #expect(steps >= 5)
    }

    /// Dragging from one column into the next selects the rest of the first column, then the top
    /// of the next — not their lines interleaved row by row — as PDFKit does. The same holds
    /// dragging backwards, from the second column up into the first.
    @Test func selectionAcrossColumnsKeepsEachColumnTogether() throws {
        let page = try page(federalRegister, 0)
        for (from, to) in [(CGPoint(x: 46, y: 295), CGPoint(x: 330, y: 330)), (CGPoint(x: 330, y: 330), CGPoint(x: 46, y: 295))] {
            let text = collapsed(selector.selectText(on: page, from: from, to: to).text)
            #expect(text.hasPrefix("DATES: Effective date: This regulation is effective on January 10, 2024."))
            let endOfFirst = try #require(text.range(of: "maintain their deterrent values."))
            let startOfSecond = try #require(text.range(of: "FCSIC must enact regulations"))
            #expect(endOfFirst.upperBound < startOfSecond.lowerBound)
            #expect(text.hasSuffix("which penalty FCSIC may recover for its use.3 Second, section 5.65"))
            // Column three, and the text above the columns, aren't part of it.
            #expect(!text.contains("PART 1411") && !text.contains("Federal Register"))
        }
    }

    /// Double-spaced text reads like PDFKit's selection of it — the same words in the same order,
    /// with no line numbers — but as running text, its hyphenated words joined, rather than one
    /// line per line.
    @Test func doubleSpacedTextFlowsAsProse() throws {
        let page = try page(bill, billPage)
        let (from, to) = (CGPoint(x: 179, y: 81), CGPoint(x: 490, y: 330))
        let text = selector.selectText(on: page, from: from, to: to).text
        #expect(!text.contains("\n"), "one paragraph: \(text)")

        let kit = try #require(try pdfKitDocument(bill).page(at: billPage))
        let height = kit.bounds(for: .mediaBox).height
        let reference = kit.selection(from: CGPoint(x: from.x, y: height - from.y), to: CGPoint(x: to.x, y: height - to.y))?.string ?? ""
        let rejoined = reference.replacingOccurrences(of: "-\\s*\\n\\s*(?=[a-z])", with: "", options: .regularExpression)
        #expect(collapsed(text) == collapsed(rejoined))
    }

    /// A ruled table copies as one row per line with its cells separated by tabs, so it pastes
    /// into a spreadsheet as a table; a cell that wraps onto two lines stays one cell.
    @Test func ruledTableCopiesRowByRowWithTabs() throws {
        let page = try page(ieeeDraft, 0)
        let text = selector.selectText(on: page, from: CGPoint(x: 100, y: 330), to: CGPoint(x: 540, y: 470)).text
        let rows = text.components(separatedBy: "\n").map { $0.components(separatedBy: "\t") }
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { $0.count == 3 }, "three cells per row: \(rows)")
        #expect(rows.map { $0.first?.suffix(3) } == ["103", "104", "105", "106"])
        // The Information cell of row 104 wraps onto a second line.
        #expect(rows[1][1].split(separator: " ").count == 3)
    }

    /// Double-clicking a word in a narrow column selects just that word.
    @Test func doubleClickInANarrowColumnSelectsTheWord() async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url(federalRegister).path)
        let hit = try #require(try await actor.search(query: "notwithstanding").first)
        let center = CGPoint(x: hit.boundingRect.midX, y: hit.boundingRect.midY)
        let word = selector.selectWord(at: center, on: try page(federalRegister, hit.pageIndex))
        #expect(word?.text == "notwithstanding")
    }
}

// MARK: - Links and outline

@Suite(.serialized)
struct RealDocumentNavigationTests {

    private func flattened(_ nodes: [PDFOutlineNode]) -> [(String, Int?)] {
        nodes.flatMap { [(collapsed($0.title), $0.targetPage)] + flattened($0.children) }
    }

    private func flattened(_ outline: PDFOutline, in doc: PDFKit.PDFDocument) -> [(String, Int?)] {
        (0..<outline.numberOfChildren).flatMap { i -> [(String, Int?)] in
            let child = outline.child(at: i)!
            let page = child.destination?.page.map { doc.index(for: $0) }
            return [(collapsed(child.label ?? ""), page)] + flattened(child, in: doc)
        }
    }

    /// The outline (titles, nesting order and target pages) matches PDFKit's reading of it.
    @Test(arguments: [rfc, nistNote])
    func outlineMatchesPDFKit(file: String) throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url(file).path)
        let kit = try pdfKitDocument(file)
        let root = try #require(kit.outlineRoot)
        let expected = flattened(root, in: kit)
        let actual = flattened(doc.outline)
        #expect(actual.count == expected.count)
        for (a, e) in zip(actual, expected) {
            #expect(a.0 == e.0 && a.1 == e.1, "\(a) ≠ \(e)")
        }
    }

    /// The RFC's table of contents links through named destinations ("section-3.1.1"). Every
    /// link resolves to the page PDFKit resolves it to.
    @Test func namedDestinationLinksResolveLikePDFKit() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url(rfc).path)
        let kit = try pdfKitDocument(rfc)
        let tocPage = 1
        let page = try #require(kit.page(at: tocPage))
        let height = page.bounds(for: .mediaBox).height
        let kitLinks = page.annotations.filter { $0.type == "Link" && $0.destination != nil }
        let links = doc.loadLinks(for: tocPage).filter { $0.uri == nil || $0.uri?.hasPrefix("#") == true }
        #expect(links.count == kitLinks.count)
        #expect(links.count > 20)
        for link in links {
            let rect = pdfSpace(try #require(link.sourceRect), pageHeight: height)
            let match = kitLinks.first { abs($0.bounds.midX - rect.midX) < 2 && abs($0.bounds.midY - rect.midY) < 2 }
            let expectedPage = match?.destination?.page.map { kit.index(for: $0) }
            #expect(link.targetPage == expectedPage, "link at \(rect)")
        }
    }
}

// MARK: - Rendering

/// A page rendered to an 8-bit grey bitmap of `size`.
private struct Raster {
    let width: Int, height: Int
    var pixels: [UInt8]

    init(_ image: CGImage, size: CGSize) {
        width = Int(size.width); height = Int(size.height)
        pixels = [UInt8](repeating: 255, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: 0)!
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
        }
    }

    /// Fraction of dark pixels in each `cell`×`cell` tile.
    func inkMap(cell: Int) -> [Double] {
        stride(from: 0, to: height - cell + 1, by: cell).flatMap { y in
            stride(from: 0, to: width - cell + 1, by: cell).map { x in
                var dark = 0
                for yy in y..<(y + cell) { for xx in x..<(x + cell) where pixels[yy * width + xx] < 128 { dark += 1 } }
                return Double(dark) / Double(cell * cell)
            }
        }
    }
}

private func mupdfImage(_ doc: PDFDocumentCore, page: Int, rect: CGRect? = nil, scale: CGFloat) throws -> CGImage {
    let data = try #require(doc.renderPageRect(pageIndex: page, rect: rect ?? doc.pageBounds[page], scale: scale))
    return try #require(NSBitmapImageRep(data: data)?.cgImage)
}

private func pdfKitImage(_ page: PDFPage, scale: CGFloat) throws -> CGImage {
    let bounds = page.bounds(for: .mediaBox)
    let width = Int(bounds.width * scale), height = Int(bounds.height * scale)
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    ctx.setFillColor(.white)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: ctx)
    return try #require(ctx.makeImage())
}

/// Pixels that are clearly red, on a coarse grid.
private func redMask(_ image: CGImage, cell: Int) -> Set<Int> {
    let width = image.width, height = image.height
    var rgba = [UInt8](repeating: 255, count: width * height * 4)
    rgba.withUnsafeMutableBytes { buffer in
        let ctx = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    var cells = Set<Int>()
    for y in 0..<height { for x in 0..<width {
        let i = (y * width + x) * 4
        if rgba[i] > 180 && rgba[i + 1] < 110 && rgba[i + 2] < 110 { cells.insert((y / cell) * (width / cell + 1) + x / cell) }
    } }
    return cells
}

@Suite(.serialized)
struct RealDocumentRenderingTests {

    /// The engine draws each page where Core Graphics does: the share of ink in every small tile
    /// matches, so nothing is missing, moved, doubled or the wrong size.
    @Test(arguments: [(federalRegister, 0), (bill, billPage), (rfc, 0), (nistNote, 25), (ieeeDraft, 0), (ieeeDraft, 1)])
    func renderingMatchesCoreGraphics(file: String, pageIndex: Int) throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url(file).path)
        let page = try #require(try pdfKitDocument(file).page(at: pageIndex))
        let size = CGSize(width: doc.pageBounds[pageIndex].width, height: doc.pageBounds[pageIndex].height)
        let ours = Raster(try mupdfImage(doc, page: pageIndex, scale: 2), size: size).inkMap(cell: 12)
        let reference = Raster(try pdfKitImage(page, scale: 2), size: size).inkMap(cell: 12)
        try #require(ours.count == reference.count)

        let differences = zip(ours, reference).map { abs($0 - $1) }
        let mean = differences.reduce(0, +) / Double(differences.count)
        let worst = differences.max() ?? 0
        #expect(reference.reduce(0, +) > 1, "the reference page has ink")
        #expect(mean < 0.01, "average ink difference \(mean)")
        #expect(worst < 0.2, "a tile differs by \(worst)")
    }

    /// The plots' red curves come out red, in the same places as Core Graphics draws them.
    @Test func plotCurvesKeepTheirColourAndPlace() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url(nistNote).path)
        let page = try #require(try pdfKitDocument(nistNote).page(at: 25))
        let ours = redMask(try mupdfImage(doc, page: 25, scale: 1), cell: 6)
        let reference = redMask(try pdfKitImage(page, scale: 1), cell: 6)
        #expect(reference.count > 50)
        let overlap = Double(ours.intersection(reference).count) / Double(ours.union(reference).count)
        #expect(overlap > 0.8, "red curve overlap \(overlap)")
    }

    /// A tile rendered on its own (as the canvas does while scrolling and zooming) is the same as
    /// that part of the whole page, so there are no seams or shifts between tiles.
    @Test(arguments: [(nistNote, 25), (federalRegister, 0)])
    func tilesMatchTheWholePage(file: String, pageIndex: Int) throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url(file).path)
        let scale: CGFloat = 2
        let full = try mupdfImage(doc, page: pageIndex, scale: scale)
        let tile = CGRect(x: 150, y: 120, width: 256, height: 256)
        let tileImage = try mupdfImage(doc, page: pageIndex, rect: tile, scale: scale)
        let crop = try #require(full.cropping(to: CGRect(x: tile.minX * scale, y: tile.minY * scale,
                                                        width: tile.width * scale, height: tile.height * scale)))
        let size = CGSize(width: tile.width * scale, height: tile.height * scale)
        let a = Raster(tileImage, size: size).pixels, b = Raster(crop, size: size).pixels
        let differing = zip(a, b).filter { abs(Int($0) - Int($1)) > 16 }.count
        #expect(Double(differing) / Double(a.count) < 0.002, "\(differing) pixels differ")
    }
}

// MARK: - Export

@Suite(.serialized)
struct RealDocumentExportTests {
    private func plainText(_ file: String, _ index: Int) throws -> String {
        let doc = try PDFDocumentCore(filePath: Fixture.url(file).path)
        return collapsed(PDFDocumentExporter().exportPlainText(from: doc, pageIndices: [index]))
    }

    /// Three narrow columns export one after another, each read top to bottom, rather than
    /// interleaved line by line or taken for a table.
    @Test func threeColumnPageExportsColumnByColumn() throws {
        let text = try plainText(federalRegister, 0)
        let wrapped = [
            "civil money penalties (CMPs) that the Farm Credit System Insurance Corporation (FCSIC) may impose",
            "FCSIC must enact regulations that annually adjust its CMPs pursuant to the inflation adjustment formula",
            "FARM CREDIT SYSTEM INSURANCE CORPORATION",
        ]
        for phrase in wrapped {
            #expect(text.contains(phrase), "missing “\(phrase)”")
        }
        let first = try #require(text.range(of: "maintain their deterrent values"))
        let second = try #require(text.range(of: "FCSIC must enact regulations"))
        #expect(first.lowerBound < second.lowerBound)
        #expect(!text.contains("\t"))
    }
}
