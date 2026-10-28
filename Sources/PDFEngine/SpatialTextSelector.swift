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
import CoreGraphics
import Synchronization

public enum SelectionMode: String, Sendable, CaseIterable, Identifiable {
    case readingOrder = "Text"
    case rectangularArea = "Area"
    
    public var id: String { rawValue }
}

public struct SelectionResult: Sendable, Equatable {
    public let text: String
    public let highlightQuads: [PDFQuad]
    public let boundingRect: CGRect
    public let mode: SelectionMode
    
    public init(text: String, highlightQuads: [PDFQuad], boundingRect: CGRect = .zero, mode: SelectionMode = .readingOrder) {
        self.text = text
        self.highlightQuads = highlightQuads
        self.boundingRect = boundingRect
        self.mode = mode
    }
}

/// One page's slice of a selection that spans more than one page — e.g. dragging from partway
/// down page 3 into page 4. `PDFViewerViewModel.activeSelection` always holds the *first* (by
/// page number) slice, matching every existing single-page consumer unchanged; any further pages
/// are tracked separately in `additionalSelectionPages` purely for on-screen highlighting and for
/// combining the full selected text (see PDFViewerViewModel.activeSelectionCombinedText).
public struct PageSelectionResult: Sendable, Equatable {
    public let pageIndex: Int
    public let result: SelectionResult

    public init(pageIndex: Int, result: SelectionResult) {
        self.pageIndex = pageIndex
        self.result = result
    }
}

public struct TextPosition: Comparable, Sendable, Equatable {
    public let blockIndex: Int
    public let lineIndex: Int
    public let charIndex: Int
    
    public init(blockIndex: Int, lineIndex: Int, charIndex: Int) {
        self.blockIndex = blockIndex
        self.lineIndex = lineIndex
        self.charIndex = charIndex
    }
    
    public static func < (lhs: TextPosition, rhs: TextPosition) -> Bool {
        if lhs.blockIndex != rhs.blockIndex {
            return lhs.blockIndex < rhs.blockIndex
        }
        if lhs.lineIndex != rhs.lineIndex {
            return lhs.lineIndex < rhs.lineIndex
        }
        return lhs.charIndex < rhs.charIndex
    }
}

public final class SpatialTextSelector: Sendable {
    /// Minimum width for a text block to plausibly be body text, excluding narrow line-number gutters or margin annotations.
    public static let minColumnWidth: CGFloat = 60.0
    /// Horizontal gutter threshold when testing multi-column bounds.
    public static let gutterThreshold: CGFloat = 20.0

    public init() {}

    /// Ruled tables found per page. Selecting runs on every mouse move while dragging, and
    /// finding tables means walking the page's vector paths, so the last few pages' are kept.
    private let tableCache = Mutex<[PageFingerprint: [LayoutTable]]>([:])

    private struct PageFingerprint: Hashable {
        let pageIndex: Int, blockCount: Int, lineCount: Int, bounds: [CGFloat]
        init(_ page: StructuredPage) {
            pageIndex = page.pageIndex
            blockCount = page.blocks.count
            lineCount = page.blocks.reduce(0) { $0 + $1.lines.count }
            bounds = [page.bounds.width, page.bounds.height] + (page.blocks.first.map { [$0.bbox.minX, $0.bbox.minY] } ?? [])
        }
    }

    /// The page's tables with ruled borders (lattice tables). Borderless "stream" tables aren't
    /// used here: columns of ordinary text line up much like them.
    private func ruledTables(on page: StructuredPage) -> [LayoutTable] {
        let key = PageFingerprint(page)
        if let cached = tableCache.withLock({ $0[key] }) { return cached }
        let tables = PDFLayoutEngine().detectRuledTables(in: page)
        tableCache.withLock { cache in
            if cache.count >= 8 { cache.removeAll() }
            cache[key] = tables
        }
        return tables
    }
    
    /// Selects text on a StructuredPage between startPoint and endPoint, supporting both reading order flow and rectangular marquee
    public func selectText(
        on page: StructuredPage,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        mode: SelectionMode = .readingOrder
    ) -> SelectionResult {
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        guard !textBlocks.isEmpty else {
            return SelectionResult(text: "", highlightQuads: [], boundingRect: .zero, mode: mode)
        }
        
        switch mode {
        case .rectangularArea:
            return selectRectangularArea(on: textBlocks, from: startPoint, to: endPoint)
        case .readingOrder:
            return selectReadingOrder(on: textBlocks, tables: ruledTables(on: page), from: startPoint, to: endPoint)
        }
    }
    
    // MARK: - Reading Flow Selection

    /// One line's part of a selection.
    private struct SelectedSlice {
        let quad: PDFQuad
        let lineBBox: CGRect
        let sliceBBox: CGRect
        let text: String
        /// Right edge of the line's block: a line reaching it is wrapped, not the end of a paragraph.
        let blockMaxX: CGFloat
        /// Where the line sits when it is inside a ruled table.
        let cell: TableCell?
    }

    private struct TableCell: Equatable {
        let table: Int, row: Int, column: Int
        func sameRow(_ other: TableCell) -> Bool { table == other.table && row == other.row }
    }

    /// Characters as text, with a space wherever the PDF left a word gap instead of writing one.
    static func text(of characters: [TextCharacter]) -> String {
        var text = ""
        for (i, ch) in characters.enumerated() {
            text.append(ch.char)
            if i + 1 < characters.count, ch.hasWordGap(before: characters[i + 1]) { text.append(" ") }
        }
        return text
    }

    /// The text and highlight for characters `from..<to` of `line`, or nil if that's empty.
    private func makeSlice(_ line: TextLine, from fromChar: Int, to toChar: Int, blockMaxX: CGFloat, cell: TableCell?) -> SelectedSlice? {
        let validFrom = max(0, min(fromChar, line.characters.count))
        let validTo = max(validFrom, min(toChar, line.characters.count))
        guard validFrom < validTo else { return nil }

        let sliceChars = Array(line.characters[validFrom..<validTo])
        guard let firstChar = sliceChars.first, let lastChar = sliceChars.last else { return nil }

        // Continuous line quad covering words and spaces seamlessly
        let lineQuad = PDFQuad(
            ul: CGPoint(x: firstChar.boundingRect.minX, y: line.bbox.minY),
            ur: CGPoint(x: lastChar.boundingRect.maxX, y: line.bbox.minY),
            ll: CGPoint(x: firstChar.boundingRect.minX, y: line.bbox.maxY),
            lr: CGPoint(x: lastChar.boundingRect.maxX, y: line.bbox.maxY)
        )

        // Assemble line text with inter-word spacing
        let sliceText = Self.text(of: sliceChars)

        return SelectedSlice(quad: lineQuad, lineBBox: line.bbox, sliceBBox: lineQuad.boundingRect,
                             text: sliceText, blockMaxX: blockMaxX, cell: cell)
    }

    /// The ruled-table cell containing `rect`'s centre, if any.
    private func tableCell(of rect: CGRect, in tables: [LayoutTable]) -> TableCell? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for (t, table) in tables.enumerated() where table.bbox.contains(center) {
            for (r, row) in table.rows.enumerated() where row.bbox.minY - 1 <= center.y && center.y <= row.bbox.maxY + 1 {
                let column = row.cells.firstIndex { $0.bbox.minX - 1 <= center.x && center.x <= $0.bbox.maxX + 1 }
                return TableCell(table: t, row: r, column: column ?? 0)
            }
        }
        return nil
    }

    /// Puts slices in reading order: row by row, except that the lines of a ruled table are read
    /// cell by cell along each of its rows (a cell's second line before the next cell).
    private func ordered(_ slices: [SelectedSlice]) -> [SelectedSlice] {
        var items: [(frame: CGRect, slices: [SelectedSlice])] = []
        var tableItem: [Int: Int] = [:]
        for slice in slices {
            guard let cell = slice.cell else {
                items.append((slice.lineBBox, [slice]))
                continue
            }
            if let i = tableItem[cell.table] {
                items[i].frame = items[i].frame.union(slice.lineBBox)
                items[i].slices.append(slice)
            } else {
                tableItem[cell.table] = items.count
                items.append((slice.lineBBox, [slice]))
            }
        }
        for i in tableItem.values {
            items[i].slices.sort { a, b in
                let (ca, cb) = (a.cell!, b.cell!)
                if ca.row != cb.row { return ca.row < cb.row }
                if ca.column != cb.column { return ca.column < cb.column }
                return abs(a.lineBBox.midY - b.lineBBox.midY) > 3 ? a.lineBBox.midY < b.lineBBox.midY : a.lineBBox.minX < b.lineBBox.minX
            }
        }
        return readingOrder(items) { $0.frame }.flatMap(\.slices)
    }

    /// When a selection runs from one column of text into another (as opposed to across a table
    /// or along a line), the lines it covers in reading order: the rest of the first column, any
    /// columns between, then the last column down to the end. A column ends at text spanning both
    /// columns, such as a full-width heading — the ordering rule of Breuel's layout analysis.
    /// Nil when the selection doesn't cross columns.
    private func crossColumnSlices(
        textBlocks: [TextBlock], tables: [LayoutTable], pos1: TextPosition, pos2: TextPosition,
        isLineNumber: (TextLine) -> Bool
    ) -> [SelectedSlice]? {
        let block1 = textBlocks[pos1.blockIndex], block2 = textBlocks[pos2.blockIndex]
        func isColumnText(_ block: TextBlock) -> Bool {
            block.bbox.width >= Self.minColumnWidth * 2 && tableCell(of: block.bbox, in: tables) == nil
        }
        guard isColumnText(block1), isColumnText(block2),
              block1.bbox.maxX <= block2.bbox.minX || block2.bbox.maxX <= block1.bbox.minX else { return nil }

        // Read the left column first, whichever end the drag started from.
        let (firstPos, lastPos) = block1.bbox.minX < block2.bbox.minX ? (pos1, pos2) : (pos2, pos1)
        let left = textBlocks[firstPos.blockIndex].bbox, right = textBlocks[lastPos.blockIndex].bbox
        let firstLine = textBlocks[firstPos.blockIndex].lines[firstPos.lineIndex]
        let lastLine = textBlocks[lastPos.blockIndex].lines[lastPos.lineIndex]

        func overlapsX(_ a: CGRect, _ b: CGRect) -> Bool { min(a.maxX, b.maxX) > max(a.minX, b.minX) }
        let spanning = textBlocks.filter { overlapsX($0.bbox, left) && overlapsX($0.bbox, right) }
        let regionBottom = spanning.filter { $0.bbox.minY >= firstLine.bbox.maxY - 1 }.map(\.bbox.minY).min() ?? .infinity
        let regionTop = spanning.filter { $0.bbox.maxY <= lastLine.bbox.minY + 1 }.map(\.bbox.maxY).max() ?? -.infinity

        // The columns from the left one to the right one: blocks between them, grouped by overlap.
        var columns: [(range: ClosedRange<CGFloat>, blocks: [Int])] = []
        let between = textBlocks.indices
            .filter { idx in
                let bbox = textBlocks[idx].bbox
                return bbox.midX >= left.minX && bbox.midX <= right.maxX && !(overlapsX(bbox, left) && overlapsX(bbox, right))
            }
            .sorted { textBlocks[$0].bbox.minX < textBlocks[$1].bbox.minX }
        for idx in between {
            let bbox = textBlocks[idx].bbox
            if let last = columns.indices.last, bbox.minX < columns[last].range.upperBound {
                columns[last].range = columns[last].range.lowerBound...max(columns[last].range.upperBound, bbox.maxX)
                columns[last].blocks.append(idx)
            } else {
                columns.append((bbox.minX...bbox.maxX, [idx]))
            }
        }

        var result: [SelectedSlice] = []
        for column in columns {
            let isFirst = column.blocks.contains(firstPos.blockIndex)
            let isLast = column.blocks.contains(lastPos.blockIndex)
            var slices: [SelectedSlice] = []
            for bIdx in column.blocks {
                let block = textBlocks[bIdx]
                for (lIdx, line) in block.lines.enumerated() where !line.characters.isEmpty && !isLineNumber(line) {
                    let midY = line.bbox.midY
                    let top = isFirst ? firstLine.bbox.midY - 1 : regionTop
                    let bottom = isLast ? lastLine.bbox.midY + 1 : regionBottom
                    guard midY > top, midY < bottom else { continue }
                    let from = (bIdx == firstPos.blockIndex && lIdx == firstPos.lineIndex) ? firstPos.charIndex : 0
                    let to = (bIdx == lastPos.blockIndex && lIdx == lastPos.lineIndex) ? lastPos.charIndex : line.characters.count
                    if let slice = makeSlice(line, from: from, to: to, blockMaxX: block.bbox.maxX, cell: tableCell(of: line.bbox, in: tables)) {
                        slices.append(slice)
                    }
                }
            }
            result += ordered(slices)
        }
        return result.isEmpty ? nil : result
    }

    private func selectReadingOrder(on textBlocks: [TextBlock], tables: [LayoutTable], from startPoint: CGPoint, to endPoint: CGPoint) -> SelectionResult {
        guard let pos1 = resolvePosition(at: startPoint, in: textBlocks),
              let pos2 = resolvePosition(at: endPoint, in: textBlocks) else {
            return SelectionResult(text: "", highlightQuads: [], boundingRect: .zero, mode: .readingOrder)
        }

        if pos1 == pos2 {
            return SelectionResult(text: "", highlightQuads: [], boundingRect: .zero, mode: .readingOrder)
        }

        // The page's left text margin, measured from its lines: MuPDF often puts a margin line
        // number in the same block as the body line beside it, so the check by block below
        // misses those. Only numbers left of all the page's text count, so a table's numeric
        // first column (an Order column, say) is kept.
        let isPageLineNumber = Self.lineNumberTest(for: textBlocks.flatMap(\.lines))

        var slices: [SelectedSlice]
        if let crossColumn = crossColumnSlices(textBlocks: textBlocks, tables: tables, pos1: pos1, pos2: pos2, isLineNumber: isPageLineNumber) {
            slices = crossColumn
        } else {
            slices = bandSlices(textBlocks: textBlocks, tables: tables, pos1: pos1, pos2: pos2, isLineNumber: isPageLineNumber)
            slices = ordered(slices)
        }

        // Rows of widely spaced text (double spacing, say) are as far apart as paragraphs are in
        // ordinary text. The usual gap between this selection's lines tells the two apart.
        let downwardGaps = zip(slices, slices.dropFirst()).compactMap { a, b -> CGFloat? in
            guard a.cell == nil, b.cell == nil, abs(a.lineBBox.midY - b.lineBBox.midY) >= 3 else { return nil }
            let gap = b.lineBBox.minY - a.lineBBox.maxY
            return gap > 0 ? gap : nil
        }.sorted()
        let usualGap = downwardGaps.count >= 2 ? downwardGaps[downwardGaps.count / 2] : nil

        var selectedQuads: [PDFQuad] = []
        var selectedText = ""
        var overallBoundingBox = CGRect.null
        for (idx, slice) in slices.enumerated() {
            selectedQuads.append(slice.quad)
            overallBoundingBox = overallBoundingBox.union(slice.sliceBBox)
            selectedText.append(slice.text)
            guard idx < slices.count - 1 else { continue }
            let next = slices[idx + 1]

            if let cell = slice.cell, let nextCell = next.cell, cell != nextCell {
                // Between cells of a ruled table: tabs along a row, a line break between rows,
                // so the text pastes into a spreadsheet or word processor as a table.
                selectedText.append(cell.sameRow(nextCell) ? "\t" : "\n")
                continue
            }
            if (slice.cell == nil) != (next.cell == nil) {
                selectedText.append("\n")   // into or out of a table
                continue
            }

            if abs(slice.lineBBox.midY - next.lineBBox.midY) < 3.0 {
                let hGap = next.sliceBBox.minX - slice.sliceBBox.maxX
                if hGap > 1.0 && !slice.text.hasSuffix(" ") && !next.text.hasPrefix(" ") {
                    selectedText.append(" ")
                }
                continue
            }
            if next.lineBBox.minY < slice.lineBBox.minY {
                selectedText.append("\n")   // up to the top of the next column
                continue
            }

            let vGap = next.lineBBox.minY - slice.lineBBox.maxY
            let avgH = (slice.lineBBox.height + next.lineBBox.height) / 2.0
            let reachesRightEdge = slice.lineBBox.maxX >= slice.blockMaxX - slice.lineBBox.height * 1.5
            let isUsualSpacing = usualGap.map { vGap <= $0 * 1.25 + 1 } ?? false
            if vGap > avgH * 0.75 && !(isUsualSpacing && reachesRightEdge) {
                selectedText.append("\n")
            } else {
                switch LineJoin(slice.text, next.text) {
                case .wordBreak:
                    while selectedText.last?.isWhitespace == true { selectedText.removeLast() }
                    selectedText.removeLast()
                case .hyphen:
                    while selectedText.last?.isWhitespace == true { selectedText.removeLast() }
                case .space:
                    if !slice.text.hasSuffix(" ") && !next.text.hasPrefix(" ") { selectedText.append(" ") }
                }
            }
        }

        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SelectionResult(
            text: trimmed,
            highlightQuads: selectedQuads,
            boundingRect: overallBoundingBox.isNull ? .zero : overallBoundingBox,
            mode: .readingOrder
        )
    }

    /// The lines in the horizontal band from the start of a selection to its end, within the
    /// selection's column — the usual case, a selection running down a column or along a line.
    private func bandSlices(
        textBlocks: [TextBlock], tables: [LayoutTable], pos1: TextPosition, pos2: TextPosition,
        isLineNumber: (TextLine) -> Bool
    ) -> [SelectedSlice] {
        // Order endpoints by page geometry (Y, then X) rather than block index.
        let line1 = textBlocks[pos1.blockIndex].lines[pos1.lineIndex]
        let line2 = textBlocks[pos2.blockIndex].lines[pos2.lineIndex]
        let pos1IsFirst: Bool
        if abs(line1.bbox.midY - line2.bbox.midY) > 2 {
            pos1IsFirst = line1.bbox.midY < line2.bbox.midY
        } else if pos1.blockIndex == pos2.blockIndex && pos1.lineIndex == pos2.lineIndex {
            pos1IsFirst = pos1.charIndex < pos2.charIndex
        } else {
            pos1IsFirst = line1.bbox.minX < line2.bbox.minX
        }
        let firstPos = pos1IsFirst ? pos1 : pos2
        let lastPos = pos1IsFirst ? pos2 : pos1

        var slices: [SelectedSlice] = []

        // Snap vertical band to line boundaries.
        let firstLine = textBlocks[firstPos.blockIndex].lines[firstPos.lineIndex]
        let lastLine = textBlocks[lastPos.blockIndex].lines[lastPos.lineIndex]
        let bandMinY = min(firstLine.bbox.minY, lastLine.bbox.minY)
        let bandMaxY = max(firstLine.bbox.maxY, lastLine.bbox.maxY)

        // The selection's column: the horizontal span of the blocks it starts and ends in.
        let startBlock = textBlocks[firstPos.blockIndex]
        let endBlock = textBlocks[lastPos.blockIndex]
        let spanMinX = min(startBlock.bbox.minX, endBlock.bbox.minX)
        let spanMaxX = max(startBlock.bbox.maxX, endBlock.bbox.maxX)
        func isOutsideSpan(_ block: TextBlock) -> Bool {
            let overlapWidth = min(block.bbox.maxX, spanMaxX) - max(block.bbox.minX, spanMinX)
            return block.bbox.width <= 0 || overlapWidth / block.bbox.width < 0.5
        }

        // Blocks overlapping the vertical band.
        let rowBlocks = textBlocks.enumerated().filter { _, block in
            let overlap = min(block.bbox.maxY, bandMaxY) - max(block.bbox.minY, bandMinY)
            return overlap > 1.0 || (block.bbox.midY >= bandMinY && block.bbox.midY <= bandMaxY)
        }
        // Another column of text beside these rows. Narrow blocks outside the span (list bullets,
        // the terms of a definition list, line numbers) are part of the text being selected.
        let isMultiColumn = rowBlocks.contains { _, block in block.bbox.width >= Self.minColumnWidth * 2 && isOutsideSpan(block) }
        let bandBlocks = rowBlocks
            .filter { bIdx, block in
                !isMultiColumn || bIdx == firstPos.blockIndex || bIdx == lastPos.blockIndex || !isOutsideSpan(block)
            }
            .sorted { $0.element.bbox.minY < $1.element.bbox.minY }

        for (bIdx, block) in bandBlocks {
            let isFirstBlock = (bIdx == firstPos.blockIndex)
            let isLastBlock = (bIdx == lastPos.blockIndex)

            for lIdx in 0..<block.lines.count {
                // Use line indices directly for boundary blocks to avoid ascender/descender overlap errors.
                if isFirstBlock && lIdx < firstPos.lineIndex { continue }
                if isLastBlock && lIdx > lastPos.lineIndex { continue }

                let line = block.lines[lIdx]
                guard !line.characters.isEmpty else { continue }
                if isLineNumber(line) { continue }
                // Verify intermediate lines fall within the vertical band.
                if !isFirstBlock && !isLastBlock {
                    let lineOverlap = min(line.bbox.maxY, bandMaxY) - max(line.bbox.minY, bandMinY)
                    guard (line.bbox.midY >= bandMinY && line.bbox.midY <= bandMaxY) || lineOverlap >= min(line.bbox.height * 0.4, 4.0) else { continue }
                }

                let isFirstSelectedLine = (isFirstBlock && lIdx == firstPos.lineIndex)
                let isLastSelectedLine = (isLastBlock && lIdx == lastPos.lineIndex)
                let fromChar = isFirstSelectedLine ? firstPos.charIndex : 0
                let toChar = isLastSelectedLine ? lastPos.charIndex : line.characters.count
                if let slice = makeSlice(line, from: fromChar, to: toChar, blockMaxX: block.bbox.maxX,
                                         cell: tableCell(of: line.bbox, in: tables)) {
                    slices.append(slice)
                }
            }
        }
        return slices
    }

    // MARK: - Rectangular Area Selection
    private func selectRectangularArea(on textBlocks: [TextBlock], from startPoint: CGPoint, to endPoint: CGPoint) -> SelectionResult {
        let minX = min(startPoint.x, endPoint.x)
        let maxX = max(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let maxY = max(startPoint.y, endPoint.y)
        let selRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        
        guard selRect.width > 2 && selRect.height > 2 else {
            return SelectionResult(text: "", highlightQuads: [], boundingRect: selRect, mode: .rectangularArea)
        }
        
        // Single crisp rectangular quad for the marquee area
        let areaQuad = PDFQuad(
            ul: CGPoint(x: minX, y: minY),
            ur: CGPoint(x: maxX, y: minY),
            ll: CGPoint(x: minX, y: maxY),
            lr: CGPoint(x: maxX, y: maxY)
        )
        
        var linesText: [String] = []
        for block in textBlocks where block.bbox.intersects(selRect) {
            for line in block.lines where line.bbox.intersects(selRect) {
                let charsInRect = line.characters.filter {
                    let b = $0.boundingRect
                    return selRect.contains(CGPoint(x: b.midX, y: b.midY)) || selRect.intersects(b)
                }
                if !charsInRect.isEmpty {
                    linesText.append(Self.text(of: charsInRect))
                }
            }
        }
        
        let text = linesText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return SelectionResult(
            text: text,
            highlightQuads: [areaQuad],
            boundingRect: selRect,
            mode: .rectangularArea
        )
    }
    
    // MARK: - Position Resolution
    private func resolvePosition(at point: CGPoint, in textBlocks: [TextBlock]) -> TextPosition? {
        guard !textBlocks.isEmpty else { return nil }

        var bestBlockIdx = -1
        var bestLineIdx = -1
        var bestScore: CGFloat = .infinity
        var bestLineDX: CGFloat = .infinity

        // How far right each block's column reaches: the widest of the blocks sharing its left
        // edge. Distance to a line is measured to its column, so beside the short last line of a
        // paragraph the point stays with that paragraph rather than jumping to the next column.
        let columnMaxX = textBlocks.map { block in
            textBlocks.filter { abs($0.bbox.minX - block.bbox.minX) <= 2 }.map(\.bbox.maxX).max() ?? block.bbox.maxX
        }

        for bIdx in 0..<textBlocks.count {
            let block = textBlocks[bIdx]
            for lIdx in 0..<block.lines.count {
                let line = block.lines[lIdx]
                
                let yOverlap = (point.y >= line.bbox.minY - 3 && point.y <= line.bbox.maxY + 3)
                let dy: CGFloat
                if yOverlap {
                    dy = 0
                } else if point.y < line.bbox.minY {
                    dy = line.bbox.minY - point.y
                } else {
                    dy = point.y - line.bbox.maxY
                }
                
                // A line number shares its block's left edge but isn't text that runs on.
                let isText = line.characters.contains { $0.char.isLetter }
                let reachX = isText ? max(line.bbox.maxX, columnMaxX[bIdx]) : line.bbox.maxX
                let dx: CGFloat
                if point.x >= line.bbox.minX && point.x <= reachX {
                    dx = 0
                } else if point.x < line.bbox.minX {
                    dx = line.bbox.minX - point.x
                } else {
                    dx = point.x - reachX
                }
                
                // Prioritize vertical alignment (same line) heavily
                let score = (dy * 4.0) + dx
                // Between equally near lines — the pieces MuPDF splits a widely justified line
                // into all reach the column edge — the one actually nearest the point wins.
                let lineDX = point.x < line.bbox.minX ? line.bbox.minX - point.x : max(0, point.x - line.bbox.maxX)
                if score < bestScore || (score == bestScore && lineDX < bestLineDX) {
                    bestScore = score
                    bestLineDX = lineDX
                    bestBlockIdx = bIdx
                    bestLineIdx = lIdx
                }
            }
        }
        
        guard bestScore < .infinity,
              bestBlockIdx >= 0, bestBlockIdx < textBlocks.count,
              bestLineIdx >= 0, bestLineIdx < textBlocks[bestBlockIdx].lines.count else {
            return nil
        }

        let line = textBlocks[bestBlockIdx].lines[bestLineIdx]
        guard !line.characters.isEmpty else {
            return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: 0)
        }
        
        // Find character index on bestLine
        if point.x <= line.characters[0].boundingRect.minX {
            return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: 0)
        }
        if let lastChar = line.characters.last, point.x >= lastChar.boundingRect.maxX {
            return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: line.characters.count)
        }
        
        for i in 0..<line.characters.count {
            let box = line.characters[i].boundingRect
            if point.x <= box.maxX {
                let charIdx = (point.x < box.midX) ? i : (i + 1)
                return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: charIdx)
            }
        }
        
        return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: line.characters.count)
    }

    // MARK: - Point Target Resolution
    /// Determines whether a line belongs to a margin line-number gutter (numeric/punctuation only and narrow or in left margin)
    public static func isLineNumberGutter(line: TextLine, bodyLeftMargin: CGFloat) -> Bool {
        // Line numbers sit in the margin gutter to the left of the body column
        guard line.bbox.minX < bodyLeftMargin else { return false }
        // A plain number: "4.2" or "(a)" hanging in the margin numbers a clause, not a line.
        guard lineNumberValue(line) != nil else { return false }
        return line.bbox.maxX <= bodyLeftMargin + 8 || line.bbox.width < 45
    }

    /// The number a line holds, allowing one trailing "." or ":" ("15."), or nil.
    private static func lineNumberValue(_ line: TextLine) -> Int? {
        var text = line.text.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix(".") || text.hasSuffix(":") { text.removeLast() }
        return Int(text)
    }

    /// Which of a page's `lines` are margin line numbers: plain numbers left of the body text
    /// that count up at a steady pitch — numbering every line, or every fifth, say — or, with too
    /// few to tell (a title page's two), one per line of text. Section or clause numbers hanging
    /// in the margin also count up, but are as far apart as their paragraphs are long.
    static func lineNumberTest(for lines: [TextLine]) -> (TextLine) -> Bool {
        guard let bodyLeft = bodyLeftEdge(of: lines) else { return { _ in false } }
        let candidates = lines.filter { isLineNumberGutter(line: $0, bodyLeftMargin: bodyLeft) }
            .sorted { $0.bbox.midY < $1.bbox.midY }
        guard candidates.count >= 2 else { return { _ in false } }

        // Distance down the page per number, against the distance between lines of text.
        var pitches: [CGFloat] = []
        for (a, b) in zip(candidates, candidates.dropFirst()) {
            let step = lineNumberValue(b)! - lineNumberValue(a)!
            if step > 0 { pitches.append((b.bbox.midY - a.bbox.midY) / CGFloat(step)) }
        }
        let pairs = candidates.count - 1
        guard pitches.count * 4 >= pairs * 3 else { return { _ in false } }
        func mostlyNear(_ pitch: CGFloat) -> Bool {
            pitch > 0 && pitches.filter { abs($0 - pitch) <= pitch * 0.2 }.count * 4 >= pairs * 3
        }
        let isSteady = pitches.count >= 2 && mostlyNear(pitches.sorted()[pitches.count / 2])
        let matchesText = textLinePitch(lines).map(mostlyNear) ?? false
        guard isSteady || matchesText else { return { _ in false } }
        return { isLineNumberGutter(line: $0, bodyLeftMargin: bodyLeft) }
    }

    /// The usual distance from one row of text to the next.
    private static func textLinePitch(_ lines: [TextLine]) -> CGFloat? {
        let rows = lines.filter { $0.characters.contains { $0.char.isLetter } }.map(\.bbox.midY).sorted()
        let gaps = zip(rows, rows.dropFirst()).map { $1 - $0 }.filter { $0 >= 3 }.sorted()
        return gaps.isEmpty ? nil : gaps[gaps.count / 2]
    }

    /// The left edge of the body text among `lines`: the leftmost x at which at least three lines
    /// with letters in them start — a margin text is aligned to, so margin line numbers (no
    /// letters) and one-off strays such as a printer's slug line don't count. Nil if no such edge.
    static func bodyLeftEdge(of lines: [TextLine]) -> CGFloat? {
        let starts = lines.filter { $0.characters.contains { $0.char.isLetter } }.map(\.bbox.minX).sorted()
        guard starts.count >= 3 else { return nil }
        return starts.indices.dropLast(2).first { starts[$0 + 2] - starts[$0] <= 2 }.map { starts[$0] }
    }

    /// Resolves the primary content line for a target location (such as a cross-reference destination or bookmark),
    /// consistent with mouse selection: filtering out narrow line-number gutters and margin annotations,
    /// identifying the appropriate body column, and accurately targeting figure/table titles and equations.
    public func targetLine(on page: StructuredPage, at point: CGPoint, label: String? = nil, uri: String? = nil) -> TextLine? {
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        guard !textBlocks.isEmpty else { return nil }

        // 1. Separate body text blocks from narrow margin gutters (line numbers, marginalia).
        // Consistent with selectReadingOrder's minColumnWidth (60pt).
        let bodyBlocks = textBlocks.filter { $0.bbox.width >= Self.minColumnWidth }
        let candidateBlocks = bodyBlocks.isEmpty ? textBlocks : bodyBlocks
        let isLineNumber = Self.lineNumberTest(for: textBlocks.flatMap(\.lines))

        // 2. Parse target reference intent from label and URI (e.g. "Table 27-14", "Equation (27-19)", "Figure 3", "[2]")
        let cleanLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var eqTargetNum: String? = nil
        var tableOrFigKind: String? = nil
        var tableOrFigNum: String? = nil
        var refTargetNums: [String] = []

        // 1. Primary ground truth: If the link's URI explicitly identifies a reference target (e.g. "#nameddest=Rpone.0221551.ref003", "#ref3", "#bib2"),
        // that takes precedence over whatever anchor text was captured under the link's bounding box.
        if let uri, !uri.isEmpty {
            let uriRefPattern = #"(?<![A-Za-z])(?:bibitem|bib|cite|ref)[^0-9/]*0*([0-9]+)$"#
            if let uriRegex = try? NSRegularExpression(pattern: uriRefPattern, options: .caseInsensitive),
               let match = uriRegex.firstMatch(in: uri, range: NSRange(location: 0, length: (uri as NSString).length)) {
                let ns = uri as NSString
                if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                    refTargetNums = [ns.substring(with: match.range(at: 1))]
                }
            }
        }

        if !cleanLabel.isEmpty {
            // Check for Academic Reference pattern in anchor label if not already definitively identified by URI
            if refTargetNums.isEmpty {
                let bracketPattern = #"\[([^\]]+)\]"#
                if let bRegex = try? NSRegularExpression(pattern: bracketPattern),
                   let bMatch = bRegex.firstMatch(in: cleanLabel, range: NSRange(location: 0, length: (cleanLabel as NSString).length)) {
                    let ns = cleanLabel as NSString
                    let inner = ns.substring(with: bMatch.range(at: 1))
                    let numRegex = try? NSRegularExpression(pattern: #"\b([0-9]+)\b"#)
                    let numMatches = numRegex?.matches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) ?? []
                    for nm in numMatches {
                        refTargetNums.append((inner as NSString).substring(with: nm.range))
                    }
                } else {
                    let refPrefixPattern = #"\b(?:ref(?:erence)?s?|cite|bib)\.?\s*([0-9,\s–\-]+)"#
                    if let pRegex = try? NSRegularExpression(pattern: refPrefixPattern, options: .caseInsensitive),
                       let pMatch = pRegex.firstMatch(in: cleanLabel, range: NSRange(location: 0, length: (cleanLabel as NSString).length)) {
                        let ns = cleanLabel as NSString
                        let inner = ns.substring(with: pMatch.range(at: 1))
                        let numRegex = try? NSRegularExpression(pattern: #"\b([0-9]+)\b"#)
                        let numMatches = numRegex?.matches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) ?? []
                        for nm in numMatches {
                            refTargetNums.append((inner as NSString).substring(with: nm.range))
                        }
                    }
                }
            }

            // Check for Equation pattern: e.g. "Equation (27-19)", "Eq. (27-19)", "Equation 27-19", "(27-19)"
            let eqPattern = #"\b(?:Equation|Eq\.?)\s*(?:\(?([0-9A-Za-z\.\-]+)\)?|\(([^\)]+)\))"#
            if let eqRegex = try? NSRegularExpression(pattern: eqPattern, options: .caseInsensitive),
               let match = eqRegex.firstMatch(in: cleanLabel, range: NSRange(location: 0, length: (cleanLabel as NSString).length)) {
                let ns = cleanLabel as NSString
                if match.numberOfRanges > 1 && match.range(at: 1).location != NSNotFound {
                    eqTargetNum = ns.substring(with: match.range(at: 1))
                } else if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                    eqTargetNum = ns.substring(with: match.range(at: 2))
                }
            } else if cleanLabel.hasPrefix("(") && cleanLabel.hasSuffix(")") {
                let inner = String(cleanLabel.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if !inner.isEmpty && inner.rangeOfCharacter(from: .decimalDigits) != nil {
                    eqTargetNum = inner
                }
            }

            // Check for Table / Figure pattern: e.g. "Table 27-14", "Figure 3", "Fig. 2", "TABLE I", "table.caption.3", "S12 Fig"
            let tfPattern = #"\b(?:(Tables?|Figures?|Figs?\.?)\s*([0-9][0-9A-Za-z\.\-]*|[A-Z](?:[.\-]?[0-9][0-9\.\-]*)?|[IVXLC]+)|(S[0-9]+)\s*(Fig(?:ure|\.)?))\b"#
            if let tfRegex = try? NSRegularExpression(pattern: tfPattern, options: .caseInsensitive),
               let match = tfRegex.firstMatch(in: cleanLabel, range: NSRange(location: 0, length: (cleanLabel as NSString).length)) {
                let ns = cleanLabel as NSString
                if match.range(at: 1).location != NSNotFound && match.range(at: 2).location != NSNotFound {
                    let prefix = ns.substring(with: match.range(at: 1)).lowercased()
                    tableOrFigKind = prefix.hasPrefix("fig") ? "figure" : "table"
                    tableOrFigNum = ns.substring(with: match.range(at: 2)).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
                } else if match.range(at: 3).location != NSNotFound {
                    tableOrFigKind = "figure"
                    tableOrFigNum = ns.substring(with: match.range(at: 3)).lowercased()
                }
            }

            // A link on just the number ("3", "(2.1)"), as LaTeX's `Figure~\ref{}` makes: its
            // destination name says what it numbers; with none, a bare number is a citation.
            let bareNumber = cleanLabel.trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
            if refTargetNums.isEmpty && eqTargetNum == nil && tableOrFigNum == nil,
               !bareNumber.isEmpty, bareNumber.first?.isNumber == true,
               bareNumber.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
                switch LinkTargetKind(uri: uri, outlineDestinationKeys: []) {
                case .figure:
                    (tableOrFigKind, tableOrFigNum) = ("figure", bareNumber)
                case .table:
                    (tableOrFigKind, tableOrFigNum) = ("table", bareNumber)
                case .equation:
                    eqTargetNum = bareNumber
                case .citation, .unknown:
                    if bareNumber.allSatisfy(\.isNumber) { refTargetNums = [bareNumber] }
                default:
                    break
                }
            }
        }

        // 3. Specialized search: Academic References / Bibliography entries
        if !refTargetNums.isEmpty {
            var bestRefLine: TextLine? = nil
            var bestRefScore: CGFloat = .infinity

            for refNum in refTargetNums {
                // Matches entry starting with "2.", "[2]", "(2)", "[2, 3]", "[2-4]", or "2 "
                let numPattern = #"^\s*(?:\[\s*\#(refNum)(?:\s*[,–\-]\s*[0-9]+)?\s*\]|\#(refNum)\.(?!\d)|\(\s*\#(refNum)\s*\)|\#(refNum)\s+)"#
                guard let refRegex = try? NSRegularExpression(pattern: numPattern, options: .caseInsensitive) else { continue }

                for block in candidateBlocks {
                    for line in block.lines {
                        if isLineNumber(line) { continue }
                        let lineText = line.text.trimmingCharacters(in: .whitespaces)
                        let nsText = lineText as NSString
                        if refRegex.firstMatch(in: lineText, range: NSRange(location: 0, length: nsText.length)) != nil {
                            let dy = abs(line.bbox.midY - point.y)
                            if dy < bestRefScore {
                                bestRefScore = dy
                                bestRefLine = line
                            }
                        }
                    }
                }
            }

            if let refLine = bestRefLine {
                // Frame the initial lines of the bibliography entry within the same block
                if let block = candidateBlocks.first(where: { $0.lines.contains(where: { $0.bbox == refLine.bbox }) }) {
                    let sortedLines = block.lines.sorted { $0.bbox.minY < $1.bbox.minY }
                    if let startIdx = sortedLines.firstIndex(where: { $0.bbox == refLine.bbox }) {
                        var entryLines: [TextLine] = [sortedLines[startIdx]]
                        var prevMaxY = sortedLines[startIdx].bbox.maxY
                        for i in (startIdx + 1)..<sortedLines.count {
                            let l = sortedLines[i]
                            if l.bbox.minY - prevMaxY <= 15 && l.bbox.minY - sortedLines[startIdx].bbox.minY <= 80 {
                                entryLines.append(l)
                                prevMaxY = l.bbox.maxY
                            } else {
                                break
                            }
                        }
                        if entryLines.count > 1 {
                            let minX = entryLines.map { $0.bbox.minX }.min() ?? refLine.bbox.minX
                            let maxX = entryLines.map { $0.bbox.maxX }.max() ?? refLine.bbox.maxX
                            let minY = entryLines.map { $0.bbox.minY }.min() ?? refLine.bbox.minY
                            let maxY = entryLines.map { $0.bbox.maxY }.max() ?? refLine.bbox.maxY
                            let combinedBBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                            return TextLine(bbox: combinedBBox, characters: entryLines.flatMap { $0.characters })
                        }
                    }
                }
                return refLine
            }
        }

        // 3. Specialized search: Equation References
        // If referencing an equation (e.g. "Equation (27-19)", "Eq. (2)"), locate the equation's number tag or formula,
        // prioritizing standalone equation tags/numbering on the right margin over prose paragraphs referencing the equation,
        // and strictly avoiding following prose clauses ("where ...").
        if let eqNum = eqTargetNum {
            let targetParens = "(\(eqNum))"
            var bestEqLine: TextLine? = nil
            var bestEqScore: CGFloat = .infinity

            for block in page.blocks where block.type == .text {
                for line in block.lines {
                    // Strictly exclude margin line numbers: numeric-only with narrow width or far left
                    if isLineNumber(line) { continue }
                    if line.characters.allSatisfy({ $0.char.isNumber || $0.char.isWhitespace }) && line.bbox.width < 40 { continue }

                    let lineText = line.text.trimmingCharacters(in: .whitespaces)
                    let isExactTag = (lineText == targetParens || lineText == eqNum)
                    let isRightAlignedTag = (lineText.hasSuffix(targetParens) || lineText.hasSuffix(eqNum)) &&
                                            (line.bbox.minX > page.bounds.midX) &&
                                            (lineText.count <= targetParens.count + 6)
                    let isStandaloneTag = isExactTag || isRightAlignedTag

                    let dy = abs(line.bbox.midY - point.y)
                    guard dy <= 450 else { continue }

                    // Standalone equation tags get massive priority over prose paragraphs mentioning the equation
                    let tagBonus: CGFloat = isStandaloneTag ? 1000.0 : (lineText.contains(targetParens) ? 100.0 : 0.0)
                    guard tagBonus > 0 else { continue }

                    let score = dy - tagBonus
                    if score < bestEqScore {
                        bestEqScore = score
                        bestEqLine = line
                    }
                }
            }

            if let eqNumLine = bestEqLine {
                // If there are formula lines on this same equation row, expand horizontally to frame
                // both the formula and the equation number, strictly excluding margin line numbers.
                let rowMinY = eqNumLine.bbox.minY - 15
                let rowMaxY = eqNumLine.bbox.maxY + 15
                let rowLines = page.blocks.filter { $0.type == .text }.flatMap { $0.lines }.filter { line in
                    // Exclude margin line numbers: narrow numeric lines on the left, or in gutter
                    if line.characters.allSatisfy({ $0.char.isNumber || $0.char.isWhitespace }) && line.bbox.width < 45 && line.bbox.minX < page.bounds.midX {
                        return false
                    }
                    guard !isLineNumber(line) else { return false }
                    return line.bbox.minY >= rowMinY && line.bbox.maxY <= rowMaxY
                }
                if !rowLines.isEmpty {
                    let minX = rowLines.map { $0.bbox.minX }.min() ?? eqNumLine.bbox.minX
                    let maxX = rowLines.map { $0.bbox.maxX }.max() ?? eqNumLine.bbox.maxX
                    let minY = rowLines.map { $0.bbox.minY }.min() ?? eqNumLine.bbox.minY
                    let maxY = rowLines.map { $0.bbox.maxY }.max() ?? eqNumLine.bbox.maxY
                    let combinedBBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                    return TextLine(bbox: combinedBBox, characters: rowLines.flatMap { $0.characters })
                }
                return eqNumLine
            }
        }

        // 4. Specialized search: Table or Figure References
        // If referencing a Table or Figure (e.g. "Table 27-14", "Figure 1"), directly locate the caption headline.
        if let kind = tableOrFigKind, let num = tableOrFigNum {
            var bestTitleLine: TextLine? = nil
            var bestTitleDy: CGFloat = .infinity

            // For tables, title is near anchor (±250pt).
            // For figures, caption is almost always below the figure illustration (up to 500pt below anchor).
            let maxDyAbove: CGFloat = (kind == "figure") ? 60 : 250
            let maxDyBelow: CGFloat = (kind == "figure") ? 500 : 250

            let numPattern = #"(?:\b|\()\#(NSRegularExpression.escapedPattern(for: num))(?:\b|\))"#
            let numRegex = try? NSRegularExpression(pattern: numPattern, options: .caseInsensitive)

            for block in candidateBlocks {
                for line in block.lines {
                    if isLineNumber(line) { continue }
                    let lineLower = line.text.lowercased()
                    let kindPattern = (kind == "figure") ? #"\bfig(?:ure)?s?\b"# : #"\btables?\b"#
                    let containsKind = lineLower.range(of: kindPattern, options: .regularExpression) != nil
                    // A caption starts with its label; prose mentioning the table only contains it.
                    let startsWithKind = lineLower.trimmingCharacters(in: .whitespaces)
                        .range(of: "^" + kindPattern, options: .regularExpression) != nil

                    let containsNum: Bool
                    if let numRegex {
                        let nsLine = lineLower as NSString
                        containsNum = numRegex.firstMatch(in: lineLower, range: NSRange(location: 0, length: nsLine.length)) != nil
                    } else {
                        containsNum = lineLower.contains(num)
                    }

                    if containsKind && containsNum {
                        let dy = line.bbox.midY - point.y
                        if dy >= -maxDyAbove && dy <= maxDyBelow {
                            let score = abs(dy) + (startsWithKind ? 0 : 1000)
                            if score < bestTitleDy {
                                bestTitleDy = score
                                bestTitleLine = line
                            }
                        }
                    }
                }
            }

            if let titleLine = bestTitleLine {
                // If title wraps across subsequent lines in the same block, frame the full title heading
                if let block = candidateBlocks.first(where: { $0.lines.contains(where: { $0.bbox == titleLine.bbox }) }) {
                    let sortedLines = block.lines.sorted { $0.bbox.minY < $1.bbox.minY }
                    if let startIdx = sortedLines.firstIndex(where: { $0.bbox == titleLine.bbox }) {
                        var captionLines: [TextLine] = [sortedLines[startIdx]]
                        var prevMaxY = sortedLines[startIdx].bbox.maxY
                        for i in (startIdx + 1)..<sortedLines.count {
                            let l = sortedLines[i]
                            if l.bbox.minY - prevMaxY <= 15 && l.bbox.minY - sortedLines[startIdx].bbox.minY <= 80 {
                                captionLines.append(l)
                                prevMaxY = l.bbox.maxY
                            } else {
                                break
                            }
                        }
                        if captionLines.count > 1 {
                            let minX = captionLines.map { $0.bbox.minX }.min() ?? titleLine.bbox.minX
                            let maxX = captionLines.map { $0.bbox.maxX }.max() ?? titleLine.bbox.maxX
                            let minY = captionLines.map { $0.bbox.minY }.min() ?? titleLine.bbox.minY
                            let maxY = captionLines.map { $0.bbox.maxY }.max() ?? titleLine.bbox.maxY
                            let combinedBBox = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                            return TextLine(bbox: combinedBBox, characters: captionLines.flatMap { $0.characters })
                        }
                    }
                }
                return titleLine
            }
        }

        // 5. General Spatial Proximity Scoring (fallback for other references)
        let minBodyX = candidateBlocks.map { $0.bbox.minX }.min() ?? (page.bounds.minX + Self.minColumnWidth)
        let effectiveX: CGFloat
        if point.x <= page.bounds.minX + Self.minColumnWidth {
            effectiveX = minBodyX + 10
        } else {
            effectiveX = point.x
        }
        let targetPoint = CGPoint(x: effectiveX, y: point.y)

        // Multi-column detection: only constrain to a column if the page actually contains
        // side-by-side body text columns, preventing single-column centered headings from being discarded.
        let isMultiColumn = candidateBlocks.contains { b1 in
            candidateBlocks.contains { b2 in
                b1.bbox != b2.bbox && abs(b1.bbox.midX - b2.bbox.midX) > 150 &&
                min(b1.bbox.maxY, b2.bbox.maxY) > max(b1.bbox.minY, b2.bbox.minY) + 40
            }
        }

        var bestLine: TextLine? = nil
        var bestScore: CGFloat = .infinity

        for block in candidateBlocks {
            if isMultiColumn && point.x > page.bounds.minX + Self.minColumnWidth {
                let overlapWidth = min(block.bbox.maxX, point.x + Self.gutterThreshold) - max(block.bbox.minX, point.x - Self.gutterThreshold)
                if overlapWidth <= 0 && abs(block.bbox.midX - point.x) > 120 {
                    continue
                }
            }

            for line in block.lines {
                guard !line.characters.isEmpty else { continue }
                // Exclude narrow margin gutter line numbers
                guard !isLineNumber(line) else { continue }
                guard line.bbox.width >= 40 || line.characters.contains(where: { $0.char.isLetter }) else { continue }

                // Vertical distance metric identical to resolvePosition:
                let yOverlap = (targetPoint.y >= line.bbox.minY - 3 && targetPoint.y <= line.bbox.maxY + 3)
                let dy: CGFloat
                if yOverlap {
                    dy = 0
                } else if targetPoint.y < line.bbox.minY {
                    dy = line.bbox.minY - targetPoint.y
                } else {
                    dy = (targetPoint.y - line.bbox.maxY) * 1.5
                }

                // Optional label token boost (e.g. section number or name)
                var labelBoost: CGFloat = 0.0
                if !cleanLabel.isEmpty {
                    let lineLower = line.text.lowercased()
                    for token in cleanLabel.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "." }) {
                        let t = String(token).lowercased()
                        if t.count >= 2 && lineLower.contains(t) {
                            labelBoost += 1000.0
                        } else if t.count == 1 && lineLower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(Substring(t)) {
                            labelBoost += 500.0
                        }
                    }
                }

                // Restrict search to reasonable vertical proximity, unless the anchor is at the top of the page
                let isTopAnchored = targetPoint.y <= page.bounds.minY + 60
                if isTopAnchored && labelBoost > 0 {
                    // Allowed across the page when strongly matched by label
                } else if isTopAnchored {
                    guard dy <= 150 else { continue }
                } else {
                    guard dy <= 120 else { continue }
                }

                // Horizontal distance metric identical to resolvePosition:
                let dx: CGFloat
                if targetPoint.x >= line.bbox.minX && targetPoint.x <= line.bbox.maxX {
                    dx = 0
                } else if targetPoint.x < line.bbox.minX {
                    dx = line.bbox.minX - targetPoint.x
                } else {
                    dx = targetPoint.x - line.bbox.maxX
                }

                // Deprioritize running page headers when the target point is within body content
                let isPageHeader = line.bbox.minY <= page.bounds.minY + 45
                let headerPenalty: CGFloat = (isPageHeader && targetPoint.y > page.bounds.minY + 50) ? 500.0 : 0.0

                // Heavy vertical prioritization matching resolvePosition: (effectiveDy * 4.0) + dx + headerPenalty - labelBoost
                let effectiveDy: CGFloat = (isTopAnchored && labelBoost > 0) ? 0 : dy
                let score = (effectiveDy * 4.0) + dx + headerPenalty - labelBoost

                if score < bestScore {
                    bestScore = score
                    bestLine = line
                }
            }
        }

        return bestLine
    }

    // MARK: - Word & Line Selection
    public func selectWord(at point: CGPoint, on page: StructuredPage) -> SelectionResult? {
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        guard let pos = resolvePosition(at: point, in: textBlocks),
              pos.blockIndex < textBlocks.count else { return nil }
        let block = textBlocks[pos.blockIndex]
        guard pos.lineIndex < block.lines.count else { return nil }
        let line = block.lines[pos.lineIndex]
        guard !line.characters.isEmpty else { return nil }

        func isWordChar(_ c: Character) -> Bool {
            c.isLetter || c.isNumber || c == "_"
        }

        var targetIdx = min(pos.charIndex, line.characters.count - 1)
        if targetIdx > 0 && !isWordChar(line.characters[targetIdx].char) && isWordChar(line.characters[targetIdx - 1].char) {
            targetIdx -= 1
        } else if targetIdx + 1 < line.characters.count && !isWordChar(line.characters[targetIdx].char) && isWordChar(line.characters[targetIdx + 1].char) {
            targetIdx += 1
        }

        let isWord = isWordChar(line.characters[targetIdx].char)
        var startIdx = targetIdx
        var endIdx = targetIdx + 1

        if isWord {
            while startIdx > 0 && isWordChar(line.characters[startIdx - 1].char) {
                startIdx -= 1
            }
            while endIdx < line.characters.count && isWordChar(line.characters[endIdx].char) {
                endIdx += 1
            }
        }

        let sliceChars = Array(line.characters[startIdx..<endIdx])
        guard let firstChar = sliceChars.first, let lastChar = sliceChars.last else { return nil }

        let lineQuad = PDFQuad(
            ul: CGPoint(x: firstChar.boundingRect.minX, y: line.bbox.minY),
            ur: CGPoint(x: lastChar.boundingRect.maxX, y: line.bbox.minY),
            ll: CGPoint(x: firstChar.boundingRect.minX, y: line.bbox.maxY),
            lr: CGPoint(x: lastChar.boundingRect.maxX, y: line.bbox.maxY)
        )

        let wordText = Self.text(of: sliceChars)

        return SelectionResult(
            text: wordText,
            highlightQuads: [lineQuad],
            boundingRect: lineQuad.boundingRect,
            mode: .readingOrder
        )
    }

    public func selectLine(at point: CGPoint, on page: StructuredPage) -> SelectionResult? {
        let textBlocks = page.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        guard let pos = resolvePosition(at: point, in: textBlocks),
              pos.blockIndex < textBlocks.count else { return nil }
        let block = textBlocks[pos.blockIndex]
        guard pos.lineIndex < block.lines.count else { return nil }
        let line = block.lines[pos.lineIndex]
        guard !line.characters.isEmpty else { return nil }

        let sliceChars = line.characters
        guard let firstChar = sliceChars.first, let lastChar = sliceChars.last else { return nil }

        let lineQuad = PDFQuad(
            ul: CGPoint(x: firstChar.boundingRect.minX, y: line.bbox.minY),
            ur: CGPoint(x: lastChar.boundingRect.maxX, y: line.bbox.minY),
            ll: CGPoint(x: firstChar.boundingRect.minX, y: line.bbox.maxY),
            lr: CGPoint(x: lastChar.boundingRect.maxX, y: line.bbox.maxY)
        )

        let lineText = Self.text(of: sliceChars)

        return SelectionResult(
            text: lineText,
            highlightQuads: [lineQuad],
            boundingRect: lineQuad.boundingRect,
            mode: .readingOrder
        )
    }
}
