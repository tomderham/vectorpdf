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
// ----------------------------------------------------------------------
//
// This file contains a port of pdf2docx.
// Original Copyright (c) 2026 Artifex Software, Inc.
// Licensed under the MIT License:
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import Foundation
import CoreGraphics
import AppKit

/// Formats supported for document export.
public enum ExportDocumentFormat: String, CaseIterable, Identifiable, Sendable {
    case plainText = "Plain Text (.txt)"
    case wordDocument = "Word Document (.docx)"
    case svgDocument = "Scalable Vector Graphics (.svg)"
    case flattenedPDF = "Flattened PDF (.pdf)"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .wordDocument: return "docx"
        case .svgDocument: return "svg"
        case .flattenedPDF: return "pdf"
        }
    }

    public var defaultMimeType: String {
        switch self {
        case .plainText: return "text/plain"
        case .wordDocument: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .svgDocument: return "image/svg+xml"
        case .flattenedPDF: return "application/pdf"
        }
    }
}

/// Native document exporter converting PDF structure into Plain Text or formatted Microsoft Word (.docx) documents.
public final class PDFDocumentExporter: Sendable {

    public init() {}

    // MARK: - Plain Text Export

    /// Exports pages from a PDF document into a clean, formatted UTF-8 plain text string.
    public func exportPlainText(
        from document: PDFDocumentCore,
        pageIndices: [Int]? = nil,
        includePageHeaders: Bool = true
    ) -> String {
        let indices = pageIndices ?? Array(0..<document.pageCount)
        let layoutEngine = PDFLayoutEngine()
        var pageElements: [[PDFLayoutElement]] = []

        for pIdx in indices {
            guard let stext = document.loadStructuredPage(for: pIdx) else {
                pageElements.append([])
                continue
            }
            pageElements.append(layoutEngine.reconstructLayout(for: stext))
        }

        layoutEngine.stitchContinuingTables(pages: &pageElements)

        var fullText = ""
        for (i, pIdx) in indices.enumerated() {
            let elements = pageElements[i]
            guard !elements.isEmpty else { continue }

            if includePageHeaders && indices.count > 1 {
                if !fullText.isEmpty {
                    fullText.append("\n\n")
                }
                fullText.append("--- Page \(pIdx + 1) ---\n\n")
            } else if !fullText.isEmpty {
                fullText.append("\n\n")
            }

            var pageTextBlocks: [String] = []
            for elem in elements {
                switch elem {
                case .heading(_, let runs, _, _, _):
                    let str = runs.map { $0.text }.joined().trimmingCharacters(in: .whitespaces)
                    if !str.isEmpty { pageTextBlocks.append(str) }
                case .paragraph(let runs, _, _, _, _, _, _):
                    let str = runs.map { $0.text }.joined().trimmingCharacters(in: .whitespaces)
                    if !str.isEmpty { pageTextBlocks.append(str) }
                case .table(let table):
                    var tblLines: [String] = []
                    for row in table.rows {
                        let rowStr = row.cells.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: "\t")
                        if !rowStr.isEmpty { tblLines.append(rowStr) }
                    }
                    if !tblLines.isEmpty { pageTextBlocks.append(tblLines.joined(separator: "\n")) }
                case .image:
                    break
                }
            }

            let pageText = pageTextBlocks.joined(separator: "\n\n")
            fullText.append(pageText)
        }

        return fullText
    }

    // MARK: - SVG Export

    /// Exports a single page as an SVG string via MuPDF's vector SVG device.
    /// - Parameters:
    ///   - document: Source document.
    ///   - pageIndex: 0-based page index.
    ///   - textAsPath: If true, text and math glyphs are converted to vector path outlines (preserving exact math typography without external font dependencies); if false, raw <text> elements are emitted.
    public func exportPageSVG(
        from document: PDFDocumentCore,
        pageIndex: Int,
        textAsPath: Bool = true
    ) throws -> String {
        try document.exportPageToSVG(pageIndex: pageIndex, textAsPath: textAsPath)
    }

    /// Exports pages from a PDF document into Scalable Vector Graphics (.svg) files.
    /// - If 1 page is exported, writes directly to `destinationURL` as a single .svg file.
    /// - If multiple pages are exported, creates a dedicated directory and places each page's SVG file inside it.
    @discardableResult
    public func exportSVG(
        from document: PDFDocumentCore,
        to destinationURL: URL,
        pageIndices: [Int]? = nil,
        textAsPath: Bool = true
    ) throws -> URL {
        let indices = pageIndices ?? Array(0..<document.pageCount)
        guard !indices.isEmpty else { return destinationURL }

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destinationURL.path, isDirectory: &isDir)
        let destinationIsDirectory = exists && isDir.boolValue
        let docName = URL(fileURLWithPath: document.filePath).deletingPathExtension().lastPathComponent

        if indices.count == 1 {
            let fileURL = destinationIsDirectory ? destinationURL.appendingPathComponent("\(docName).svg") : destinationURL
            try document.exportPageToSVGFile(pageIndex: indices[0], destinationURL: fileURL, textAsPath: textAsPath)
            return fileURL
        }

        // Multiple pages: one folder containing a file per page.
        let folderURL: URL
        let baseName: String

        if destinationIsDirectory {
            // Existing directory: create a subfolder named after the document
            baseName = docName
            folderURL = destinationURL.appendingPathComponent(docName)
        } else if destinationURL.pathExtension.lowercased() == "svg" {
            // Destination ended with .svg (e.g. from Save panel): strip extension to form folder name
            folderURL = destinationURL.deletingPathExtension()
            baseName = destinationURL.deletingPathExtension().lastPathComponent
        } else {
            folderURL = destinationURL
            baseName = destinationURL.lastPathComponent
        }

        var folderIsDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &folderIsDir), !folderIsDir.boolValue {
            throw PDFError.operationFailed("A file named “\(folderURL.lastPathComponent)” already exists. Choose a different name for the SVG folder.")
        }
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        for pIdx in indices {
            let pageURL = folderURL.appendingPathComponent("\(baseName)_page_\(pIdx + 1).svg")
            try document.exportPageToSVGFile(pageIndex: pIdx, destinationURL: pageURL, textAsPath: textAsPath)
        }

        return folderURL
    }

    // MARK: - Word (.docx) Export

    /// Exports pages from a PDF document into a standardized OpenXML Word Document (.docx) package.
    public func exportWordDocument(
        from document: PDFDocumentCore,
        to destinationURL: URL,
        pageIndices: [Int]? = nil
    ) throws {
        let indices = pageIndices ?? Array(0..<document.pageCount)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("docx_export_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let wordDir = tempDir.appendingPathComponent("word")
        let relsDir = tempDir.appendingPathComponent("_rels")
        let wordRelsDir = wordDir.appendingPathComponent("_rels")
        let wordMediaDir = wordDir.appendingPathComponent("media")
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordMediaDir, withIntermediateDirectories: true)

        // 1. [Content_Types].xml
        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="png" ContentType="image/png"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
          <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
        </Types>
        """
        try contentTypesXML.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        // 2. _rels/.rels
        let relsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """
        try relsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        // 3. word/styles.xml (Standard typography definitions)
        let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:docDefaults>
            <w:rPrDefault>
              <w:rPr>
                <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>
                <w:sz w:val="22"/>
                <w:szCs w:val="22"/>
                <w:lang w:val="en-US"/>
              </w:rPr>
            </w:rPrDefault>
          </w:docDefaults>
          <w:style w:type="paragraph" w:default="1" w:styleId="Normal">
            <w:name w:val="Normal"/>
            <w:pPr>
              <w:spacing w:after="160" w:line="240" w:lineRule="auto"/>
            </w:pPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading1">
            <w:name w:val="heading 1"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:pPr>
              <w:spacing w:before="240" w:after="100"/>
            </w:pPr>
            <w:rPr>
              <w:b/>
            </w:rPr>
          </w:style>
          <w:style w:type="paragraph" w:styleId="Heading2">
            <w:name w:val="heading 2"/>
            <w:basedOn w:val="Normal"/>
            <w:next w:val="Normal"/>
            <w:pPr>
              <w:spacing w:before="180" w:after="80"/>
            </w:pPr>
            <w:rPr>
              <w:b/>
            </w:rPr>
          </w:style>
        </w:styles>
        """
        try stylesXML.write(to: wordDir.appendingPathComponent("styles.xml"), atomically: true, encoding: .utf8)

        // 4. word/document.xml & media relationships
        var docBodyXML = ""
        var imageRels: [(id: String, target: String)] = [("rIdStyles", "styles.xml")]
        var imageCounter = 0
        
        struct ReconstructedPage {
            let pageIndex: Int
            let bounds: CGRect
            var elements: [PDFLayoutElement]
            let baseFontSize: Float
        }

        let layoutEngine = PDFLayoutEngine()
        var reconstructedPages: [ReconstructedPage] = []

        for pIdx in indices {
            guard let stext = document.loadStructuredPage(for: pIdx) else { continue }
            let allChars = stext.blocks.filter { $0.type == .text }.flatMap { $0.lines }.flatMap { $0.characters }
            let validSizes = allChars.map { $0.size }.filter { $0 > 0 }.sorted()
            let baseFontSize: Float = validSizes.isEmpty ? 11.0 : validSizes[validSizes.count / 2]

            let elements = layoutEngine.reconstructLayout(for: stext)
            reconstructedPages.append(ReconstructedPage(pageIndex: pIdx, bounds: stext.bounds, elements: elements, baseFontSize: baseFontSize))
        }

        var allPageElements = reconstructedPages.map { $0.elements }
        layoutEngine.stitchContinuingTables(pages: &allPageElements)
        for i in 0..<reconstructedPages.count {
            reconstructedPages[i].elements = allPageElements[i]
        }

        // Running headers/footers: paragraphs in the top/bottom margin whose text (with numbers
        // masked) recurs on more than one page, or that are just a page number.
        var marginTextPageCounts: [String: Int] = [:]
        for page in reconstructedPages {
            var seen = Set<String>()
            for case .paragraph(let runs, let bbox, _, _, _, _, _) in page.elements where isInMarginZone(bbox: bbox, pageBounds: page.bounds) {
                seen.insert(normalizedMarginText(runs.map(\.text).joined()))
            }
            for key in seen { marginTextPageCounts[key, default: 0] += 1 }
        }
        let repeatedMarginTexts = Set(marginTextPageCounts.filter { $0.value >= 2 }.keys)
        func isHeaderOrFooter(runs: [TextRun], bbox: CGRect, pageBounds: CGRect) -> Bool {
            guard isInMarginZone(bbox: bbox, pageBounds: pageBounds) else { return false }
            let text = runs.map(\.text).joined()
            return repeatedMarginTexts.contains(normalizedMarginText(text)) || isPageNumberText(text)
        }

        for (pageSeq, page) in reconstructedPages.enumerated() {
            // Check if page has substantive body content
            let substantiveElements = page.elements.filter { elem in
                switch elem {
                case .heading(_, let runs, _, _, _):
                    return !runs.map(\.text).joined().trimmingCharacters(in: .whitespaces).isEmpty
                case .paragraph(let runs, let bbox, _, _, _, _, _):
                    if isHeaderOrFooter(runs: runs, bbox: bbox, pageBounds: page.bounds) {
                        return false
                    }
                    return !runs.map(\.text).joined().trimmingCharacters(in: .whitespaces).isEmpty
                case .table, .image:
                    return true
                }
            }

            guard !substantiveElements.isEmpty else { continue }

            // Insert native page break between pages (starting from page 2)
            if pageSeq > 0 && !docBodyXML.isEmpty {
                docBodyXML.append("""
                    <w:p>
                      <w:r>
                        <w:br w:type="page"/>
                      </w:r>
                    </w:p>
                """)
            }

            for elem in page.elements {
                switch elem {
                case .heading(let level, let runs, _, let spaceBefore, let spaceAfter):
                    let styleName = (level == 1) ? "Heading1" : "Heading2"
                    let outlineLvl = (level == 1) ? 0 : 1
                    var pXML = """
                    <w:p>
                      <w:pPr>
                        <w:pStyle w:val="\(styleName)"/>
                        <w:outlineLvl w:val="\(outlineLvl)"/>
                        <w:spacing w:before="\(spaceBefore)" w:after="\(spaceAfter)"/>
                      </w:pPr>
                    """
                    for run in runs {
                        pXML.append(generateRunXML(run))
                    }
                    pXML.append("</w:p>\n")
                    docBodyXML.append(pXML)

                case .paragraph(let runs, let bbox, let spaceBefore, let spaceAfter, let leftIndent, let firstLineIndent, let alignment):
                    if isHeaderOrFooter(runs: runs, bbox: bbox, pageBounds: page.bounds) {
                        continue
                    }

                    if let tocMatch = parseToCEntry(runs: runs) {
                        var pPr = "<w:pPr><w:pStyle w:val=\"Normal\"/>"
                        let tabPos = max(2880, 9360 - leftIndent)
                        pPr.append("<w:tabs><w:tab w:val=\"right\" w:leader=\"dot\" w:pos=\"\(tabPos)\"/></w:tabs>")
                        pPr.append("<w:spacing w:before=\"40\" w:after=\"40\"/>")
                        if leftIndent > 0 {
                            pPr.append("<w:ind w:left=\"\(leftIndent)\"/>")
                        }
                        pPr.append("</w:pPr>")

                        var pXML = "<w:p>\(pPr)"
                        for run in tocMatch.titleRuns {
                            pXML.append(generateRunXML(run))
                        }
                        pXML.append("<w:r><w:tab/></w:r>")
                        pXML.append(generateRunXML(tocMatch.pageRun))
                        pXML.append("</w:p>\n")
                        docBodyXML.append(pXML)
                        continue
                    }

                    var pPr = "<w:pPr><w:pStyle w:val=\"Normal\"/>"
                    pPr.append("<w:spacing w:before=\"\(spaceBefore)\" w:after=\"\(spaceAfter)\"/>")
                    if leftIndent > 0 || firstLineIndent != 0 {
                        pPr.append("<w:ind w:left=\"\(leftIndent)\" w:firstLine=\"\(firstLineIndent)\"/>")
                    }
                    if alignment == .center {
                        pPr.append("<w:jc w:val=\"center\"/>")
                    } else if alignment == .right {
                        pPr.append("<w:jc w:val=\"right\"/>")
                    }
                    pPr.append("</w:pPr>")

                    var pXML = "<w:p>\(pPr)"
                    for run in runs {
                        pXML.append(generateRunXML(run))
                    }
                    pXML.append("</w:p>\n")
                    docBodyXML.append(pXML)

                case .table(let table):
                    let tblXML = generateTableXML(table: table, baseFontSize: page.baseFontSize)
                    docBodyXML.append(tblXML)

                case .image(let bbox, _):
                    if let imgData = document.renderPageRect(pageIndex: page.pageIndex, rect: bbox, scale: 2.0) {
                        imageCounter += 1
                        let imgFilename = "image\(imageCounter).png"
                        let relId = "rIdImg\(imageCounter)"
                        let imgFileURL = wordMediaDir.appendingPathComponent(imgFilename)
                        try? imgData.write(to: imgFileURL)
                        imageRels.append((id: relId, target: "media/\(imgFilename)"))

                        let drawingXML = generateDrawingXML(imageCounter: imageCounter, relId: relId, bbox: bbox)
                        docBodyXML.append(drawingXML)
                    }
                }
            }
        }

        // 2b. Write word/_rels/document.xml.rels with styles and all embedded image relationships
        var docRelsXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\n"
        for rel in imageRels {
            let type = rel.target.starts(with: "media/")
                ? "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
                : "http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"
            docRelsXML.append("  <Relationship Id=\"\(rel.id)\" Type=\"\(type)\" Target=\"\(rel.target)\"/>\n")
        }
        docRelsXML.append("</Relationships>")
        try docRelsXML.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
        \(docBodyXML)
            <w:sectPr>
              <w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """
        try documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        // 5. Package into .docx using /usr/bin/zip
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let zipProc = Process()
        zipProc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProc.currentDirectoryURL = tempDir
        zipProc.arguments = ["-q", "-r", destinationURL.path, "[Content_Types].xml", "_rels", "word"]
        try zipProc.run()
        zipProc.waitUntilExit()

        guard zipProc.terminationStatus == 0 else {
            // Fallback to ditto if zip returned an error
            let dittoProc = Process()
            dittoProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProc.arguments = ["-c", "-k", "--sequesterRsrc", tempDir.path, destinationURL.path]
            try dittoProc.run()
            dittoProc.waitUntilExit()
            if dittoProc.terminationStatus != 0 {
                throw PDFError.operationFailed("Packaging .docx failed")
            }
            return
        }
    }

    // MARK: - Drawing & Table Helpers

    private func cleanFontFamily(_ rawName: String) -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Calibri" }
        if let plusIdx = name.firstIndex(of: "+") {
            name = String(name[name.index(after: plusIdx)...])
        }
        let lower = name.lowercased()
        if lower.contains("times") {
            return "Times New Roman"
        } else if lower.contains("helvetica") {
            return "Helvetica"
        } else if lower.contains("arial") {
            return "Arial"
        } else if lower.contains("calibri") {
            return "Calibri"
        } else if lower.contains("courier") {
            return "Courier New"
        } else if lower.contains("georgia") {
            return "Georgia"
        } else if lower.contains("verdana") {
            return "Verdana"
        } else if lower.contains("cambria") {
            return "Cambria"
        } else if lower.contains("garamond") {
            return "Garamond"
        } else if lower.contains("trebuchet") {
            return "Trebuchet MS"
        } else if lower.contains("tahoma") {
            return "Tahoma"
        } else if lower.contains("palatino") {
            return "Palatino"
        } else if lower.contains("consolas") || lower.contains("monaco") || lower.contains("menlo") {
            return "Consolas"
        } else if lower.contains("baskerville") {
            return "Baskerville"
        } else if lower.contains("futura") {
            return "Futura"
        } else if lower.contains("optima") {
            return "Optima"
        }
        name = name.replacingOccurrences(of: "-BoldItalic", with: "")
                   .replacingOccurrences(of: "-Bold", with: "")
                   .replacingOccurrences(of: "-Italic", with: "")
                   .replacingOccurrences(of: "-Regular", with: "")
                   .replacingOccurrences(of: "PSMT", with: "")
                   .replacingOccurrences(of: "MT", with: "")
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Calibri" : trimmed
    }

    private func generateRunXML(_ run: TextRun) -> String {
        var rPr = ""
        if run.isBold { rPr.append("<w:b/>") }
        if run.isItalic { rPr.append("<w:i/>") }
        if run.isUnderline { rPr.append("<w:u w:val=\"single\"/>") }
        if run.isStrikethrough { rPr.append("<w:strike/>") }
        let halfPts = Int(round(run.size * 2))
        rPr.append("<w:sz w:val=\"\(halfPts)\"/><w:szCs w:val=\"\(halfPts)\"/>")
        let cleanFont = cleanFontFamily(run.fontName)
        if !cleanFont.isEmpty {
            rPr.append("<w:rFonts w:ascii=\"\(xmlEscape(cleanFont))\" w:hAnsi=\"\(xmlEscape(cleanFont))\" w:cs=\"\(xmlEscape(cleanFont))\"/>")
        }
        rPr.append("<w:color w:val=\"\(run.colorHex)\"/>")

        let escapedText = xmlEscape(run.text)
        let rPrXML = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
        return "<w:r>\(rPrXML)<w:t xml:space=\"preserve\">\(escapedText)</w:t></w:r>"
    }

    private func generateTableXML(table: LayoutTable, baseFontSize: Float) -> String {
        let maxPtWidth: CGFloat = 468.0
        let totalTablePtWidth = max(1.0, table.colWidths.reduce(0, +))
        let scaleRatio = min(1.0, maxPtWidth / totalTablePtWidth)

        let borderXML: String
        if table.isLattice {
            borderXML = """
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:space="0" w:color="808080"/>
              <w:bottom w:val="single" w:sz="6" w:space="0" w:color="808080"/>
              <w:left w:val="single" w:sz="6" w:space="0" w:color="808080"/>
              <w:right w:val="single" w:sz="6" w:space="0" w:color="808080"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="A0A0A0"/>
              <w:insideV w:val="single" w:sz="4" w:space="0" w:color="A0A0A0"/>
            </w:tblBorders>
            """
        } else {
            borderXML = """
            <w:tblBorders>
              <w:top w:val="single" w:sz="6" w:space="0" w:color="B0B0B0"/>
              <w:bottom w:val="single" w:sz="6" w:space="0" w:color="B0B0B0"/>
              <w:insideH w:val="single" w:sz="4" w:space="0" w:color="DCDCDC"/>
              <w:left w:val="none"/>
              <w:right w:val="none"/>
              <w:insideV w:val="none"/>
            </w:tblBorders>
            """
        }

        var tblXML = """
        <w:tbl>
          <w:tblPr>
            <w:tblW w:w="0" w:type="auto"/>
            <w:jc w:val="center"/>
            \(borderXML)
            <w:tblCellMar>
              <w:top w:w="120" w:type="dxa"/>
              <w:bottom w:w="120" w:type="dxa"/>
              <w:left w:w="160" w:type="dxa"/>
              <w:right w:w="160" w:type="dxa"/>
            </w:tblCellMar>
          </w:tblPr>
          <w:tblGrid>
        """
        for w in table.colWidths {
            let twips = Int(round(w * scaleRatio * 20.0))
            tblXML.append("\n    <w:gridCol w:w=\"\(twips)\"/>")
        }
        tblXML.append("\n  </w:tblGrid>")

        let isBoxedFigure = table.rows.count == 1 || (table.rows.count == 2 && !table.rows[1].isBordered)

        for (rIdx, row) in table.rows.enumerated() {
            let isHeader = (rIdx == 0 && !isBoxedFigure)
            tblXML.append("\n  <w:tr>")
            if isHeader {
                tblXML.append("\n    <w:trPr><w:tblHeader/></w:trPr>")
            }

            for (cIdx, cell) in row.cells.enumerated() {
                let colW = (cIdx < table.colWidths.count) ? table.colWidths[cIdx] : (table.colWidths.last ?? 100)
                let cellTwips = Int(round(colW * scaleRatio * 20.0))

                var tcPr = "<w:tcPr><w:tcW w:w=\"\(cellTwips)\" w:type=\"dxa\"/>"
                if !row.isBordered {
                    tcPr.append("""
                    <w:tcBorders>
                      <w:top w:val="none"/>
                      <w:left w:val="none"/>
                      <w:bottom w:val="none"/>
                      <w:right w:val="none"/>
                    </w:tcBorders>
                    """)
                } else if isBoxedFigure {
                    tcPr.append("""
                    <w:tcBorders>
                      <w:top w:val="single" w:sz="6" w:space="0" w:color="000000"/>
                      <w:bottom w:val="single" w:sz="6" w:space="0" w:color="000000"/>
                      <w:left w:val="single" w:sz="6" w:space="0" w:color="000000"/>
                      <w:right w:val="single" w:sz="6" w:space="0" w:color="000000"/>
                    </w:tcBorders>
                    """)
                } else if isHeader {
                    tcPr.append("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F2F2F2\"/>")
                }
                tcPr.append("</w:tcPr>")

                let trimmed = cell.text.trimmingCharacters(in: .whitespaces)
                let isNumeric = !trimmed.isEmpty && trimmed.allSatisfy { $0.isNumber || $0 == "." || $0 == "," || $0 == "$" || $0 == "%" || $0 == "-" || $0 == "+" }
                let alignVal: String
                if isBoxedFigure {
                    alignVal = "center"
                } else if isNumeric {
                    alignVal = "right"
                } else {
                    alignVal = "left"
                }

                var pRuns = ""
                for run in cell.runs {
                    var rPr = ""
                    if isHeader || run.isBold { rPr.append("<w:b/>") }
                    if run.isItalic { rPr.append("<w:i/>") }
                    if run.isUnderline { rPr.append("<w:u w:val=\"single\"/>") }
                    if run.isStrikethrough { rPr.append("<w:strike/>") }
                    let halfPts = Int(round(run.size * 2))
                    rPr.append("<w:sz w:val=\"\(halfPts)\"/><w:szCs w:val=\"\(halfPts)\"/>")
                    let cleanFont = cleanFontFamily(run.fontName)
                    if !cleanFont.isEmpty {
                        rPr.append("<w:rFonts w:ascii=\"\(xmlEscape(cleanFont))\" w:hAnsi=\"\(xmlEscape(cleanFont))\" w:cs=\"\(xmlEscape(cleanFont))\"/>")
                    }
                    rPr.append("<w:color w:val=\"\(run.colorHex)\"/>")

                    let escaped = xmlEscape(run.text)
                    let rPrXML = rPr.isEmpty ? "" : "<w:rPr>\(rPr)</w:rPr>"
                    pRuns.append("<w:r>\(rPrXML)<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r>")
                }
                if pRuns.isEmpty {
                    pRuns = "<w:r><w:t></w:t></w:r>"
                }

                tblXML.append("""
                \n    <w:tc>
                      \(tcPr)
                      <w:p>
                        <w:pPr>
                          <w:spacing w:before="60" w:after="60" w:line="220" w:lineRule="auto"/>
                          <w:jc w:val="\(alignVal)"/>
                        </w:pPr>
                        \(pRuns)
                      </w:p>
                    </w:tc>
                """)
            }
            tblXML.append("\n  </w:tr>")
        }
        tblXML.append("\n</w:tbl>\n")
        return tblXML
    }

    private func generateDrawingXML(imageCounter: Int, relId: String, bbox: CGRect) -> String {
        let maxPtWidth: CGFloat = 468.0
        let maxPtHeight: CGFloat = 580.0
        let scaleRatio = min(1.0, min(maxPtWidth / max(1.0, bbox.width), maxPtHeight / max(1.0, bbox.height)))
        let cx = Int(round(bbox.width * scaleRatio * 12700.0))
        let cy = Int(round(bbox.height * scaleRatio * 12700.0))

        return """
        <w:p>
          <w:pPr>
            <w:jc w:val="center"/>
            <w:spacing w:before="180" w:after="180"/>
          </w:pPr>
          <w:r>
            <w:drawing>
              <wp:inline distT="0" distB="0" distL="0" distR="0" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing">
                <wp:extent cx="\(cx)" cy="\(cy)"/>
                <wp:effectExtent l="0" t="0" r="0" b="0"/>
                <wp:docPr id="\(imageCounter)" name="Picture \(imageCounter)"/>
                <wp:cNvGraphicFramePr>
                  <a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/>
                </wp:cNvGraphicFramePr>
                <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
                  <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                    <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
                      <pic:nvPicPr>
                        <pic:cNvPr id="\(imageCounter)" name="Picture \(imageCounter)"/>
                        <pic:cNvPicPr/>
                      </pic:nvPicPr>
                      <pic:blipFill>
                        <a:blip r:embed="\(relId)" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/>
                        <a:stretch>
                          <a:fillRect/>
                        </a:stretch>
                      </pic:blipFill>
                      <pic:spPr>
                        <a:xfrm>
                          <a:off x="0" y="0"/>
                          <a:ext cx="\(cx)" cy="\(cy)"/>
                        </a:xfrm>
                        <a:prstGeom prst="rect">
                          <a:avLst/>
                        </a:prstGeom>
                      </pic:spPr>
                    </pic:pic>
                  </a:graphicData>
                </a:graphic>
              </wp:inline>
            </w:drawing>
          </w:r>
        </w:p>
        \n
        """
    }

    private func xmlEscape(_ string: String) -> String {
        var out = ""
        for scalar in string.unicodeScalars {
            let v = scalar.value
            // XML 1.0 valid character ranges: 0x9, 0xA, 0xD, 0x20-0xD7FF, 0xE000-0xFFFD, 0x10000-0x10FFFF
            if v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD) || (v >= 0x10000 && v <= 0x10FFFF) {
                switch v {
                case 38: out.append("&amp;")
                case 60: out.append("&lt;")
                case 62: out.append("&gt;")
                case 34: out.append("&quot;")
                case 39: out.append("&apos;")
                default: out.append(String(scalar))
                }
            }
        }
        return out
    }

    /// Whether a block lies entirely within the top or bottom margin band of its page.
    private func isInMarginZone(bbox: CGRect, pageBounds: CGRect) -> Bool {
        let band = min(54.0, pageBounds.height * 0.08)
        return bbox.maxY <= pageBounds.minY + band || bbox.minY >= pageBounds.maxY - band
    }

    /// Lowercased, whitespace-collapsed, with digit runs masked — so "Page 3 of 12" and
    /// "Page 4 of 12" count as the same running footer.
    private func normalizedMarginText(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// A bare page number such as "3", "- 3 -", "Page 3", "3 of 12" or "iv".
    private func isPageNumberText(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.range(of: #"^(?i)(page\s*)?[-–—]?\s*(\d+|[ivxlcdm]+)\s*[-–—]?(\s*(of|/)\s*\d+)?$"#, options: .regularExpression) != nil
    }

    // MARK: - ToC Parsing Helper

    private struct ToCEntry {
        let titleRuns: [TextRun]
        let pageRun: TextRun
    }

    private func parseToCEntry(runs: [TextRun]) -> ToCEntry? {
        let fullText = runs.map(\.text).joined()
        let pattern = #"^(.*?)\s*(\.{3,}|\t+)\s*(\d+|[ivxlcdmIVXLCDM]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: fullText, range: NSRange(fullText.startIndex..., in: fullText)),
              let titleRange = Range(match.range(at: 1), in: fullText),
              let pageRange = Range(match.range(at: 3), in: fullText) else {
            return nil
        }

        let titleStr = String(fullText[titleRange]).trimmingCharacters(in: .whitespaces)
        let pageStr = String(fullText[pageRange]).trimmingCharacters(in: .whitespaces)
        guard !titleStr.isEmpty, !pageStr.isEmpty else { return nil }

        if runs.count == 1 {
            let r = runs[0]
            let tRun = TextRun(text: titleStr, isBold: r.isBold, isItalic: r.isItalic, isUnderline: r.isUnderline, isStrikethrough: r.isStrikethrough, size: r.size, fontName: r.fontName, colorHex: r.colorHex)
            let pRun = TextRun(text: pageStr, isBold: r.isBold, isItalic: r.isItalic, isUnderline: r.isUnderline, isStrikethrough: r.isStrikethrough, size: r.size, fontName: r.fontName, colorHex: r.colorHex)
            return ToCEntry(titleRuns: [tRun], pageRun: pRun)
        }

        var titleRuns: [TextRun] = []
        var accumulatedLen = 0
        let titleLen = titleStr.utf16.count

        for r in runs {
            let rLen = r.text.utf16.count
            if accumulatedLen + rLen <= titleLen {
                titleRuns.append(r)
                accumulatedLen += rLen
            } else if accumulatedLen < titleLen {
                let needed = titleLen - accumulatedLen
                let splitIndex = r.text.index(r.text.startIndex, offsetBy: min(r.text.count, needed))
                let sub = String(r.text[..<splitIndex])
                if !sub.isEmpty {
                    titleRuns.append(TextRun(text: sub, isBold: r.isBold, isItalic: r.isItalic, isUnderline: r.isUnderline, isStrikethrough: r.isStrikethrough, size: r.size, fontName: r.fontName, colorHex: r.colorHex))
                }
                break
            } else {
                break
            }
        }

        if titleRuns.isEmpty {
            let r = runs.first ?? TextRun(text: titleStr, isBold: false, isItalic: false, size: 10.0, fontName: "")
            titleRuns.append(TextRun(text: titleStr, isBold: r.isBold, isItalic: r.isItalic, isUnderline: r.isUnderline, isStrikethrough: r.isStrikethrough, size: r.size, fontName: r.fontName, colorHex: r.colorHex))
        }

        let lastRun = runs.last ?? titleRuns.last!
        let pageRun = TextRun(text: pageStr, isBold: lastRun.isBold, isItalic: lastRun.isItalic, isUnderline: lastRun.isUnderline, isStrikethrough: lastRun.isStrikethrough, size: lastRun.size, fontName: lastRun.fontName, colorHex: lastRun.colorHex)

        return ToCEntry(titleRuns: titleRuns, pageRun: pageRun)
    }
}
