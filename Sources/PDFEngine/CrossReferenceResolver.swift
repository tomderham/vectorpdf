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
    // Only the cache file's name is persisted (via ReadingStateManager's JSON-in-UserDefaults
    // storage) — the actual bitmap lives in a file under ~/Library/Caches instead, since
    // UserDefaults' plist-backed storage isn't meant to hold raw image bytes.
    public let thumbnailFileName: String?
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        label: String,
        snippet: String = "",
        targetPage: Int,
        targetPoint: CGPoint? = nil,
        targetRect: CGRect? = nil,
        sourceRect: CGRect? = nil,
        sourcePage: Int,
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

    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VectorPDFSnapshotThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func writeThumbnailFile(id: UUID, data: Data) -> String? {
        let fileName = "\(id.uuidString).png"
        do {
            try data.write(to: cacheDirectory.appendingPathComponent(fileName))
            return fileName
        } catch {
            return nil
        }
    }

    public var thumbnailImage: NSImage? {
        guard let thumbnailFileName else { return nil }
        guard let data = try? Data(contentsOf: SnapshotTarget.cacheDirectory.appendingPathComponent(thumbnailFileName)) else { return nil }
        return NSImage(data: data)
    }

    /// Deletes this snapshot's cached thumbnail file, if any. Called when a snapshot is removed so
    /// its file doesn't linger in the cache directory forever.
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
            
            if let cUri = mupdf_link_uri(link) {
                let uri = String(cString: cUri)
                var destPage: Int32 = -1
                var destX: Float = 0
                var destY: Float = 0
                
                if mupdf_resolve_link_page(ctx, doc, uri, &destPage, &destX, &destY) == 0 && destPage >= 0 {
                    let point = CGPoint(x: CGFloat(destX), y: CGFloat(destY))
                    let label = uri.starts(with: "#") ? String(uri.dropFirst()) : uri
                    targets.append(SnapshotTarget(
                        label: label.isEmpty ? "Page \(destPage + 1)" : label,
                        targetPage: Int(destPage),
                        targetPoint: point,
                        sourceRect: linkRect,
                        sourcePage: pageIndex,
                        uri: uri
                    ))
                } else if uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:") {
                    targets.append(SnapshotTarget(
                        label: uri,
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
