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
import MuPDFBridge

public struct TextCharacter: Sendable, Equatable {
    public let char: Character
    public let quad: PDFQuad
    public let origin: CGPoint
    public let size: Float
    public let isBold: Bool
    public let isItalic: Bool
    public var isUnderline: Bool
    public var isStrikethrough: Bool
    public let fontName: String
    public let color: UInt32
    
    public init(
        char: Character,
        quad: PDFQuad,
        origin: CGPoint,
        size: Float,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderline: Bool = false,
        isStrikethrough: Bool = false,
        fontName: String = "",
        color: UInt32 = 0xFF000000
    ) {
        self.char = char
        self.quad = quad
        self.origin = origin
        self.size = size
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isStrikethrough = isStrikethrough
        self.fontName = fontName
        self.color = color
    }
    
    public var boundingRect: CGRect {
        quad.boundingRect
    }
}

/// A contiguous run of characters within a line sharing the same styling (bold, italic, underline, strikethrough, font size, font family, color).
public struct TextRun: Sendable, Equatable {
    public let text: String
    public let isBold: Bool
    public let isItalic: Bool
    public let isUnderline: Bool
    public let isStrikethrough: Bool
    public let size: Float
    public let fontName: String
    public let colorHex: String
    
    public init(text: String, isBold: Bool, isItalic: Bool, isUnderline: Bool = false, isStrikethrough: Bool = false, size: Float, fontName: String, colorHex: String = "000000") {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderline = isUnderline
        self.isStrikethrough = isStrikethrough
        self.size = size
        self.fontName = fontName
        self.colorHex = colorHex
    }
}

public struct TextLine: Sendable, Equatable {
    public let bbox: CGRect
    public let characters: [TextCharacter]
    public let text: String
    
    public init(bbox: CGRect, characters: [TextCharacter]) {
        self.bbox = bbox
        self.characters = characters
        self.text = String(characters.map { $0.char })
    }

    /// Groups characters into styled runs for efficient OpenXML / RTF generation.
    public var runs: [TextRun] {
        guard !characters.isEmpty else { return [] }
        var result: [TextRun] = []
        var currentText = ""
        var currentBold = characters[0].isBold
        var currentItalic = characters[0].isItalic
        var currentUnderline = characters[0].isUnderline
        var currentStrike = characters[0].isStrikethrough
        var currentSize = characters[0].size
        var currentFont = characters[0].fontName
        var currentColor = String(format: "%06X", characters[0].color & 0x00FFFFFF)

        for ch in characters {
            let chColor = String(format: "%06X", ch.color & 0x00FFFFFF)
            let matches = (ch.isBold == currentBold && ch.isItalic == currentItalic && ch.isUnderline == currentUnderline && ch.isStrikethrough == currentStrike && abs(ch.size - currentSize) < 0.2 && ch.fontName == currentFont && chColor == currentColor)
            if matches {
                currentText.append(ch.char)
            } else {
                if !currentText.isEmpty {
                    result.append(TextRun(text: currentText, isBold: currentBold, isItalic: currentItalic, isUnderline: currentUnderline, isStrikethrough: currentStrike, size: currentSize, fontName: currentFont, colorHex: currentColor))
                }
                currentText = String(ch.char)
                currentBold = ch.isBold
                currentItalic = ch.isItalic
                currentUnderline = ch.isUnderline
                currentStrike = ch.isStrikethrough
                currentSize = ch.size
                currentFont = ch.fontName
                currentColor = chColor
            }
        }
        if !currentText.isEmpty {
            result.append(TextRun(text: currentText, isBold: currentBold, isItalic: currentItalic, isUnderline: currentUnderline, isStrikethrough: currentStrike, size: currentSize, fontName: currentFont, colorHex: currentColor))
        }
        return result
    }
}

public enum BlockType: Int, Sendable {
    case text = 0
    case image = 1
    case vector = 3
    case other = 2
}

public struct VectorInfo: Sendable, Equatable {
    public let flags: UInt32
    public let color: UInt32

    public var isStroked: Bool { (flags & 1) != 0 }
    public var isRectangle: Bool { (flags & 2) != 0 }
    public var isUnderline: Bool { (flags & 16) != 0 }
    public var isHighlight: Bool { (flags & 8) != 0 }
    public var isStrikeout: Bool { (flags & 32) != 0 }

    public init(flags: UInt32, color: UInt32) {
        self.flags = flags
        self.color = color
    }
}

public struct TextBlock: Sendable, Equatable {
    public let type: BlockType
    public let bbox: CGRect
    public var lines: [TextLine]
    public let text: String
    public let vectorInfo: VectorInfo?

    public init(type: BlockType, bbox: CGRect, lines: [TextLine], vectorInfo: VectorInfo? = nil) {
        self.type = type
        self.bbox = bbox
        self.lines = lines
        self.text = lines.map { $0.text }.joined(separator: "\n")
        self.vectorInfo = vectorInfo
    }
}

public struct StructuredPage: Sendable {
    public let pageIndex: Int
    public let bounds: CGRect
    public let blocks: [TextBlock]
    
    public var plainText: String {
        blocks.filter { $0.type == .text }.map { $0.text }.joined(separator: "\n\n")
    }

    /// Plain text extracted only from blocks matching running prose width thresholds.
    public var proseText: String {
        let textBlocks = blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        let prose = textBlocks.filter { block in
            let averageLineWidth = block.lines.map { $0.bbox.width }.reduce(0, +) / CGFloat(block.lines.count)
            return averageLineWidth > bounds.width * 0.15
        }
        return prose.map { $0.text }.joined(separator: "\n\n")
    }
    
    public var allLines: [TextLine] {
        blocks.flatMap { $0.lines }
    }
    
    public var allCharacters: [TextCharacter] {
        allLines.flatMap { $0.characters }
    }
    
    /// Builds unified plain text where each character offset maps 1:1 to an optional PDFQuad on the page
    public var searchableIndex: (text: String, quads: [PDFQuad?]) {
        var fullText = ""
        var quads: [PDFQuad?] = []
        
        let textBlocks = blocks.filter { $0.type == .text }
        for (bIdx, block) in textBlocks.enumerated() {
            for (lIdx, line) in block.lines.enumerated() {
                for char in line.characters {
                    fullText.append(char.char)
                    for _ in 0..<char.char.utf16.count {
                        quads.append(char.quad)
                    }
                }
                if lIdx < block.lines.count - 1 {
                    fullText.append(" ")
                    quads.append(nil)
                }
            }
            if bIdx < textBlocks.count - 1 {
                fullText.append("\n\n")
                quads.append(nil)
                quads.append(nil)
            }
        }
        return (fullText, quads)
    }
    
    /// Loads structured text from an already loaded stext page
    public static func load(fromStext stext: FZStextPage, pageIndex: Int, pageBounds: CGRect, ctx: FZContext? = nil) -> StructuredPage {
        var blocks: [TextBlock] = []
        var blockPtr = mupdf_stext_first_block(stext)
        while let b = blockPtr {
            let rawType = mupdf_stext_block_type(b)
            let bType: BlockType
            switch rawType {
            case 0: bType = .text
            case 1: bType = .image
            case 3: bType = .vector
            default: bType = .other
            }
            let bRect = mupdf_stext_block_bbox(b)
            let blockBBox = CGRect(
                x: CGFloat(bRect.x0),
                y: CGFloat(bRect.y0),
                width: CGFloat(bRect.x1 - bRect.x0),
                height: CGFloat(bRect.y1 - bRect.y0)
            )
            
            var lines: [TextLine] = []
            if bType == .text {
                var linePtr = mupdf_stext_block_first_line(b)
                while let l = linePtr {
                    let lRect = mupdf_stext_line_bbox(l)
                    let lineBBox = CGRect(
                        x: CGFloat(lRect.x0),
                        y: CGFloat(lRect.y0),
                        width: CGFloat(lRect.x1 - lRect.x0),
                        height: CGFloat(lRect.y1 - lRect.y0)
                    )
                    
                    var characters: [TextCharacter] = []
                    var charPtr = mupdf_stext_line_first_char(l)
                    while let c = charPtr {
                        let unicodeVal = mupdf_stext_char_c(c)
                        if let scalar = UnicodeScalar(UInt32(unicodeVal)) {
                            let ch = Character(scalar)
                            let q = mupdf_stext_char_quad(c)
                            let o = mupdf_stext_char_origin(c)
                            let size = mupdf_stext_char_size(c)
                            let isBold = (mupdf_stext_char_is_bold(ctx, c) != 0)
                            let isItalic = (mupdf_stext_char_is_italic(ctx, c) != 0)
                            let fontName: String
                            if let cFont = mupdf_stext_char_font_name(ctx, c) {
                                fontName = String(cString: cFont)
                            } else {
                                fontName = ""
                            }
                            
                            let rawColor = mupdf_stext_char_color(c)
                            
                            let textChar = TextCharacter(
                                char: ch,
                                quad: PDFQuad(fzQuad: q),
                                origin: CGPoint(x: CGFloat(o.x), y: CGFloat(o.y)),
                                size: size,
                                isBold: isBold,
                                isItalic: isItalic,
                                fontName: fontName,
                                color: rawColor
                            )

                            // Synthesize space if PDF glyph stream positioned the word with an offset rather than a space character
                            if let lastChar = characters.last {
                                let gap = textChar.boundingRect.minX - lastChar.boundingRect.maxX
                                if gap > CGFloat(lastChar.size) * 0.22 && lastChar.char != " " && textChar.char != " " {
                                    let spaceQuad = PDFQuad(
                                        ul: CGPoint(x: lastChar.boundingRect.maxX, y: lastChar.boundingRect.minY),
                                        ur: CGPoint(x: textChar.boundingRect.minX, y: lastChar.boundingRect.minY),
                                        ll: CGPoint(x: lastChar.boundingRect.maxX, y: lastChar.boundingRect.maxY),
                                        lr: CGPoint(x: textChar.boundingRect.minX, y: lastChar.boundingRect.maxY)
                                    )
                                    let spaceChar = TextCharacter(
                                        char: " ",
                                        quad: spaceQuad,
                                        origin: CGPoint(x: lastChar.boundingRect.maxX, y: lastChar.origin.y),
                                        size: lastChar.size,
                                        isBold: lastChar.isBold,
                                        isItalic: lastChar.isItalic,
                                        fontName: lastChar.fontName,
                                        color: lastChar.color
                                    )
                                    characters.append(spaceChar)
                                }
                            }

                            characters.append(textChar)
                        }
                        charPtr = mupdf_stext_next_char(c)
                    }
                    lines.append(TextLine(bbox: lineBBox, characters: characters))
                    linePtr = mupdf_stext_next_line(l)
                }
            }
            
            let vectorInfo: VectorInfo?
            if bType == .vector {
                let vFlags = mupdf_stext_block_vector_flags(b)
                let vArgb = mupdf_stext_block_vector_argb(b)
                vectorInfo = VectorInfo(flags: vFlags, color: vArgb)
            } else {
                vectorInfo = nil
            }

            blocks.append(TextBlock(type: bType, bbox: blockBBox, lines: lines, vectorInfo: vectorInfo))
            blockPtr = mupdf_stext_next_block(b)
        }

        // Match vector strokes against text characters across all text blocks to detect underlines and strikethroughs
        let vectorBlocks = blocks.filter { $0.type == .vector }
        if !vectorBlocks.isEmpty {
            for bIdx in 0..<blocks.count {
                guard blocks[bIdx].type == .text else { continue }
                for lIdx in 0..<blocks[bIdx].lines.count {
                    let line = blocks[bIdx].lines[lIdx]
                    let lineMinY = line.bbox.minY - 3.5
                    let lineMaxY = line.bbox.maxY + 3.5

                    let candidateVectors = vectorBlocks.filter { v in
                        v.bbox.height <= 2.5 && v.bbox.width >= 2.5 && v.bbox.midY >= lineMinY && v.bbox.midY <= lineMaxY
                    }
                    guard !candidateVectors.isEmpty else { continue }

                    var updatedCharacters = line.characters
                    var lineChanged = false

                    for cIdx in 0..<updatedCharacters.count {
                        let char = updatedCharacters[cIdx]
                        let charMidX = char.boundingRect.midX
                        let charBaseline = char.origin.y

                        for v in candidateVectors {
                            guard charMidX >= (v.bbox.minX - 0.5) && charMidX <= (v.bbox.maxX + 0.5) else { continue }

                            if v.bbox.midY >= charBaseline - 1.2 && v.bbox.midY <= charBaseline + 3.0 {
                                updatedCharacters[cIdx].isUnderline = true
                                lineChanged = true
                            } else if v.bbox.midY < charBaseline - 1.5 && v.bbox.midY >= charBaseline - CGFloat(char.size) * 0.85 {
                                updatedCharacters[cIdx].isStrikethrough = true
                                lineChanged = true
                            }
                        }
                    }

                    // Post-process: interpolate underline and strikethrough across spaces between decorated characters
                    for cIdx in 0..<updatedCharacters.count {
                        guard updatedCharacters[cIdx].char == " " else { continue }
                        var prevIdx = cIdx - 1
                        while prevIdx >= 0 && updatedCharacters[prevIdx].char == " " {
                            prevIdx -= 1
                        }
                        var nextIdx = cIdx + 1
                        while nextIdx < updatedCharacters.count && updatedCharacters[nextIdx].char == " " {
                            nextIdx += 1
                        }

                        if prevIdx >= 0 && nextIdx < updatedCharacters.count {
                            if updatedCharacters[prevIdx].isUnderline && updatedCharacters[nextIdx].isUnderline {
                                updatedCharacters[cIdx].isUnderline = true
                                lineChanged = true
                            }
                            if updatedCharacters[prevIdx].isStrikethrough && updatedCharacters[nextIdx].isStrikethrough {
                                updatedCharacters[cIdx].isStrikethrough = true
                                lineChanged = true
                            }
                        }
                    }

                    if lineChanged {
                        blocks[bIdx].lines[lIdx] = TextLine(bbox: line.bbox, characters: updatedCharacters)
                    }
                }
            }
        }
        
        return StructuredPage(pageIndex: pageIndex, bounds: pageBounds, blocks: blocks)
    }
    
    /// Loads structured text for a page
    public static func load(from page: FZPage, pageIndex: Int, ctx: FZContext) throws -> StructuredPage {
        var stextPtr: FZStextPage?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_stext_page_load(ctx, page, &stextPtr, &errorMsg)
        guard ret == 0, let stext = stextPtr else {
            let msg = errorMsg != nil ? String(cString: errorMsg!) : "Failed to load structured text"
            throw PDFError.stextFailed(msg)
        }
        defer { mupdf_stext_page_drop(ctx, stext) }
        
        var rect = fz_rect()
        mupdf_page_bounds(ctx, page, &rect, nil)
        let pageBounds = CGRect(x: CGFloat(rect.x0), y: CGFloat(rect.y0), width: CGFloat(rect.x1 - rect.x0), height: CGFloat(rect.y1 - rect.y0))
        
        return load(fromStext: stext, pageIndex: pageIndex, pageBounds: pageBounds, ctx: ctx)
    }
}
