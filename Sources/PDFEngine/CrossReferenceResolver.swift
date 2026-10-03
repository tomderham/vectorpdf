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
import AppKit
import MuPDFBridge

public struct SnapshotTarget: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let label: String
    public let snippet: String
    public let targetPage: Int
    public let targetPoint: CGPoint?
    public let targetRect: CGRect?
    public let sourceRect: CGRect?
    public let sourcePage: Int
    public let uri: String?
    // Cache file name persisted in state; bitmap is stored in the cache directory.
    public internal(set) var thumbnailFileName: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        snippet: String = "",
        targetPage: Int,
        targetPoint: CGPoint? = nil,
        targetRect: CGRect? = nil,
        sourceRect: CGRect? = nil,
        sourcePage: Int = 0,
        uri: String? = nil,
        thumbnailData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.snippet = snippet.isEmpty ? label : snippet
        self.targetPage = targetPage
        self.targetPoint = targetPoint
        self.targetRect = targetRect
        self.sourceRect = sourceRect
        self.sourcePage = sourcePage
        self.uri = uri
        self.thumbnailFileName = thumbnailData.flatMap { SnapshotTarget.writeThumbnailFile(id: id, data: $0) }
        self.createdAt = createdAt
    }

    public static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VectorPDFSnapshotThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    public static func writeThumbnailFile(id: UUID, data: Data) -> String? {
        let fileName = "\(id.uuidString).png"
        do {
            try data.write(to: cacheDirectory.appendingPathComponent(fileName))
            return fileName
        } catch {
            return nil
        }
    }

    public static func hasCachedThumbnail(fileName: String?) -> Bool {
        guard let fileName else { return false }
        return FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent(fileName).path)
    }

    public var thumbnailImage: NSImage? {
        guard let thumbnailFileName else { return nil }
        guard let data = try? Data(contentsOf: SnapshotTarget.cacheDirectory.appendingPathComponent(thumbnailFileName)) else { return nil }
        return NSImage(data: data)
    }

    /// Formatted display title showing page number and anchor text.
    public var menuDisplayTitle: String {
        let pageNum = targetPage + 1
        let pagePrefix = "Page \(pageNum)"

        // Pick the most informative descriptive text: label first, fallback to snippet
        let rawDesc = !label.isEmpty ? label : snippet
        let trimmed = rawDesc.trimmingCharacters(in: .whitespacesAndNewlines)

        // If empty or purely "Page X", just show "Page X"
        if trimmed.isEmpty || trimmed.lowercased() == pagePrefix.lowercased() {
            return pagePrefix
        }

        // If it already starts with "Page X", strip or format cleanly
        if trimmed.lowercased().hasPrefix(pagePrefix.lowercased()) {
            let afterPrefix = trimmed.dropFirst(pagePrefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if afterPrefix.isEmpty {
                return pagePrefix
            }
            var cleanDesc = afterPrefix
            if cleanDesc.hasPrefix(":") || cleanDesc.hasPrefix("-") || cleanDesc.hasPrefix("•") {
                cleanDesc = cleanDesc.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if cleanDesc.hasPrefix("“") || cleanDesc.hasPrefix("\"") {
                return "\(pagePrefix) \(cleanDesc)"
            }
            let maxLen = 45
            let truncated = cleanDesc.count > maxLen ? String(cleanDesc.prefix(maxLen)) + "…" : cleanDesc
            return "\(pagePrefix) “\(truncated)”"
        }

        // Otherwise, format as: Page X "Description"
        let maxLen = 45
        let truncated = trimmed.count > maxLen ? String(trimmed.prefix(maxLen)) + "…" : trimmed
        return "\(pagePrefix) “\(truncated)”"
    }

    /// Deletes the cached thumbnail file for this snapshot.
    public func deleteThumbnailFile() {
        guard let thumbnailFileName else { return }
        try? FileManager.default.removeItem(at: SnapshotTarget.cacheDirectory.appendingPathComponent(thumbnailFileName))
    }
}

public final class CrossReferenceResolver: @unchecked Sendable {
    public init() {}
    
    /// Loads interactive PDF links on a page and resolves internal page destinations
    public func resolveLinks(on page: FZPage, pageIndex: Int, doc: FZDocument, ctx: FZContext) -> [SnapshotTarget] {
        var linksPtr: FZLink?
        var errorMsg: UnsafePointer<CChar>?
        let ret = mupdf_links_load(ctx, page, &linksPtr, &errorMsg)
        guard ret == 0, let links = linksPtr else {
            return []
        }
        defer { mupdf_links_drop(ctx, links) }
        
        let stext = try? StructuredPage.load(from: page, pageIndex: pageIndex, ctx: ctx)
        
        var targets: [SnapshotTarget] = []
        var curr: FZLink? = links
        
        while let link = curr {
            let rect = mupdf_link_rect(link)
            let linkRect = CGRect(
                x: CGFloat(rect.x0),
                y: CGFloat(rect.y0),
                width: CGFloat(rect.x1 - rect.x0),
                height: CGFloat(rect.y1 - rect.y0)
            )
            
            // Extract visible anchor text at linkRect on the source page.
            var sourceText = ""
            if let stext {
                let chars = stext.allCharacters.filter { ch in
                    let inter = linkRect.intersection(ch.boundingRect)
                    guard !inter.isNull && inter.width > 0 && inter.height > 0 else { return false }
                    return (inter.height / ch.boundingRect.height) >= 0.35
                }
                if !chars.isEmpty {
                    var str = String(chars.map { $0.char })
                        .replacingOccurrences(of: "\n", with: " ")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    while str.contains("  ") {
                        str = str.replacingOccurrences(of: "  ", with: " ")
                    }
                    if !str.isEmpty && str.count <= 100 {
                        sourceText = str
                    }
                }
            }
            
            if let cUri = mupdf_link_uri(link) {
                let uri = String(cString: cUri)
                var destPage: Int32 = -1
                var destX: Float = 0
                var destY: Float = 0
                
                if mupdf_resolve_link_page(ctx, doc, uri, &destPage, &destX, &destY) == 0 && destPage >= 0 {
                    let point = CGPoint(x: CGFloat(destX), y: CGFloat(destY))
                    let uriLabel = uri.starts(with: "#") ? String(uri.dropFirst()) : uri
                    let label = !sourceText.isEmpty ? sourceText : (uriLabel.isEmpty ? "Page \(destPage + 1)" : uriLabel)
                    targets.append(SnapshotTarget(
                        label: label,
                        targetPage: Int(destPage),
                        targetPoint: point,
                        sourceRect: linkRect,
                        sourcePage: pageIndex,
                        uri: uri
                    ))
                } else if uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:") {
                    let label = !sourceText.isEmpty ? sourceText : uri
                    targets.append(SnapshotTarget(
                        label: label,
                        targetPage: -1,
                        targetPoint: nil,
                        sourceRect: linkRect,
                        sourcePage: pageIndex,
                        uri: uri
                    ))
                }
            }
            
            curr = mupdf_link_next(link)
        }
        
        // Propagate the most informative label across fragments sharing the same URI.
        var bestLabelForURI: [String: String] = [:]
        for t in targets {
            guard let uri = t.uri, !uri.isEmpty else { continue }
            let lbl = t.label
            let isInformative = lbl.range(of: #"\b(?:Table|Figure|Fig\.?|Equation|Eq\.?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            if isInformative {
                if let existing = bestLabelForURI[uri] {
                    if lbl.count > existing.count {
                        bestLabelForURI[uri] = lbl
                    }
                } else {
                    bestLabelForURI[uri] = lbl
                }
            }
        }
        if !bestLabelForURI.isEmpty {
            targets = targets.map { t in
                if let uri = t.uri, let best = bestLabelForURI[uri], t.label != best {
                    return SnapshotTarget(
                        label: best,
                        targetPage: t.targetPage,
                        targetPoint: t.targetPoint,
                        targetRect: t.targetRect,
                        sourceRect: t.sourceRect,
                        sourcePage: t.sourcePage,
                        uri: t.uri
                    )
                }
                return t
            }
        }

        return targets
    }
    
    /// Detects academic references in selected text using regex heuristics
    public func detectAcademicReferences(in text: String, sourcePage: Int, document: PDFDocumentCore) -> [SnapshotTarget] {
        var targets: [SnapshotTarget] = []
        
        let patterns = [
            #"(?:Fig(?:ure|\.)?)\s*([0-9A-Za-z\.\-]+)"#,
            #"(?:Table)\s*([0-9A-Za-z\.\-]+)"#,
            #"(?:Eq(?:uation|\.)?)\s*\(?([0-9A-Za-z\.\-]+)\)?"#,
            #"(?:Theorem|Section|Lemma|Definition)\s*([0-9A-Za-z\.\-]+)"#,
            #"\[([0-9]+)\]"#
        ]
        
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            
            for match in matches {
                let fullLabel = nsString.substring(with: match.range)
                targets.append(SnapshotTarget(
                    label: fullLabel,
                    targetPage: sourcePage,
                    targetPoint: nil,
                    sourceRect: nil,
                    sourcePage: sourcePage
                ))
            }
        }
        
        return targets
    }
}
