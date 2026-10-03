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

// MARK: - Layout Elements

/// Represents a reconstructed structural element ready for Word (.docx) or Plain Text serialization.
public enum PDFLayoutElement: Sendable {
    case heading(level: Int, runs: [TextRun], bbox: CGRect, spaceBefore: Int, spaceAfter: Int)
    case paragraph(runs: [TextRun], bbox: CGRect, spaceBefore: Int, spaceAfter: Int, leftIndent: Int, firstLineIndent: Int, alignment: LayoutAlignment)
    case table(table: LayoutTable)
    case image(bbox: CGRect, imageIndex: Int)

    public var bbox: CGRect {
        switch self {
        case .heading(_, _, let bbox, _, _): return bbox
        case .paragraph(_, let bbox, _, _, _, _, _): return bbox
        case .table(let table): return table.bbox
        case .image(let bbox, _): return bbox
        }
    }
}

public enum LayoutAlignment: Sendable {
    case left
    case center
    case right
    case justify
}

public struct LayoutCell: Sendable {
    public let bbox: CGRect
    public let lines: [TextLine]
    public let runs: [TextRun]
    public var text: String {
        runs.map { $0.text }.joined()
    }

    public init(bbox: CGRect, lines: [TextLine] = [], runs: [TextRun] = []) {
        self.bbox = bbox
        self.lines = lines
        if !runs.isEmpty {
            self.runs = runs
        } else {
            self.runs = lines.flatMap { $0.runs }
        }
    }
}

public struct LayoutRow: Sendable {
    public let bbox: CGRect
    public let cells: [LayoutCell]
    public let isBordered: Bool

    public init(bbox: CGRect, cells: [LayoutCell], isBordered: Bool = true) {
        self.bbox = bbox
        self.cells = cells
        self.isBordered = isBordered
    }
}

public struct LayoutTable: Sendable {
    public let bbox: CGRect
    public let rows: [LayoutRow]
    public let colWidths: [CGFloat]
    public let isLattice: Bool

    public init(bbox: CGRect, rows: [LayoutRow], colWidths: [CGFloat], isLattice: Bool = false) {
        self.bbox = bbox
        self.rows = rows
        self.colWidths = colWidths
        self.isLattice = isLattice
    }
}

// MARK: - PDFLayoutEngine

/// High-fidelity layout reconstruction engine ported from the principles of Artifex's pdf2docx.
/// Reconstructs flowable paragraphs, headings, lattice/stream tables, and visual elements from MuPDF structured text.
public final class PDFLayoutEngine: Sendable {

    public init() {}

    // MARK: - Public Entrypoint

    /// Reconstructs the high-level document flow (paragraphs, headings, tables, images) from a structured page.
    public func reconstructLayout(for page: StructuredPage) -> [PDFLayoutElement] {
        // 1. Calculate base/median font size for the page to determine typography scale
        let allChars = page.blocks.filter { $0.type == .text }.flatMap { $0.lines }.flatMap { $0.characters }
        let validSizes = allChars.map { $0.size }.filter { $0 > 0 }.sorted()
        let baseFontSize: Float = validSizes.isEmpty ? 11.0 : validSizes[validSizes.count / 2]

        // 2. Extract vector strokes and detect Lattice Tables (vector border-driven tables)
        let latticeTables = detectLatticeTables(in: page, baseFontSize: baseFontSize)
        var capturedTableBBoxes = latticeTables.map { $0.bbox }

        // 3. Find Stream Tables (borderless tabular data with strict column alignment)
        let streamTables = detectStreamTables(in: page, excluding: capturedTableBBoxes)
        capturedTableBBoxes.append(contentsOf: streamTables.map { $0.bbox })

        let allTables = latticeTables + streamTables

        // 4. Collect text lines that are NOT captured inside tables
        var freeLines: [TextLine] = []
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }

        let bodyBlocks = textBlocks.filter { $0.bbox.width >= 120 }
        let bodyLeftMargin = bodyBlocks.map { $0.bbox.minX }.min() ?? 72.0
        let bodyRightMargin = bodyBlocks.map { $0.bbox.maxX }.max() ?? (page.bounds.width - 72.0)

        for block in textBlocks {
            for line in block.lines {
                let center = CGPoint(x: line.bbox.midX, y: line.bbox.midY)
                let insideTable = capturedTableBBoxes.contains { tableBox in
                    tableBox.contains(center) || tableBox.insetBy(dx: -2, dy: -2).contains(center)
                }
                if insideTable { continue }

                if isMarginLineNumber(line, leftMargin: bodyLeftMargin, rightMargin: bodyRightMargin) {
                    continue
                }

                freeLines.append(line)
            }
        }

        // Sort free lines in reading order: on a two-column page, each column top-to-bottom
        // (between any full-width lines), otherwise simply top-to-bottom, left-to-right.
        let gutterX = detectColumnGutter(lines: freeLines, pageWidth: page.bounds.width)
        freeLines = readingOrderedLines(freeLines, gutterX: gutterX)

        // 5. Reconstruct Flow Paragraphs & Headings from free text lines
        let flowElements = reconstructParagraphsAndHeadings(lines: freeLines, baseFontSize: baseFontSize, pageWidth: page.bounds.width)

        // 6. Collect visual image / illustration elements
        var visualElements: [PDFLayoutElement] = []
        var imgCounter = 0
        for block in page.blocks {
            if block.type == .image {
                guard block.bbox.width >= 10 && block.bbox.height >= 10 else { continue }
                imgCounter += 1
                visualElements.append(.image(bbox: block.bbox, imageIndex: imgCounter))
            } else if block.type == .vector {
                // Vector illustration (e.g. diagram, chart)
                guard block.bbox.width >= 70 && block.bbox.height >= 50 else { continue }
                let overlapsTable = capturedTableBBoxes.contains { $0.intersects(block.bbox) }
                guard !overlapsTable else { continue }
                imgCounter += 1
                visualElements.append(.image(bbox: block.bbox, imageIndex: imgCounter))
            }
        }

        // 7. Combine all elements and sort in natural reading order (Y coordinate top to bottom)
        var allElements: [PDFLayoutElement] = []
        for tbl in allTables {
            allElements.append(.table(table: tbl))
        }
        allElements.append(contentsOf: flowElements)
        allElements.append(contentsOf: visualElements)

        if let gutterX {
            // Column-aware order: a plain sort by y would interleave the two columns' paragraphs.
            let spanningTops = allElements
                .filter { $0.bbox.minX < gutterX && $0.bbox.maxX > gutterX }
                .map { $0.bbox.minY }
            func key(_ e: PDFLayoutElement) -> (Int, Int, CGFloat) {
                let b = e.bbox
                let band = spanningTops.filter { $0 <= b.minY }.count
                let column = (b.minX < gutterX && b.maxX > gutterX) ? -1 : (b.midX < gutterX ? 0 : 1)
                return (band, column, b.minY)
            }
            allElements.sort { key($0) < key($1) }
        } else {
            allElements.sort { $0.bbox.minY < $1.bbox.minY }
        }
        return allElements
    }

    // MARK: - Column Detection

    /// The x position of the gutter between two side-by-side text columns, or nil for a
    /// single-column page. A candidate gutter must have enough lines entirely on each side, the
    /// two sides must sit next to each other vertically (not one above the other), and only a few
    /// lines (full-width headings, titles) may cross it.
    private func detectColumnGutter(lines: [TextLine], pageWidth: CGFloat) -> CGFloat? {
        guard lines.count >= 10, pageWidth > 0 else { return nil }
        var best: (x: CGFloat, crossing: Int)?
        var x = pageWidth * 0.35
        while x <= pageWidth * 0.65 {
            let left = lines.filter { $0.bbox.maxX <= x }
            let right = lines.filter { $0.bbox.minX >= x }
            let crossing = lines.count - left.count - right.count
            if left.count >= 5, right.count >= 5, crossing <= max(2, lines.count / 8) {
                let leftTop = left.map { $0.bbox.minY }.min()!, leftBottom = left.map { $0.bbox.maxY }.max()!
                let rightTop = right.map { $0.bbox.minY }.min()!, rightBottom = right.map { $0.bbox.maxY }.max()!
                let overlap = min(leftBottom, rightBottom) - max(leftTop, rightTop)
                let shorter = min(leftBottom - leftTop, rightBottom - rightTop)
                if shorter > 0, overlap >= shorter * 0.5 {
                    let isBetter = best.map { crossing < $0.crossing || (crossing == $0.crossing && abs(x - pageWidth / 2) < abs($0.x - pageWidth / 2)) } ?? true
                    if isBetter { best = (x, crossing) }
                }
            }
            x += 2
        }
        return best?.x
    }

    /// Lines in reading order. With a gutter: full-width lines split the page into bands, and
    /// within each band the left column is read before the right.
    private func readingOrderedLines(_ lines: [TextLine], gutterX: CGFloat?) -> [TextLine] {
        guard let gutterX else { return readingOrder(lines) { $0.bbox } }
        var result: [TextLine] = []
        var left: [TextLine] = []
        var right: [TextLine] = []
        func flush() {
            result += readingOrder(left) { $0.bbox }
            result += readingOrder(right) { $0.bbox }
            left = []
            right = []
        }
        for line in lines.sorted(by: { $0.bbox.minY < $1.bbox.minY }) {
            if line.bbox.minX < gutterX && line.bbox.maxX > gutterX {
                flush()
                result.append(line)
            } else if line.bbox.midX < gutterX {
                left.append(line)
            } else {
                right.append(line)
            }
        }
        flush()
        return result
    }

    // MARK: - Lattice Table Detection (Vector Borders)

    private struct StrokeLine {
        let isHorizontal: Bool
        let coord: CGFloat       // Y for horizontal, X for vertical
        let start: CGFloat       // X0 for horizontal, Y0 for vertical
        let end: CGFloat         // X1 for horizontal, Y1 for vertical
        let width: CGFloat

        var bbox: CGRect {
            if isHorizontal {
                return CGRect(x: min(start, end), y: coord - 1.5, width: abs(end - start), height: 3.0)
            } else {
                return CGRect(x: coord - 1.5, y: min(start, end), width: 3.0, height: abs(end - start))
            }
        }
    }

    private func detectLatticeTables(in page: StructuredPage, baseFontSize: Float) -> [LayoutTable] {
        let vectorBlocks = page.blocks.filter { $0.type == .vector }
        guard !vectorBlocks.isEmpty else { return [] }

        var hLines: [StrokeLine] = []
        var vLines: [StrokeLine] = []

        for b in vectorBlocks {
            let r = b.bbox
            guard r.width > 0 && r.height > 0 else { continue }

            // Skip underlines and text highlights
            if let vi = b.vectorInfo {
                if vi.isUnderline || vi.isHighlight || vi.isStrikeout {
                    continue
                }
            }

            // Horizontal line segment
            if r.height <= 3.5 && r.width >= 12.0 {
                hLines.append(StrokeLine(isHorizontal: true, coord: r.midY, start: r.minX, end: r.maxX, width: r.height))
            }
            // Vertical line segment
            else if r.width <= 3.5 && r.height >= 12.0 {
                vLines.append(StrokeLine(isHorizontal: false, coord: r.midX, start: r.minY, end: r.maxY, width: r.width))
            }
            // Stroked rectangle
            else if let vi = b.vectorInfo, vi.isStroked, r.width >= 15.0 && r.height >= 15.0 {
                hLines.append(StrokeLine(isHorizontal: true, coord: r.minY, start: r.minX, end: r.maxX, width: 1.0))
                hLines.append(StrokeLine(isHorizontal: true, coord: r.maxY, start: r.minX, end: r.maxX, width: 1.0))
                vLines.append(StrokeLine(isHorizontal: false, coord: r.minX, start: r.minY, end: r.maxY, width: 1.0))
                vLines.append(StrokeLine(isHorizontal: false, coord: r.maxX, start: r.minY, end: r.maxY, width: 1.0))
            }
        }

        guard hLines.count >= 2 && vLines.count >= 2 else { return [] }

        let allStrokes = hLines + vLines

        // Union-find to group intersecting strokes into connected table components
        var parent = Array(0..<allStrokes.count)
        func findRoot(_ i: Int) -> Int {
            var curr = i
            while parent[curr] != curr {
                parent[curr] = parent[parent[curr]]
                curr = parent[curr]
            }
            return curr
        }
        func unionRoots(_ i: Int, _ j: Int) {
            let rootI = findRoot(i)
            let rootJ = findRoot(j)
            if rootI != rootJ { parent[rootI] = rootJ }
        }

        for i in 0..<allStrokes.count {
            let boxI = allStrokes[i].bbox.insetBy(dx: -3.5, dy: -3.5)
            for j in (i + 1)..<allStrokes.count {
                if boxI.intersects(allStrokes[j].bbox) {
                    unionRoots(i, j)
                }
            }
        }

        var groups: [Int: [StrokeLine]] = [:]
        for i in 0..<allStrokes.count {
            let root = findRoot(i)
            groups[root, default: []].append(allStrokes[i])
        }

        var detectedTables: [LayoutTable] = []

        for (_, strokes) in groups {
            let groupH = strokes.filter { $0.isHorizontal }
            let groupV = strokes.filter { !$0.isHorizontal }

            guard groupH.count >= 2 && groupV.count >= 2 else { continue }

            // Cluster horizontal lines by Y (within 2.5 pt tolerance)
            let sortedY = groupH.map { $0.coord }.sorted()
            var clusterY: [CGFloat] = []
            for y in sortedY {
                if let last = clusterY.last, abs(y - last) < 2.5 { continue }
                clusterY.append(y)
            }

            // Cluster vertical lines by X (within 2.5 pt tolerance)
            let sortedX = groupV.map { $0.coord }.sorted()
            var clusterX: [CGFloat] = []
            for x in sortedX {
                if let last = clusterX.last, abs(x - last) < 2.5 { continue }
                clusterX.append(x)
            }

            // In multi-page tables, vertical column borders often extend past the last horizontal line
            // (e.g. open table bottom continuing to next page). Extend clusterY to include vertical lines' bounds.
            if !groupV.isEmpty {
                let vMinY = groupV.map { min($0.start, $0.end) }.min()!
                let vMaxY = groupV.map { max($0.start, $0.end) }.max()!
                if let firstY = clusterY.first, vMinY < firstY - 5.0 {
                    clusterY.insert(vMinY, at: 0)
                }
                if let lastY = clusterY.last, vMaxY > lastY + 5.0 {
                    clusterY.append(vMaxY)
                }
            }

            guard clusterY.count >= 2 && clusterX.count >= 2 else { continue }

            let minX = clusterX.first!
            let maxX = clusterX.last!
            let minY = clusterY.first!
            let maxY = clusterY.last!

            let tableBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

            // Check if there are text lines inside this region
            let textLinesInTable = page.blocks.filter { $0.type == .text }.flatMap { $0.lines }.filter {
                let center = CGPoint(x: $0.bbox.midX, y: $0.bbox.midY)
                return tableBox.insetBy(dx: -2, dy: -2).contains(center)
            }

            guard textLinesInTable.count >= 2 else { continue }

            // Build grid cells
            var rows: [LayoutRow] = []
            var colWidths: [CGFloat] = []
            for c in 0..<(clusterX.count - 1) {
                colWidths.append(clusterX[c + 1] - clusterX[c])
            }

            for r in 0..<(clusterY.count - 1) {
                let y0 = clusterY[r]
                let y1 = clusterY[r + 1]
                var rowCells: [LayoutCell] = []

                for c in 0..<(clusterX.count - 1) {
                    let x0 = clusterX[c]
                    let x1 = clusterX[c + 1]
                    let cellBox = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)

                    // Find text lines belonging to this cell
                    let cellLines = textLinesInTable.filter { line in
                        let center = CGPoint(x: line.bbox.midX, y: line.bbox.midY)
                        return cellBox.insetBy(dx: -1.0, dy: -1.0).contains(center)
                    }.sorted { $0.bbox.minY < $1.bbox.minY }

                    rowCells.append(LayoutCell(bbox: cellBox, lines: cellLines))
                }

                let rowBox = CGRect(x: minX, y: y0, width: maxX - minX, height: y1 - y0)
                rows.append(LayoutRow(bbox: rowBox, cells: rowCells))
            }

            // Discard artifact rows where all cells are whitespace / empty (e.g. Table 9-bb19 on page 22)
            rows = rows.filter { row in
                row.cells.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            }

            // Return table if multi-row with at least 1 non-empty row, or single-row with at least 2 columns
            let nonEmptyRows = rows.filter { row in row.cells.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } }
            guard (rows.count >= 2 && !nonEmptyRows.isEmpty) || (rows.count == 1 && colWidths.count >= 2 && !nonEmptyRows.isEmpty) else { continue }

            detectedTables.append(LayoutTable(bbox: tableBox, rows: rows, colWidths: colWidths, isLattice: true))
        }

        return detectedTables
    }

    // MARK: - Stream Table Detection (Strict Multi-Column Data)

    private func detectStreamTables(in page: StructuredPage, excluding occupiedBoxes: [CGRect]) -> [LayoutTable] {
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        var candidateLines: [TextLine] = []

        for block in textBlocks {
            // Guard: running prose blocks (wide lines spanning page) are never tables
            let avgWidth = block.lines.map { $0.bbox.width }.reduce(0, +) / CGFloat(max(1, block.lines.count))
            if avgWidth > page.bounds.width * 0.35 && block.lines.count >= 2 {
                continue
            }

            for line in block.lines {
                let center = CGPoint(x: line.bbox.midX, y: line.bbox.midY)
                let insideOccupied = occupiedBoxes.contains { $0.contains(center) }
                if !insideOccupied {
                    candidateLines.append(line)
                }
            }
        }

        guard candidateLines.count >= 6 else { return [] }

        // Split candidate lines into cell fragments based on wide horizontal whitespace gutters
        var allCells: [(bbox: CGRect, runs: [TextRun], text: String)] = []
        for line in candidateLines {
            let cells = splitLineByGutters(line)
            allCells.append(contentsOf: cells)
        }

        // Group into physical rows by vertical coordinate (within 3 pt)
        let sortedCells = readingOrder(allCells) { $0.bbox }

        var detectedRows: [(bbox: CGRect, cells: [(bbox: CGRect, runs: [TextRun], text: String)])] = []
        var currentRow: [(bbox: CGRect, runs: [TextRun], text: String)] = []

        for cell in sortedCells {
            if let first = currentRow.first {
                let yDiff = abs(cell.bbox.midY - first.bbox.midY)
                let rowH = max(cell.bbox.height, first.bbox.height)
                if yDiff <= max(4.0, rowH * 0.55) {
                    currentRow.append(cell)
                } else {
                    let sortedR = currentRow.sorted { $0.bbox.minX < $1.bbox.minX }
                    let rBox = sortedR.map { $0.bbox }.reduce(sortedR[0].bbox) { $0.union($1) }
                    detectedRows.append((bbox: rBox, cells: sortedR))
                    currentRow = [cell]
                }
            } else {
                currentRow = [cell]
            }
        }
        if !currentRow.isEmpty {
            let sortedR = currentRow.sorted { $0.bbox.minX < $1.bbox.minX }
            let rBox = sortedR.map { $0.bbox }.reduce(sortedR[0].bbox) { $0.union($1) }
            detectedRows.append((bbox: rBox, cells: sortedR))
        }

        // Find sequences of >= 3 consecutive rows with identical multi-column counts and aligned columns
        var streamTables: [LayoutTable] = []
        var curRows: [(bbox: CGRect, cells: [(bbox: CGRect, runs: [TextRun], text: String)])] = []

        for r in detectedRows {
            let hasMultiCols = r.cells.count >= 2
            let firstCellText = r.cells.first?.text.trimmingCharacters(in: .whitespaces) ?? ""
            let notList = !isListMarker(firstCellText)
            let avgLen = r.cells.map { $0.text.count }.reduce(0, +) / max(1, r.cells.count)
            let isShortData = avgLen < 50

            if hasMultiCols && notList && isShortData {
                if let last = curRows.last {
                    let gap = r.bbox.minY - last.bbox.maxY
                    let sameCount = (r.cells.count == last.cells.count)
                    if gap <= 18.0 && gap >= -3.0 && sameCount {
                        curRows.append(r)
                    } else {
                        if curRows.count >= 3, let tbl = buildStreamTable(from: curRows) {
                            streamTables.append(tbl)
                        }
                        curRows = [r]
                    }
                } else {
                    curRows = [r]
                }
            } else {
                if curRows.count >= 3, let tbl = buildStreamTable(from: curRows) {
                    streamTables.append(tbl)
                }
                curRows = []
            }
        }

        if curRows.count >= 3, let tbl = buildStreamTable(from: curRows) {
            streamTables.append(tbl)
        }

        return streamTables
    }

    private func splitLineByGutters(_ line: TextLine) -> [(bbox: CGRect, runs: [TextRun], text: String)] {
        guard !line.characters.isEmpty else { return [] }

        var splits: [Int] = [0]
        for i in 0..<(line.characters.count - 1) {
            let c1 = line.characters[i]
            let c2 = line.characters[i + 1]
            let gap = c2.origin.x - c1.boundingRect.maxX
            let threshold = max(18.0, CGFloat(c1.size) * 2.0)
            if gap >= threshold {
                splits.append(i + 1)
            }
        }

        if splits.count == 1 {
            return [(bbox: line.bbox, runs: line.runs, text: line.text)]
        }

        var cells: [(bbox: CGRect, runs: [TextRun], text: String)] = []
        for (sIdx, start) in splits.enumerated() {
            let end = (sIdx < splits.count - 1) ? splits[sIdx + 1] : line.characters.count
            let slice = Array(line.characters[start..<end])
            guard !slice.isEmpty else { continue }

            let minX = slice.map { $0.boundingRect.minX }.min() ?? line.bbox.minX
            let maxX = slice.map { $0.boundingRect.maxX }.max() ?? line.bbox.maxX
            let minY = slice.map { $0.boundingRect.minY }.min() ?? line.bbox.minY
            let maxY = slice.map { $0.boundingRect.maxY }.max() ?? line.bbox.maxY
            let cBox = CGRect(x: minX, y: minY, width: max(1.0, maxX - minX), height: max(1.0, maxY - minY))

            let dummyLine = TextLine(bbox: cBox, characters: slice)
            cells.append((bbox: cBox, runs: dummyLine.runs, text: dummyLine.text))
        }

        // If cell 0 is a list numbering marker or dot leaders, return full line intact
        if cells.count >= 2 && isListMarker(cells[0].text) {
            return [(bbox: line.bbox, runs: line.runs, text: line.text)]
        }
        if line.text.contains("....") || line.text.contains("····") || line.text.contains("…") {
            return [(bbox: line.bbox, runs: line.runs, text: line.text)]
        }

        return cells
    }

    private func buildStreamTable(from rows: [(bbox: CGRect, cells: [(bbox: CGRect, runs: [TextRun], text: String)])]) -> LayoutTable? {
        guard let first = rows.first else { return nil }
        let numCols = first.cells.count

        // Verify column X coordinate alignment across all rows (<= 10 pt jitter)
        for c in 0..<numCols {
            let xPositions = rows.map { $0.cells[c].bbox.minX }
            let minX = xPositions.min() ?? 0
            let maxX = xPositions.max() ?? 0
            if (maxX - minX) > 10.0 {
                return nil
            }
        }

        var colWidths: [CGFloat] = Array(repeating: 0, count: numCols)
        for row in rows {
            for c in 0..<numCols {
                colWidths[c] = max(colWidths[c], row.cells[c].bbox.width + 12.0)
            }
        }

        var layoutRows: [LayoutRow] = []
        for row in rows {
            var layoutCells: [LayoutCell] = []
            for cell in row.cells {
                layoutCells.append(LayoutCell(bbox: cell.bbox, runs: cell.runs))
            }
            layoutRows.append(LayoutRow(bbox: row.bbox, cells: layoutCells))
        }

        let tableBox = rows.map { $0.bbox }.reduce(rows[0].bbox) { $0.union($1) }
        return LayoutTable(bbox: tableBox, rows: layoutRows, colWidths: colWidths, isLattice: false)
    }

    // MARK: - Paragraph & Heading Reconstruction (Line Joining & Reflow)

    private func mergeHorizontalLineFragments(lines: [TextLine]) -> [TextLine] {
        guard !lines.isEmpty else { return [] }
        var merged: [TextLine] = []
        var current = lines[0]

        for i in 1..<lines.count {
            let next = lines[i]
            let isSameRow = abs(current.bbox.midY - next.bbox.midY) < 3.0
            let hGap = next.bbox.minX - current.bbox.maxX

            // If on the same row and the next line starts to the right within reasonable inline spacing
            if isSameRow && hGap >= -3.0 && hGap <= 25.0 {
                var newChars = current.characters
                let lastChar = current.characters.last
                let firstNextChar = next.characters.first
                let avgSize = CGFloat(((lastChar?.size ?? 10.0) + (firstNextChar?.size ?? 10.0)) / 2.0)

                // Add space character if there is a noticeable gap and neither character is whitespace
                if hGap > avgSize * 0.18 && lastChar?.char != " " && firstNextChar?.char != " " {
                    let spaceQuad = PDFQuad(
                        ul: CGPoint(x: current.bbox.maxX, y: current.bbox.minY),
                        ur: CGPoint(x: next.bbox.minX, y: current.bbox.minY),
                        ll: CGPoint(x: current.bbox.maxX, y: current.bbox.maxY),
                        lr: CGPoint(x: next.bbox.minX, y: current.bbox.maxY)
                    )
                    let isUnderline = (lastChar?.isUnderline == true) && (firstNextChar?.isUnderline == true)
                    let isStrikethrough = (lastChar?.isStrikethrough == true) && (firstNextChar?.isStrikethrough == true)
                    let spaceChar = TextCharacter(
                        char: " ",
                        quad: spaceQuad,
                        origin: CGPoint(x: current.bbox.maxX, y: current.bbox.maxY),
                        size: Float(avgSize),
                        isBold: lastChar?.isBold ?? false,
                        isItalic: lastChar?.isItalic ?? false,
                        isUnderline: isUnderline,
                        isStrikethrough: isStrikethrough,
                        fontName: lastChar?.fontName ?? "",
                        color: lastChar?.color ?? 0xFF000000
                    )
                    newChars.append(spaceChar)
                }
                newChars.append(contentsOf: next.characters)
                current = TextLine(bbox: current.bbox.union(next.bbox), characters: newChars)
            } else {
                merged.append(current)
                current = next
            }
        }
        merged.append(current)
        return merged
    }

    private func isMarginLineNumber(_ line: TextLine, leftMargin: CGFloat, rightMargin: CGFloat) -> Bool {
        let isNumericOrPunct = line.characters.allSatisfy { ch in
            ch.char.isNumber || ch.char.isWhitespace || ch.char == "." || ch.char == ":" || ch.char == "-" || ch.char == "—"
        }
        guard isNumericOrPunct else { return false }
        // Line numbers are narrow and located in left or right margin gutters
        if line.bbox.width < 40 && (line.bbox.maxX <= leftMargin + 8 || line.bbox.minX >= rightMargin - 8) {
            return true
        }
        return false
    }

    private func reconstructParagraphsAndHeadings(lines: [TextLine], baseFontSize: Float, pageWidth: CGFloat) -> [PDFLayoutElement] {
        guard !lines.isEmpty else { return [] }

        // 0. Merge horizontally adjacent line fragments on the same visual row
        let mergedLines = mergeHorizontalLineFragments(lines: lines)

        // 1. Calculate the modal vertical line pitch (top-to-top line leading)
        var pitches: [CGFloat] = []
        for i in 0..<(mergedLines.count - 1) {
            let pitch = mergedLines[i + 1].bbox.minY - mergedLines[i].bbox.minY
            if pitch >= 6.0 && pitch <= 35.0 {
                pitches.append(round(pitch * 2.0) / 2.0)
            }
        }
        let modalPitch: CGFloat
        if !pitches.isEmpty {
            var freq: [CGFloat: Int] = [:]
            for p in pitches { freq[p, default: 0] += 1 }
            modalPitch = freq.max(by: { $0.value < $1.value })?.key ?? 12.0
        } else {
            modalPitch = 12.0
        }

        // 2. Group consecutive lines into cohesive paragraph blocks
        var paragraphBlocks: [[TextLine]] = []
        var currentBlock: [TextLine] = []

        for line in mergedLines {
            if let prev = currentBlock.last {
                let pitch = line.bbox.minY - prev.bbox.minY

                // Check typography properties
                let prevSize = prev.characters.first?.size ?? baseFontSize
                let currSize = line.characters.first?.size ?? baseFontSize
                let sizeDiff = abs(currSize - prevSize)

                let isPrevHeading = prevSize >= (baseFontSize * 1.25)
                let isCurrHeading = currSize >= (baseFontSize * 1.25)
                let isListStart = isListMarker(line.text.trimmingCharacters(in: .whitespaces))
                let isPrevToC = isToCEntry(prev.text)

                // Sentence break heuristic: prev line ended with [.!?], is noticeably short, and next starts with capital
                let trimmedPrev = prev.text.trimmingCharacters(in: .whitespaces)
                let endsSentence = trimmedPrev.hasSuffix(".") || trimmedPrev.hasSuffix("!") || trimmedPrev.hasSuffix("?")
                let prevIsShort = prev.bbox.width < (pageWidth * 0.45)
                let firstChar = line.text.trimmingCharacters(in: .whitespaces).first
                let startsWithCap = firstChar?.isUppercase == true

                let shouldBreakSentence = endsSentence && prevIsShort && startsWithCap

                // Normal vertical continuation: pitch is within 0.70x to 1.45x modal leading
                let isNormalPitch = (pitch >= modalPitch * 0.70) && (pitch <= modalPitch * 1.45)
                let isCompatibleType = (sizeDiff <= 1.0) && (!isPrevHeading && !isCurrHeading) && !isListStart && !shouldBreakSentence && !isPrevToC

                if isNormalPitch && isCompatibleType {
                    currentBlock.append(line)
                } else {
                    paragraphBlocks.append(currentBlock)
                    currentBlock = [line]
                }
            } else {
                currentBlock = [line]
            }
        }
        if !currentBlock.isEmpty {
            paragraphBlocks.append(currentBlock)
        }

        // 3. Convert each block of lines into a reflowable Paragraph or Heading element
        var elements: [PDFLayoutElement] = []
        var prevBottomY: CGFloat = 0

        for block in paragraphBlocks {
            guard let firstLine = block.first else { continue }
            let blockBox = block.map { $0.bbox }.reduce(firstLine.bbox) { $0.union($1) }

            let avgBlockSize = block.flatMap { $0.characters }.map { $0.size }.reduce(0, +) / Float(max(1, block.flatMap { $0.characters }.count))
            // Heading requires every visible character to be bold.
            let isBoldHeading = block.allSatisfy { line in
                let visible = line.characters.filter { !$0.char.isWhitespace }
                return !visible.isEmpty && visible.allSatisfy { $0.isBold }
            }

            let isToC = isToCEntry(block.map(\.text).joined())
            let isH1 = (avgBlockSize >= (baseFontSize * 1.35)) && !isToC
            let isH2 = ((avgBlockSize >= (baseFontSize * 1.18) && avgBlockSize < (baseFontSize * 1.35)) || (isBoldHeading && block.count <= 2)) && !isToC

            // Spacing before / after calculation (1 pt = 20 twips)
            let rawSpaceBefore = prevBottomY > 0 ? max(0, blockBox.minY - prevBottomY) : 0
            let spaceBeforeTwips = min(360, Int(round(rawSpaceBefore * 20.0)))
            let spaceAfterTwips = isH1 ? 160 : (isH2 ? 120 : 80)
            prevBottomY = blockBox.maxY

            // Assemble runs with hyphen removal and clean word spacing across lines
            let runs = assembleRuns(for: block)

            if isH1 {
                elements.append(.heading(level: 1, runs: runs, bbox: blockBox, spaceBefore: max(240, spaceBeforeTwips), spaceAfter: spaceAfterTwips))
            } else if isH2 {
                elements.append(.heading(level: 2, runs: runs, bbox: blockBox, spaceBefore: max(180, spaceBeforeTwips), spaceAfter: spaceAfterTwips))
            } else {
                // Determine horizontal alignment and indentation
                let leftIndent = Int(round(max(0, blockBox.minX - 54.0) * 20.0)) // relative to page margin ~54pt
                let firstLineOffset = Int(round((firstLine.bbox.minX - blockBox.minX) * 20.0))

                var alignment: LayoutAlignment = .left
                let pageMidX = pageWidth / 2.0
                if abs(blockBox.midX - pageMidX) < 15.0 && blockBox.width < (pageWidth * 0.6) {
                    alignment = .center
                }

                elements.append(.paragraph(
                    runs: runs,
                    bbox: blockBox,
                    spaceBefore: spaceBeforeTwips,
                    spaceAfter: spaceAfterTwips,
                    leftIndent: leftIndent,
                    firstLineIndent: firstLineOffset,
                    alignment: alignment
                ))
            }
        }

        return elements
    }

    /// Assembles runs across multiple lines in a paragraph, removing trailing hyphens and ensuring clean word spacing.
    private func assembleRuns(for lines: [TextLine]) -> [TextRun] {
        var runs: [TextRun] = []

        for (lIdx, line) in lines.enumerated() {
            var lineRuns = line.runs
            guard !lineRuns.isEmpty else { continue }

            let isLastLine = (lIdx == lines.count - 1)

            if !isLastLine {
                // Check if line ends with a hyphen and next line starts with lowercase
                let nextFirstChar = lines[lIdx + 1].text.trimmingCharacters(in: .whitespaces).first
                let lastRunIdx = lineRuns.count - 1
                let lastRunText = lineRuns[lastRunIdx].text

                if lastRunText.hasSuffix("-") && nextFirstChar?.isLowercase == true {
                    // Strip the trailing hyphen: word joins seamlessly
                    let stripped = String(lastRunText.dropLast())
                    let r = lineRuns[lastRunIdx]
                    lineRuns[lastRunIdx] = TextRun(text: stripped, isBold: r.isBold, isItalic: r.isItalic, isUnderline: r.isUnderline, isStrikethrough: r.isStrikethrough, size: r.size, fontName: r.fontName, colorHex: r.colorHex)
                } else if !lastRunText.hasSuffix(" ") {
                    // Append a single space between wrapped lines
                    let r = lineRuns[lastRunIdx]
                    lineRuns[lastRunIdx] = TextRun(text: lastRunText + " ", isBold: r.isBold, isItalic: r.isItalic, isUnderline: r.isUnderline, isStrikethrough: r.isStrikethrough, size: r.size, fontName: r.fontName, colorHex: r.colorHex)
                }
            }

            runs.append(contentsOf: lineRuns)
        }

        return runs
    }

    // MARK: - ToC and List Marker Utilities

    private func isToCEntry(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        return t.range(of: #"\.{3,}\s*(\d+|[ivxlcdmIVXLCDM]+)$"#, options: .regularExpression) != nil
    }

    private func isListMarker(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }

        // Standalone bullets: •, -, –, —, *, o
        if t == "•" || t == "-" || t == "–" || t == "—" || t == "*" || t == "o" || t == "▪" || t == "▫" {
            return true
        }

        // Bullet at start of line: "• ", "— ", "– ", "- ", "* "
        if t.hasPrefix("• ") || t.hasPrefix("— ") || t.hasPrefix("– ") || t.hasPrefix("- ") || t.hasPrefix("* ") {
            return true
        }

        // Regex patterns for numbered lists: "1.", "1.1", "1.1.1", "(1)", "1)", "a.", "a)", "(a)", "A.", "I.", "iv."
        let standalonePattern = #"^(\d+(\.\d+)*\.?|\([0-9a-zA-Z]+\)|[0-9a-zA-Z]+[.)])$"#
        if t.range(of: standalonePattern, options: .regularExpression) != nil {
            return true
        }

        let prefixPattern = #"^(\d+\.|\d+(\.\d+)+\.?|\([0-9a-zA-Z]+\)|[0-9a-zA-Z]+[.)])\s+"#
        return t.range(of: prefixPattern, options: .regularExpression) != nil
    }

    // MARK: - Multi-Page Table Stitching

    /// Merges continuing tables across page breaks (e.g. Table 9-87 across pages 16-19) into unified tables,
    /// removing duplicate header rows and artificial "(continued)" headings.
    public func stitchContinuingTables(pages: inout [[PDFLayoutElement]]) {
        guard pages.count >= 2 else { return }

        // Track the currently active table that might continue onto subsequent pages
        var activeTablePageIdx: Int? = nil
        var activeTableElemIdx: Int? = nil

        for p in 0..<pages.count {
            var elemIdx = 0
            while elemIdx < pages[p].count {
                guard case .table(let currentTable) = pages[p][elemIdx] else {
                    elemIdx += 1
                    continue
                }

                // Check if currentTable is a continuation of the active table from the preceding page.
                let isFirstTableOnPage = !pages[p][..<elemIdx].contains { if case .table = $0 { return true } else { return false } }
                if let aPage = activeTablePageIdx, let aElem = activeTableElemIdx, aPage == p - 1, isFirstTableOnPage {
                    if case .table(let prevTable) = pages[aPage][aElem] {
                        let isMatch = areTablesContinuing(prev: prevTable, next: currentTable, onNextPage: pages[p], tableElemIdx: elemIdx)
                        if isMatch {
                            // Check if next table repeated the header row
                            let prevHeader = prevTable.rows.first?.cells.map(\.text).joined() ?? ""
                            let nextHeader = currentTable.rows.first?.cells.map(\.text).joined() ?? ""
                            let headerMatches = !prevHeader.isEmpty && prevHeader == nextHeader

                            let rowsToAppend: [LayoutRow]
                            if headerMatches && currentTable.rows.count > 1 {
                                rowsToAppend = Array(currentTable.rows.dropFirst())
                            } else if headerMatches {
                                rowsToAppend = []
                            } else {
                                rowsToAppend = currentTable.rows
                            }

                            var mergedRows = prevTable.rows
                            mergedRows.append(contentsOf: rowsToAppend)

                            let mergedTable = LayoutTable(
                                bbox: prevTable.bbox.union(currentTable.bbox),
                                rows: mergedRows,
                                colWidths: prevTable.colWidths,
                                isLattice: prevTable.isLattice || currentTable.isLattice
                            )

                            // Update active table with newly merged rows
                            pages[aPage][aElem] = .table(table: mergedTable)

                            // Remove continuation heading preceding currentTable if present
                            for i in (0..<elemIdx).reversed() {
                                if case .heading(_, let runs, _, _, _) = pages[p][i] {
                                    let hText = runs.map(\.text).joined()
                                    if hText.localizedCaseInsensitiveContains("continued") || hText.localizedCaseInsensitiveContains("cont.") {
                                        pages[p].remove(at: i)
                                        elemIdx -= 1
                                        break
                                    }
                                }
                            }

                            // Remove currentTable from page p
                            pages[p].remove(at: elemIdx)
                            // Continue checking remaining elements on page p without incrementing elemIdx
                            continue
                        }
                    }
                }

                // Current table becomes the candidate active table.
                activeTablePageIdx = p
                activeTableElemIdx = elemIdx
                elemIdx += 1
            }
        }
    }

    private func areTablesContinuing(prev: LayoutTable, next: LayoutTable, onNextPage: [PDFLayoutElement], tableElemIdx: Int) -> Bool {
        // 1. Column count must match
        guard prev.colWidths.count == next.colWidths.count else { return false }

        // 2. Column widths must be very similar (within 15 pt total difference)
        var widthDiff: CGFloat = 0
        for c in 0..<prev.colWidths.count {
            widthDiff += abs(prev.colWidths[c] - next.colWidths[c])
        }
        guard widthDiff < 15.0 else { return false }

        // 3. Check for "(continued)" heading preceding next table
        for i in 0..<tableElemIdx {
            if case .heading(_, let runs, _, _, _) = onNextPage[i] {
                let text = runs.map(\.text).joined()
                if text.localizedCaseInsensitiveContains("continued") || text.localizedCaseInsensitiveContains("cont.") {
                    return true
                }
            }
        }

        // 4. Or check if header row matches
        let prevHeader = prev.rows.first?.cells.map(\.text).joined() ?? ""
        let nextHeader = next.rows.first?.cells.map(\.text).joined() ?? ""
        if !prevHeader.isEmpty && prevHeader == nextHeader {
            return true
        }

        return false
    }
}
