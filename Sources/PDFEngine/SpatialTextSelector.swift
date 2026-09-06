import Foundation
import CoreGraphics

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
    public init() {}
    
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
            return selectReadingOrder(on: textBlocks, from: startPoint, to: endPoint)
        }
    }
    
    // MARK: - Reading Flow Selection
    private func selectReadingOrder(on textBlocks: [TextBlock], from startPoint: CGPoint, to endPoint: CGPoint) -> SelectionResult {
        guard let pos1 = resolvePosition(at: startPoint, in: textBlocks),
              let pos2 = resolvePosition(at: endPoint, in: textBlocks) else {
            return SelectionResult(text: "", highlightQuads: [], boundingRect: .zero, mode: .readingOrder)
        }

        if pos1 == pos2 {
            return SelectionResult(text: "", highlightQuads: [], boundingRect: .zero, mode: .readingOrder)
        }

        // Which of the two drag endpoints comes first in reading order — determined by actual
        // page geometry (top-to-bottom, then left-to-right), NOT by TextPosition's own
        // Comparable conformance (which compares blockIndex first). That comparison silently
        // assumes mupdf enumerates text blocks in strict top-to-bottom order, which breaks for
        // section headings, tables, and anything else mupdf orders differently from where it
        // actually sits on the page — and when it breaks, `firstPos`/`lastPos` end up wrong
        // (potentially even swapped), corrupting the vertical band and trim points below no
        // matter how correct the rest of the algorithm is.
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

        var selectedQuads: [PDFQuad] = []
        var selectedText = ""
        var overallBoundingBox = CGRect.null

        // Vertical band spanned by the drag, snapped to the actual top/bottom of the first and
        // last selected lines rather than the raw drag points (which can land slightly off a
        // line, or past the page edge).
        let firstLine = textBlocks[firstPos.blockIndex].lines[firstPos.lineIndex]
        let lastLine = textBlocks[lastPos.blockIndex].lines[lastPos.lineIndex]
        let bandMinY = min(firstLine.bbox.minY, lastLine.bbox.minY)
        let bandMaxY = max(firstLine.bbox.maxY, lastLine.bbox.maxY)

        // Multi-column guard: only blocks wide enough to plausibly be body text are considered
        // when determining columns, excluding narrow line-number gutters or margin annotations.
        // Anchored on whichever start/end block is wider to prevent drags originating in margins
        // from incorrectly constraining selections.
        let startBlock = textBlocks[firstPos.blockIndex]
        let endBlock = textBlocks[lastPos.blockIndex]
        let anchorBlock = startBlock.bbox.width >= endBlock.bbox.width ? startBlock : endBlock
        let minColumnWidth: CGFloat = 60
        let isMultiColumn = textBlocks.contains { $0.bbox.width > minColumnWidth && abs($0.bbox.midX - anchorBlock.bbox.midX) > 100 }
        let gutterThreshold: CGFloat = 20.0
        let constrainToColumn = isMultiColumn && (max(startPoint.x, endPoint.x) < anchorBlock.bbox.maxX + gutterThreshold)

        // Include every text block whose vertical extent overlaps the drag's band, walked in
        // page (top-to-bottom) order — not by mupdf's block *enumeration* index, which can place
        // a differently-styled block (e.g. a section heading in its own paragraph style) at an
        // index outside the numeric [firstPos.blockIndex, lastPos.blockIndex] range even though
        // it sits visually between them, silently dropping it from a selection that visibly
        // spans it.
        let bandBlocks = textBlocks.enumerated()
            .filter { _, block in block.bbox.maxY >= bandMinY && block.bbox.minY <= bandMaxY }
            .filter { _, block in
                // Only exclude a block when it's confined to a clearly different horizontal
                // region than the anchor column — measured as the fraction of the *narrower* of
                // the two blocks' widths that the overlap covers, not raw distance between
                // centers or a bare yes/no overlap test. A full-width paragraph or a table row
                // spanning several cells fully contains a single cell/column's X-range (overlap
                // fraction near 100%), so it's always kept; a genuinely separate column merely
                // grazes the anchor's edge (a small overlap fraction), so it's still excluded.
                guard constrainToColumn else { return true }
                let overlapWidth = min(block.bbox.maxX, anchorBlock.bbox.maxX) - max(block.bbox.minX, anchorBlock.bbox.minX)
                guard overlapWidth > 0 else { return false }
                let narrowerWidth = min(block.bbox.width, anchorBlock.bbox.width)
                guard narrowerWidth > 0 else { return false }
                return (overlapWidth / narrowerWidth) >= 0.5
            }
            .sorted { $0.element.bbox.minY < $1.element.bbox.minY }

        for (bIdx, block) in bandBlocks {
            let isFirstBlock = (bIdx == firstPos.blockIndex)
            let isLastBlock = (bIdx == lastPos.blockIndex)

            for lIdx in 0..<block.lines.count {
                // For the two boundary blocks — where resolvePosition gave us an exact starting
                // or ending line — trust that exact line index rather than a Y-range test.
                // Adjacent lines' bounding boxes can overlap by a point or two in tightly-leaded
                // technical documents (ascender/descender padding), which would let the line just
                // before/after the intended boundary sneak into the selection under a pure
                // Y-overlap check.
                if isFirstBlock && lIdx < firstPos.lineIndex { continue }
                if isLastBlock && lIdx > lastPos.lineIndex { continue }

                let line = block.lines[lIdx]
                guard !line.characters.isEmpty else { continue }
                // Any other ("extra", in-between) block was picked up purely by vertical-band
                // overlap at the block level above — for those, still confirm each individual
                // line is actually within the band, guarding against a tall block that only
                // partially dips into the band at one edge.
                if !isFirstBlock && !isLastBlock {
                    guard line.bbox.maxY >= bandMinY && line.bbox.minY <= bandMaxY else { continue }
                }

                let isFirstSelectedLine = (isFirstBlock && lIdx == firstPos.lineIndex)
                let isLastSelectedLine = (isLastBlock && lIdx == lastPos.lineIndex)
                let fromChar = isFirstSelectedLine ? firstPos.charIndex : 0
                let toChar = isLastSelectedLine ? lastPos.charIndex : line.characters.count

                let validFrom = max(0, min(fromChar, line.characters.count))
                let validTo = max(validFrom, min(toChar, line.characters.count))

                guard validFrom < validTo else { continue }

                let sliceChars = Array(line.characters[validFrom..<validTo])
                guard let firstChar = sliceChars.first, let lastChar = sliceChars.last else { continue }

                let sliceMinX = firstChar.boundingRect.minX
                let sliceMaxX = lastChar.boundingRect.maxX
                let lineMinY = line.bbox.minY
                let lineMaxY = line.bbox.maxY

                // Continuous line quad covering words and spaces seamlessly
                let lineQuad = PDFQuad(
                    ul: CGPoint(x: sliceMinX, y: lineMinY),
                    ur: CGPoint(x: sliceMaxX, y: lineMinY),
                    ll: CGPoint(x: sliceMinX, y: lineMaxY),
                    lr: CGPoint(x: sliceMaxX, y: lineMaxY)
                )
                selectedQuads.append(lineQuad)
                overallBoundingBox = overallBoundingBox.union(lineQuad.boundingRect)

                // Assemble line text with inter-word spacing
                for (cIdx, char) in sliceChars.enumerated() {
                    selectedText.append(char.char)
                    if cIdx < sliceChars.count - 1 {
                        let nextChar = sliceChars[cIdx + 1]
                        let gap = nextChar.boundingRect.minX - char.boundingRect.maxX
                        if gap > CGFloat(char.size) * 0.20 && char.char != " " && nextChar.char != " " {
                            selectedText.append(" ")
                        }
                    }
                }

                // Line break / space
                if !isLastSelectedLine {
                    if lIdx == block.lines.count - 1 {
                        selectedText.append("\n\n")
                    } else {
                        selectedText.append(" ")
                    }
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
                    var lineStr = ""
                    for (idx, c) in charsInRect.enumerated() {
                        lineStr.append(c.char)
                        if idx < charsInRect.count - 1 {
                            let next = charsInRect[idx + 1]
                            let gap = next.boundingRect.minX - c.boundingRect.maxX
                            if gap > CGFloat(c.size) * 0.20 && c.char != " " && next.char != " " {
                                lineStr.append(" ")
                            }
                        }
                    }
                    linesText.append(lineStr)
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
        var bestBlockIdx = 0
        var bestLineIdx = 0
        var bestScore: CGFloat = .infinity
        
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
                
                let dx: CGFloat
                if point.x >= line.bbox.minX && point.x <= line.bbox.maxX {
                    dx = 0
                } else if point.x < line.bbox.minX {
                    dx = line.bbox.minX - point.x
                } else {
                    dx = point.x - line.bbox.maxX
                }
                
                // Prioritize vertical alignment (same line) heavily
                let score = (dy * 4.0) + dx
                if score < bestScore {
                    bestScore = score
                    bestBlockIdx = bIdx
                    bestLineIdx = lIdx
                }
            }
        }
        
        let line = textBlocks[bestBlockIdx].lines[bestLineIdx]
        guard !line.characters.isEmpty else {
            return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: 0)
        }
        
        // Find character index on bestLine
        if point.x <= line.characters[0].boundingRect.minX {
            return TextPosition(blockIndex: bestBlockIdx, lineIndex: bestLineIdx, charIndex: 0)
        }
        if point.x >= line.characters.last!.boundingRect.maxX {
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
}
