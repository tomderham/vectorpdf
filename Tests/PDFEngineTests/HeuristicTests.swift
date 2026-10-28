import Foundation
import CoreGraphics
import Testing
@testable import PDFEngine

// Checks of the layout, selection, link-target and retrieval heuristics against the kinds of
// document that trip simple rules: two-column pages, borderless number tables, abbreviations
// at the start of a line, number-only links, narrow margins.

/// A line of 10 pt text, 5 pt per character and 12 pt tall, starting at (`x`, `y`).
private func line(_ text: String, x: CGFloat, y: CGFloat, size: Float = 10, bold: Bool = false) -> TextLine {
    let chars = text.enumerated().map { i, ch in
        TextCharacter(char: ch, quad: PDFQuad(rect: CGRect(x: x + CGFloat(i) * 5, y: y, width: 5, height: 12)),
                      origin: CGPoint(x: x + CGFloat(i) * 5, y: y + 10), size: size, isBold: bold, fontName: "Helvetica")
    }
    return TextLine(bbox: CGRect(x: x, y: y, width: CGFloat(text.count) * 5, height: 12), characters: chars)
}

private func block(_ lines: [TextLine]) -> TextBlock {
    let bbox = lines.dropFirst().reduce(lines[0].bbox) { $0.union($1.bbox) }
    return TextBlock(type: .text, bbox: bbox, lines: lines)
}

private func page(_ blocks: [TextBlock]) -> StructuredPage {
    StructuredPage(pageIndex: 0, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), blocks: blocks)
}

private func runs(_ text: String) -> [TextRun] {
    [TextRun(text: text, isBold: false, isItalic: false, size: 10, fontName: "Helvetica")]
}

private func paragraphs(_ elements: [PDFLayoutElement]) -> [(text: String, bbox: CGRect, leftIndent: Int)] {
    elements.compactMap {
        guard case .paragraph(let runs, let bbox, _, _, let leftIndent, _, _) = $0 else { return nil }
        return (runs.map(\.text).joined(), bbox, leftIndent)
    }
}

// MARK: - Layout

@Suite struct LayoutHeuristicTests {
    /// Six 40-character lines per column, 14 pt apart: left column at `leftX`, right at 330.
    private func twoColumnPage(leftX: CGFloat = 50, left: [String], right: [String]) -> StructuredPage {
        let leftLines = left.enumerated().map { line($1, x: leftX, y: 100 + CGFloat($0) * 14) }
        let rightLines = right.enumerated().map { line($1, x: 330, y: 100 + CGFloat($0) * 14) }
        return page([block(leftLines), block(rightLines)])
    }

    private let filler = Array(repeating: "words that fill a column line of text ok", count: 6)

    /// In a column narrower than half the page every line is "short"; a sentence ending at the
    /// end of a full line doesn't end the paragraph.
    @Test func sentenceEndingAtAFullColumnLineContinuesTheParagraph() {
        let left = [
            "The first sentence of the paragraph runs",
            "on to the end of this line and stops here.",
            "Then the next sentence starts a new line,",
            "which still belongs to the same paragraph",
            "and carries on down the narrow column for",
            "a while before it finally comes to an end.",
        ]
        let elements = PDFLayoutEngine().reconstructLayout(for: twoColumnPage(left: left, right: filler))
        let leftParagraphs = paragraphs(elements).filter { $0.bbox.maxX < 300 }
        #expect(leftParagraphs.count == 1, "got \(leftParagraphs.map(\.text))")
    }

    /// Indents are measured from a paragraph's own column, not a fixed page margin.
    @Test func paragraphIndentIsRelativeToItsColumn() {
        let elements = PDFLayoutEngine().reconstructLayout(for: twoColumnPage(leftX: 72, left: filler, right: filler))
        let found = paragraphs(elements)
        #expect(!found.isEmpty)
        for paragraph in found {
            #expect(paragraph.leftIndent == 0, "indent \(paragraph.leftIndent) for paragraph at x = \(paragraph.bbox.minX)")
        }
    }

    /// An abbreviation at the start of a line ("Dr.", "Fig.") is not a list item.
    @Test func abbreviationAtLineStartIsNotAListItem() {
        let lines = [
            "The committee heard evidence from several witnesses over the course of the long day, and",
            "Dr. Smith agreed with the findings of the panel after a long discussion of the evidence, as",
            "Fig. 3 of the report shows clearly, and the committee then adjourned for the evening session.",
        ].enumerated().map { line($1, x: 72, y: 100 + CGFloat($0) * 14) }
        let found = paragraphs(PDFLayoutEngine().reconstructLayout(for: page([block(lines)])))
        #expect(found.count == 1, "got \(found.map(\.text))")
    }

    /// A borderless table whose number column is right-aligned, as amounts usually are.
    @Test func borderlessTableWithRightAlignedNumbers() {
        let rows = [("Widget", "5"), ("Gadget assembly", "1,234"), ("Bolt", "12.50"), ("Washer pack", "310")]
        var blocks: [TextBlock] = []
        for (i, row) in rows.enumerated() {
            let y = 100 + CGFloat(i) * 16
            blocks.append(block([line(row.0, x: 72, y: y)]))
            blocks.append(block([line(row.1, x: 300 - CGFloat(row.1.count) * 5, y: y)]))
        }
        let tables = PDFLayoutEngine().detectTables(in: page(blocks))
        #expect(tables.count == 1)
        #expect(tables.first?.rows.count == 4)
        #expect(tables.first?.colWidths.count == 2)
    }

    private func table(header: String, y: CGFloat) -> LayoutTable {
        let rows = [header, "a", "b"].enumerated().map { i, text in
            let rowBox = CGRect(x: 72, y: y + CGFloat(i) * 20, width: 200, height: 20)
            return LayoutRow(bbox: rowBox, cells: [
                LayoutCell(bbox: CGRect(x: 72, y: rowBox.minY, width: 100, height: 20), runs: runs(text)),
                LayoutCell(bbox: CGRect(x: 172, y: rowBox.minY, width: 100, height: 20), runs: runs(text + "2")),
            ])
        }
        return LayoutTable(bbox: CGRect(x: 72, y: y, width: 200, height: 60), rows: rows, colWidths: [100, 100])
    }

    private func heading(_ text: String) -> PDFLayoutElement {
        .heading(level: 2, runs: runs(text), bbox: CGRect(x: 72, y: 60, width: 200, height: 14), spaceBefore: 0, spaceAfter: 0)
    }

    /// "Discontinued Operations" contains "continued" but is a heading of its own, and the table
    /// under it a new table.
    @Test func discontinuedIsNotAContinuationHeading() {
        var pages: [[PDFLayoutElement]] = [
            [.table(table: table(header: "Revenue", y: 600))],
            [heading("Discontinued Operations"), .table(table: table(header: "Losses", y: 80))],
        ]
        PDFLayoutEngine().stitchContinuingTables(pages: &pages)
        #expect(pages[1].count == 2)
    }

    @Test func continuedHeadingStitchesItsTable() {
        var pages: [[PDFLayoutElement]] = [
            [.table(table: table(header: "Revenue", y: 600))],
            [heading("Table 3 (continued)"), .table(table: table(header: "Losses", y: 80))],
        ]
        PDFLayoutEngine().stitchContinuingTables(pages: &pages)
        #expect(pages[1].isEmpty)
        guard case .table(let merged) = pages[0][0] else { Issue.record("no table"); return }
        #expect(merged.rows.count == 6)
    }

    /// The text the Agent indexes keeps a table's cells, however narrow.
    @Test func proseTextKeepsTableCells() {
        let paragraph = block([line("The transmitter shall not exceed the limits given in the table below.", x: 72, y: 100)])
        let cells = [
            block([line("Max power", x: 72, y: 130)]), block([line("20 dBm", x: 200, y: 130)]),
            block([line("Bandwidth", x: 72, y: 146)]), block([line("80 MHz", x: 200, y: 146)]),
        ]
        let text = page([paragraph] + cells).proseText
        #expect(text.contains("20 dBm"))
        #expect(text.contains("Max power"))
    }
}

// MARK: - Link targets

@Suite struct LinkTargetHeuristicTests {
    private func target(_ lines: [TextLine], at point: CGPoint, label: String, uri: String? = nil) -> String? {
        let p = page(lines.map { block([$0]) })
        return SpatialTextSelector().targetLine(on: p, at: point, label: label, uri: uri)?.text
    }

    /// LaTeX's `Figure~\ref{}` links only the number; the destination name says it's a figure.
    @Test func numberOnlyFigureLinkFindsTheCaption() {
        let lines = [
            line("3. The third item of a numbered list in the text.", x: 72, y: 100),
            line("Some body text above the figure on this page here.", x: 72, y: 300),
            line("Figure 3: Results of the experiment over time.", x: 72, y: 420),
        ]
        let found = target(lines, at: CGPoint(x: 72, y: 400), label: "3", uri: "#nameddest=figure.3")
        #expect(found?.hasPrefix("Figure 3") == true, "got \(found ?? "nil")")
    }

    /// "stable" contains "table"; the caption is the line that starts with the label.
    @Test func tableCaptionIsNotAnyLineContainingTable() {
        let lines = [
            line("The results are stable at 3 dB across the band.", x: 72, y: 305),
            line("Table 3: Measured values for each channel.", x: 72, y: 330),
        ]
        let found = target(lines, at: CGPoint(x: 72, y: 300), label: "Table 3")
        #expect(found?.hasPrefix("Table 3") == true, "got \(found ?? "nil")")
    }

    /// A bibliography set closer to the page edge than 45 pt.
    @Test func referenceEntryInANarrowMargin() {
        let lines = [
            line("[1] A. Author, The first paper, Journal vol. 2, 2020.", x: 36, y: 100),
            line("[2] B. Author, The second paper, Journal, 2021.", x: 36, y: 140),
        ]
        let found = target(lines, at: CGPoint(x: 36, y: 112), label: "[2]")
        #expect(found?.hasPrefix("[2]") == true, "got \(found ?? "nil")")
    }
}

// MARK: - Search, Agent and OCR

@Suite struct RetrievalHeuristicTests {
    /// A phrase wrapping onto the next line is found without smart search, as with it.
    @Test func plainSearchFindsAPhraseAcrossALineBreak() async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url("federal-register-2024-00301.pdf").path)
        let smart = try await actor.search(query: "Insurance Corporation", options: SearchOptions(smartSearch: true))
        let plain = try await actor.search(query: "Insurance Corporation", options: SearchOptions(smartSearch: false))
        #expect(!smart.isEmpty)
        #expect(plain.count == smart.count)
    }

    /// A word hyphenated across a line break ("divi-" / "sion", with a margin line number
    /// between) is found whole, with a highlight on each line.
    @Test func searchFindsAWordHyphenatedAcrossLines() async throws {
        let actor = PDFSearchActor()
        try await actor.openDocument(filePath: Fixture.url("hr1968-ih.pdf").path)
        let hits = try await actor.search(query: "division")
        #expect(hits.contains { $0.pageIndex == 2 && Set($0.highlightQuads.map { Int($0.boundingRect.midY) }).count >= 2 })
    }

    @Test @MainActor func onlyAnaphoricQuestionsAreFollowUps() {
        let vm = PDFViewerViewModel()
        #expect(vm.shouldFoldPreviousQuestion("Why?"))
        #expect(vm.shouldFoldPreviousQuestion("Tell me more about it"))
        #expect(vm.shouldFoldPreviousQuestion("What happens to them after the timeout expires?"))
        #expect(!vm.shouldFoldPreviousQuestion("How is the maximum transmit power calculated in the 5 GHz band?"))
        #expect(!vm.shouldFoldPreviousQuestion("Which field indicates that the frame is protected by encryption?"))
        #expect(!vm.shouldFoldPreviousQuestion("Explain the four-way handshake used by WPA3 networks"))
    }

    /// OCR lines are read row by row, however close two rows are and wherever a row falls.
    @Test func ocrLinesAreReadInRows() async {
        func ocrLine(_ text: String, x: CGFloat, y: CGFloat) -> PDFOCRLine {
            PDFOCRLine(text: text, confidence: 1, boundingBox: CGRect(x: x, y: y, width: 100, height: 10))
        }
        let merged = await PDFOCREngine().mergeOCRResults(pageIndex: 0, results: [PDFOCRPageResult(pageIndex: 0, lines: [
            ocrLine("second row", x: 72, y: 103),
            ocrLine("first row", x: 100, y: 91),
            ocrLine("right of row", x: 300, y: 29),
            ocrLine("left of row", x: 72, y: 31),
        ], fullText: "")])
        #expect(merged.lines.map(\.text) == ["left of row", "right of row", "first row", "second row"])
    }
}

// MARK: - One rule each

@Suite struct ConsistencyHeuristicTests {
    /// A line of 10 pt characters, 5 pt wide, with `gap` points before the second word.
    private func twoWords(gap: CGFloat) -> TextLine {
        var chars: [TextCharacter] = []
        var x: CGFloat = 72
        for (i, ch) in "ab cd".replacingOccurrences(of: " ", with: "").enumerated() {
            if i == 2 { x += gap }
            chars.append(TextCharacter(char: ch, quad: PDFQuad(rect: CGRect(x: x, y: 100, width: 5, height: 12)),
                                       origin: CGPoint(x: x, y: 110), size: 10))
            x += 5
        }
        return TextLine(bbox: CGRect(x: 72, y: 100, width: x - 72, height: 12), characters: chars)
    }

    /// The gap that makes a space is the same when selecting text and finding references in it.
    @Test func wordGapIsOneRule() {
        for (gap, expected) in [(2.1, "abcd"), (2.5, "ab cd")] as [(CGFloat, String)] {
            let line = twoWords(gap: gap)
            let selected = SpatialTextSelector().selectLine(at: CGPoint(x: 74, y: 106), on: page([block([line])]))
            #expect(selected?.text == expected)
            #expect(ReferenceExtractor.blockText(block([line])).0 == expected)
        }
    }

    /// Lines join the same way when copied, exported and searched for references: a word
    /// hyphenated across lines is whole, a hyphen in a range ("4-" / "7") stays, without a space.
    @Test func hyphenatedLinesJoinByOneRule() {
        let lines = [
            line("The Supplier's obli-", x: 72, y: 100),
            line("gations under Sections 4-", x: 72, y: 114),
            line("7 apply to every order.", x: 72, y: 128),
        ]
        let expected = "The Supplier's obligations under Sections 4-7 apply to every order."
        #expect(ReferenceExtractor.blockText(block(lines)).0 == expected)
        let selected = SpatialTextSelector().selectText(on: page([block(lines)]), from: CGPoint(x: 72, y: 106), to: CGPoint(x: 72 + 23 * 5, y: 134))
        #expect(selected.text == expected)
        let exported = PDFLayoutEngine().reconstructLayout(for: page([block(lines)]))
        #expect(paragraphs(exported).map(\.text).joined() == expected)
        #expect(page([block(lines)]).searchableIndex.text == expected)
        #expect(ReferenceExtractor.references(in: ReferenceExtractor.blockText(block(lines)).0).first?.identifier == "4")
    }

    /// Plain-text export leaves out running headers and page numbers, as Word export does.
    @Test func plainTextExportDropsRunningHeaders() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url("federal-register-2024-00301.pdf").path)
        let text = PDFDocumentExporter().exportPlainText(from: doc, pageIndices: [0, 1])
        #expect(!text.contains("Federal Register / Vol. 89"))
        #expect(text.contains("Inflation Adjustment Act"))
    }

    @Test func pageNumbersAreNumbersOrRomanNumerals() {
        for text in ["3", "- 3 -", "Page 3", "3 of 12", "iv", "XII", "xxxix"] {
            #expect(PDFDocumentExporter.isPageNumberText(text), "\(text)")
        }
        for text in ["Civil", "mid", "did", "mix", "Vivid", "IvX", ""] {
            #expect(!PDFDocumentExporter.isPageNumberText(text), "\(text)")
        }
    }

    /// One bold term doesn't make a line a heading.
    @Test func emphasisMeansMostlyBold() {
        let plain = line("the Effective Date is defined below", x: 72, y: 100)
        var chars = plain.characters
        for i in 4..<18 { chars[i] = TextCharacter(char: chars[i].char, quad: chars[i].quad, origin: chars[i].origin, size: 10, isBold: true) }
        #expect(!CrossDocReferenceMatcher.isEmphasised(TextLine(bbox: plain.bbox, characters: chars), bodySize: 10))
        #expect(CrossDocReferenceMatcher.isEmphasised(line("4.2 Payment Terms", x: 72, y: 100, bold: true), bodySize: 10))
        #expect(CrossDocReferenceMatcher.isEmphasised(line("4.2 Payment Terms", x: 72, y: 100, size: 12), bodySize: 10))
    }

    @Test func cloudServiceFromItsFolder() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(CloudStorageHelper.cloudServiceName(for: home + "/Library/CloudStorage/Box-Box/Reports/a.pdf") == "Box")
        #expect(CloudStorageHelper.cloudServiceName(for: home + "/Library/CloudStorage/OneDrive-Personal/Toolbox/a.pdf") == "OneDrive")
        #expect(CloudStorageHelper.cloudServiceName(for: home + "/Library/CloudStorage/GoogleDrive-user@example.com/My Drive/a.pdf") == "Google Drive")
        #expect(CloudStorageHelper.cloudServiceName(for: home + "/Library/CloudStorage/ProtonDrive-user@example.com/Boxes/a.pdf") == "Cloud Storage")
        #expect(CloudStorageHelper.cloudServiceName(for: home + "/Dropbox/a.pdf") == "Dropbox")
    }

    @Test func academicReferencesAreWholeWords() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.url("federal-register-2024-00301.pdf").path)
        let refs = CrossReferenceResolver().detectAcademicReferences(in: "the configuration 3, a suitable 4 and the frequency 2", sourcePage: 0, document: doc)
        #expect(refs.isEmpty, "got \(refs.map(\.label))")
    }
}

