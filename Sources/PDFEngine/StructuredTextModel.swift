import Foundation
import CoreGraphics
import MuPDFBridge

public struct TextCharacter: Sendable, Equatable {
    public let char: Character
    public let quad: PDFQuad
    public let origin: CGPoint
    public let size: Float
    
    public var boundingRect: CGRect {
        quad.boundingRect
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
}

public enum BlockType: Int, Sendable {
    case text = 0
    case image = 1
    case other = 2
}

public struct TextBlock: Sendable, Equatable {
    public let type: BlockType
    public let bbox: CGRect
    public let lines: [TextLine]
    public let text: String
    
    public init(type: BlockType, bbox: CGRect, lines: [TextLine]) {
        self.type = type
        self.bbox = bbox
        self.lines = lines
        self.text = lines.map { $0.text }.joined(separator: "\n")
    }
}

public struct StructuredPage: Sendable {
    public let pageIndex: Int
    public let bounds: CGRect
    public let blocks: [TextBlock]
    
    public var plainText: String {
        blocks.filter { $0.type == .text }.map { $0.text }.joined(separator: "\n\n")
    }

    /// Plain text built only from blocks that read like actual running prose, excluding
    /// figure/table/diagram fragments — used by the Agent tab's indexing (see
    /// SemanticIndexBuilder), where that kind of layout noise dilutes embeddings and can visibly
    /// confuse the on-device model during answer synthesis. Extracted text can't tell a table cell
    /// from a paragraph by content alone (both are just embedded characters), but their geometry
    /// differs consistently: a paragraph's lines wrap close to the page's usable text width, while
    /// table/diagram labels sit in short, narrow lines regardless of what words they contain.
    /// Verified against a real technical PDF: every genuine prose block measured >= 0.27 of the page
    /// width, every figure/table fragment <= 0.10 — comfortable margin either side of the 0.15
    /// cutoff here.
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
    public static func load(fromStext stext: FZStextPage, pageIndex: Int, pageBounds: CGRect) -> StructuredPage {
        var blocks: [TextBlock] = []
        var blockPtr = mupdf_stext_first_block(stext)
        while let b = blockPtr {
            let rawType = mupdf_stext_block_type(b)
            let bType: BlockType = (rawType == 0) ? .text : ((rawType == 1) ? .image : .other)
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
                            
                            characters.append(TextCharacter(
                                char: ch,
                                quad: PDFQuad(fzQuad: q),
                                origin: CGPoint(x: CGFloat(o.x), y: CGFloat(o.y)),
                                size: size
                            ))
                        }
                        charPtr = mupdf_stext_next_char(c)
                    }
                    lines.append(TextLine(bbox: lineBBox, characters: characters))
                    linePtr = mupdf_stext_next_line(l)
                }
            }
            
            blocks.append(TextBlock(type: bType, bbox: blockBBox, lines: lines))
            blockPtr = mupdf_stext_next_block(b)
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
        
        return load(fromStext: stext, pageIndex: pageIndex, pageBounds: pageBounds)
    }
}
