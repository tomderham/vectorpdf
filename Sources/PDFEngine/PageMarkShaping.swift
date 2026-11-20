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

import CoreGraphics
import CoreText
import Foundation
import MuPDFBridge

/// Marks in characters the standard fonts (Windows-1252) don't have: laid out with Core Text,
/// which shapes every script and finds fonts for what the chosen one lacks, then drawn as those
/// fonts' glyphs, the fonts embedded with only the glyphs used.
enum PageMarkShaping {
    /// Whether the standard fonts can show all of `text`.
    static func fitsStandardFonts(_ text: String) -> Bool {
        text.canBeConverted(to: .windowsCP1252)
    }

    static func baseFont(_ font: PageMarkSettings.MarkFont, size: CGFloat) -> CTFont {
        let name: String
        switch font {
        case .helvetica: name = "Helvetica"
        case .times: name = "Times-Roman"
        case .courier: name = "Courier"
        case .helveticaBold: name = "Helvetica-Bold"
        }
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    /// One line of text, shaped: runs of glyphs, each in one font, placed from the line's start
    /// on its baseline (y up).
    struct Line {
        struct Run {
            let font: CTFont
            let glyphs: [CGGlyph]
            let positions: [CGPoint]
            /// Each glyph's advance as the font gives it (what readers move by).
            let advances: [CGFloat]
            /// The text each glyph stands for: its cluster, for the first glyph of one.
            let texts: [String]
            /// Stretches of glyphs, in order, with the text to find them as when their order
            /// isn't the text's (a vowel sign drawn before its consonant); nil when it is.
            let segments: [(count: Int, actualText: String?)]
        }
        let runs: [Run]
        let width: CGFloat
    }

    /// `avoiding`: fonts (by PostScript name) not to fall back on, as they couldn't be embedded.
    static func shape(_ text: String, font: PageMarkSettings.MarkFont, size: CGFloat, avoiding: Set<String> = []) -> Line {
        var base = baseFont(font, size: size)
        // The fonts Core Text would fall back on for the user's languages, less those that
        // can't be embedded (PingFang's outlines MuPDF can't read) and those to avoid.
        let languages = Locale.preferredLanguages as CFArray
        // Then fonts that can, for scripts whose usual fonts can't (Chinese, Korean).
        let extra = ["STHeitiSC-Light", "STHeitiTC-Light", "HiraginoSans-W3", "AppleSDGothicNeo-Regular"]
            .map { CTFontDescriptorCreateWithNameAndSize($0 as CFString, size) }
        let cascade = ((CTFontCopyDefaultCascadeListForLanguages(base, languages) as? [CTFontDescriptor] ?? []) + extra).filter { descriptor in
            guard let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return true }
            let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
            // Only fonts that exist: a missing one comes back as another.
            return !avoiding.contains(name) && (CTFontCopyPostScriptName(font) as String) == name && canEmbed(font)
        }
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontCascadeListAttribute: cascade] as CFDictionary)
        base = CTFontCreateCopyWithAttributes(base, size, nil, descriptor)
        let attributed = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): base])
        let line = CTLineCreateWithAttributedString(attributed)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let runs = (CTLineGetGlyphRuns(line) as? [CTRun] ?? []).compactMap { run -> Line.Run? in
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { return nil }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = attributes[kCTFontAttributeName] as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            var sizes = [CGSize](repeating: .zero, count: count)
            CTFontGetAdvancesForGlyphs(runFont, .horizontal, glyphs, &sizes, count)
            // Each glyph's text: from its index in the string to the next index any glyph
            // starts at (in logical order), so a conjunct maps to all its characters.
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            let utf16 = Array(text.utf16)
            let range = CTRunGetStringRange(run)
            let starts = Set(indices).sorted()
            var seen = Set<CFIndex>()
            let texts = indices.map { start -> String in
                guard seen.insert(start).inserted else { return "" }
                let end = starts.first(where: { $0 > start }) ?? (range.location + range.length)
                guard start >= 0, end <= utf16.count, start < end else { return "" }
                return String(decoding: utf16[start..<end], as: UTF16.self)
            }
            let segments = Self.segments(indices: indices, texts: texts, utf16: utf16, runEnd: range.location + range.length,
                                         rightToLeft: CTRunGetStatus(run).contains(.rightToLeft))
            return Line.Run(font: runFont, glyphs: glyphs, positions: positions, advances: sizes.map(\.width), texts: texts, segments: segments)
        }
        return Line(runs: runs, width: width)
    }

    /// A run's glyphs split where every glyph before comes earlier in the text than every glyph
    /// after; each stretch with its text if its glyphs, read in order, don't say it. A run set
    /// right to left is one stretch, without.
    static func segments(indices: [CFIndex], texts: [String], utf16: [UInt16], runEnd: Int, rightToLeft: Bool) -> [(count: Int, actualText: String?)] {
        let n = indices.count
        guard n > 0 else { return [] }
        func logical(_ from: Int, _ to: Int) -> String {
            let lo = max(0, from), hi = min(utf16.count, to)
            return lo < hi ? String(decoding: utf16[lo..<hi], as: UTF16.self) : ""
        }
        // Glyphs set right to left are read back in text order by readers' own bidi handling,
        // which ActualText only confuses.
        if rightToLeft { return [(n, nil)] }
        var suffixMin = [CFIndex](repeating: .max, count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) { suffixMin[i] = min(indices[i], suffixMin[i + 1]) }
        var result: [(count: Int, actualText: String?)] = []
        var start = 0, prefixMax: CFIndex = .min
        let starts = Set(indices).sorted()
        for i in 0..<n {
            prefixMax = max(prefixMax, indices[i])
            guard i == n - 1 || prefixMax < suffixMin[i + 1] else { continue }
            let segment = start...i
            let inOrder = segment.map { texts[$0] }.joined()
            let lo = segment.map { indices[$0] }.min()!
            let hi = starts.first(where: { $0 > prefixMax }) ?? runEnd
            let text = logical(lo, hi)
            result.append((segment.count, inOrder == text ? nil : text))
            start = i + 1
        }
        return result
    }

    /// A font as a standalone OpenType file, from its tables (so one face of a collection works
    /// too); nil if its licence doesn't allow embedding.
    static func fontData(_ font: CTFont) -> Data? {
        let name = CTFontCopyPostScriptName(font) as String as NSString
        if let cached = fontDataCache.object(forKey: name) { return cached.length == 0 ? nil : cached as Data }
        let data = buildFontData(font)
        fontDataCache.setObject((data ?? Data()) as NSData, forKey: name, cost: data?.count ?? 0)
        return data
    }

    /// Whether a font can be embedded: its licence allows it, and its outlines are TrueType or
    /// CFF, which MuPDF can subset. From its table list, so it's quick; remembered by name.
    static func canEmbed(_ font: CTFont) -> Bool {
        let name = CTFontCopyPostScriptName(font) as String as NSString
        if let known = embeddableCache.object(forKey: name) { return known.boolValue }
        var result = false
        if let tagArray = CTFontCopyAvailableTables(font, []) {
            let tags = Set((0..<CFArrayGetCount(tagArray)).map { UInt32(truncatingIfNeeded: Int(bitPattern: CFArrayGetValueAtIndex(tagArray, $0))) })
            let outlines = (tags.contains(0x676C_7966) && tags.contains(0x6C6F_6361)) || tags.contains(0x4346_4620) || tags.contains(0x4346_4632)
            var licensed = true
            if let os2 = CTFontCopyTable(font, 0x4F53_2F32, []) as Data?, os2.count >= 10 {
                licensed = (UInt16(os2[8]) << 8 | UInt16(os2[9])) & 0x000F != 0x0002
            }
            result = outlines && licensed
        }
        embeddableCache.setObject(NSNumber(value: result), forKey: name)
        return result
    }

    nonisolated(unsafe) private static let embeddableCache = NSCache<NSString, NSNumber>()

    /// Fonts rebuilt lately, as the preview lays the marks out again with each change.
    nonisolated(unsafe) private static let fontDataCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()

    private static func buildFontData(_ font: CTFont) -> Data? {
        // The array holds the tags themselves, not objects.
        guard let tagArray = CTFontCopyAvailableTables(font, []) else { return nil }
        let tags = (0..<CFArrayGetCount(tagArray)).map { UInt32(truncatingIfNeeded: Int(bitPattern: CFArrayGetValueAtIndex(tagArray, $0))) }
        // Outlines MuPDF can subset: TrueType ('glyf' with 'loca') or CFF. Not Apple's 'hvgl'
        // (PingFang's), nor bitmaps.
        let hasTrueType = tags.contains(0x676C_7966) && tags.contains(0x6C6F_6361)
        let hasCFF = tags.contains(0x4346_4620) || tags.contains(0x4346_4632)
        guard hasTrueType || hasCFF else { return nil }
        var tables: [(tag: UInt32, data: Data)] = []
        for tag in tags {
            guard let data = CTFontCopyTable(font, tag, []) as Data? else { continue }
            tables.append((tag, data))
        }
        tables.sort { $0.tag < $1.tag }
        // OS/2 fsType bit 1: may not be embedded.
        if let os2 = tables.first(where: { $0.tag == 0x4F53_2F32 })?.data, os2.count >= 10 {
            let fsType = UInt16(os2[8]) << 8 | UInt16(os2[9])
            if fsType & 0x000F == 0x0002 { return nil }
        }
        let isCFF = tables.contains { $0.tag == 0x4346_4620 || $0.tag == 0x4346_4632 }  // 'CFF ', 'CFF2'
        var out = Data()
        func u16(_ v: Int) { out.append(UInt8(v >> 8 & 0xFF)); out.append(UInt8(v & 0xFF)) }
        func u32(_ v: UInt32) { for shift in [24, 16, 8, 0] { out.append(UInt8(v >> UInt32(shift) & 0xFF)) } }
        func checksum(_ data: Data) -> UInt32 {
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> UInt32 in
                var sum: UInt32 = 0
                let words = raw.count / 4
                for i in 0..<words { sum &+= UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)) }
                var last: UInt32 = 0
                for k in 0..<4 { last = last << 8 | UInt32(words * 4 + k < raw.count ? raw[words * 4 + k] : 0) }
                return raw.count % 4 == 0 ? sum : sum &+ last
            }
        }
        let n = tables.count
        var power = 1, log = 0
        while power * 2 <= n { power *= 2; log += 1 }
        u32(isCFF ? 0x4F54_544F : 0x0001_0000)
        u16(n); u16(power * 16); u16(log); u16(n * 16 - power * 16)
        var offset = 12 + 16 * n
        for table in tables {
            u32(table.tag)
            u32(checksum(table.data))
            u32(UInt32(offset))
            u32(UInt32(table.data.count))
            offset += (table.data.count + 3) & ~3
        }
        for table in tables {
            out.append(table.data)
            out.append(contentsOf: [UInt8](repeating: 0, count: ((table.data.count + 3) & ~3) - table.data.count))
        }
        return out
    }

    /// The fonts the shaped lines of a set of marks use, each embedded once with the glyphs used.
    final class Fonts {
        private var fonts: [String: CTFont] = [:]
        private var glyphs: [String: Set<CGGlyph>] = [:]
        /// What each glyph of each font stands for, the first time it's met.
        private var glyphTexts: [String: [CGGlyph: String]] = [:]
        private(set) var objects: [String: Int32] = [:]
        /// The glyphs each font was embedded with.
        private var embeddedGlyphs: [String: Set<CGGlyph>] = [:]

        init() {}

        /// With the fonts an earlier attempt embedded, to use again: embedded again, with the
        /// glyphs of both, if this one uses glyphs of theirs that one didn't.
        init(after earlier: Fonts) {
            objects = earlier.objects
            embeddedGlyphs = earlier.embeddedGlyphs
            glyphTexts = earlier.glyphTexts
        }

        func add(_ line: Line) {
            for run in line.runs {
                let name = CTFontCopyPostScriptName(run.font) as String
                fonts[name] = fonts[name] ?? run.font
                glyphs[name, default: []].formUnion(run.glyphs)
                for (glyph, text) in zip(run.glyphs, run.texts) where !text.isEmpty && glyphTexts[name]?[glyph] == nil {
                    glyphTexts[name, default: [:]][glyph] = text
                }
            }
        }

        /// Embeds them in `doc`; returns those that couldn't be (by their licence, or as MuPDF
        /// can't subset them), to lay the text out again without them.
        func embed(ctx: FZContext, doc: FZDocument) -> Set<String> {
            var failed = Set<String>()
            for (name, font) in fonts.sorted(by: { $0.key < $1.key }) where !(glyphs[name] ?? []).isSubset(of: embeddedGlyphs[name] ?? []) || objects[name] == nil {
                guard let data = PageMarkShaping.fontData(font) else { failed.insert(name); continue }
                let used = (glyphs[name] ?? []).union(embeddedGlyphs[name] ?? [])
                let gids = used.sorted().map { Int32($0) }
                var objnum: Int32 = 0
                var error: UnsafePointer<CChar>?
                let status = data.withUnsafeBytes { bytes in
                    gids.withUnsafeBufferPointer {
                        mupdf_pdf_add_mark_font(ctx, doc, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, $0.baseAddress, Int32($0.count), &objnum, &error)
                    }
                }
                guard status == 0 else {
                    print("Couldn't embed \(name) for a page mark: \(error.map { String(cString: $0) } ?? "")")
                    failed.insert(name)
                    continue
                }
                objects[name] = objnum
                embeddedGlyphs[name] = used
                setText(ctx: ctx, doc: doc, font: name, objnum: objnum)
            }
            return failed
        }

        /// The font's ToUnicode map, from what its glyphs stood for in the text laid out.
        private func setText(ctx: FZContext, doc: FZDocument, font name: String, objnum: Int32) {
            let mapped = (glyphTexts[name] ?? [:]).sorted { $0.key < $1.key }
            guard !mapped.isEmpty else { return }
            let gids = mapped.map { UInt16($0.key) }
            let strings = mapped.map { strdup($0.value) }
            defer { strings.forEach { free($0) } }
            var error: UnsafePointer<CChar>?
            let pointers = strings.map { UnsafePointer($0) }
            _ = gids.withUnsafeBufferPointer { g in
                pointers.withUnsafeBufferPointer { t in
                    mupdf_pdf_set_mark_font_text(ctx, doc, objnum, g.baseAddress, t.baseAddress, Int32(g.count), &error)
                }
            }
        }

        /// Whether every font used is embedded.
        var allEmbedded: Bool {
            fonts.keys.allSatisfy { objects[$0] != nil && (glyphs[$0] ?? []).isSubset(of: embeddedGlyphs[$0] ?? []) }
        }

        func object(for font: CTFont) -> Int32 { objects[CTFontCopyPostScriptName(font) as String] ?? 0 }
    }

    /// Draws shaped lines as a mark on `page`: `lines` with their origins in the mark's space,
    /// placed on the page by `matrix`.
    static func addMark(ctx: FZContext, doc: FZDocument, page: Int, fonts: Fonts, lines: [(Line, CGPoint)], size: CGFloat,
                        kind: String, artifact: String, color: PageMarkSettings.MarkColor, opacity: Double?,
                        matrix: CGAffineTransform, text: String) throws {
        var runs: [(objnum: Int32, gids: [UInt16], xy: [Float], advances: [Float], segments: [(count: Int, actualText: String?)])] = []
        for (line, origin) in lines {
            for run in line.runs {
                let objnum = fonts.object(for: run.font)
                guard objnum > 0 else { continue }
                let xy = run.positions.flatMap { [Float(origin.x + $0.x), Float(origin.y + $0.y)] }
                runs.append((objnum, run.glyphs.map { UInt16($0) }, xy, run.advances.map { Float($0) }, run.segments))
            }
        }
        guard !runs.isEmpty else { return }
        var error: UnsafePointer<CChar>?
        // Buffers of our own for C to read, freed afterwards.
        var allocated: [UnsafeMutableRawPointer] = []
        var texts: [UnsafeMutablePointer<CChar>] = []
        defer {
            allocated.forEach { $0.deallocate() }
            texts.forEach { free($0) }
        }
        let cRuns: [mupdf_glyph_run] = runs.map { run in
            let gids = UnsafeMutablePointer<UInt16>.allocate(capacity: run.gids.count)
            gids.initialize(from: run.gids, count: run.gids.count)
            let xy = UnsafeMutablePointer<Float>.allocate(capacity: run.xy.count)
            xy.initialize(from: run.xy, count: run.xy.count)
            let advances = UnsafeMutablePointer<Float>.allocate(capacity: run.advances.count)
            advances.initialize(from: run.advances, count: run.advances.count)
            let counts = UnsafeMutablePointer<Int32>.allocate(capacity: max(1, run.segments.count))
            let segmentTexts = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: max(1, run.segments.count))
            for (k, segment) in run.segments.enumerated() {
                counts[k] = Int32(segment.count)
                if let text = segment.actualText, let copy = strdup(text) {
                    texts.append(copy)
                    segmentTexts[k] = UnsafePointer(copy)
                } else {
                    segmentTexts[k] = nil
                }
            }
            allocated += [UnsafeMutableRawPointer(gids), UnsafeMutableRawPointer(xy), UnsafeMutableRawPointer(advances),
                          UnsafeMutableRawPointer(counts), UnsafeMutableRawPointer(segmentTexts)]
            return mupdf_glyph_run(font_objnum: run.objnum, size: Float(size), n: Int32(run.gids.count), gids: gids, xy: xy, advances: advances,
                                   n_segments: Int32(run.segments.count), segment_counts: counts, segment_texts: segmentTexts)
        }
        let status: Int32 = kind.withCString { cKind in
            artifact.withCString { cArtifact in
                text.withCString { cText in
                    cRuns.withUnsafeBufferPointer { runPointer in
                        var mark = mupdf_glyph_mark()
                        mark.kind = cKind
                        mark.artifact = cArtifact
                        mark.size = Float(size)
                        mark.color = (Float(color.red), Float(color.green), Float(color.blue))
                        mark.opacity = Float(opacity ?? -1)
                        mark.matrix = (Float(matrix.a), Float(matrix.b), Float(matrix.c), Float(matrix.d), Float(matrix.tx), Float(matrix.ty))
                        mark.n_runs = Int32(runPointer.count)
                        mark.runs = runPointer.baseAddress
                        mark.actual_text = nil
                        _ = cText
                        return mupdf_page_add_glyph_mark(ctx, doc, Int32(page), &mark, &error)
                    }
                }
            }
        }
        guard status == 0 else { throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The mark can't be added") }
    }
}
