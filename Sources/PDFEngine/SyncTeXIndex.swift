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
import Foundation
import SyncTeX

/// A place in a TeX source file.
public struct SyncTeXSourceLocation: Equatable, Sendable {
    /// Absolute path.
    public let file: String
    /// 1-based.
    public let line: Int
    /// 0-based, or nil when TeX didn't record one (it usually doesn't).
    public let column: Int?
}

/// A box TeX set for a line of source, in SyncTeX's space: PDF points from the top-left of the
/// page's MediaBox, y down. `SyncTeXPageMapping` takes it to page space.
public struct SyncTeXBox: Equatable, Sendable {
    /// 0-based.
    public let pageIndex: Int
    public let rect: CGRect
}

/// Where a PDF's SyncTeX file is. TeX names it after the PDF it wrote — `paper.pdf` gets
/// `paper.synctex.gz` — so only a file of that name counts; another PDF in the same folder never
/// uses it.
public struct SyncTeXFile: Equatable, Sendable {
    public let url: URL
    /// Set while TeX is writing a new one (`paper.synctex(busy)`); `url` is then the last build's.
    public let isBusy: Bool

    /// Folders besides the PDF's own where builds commonly put the SyncTeX file, relative to it.
    static let buildDirectories = ["build", "out", "output", "aux", ".aux"]

    /// The SyncTeX file for the PDF at `pdfPath`, if there is one.
    public static func find(forPDF pdfPath: String) -> SyncTeXFile? {
        let pdf = URL(fileURLWithPath: pdfPath)
        let base = pdf.deletingPathExtension().lastPathComponent
        // TeX quotes a job name with spaces in it: "my paper".synctex.gz.
        let names = [base, "\"\(base)\""]
        let folders = [pdf.deletingLastPathComponent()]
            + buildDirectories.map { pdf.deletingLastPathComponent().appendingPathComponent($0, isDirectory: true) }
        let fm = FileManager.default
        for folder in folders {
            for name in names {
                let busy = fm.fileExists(atPath: folder.appendingPathComponent("\(name).synctex(busy)").path)
                for suffix in [".synctex.gz", ".synctex"] {
                    let candidate = folder.appendingPathComponent(name + suffix)
                    var isDirectory: ObjCBool = false
                    if fm.fileExists(atPath: candidate.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                        return SyncTeXFile(url: candidate, isBusy: busy)
                    }
                }
            }
        }
        return nil
    }

    /// Modification date and size, to tell when TeX has written it again.
    public var signature: Signature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int64 else { return nil }
        return Signature(modified: date, size: size)
    }

    public struct Signature: Equatable, Sendable {
        public let modified: Date
        public let size: Int64
    }
}

/// A parsed SyncTeX file, answering forward (source → PDF) and backward (PDF → source) queries
/// through the official SyncTeX parser. Its scanner isn't thread-safe, so every use is under a
/// lock; parsing a large file takes a moment, so make one off the main thread.
public final class SyncTeXIndex: @unchecked Sendable {
    public let file: SyncTeXFile
    public let signature: SyncTeXFile.Signature?
    /// The PDF the index is for.
    public let pdfPath: String
    /// Pages the SyncTeX file describes.
    public let pageCount: Int

    private let lock = NSLock()
    private let scanner: synctex_scanner_p

    /// Parses `file`, made for the PDF at `pdfPath`; nil if it can't be read.
    public init?(file: SyncTeXFile, pdfPath: String) {
        let signature = file.signature
        // The parser finds the file from the PDF's path; tell it the folder when it isn't the PDF's.
        let pdfFolder = URL(fileURLWithPath: pdfPath).deletingLastPathComponent().standardizedFileURL.path
        let fileFolder = file.url.deletingLastPathComponent().standardizedFileURL.path
        let buildDirectory = fileFolder == pdfFolder ? nil : fileFolder
        let made: synctex_scanner_p? = pdfPath.withCString { output in
            if let buildDirectory {
                return buildDirectory.withCString { synctex_scanner_new_with_output_file(output, $0, 1) }
            }
            return synctex_scanner_new_with_output_file(output, nil, 1)
        }
        guard let made else { return nil }
        var pages = 0
        while synctex_sheet(made, Int32(pages + 1)) != nil { pages += 1 }
        guard pages > 0 else {
            synctex_scanner_free(made)
            return nil
        }
        self.scanner = made
        self.file = file
        self.signature = signature
        self.pdfPath = pdfPath
        self.pageCount = pages
    }

    deinit {
        synctex_scanner_free(scanner)
    }

    /// Whether this was made for a PDF of `pageCount` pages. A SyncTeX file describing pages the
    /// PDF doesn't have was left by a different document of the same name.
    public func matches(pageCount documentPages: Int) -> Bool {
        pageCount <= documentPages
    }

    /// Whether the file on disk is still the one parsed.
    public var isCurrent: Bool {
        file.signature == signature && SyncTeXFile.find(forPDF: pdfPath)?.url == file.url
    }

    /// The boxes `line` of `source` made, closest to `pageHint` (0-based) first, and only those on
    /// the first page with any. Empty if TeX recorded nothing for that line.
    public func boxes(source: String, line: Int, column: Int?, pageHint: Int) -> [SyncTeXBox] {
        lock.lock()
        defer { lock.unlock() }
        let found = queryBoxes(name: source, line: line, column: column, pageHint: pageHint)
        if !found.isEmpty { return found }
        // The editor's name for the file can differ from TeX's (/tmp and /private/tmp, a symlinked
        // folder): ask again with the name TeX recorded for the same file on disk.
        guard let recorded = recordedName(sameFileAs: source), recorded != source else { return [] }
        return queryBoxes(name: recorded, line: line, column: column, pageHint: pageHint)
    }

    /// The input name TeX recorded for the file at `path`: the one that is the same file on disk
    /// (same device and inode), whatever the path to it.
    private func recordedName(sameFileAs path: String) -> String? {
        guard let wanted = Self.fileIdentity(path) else { return nil }
        var tag: Int32 = 1
        while tag <= 100_000, let name = synctex_scanner_get_name(scanner, tag) {
            let recorded = String(cString: name)
            if Self.fileIdentity(resolve(recorded)) == wanted { return recorded }
            tag += 1
        }
        return nil
    }

    private struct FileIdentity: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    private static func fileIdentity(_ path: String) -> FileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }

    private func queryBoxes(name source: String, line: Int, column: Int?, pageHint: Int) -> [SyncTeXBox] {
        let count = source.withCString { name in
            synctex_display_query(scanner, name, Int32(clamping: line), Int32(clamping: column ?? -1), Int32(clamping: pageHint + 1))
        }
        guard count > 0 else { return [] }
        var result: [SyncTeXBox] = []
        while let node = synctex_scanner_next_result(scanner) {
            let page = Int(synctex_node_page(node)) - 1
            guard page >= 0 else { continue }
            if let first = result.first, first.pageIndex != page { continue }
            let h = CGFloat(synctex_node_box_visible_h(node))
            let v = CGFloat(synctex_node_box_visible_v(node))
            let width = CGFloat(synctex_node_box_visible_width(node))
            let height = CGFloat(synctex_node_box_visible_height(node))
            let depth = CGFloat(synctex_node_box_visible_depth(node))
            // The box's baseline is at v; it rises `height` above it and drops `depth` below. A
            // negative width runs leftwards from h.
            let rect = CGRect(x: h, y: v - height, width: width, height: height + depth).standardized
            guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite else { continue }
            result.append(SyncTeXBox(pageIndex: page, rect: rect))
        }
        return result
    }

    /// The source line that made what's at `point` (SyncTeX space) on page `pageIndex` (0-based).
    public func sourceLocation(pageIndex: Int, point: CGPoint) -> SyncTeXSourceLocation? {
        lock.lock()
        defer { lock.unlock() }
        guard point.x.isFinite, point.y.isFinite,
              synctex_edit_query(scanner, Int32(clamping: pageIndex + 1), Float(point.x), Float(point.y)) > 0 else { return nil }
        while let node = synctex_scanner_next_result(scanner) {
            let line = Int(synctex_node_line(node))
            guard line > 0, let name = synctex_scanner_get_name(scanner, synctex_node_tag(node)) else { continue }
            let column = Int(synctex_node_column(node))
            return SyncTeXSourceLocation(file: resolve(String(cString: name)), line: line, column: column >= 0 ? column : nil)
        }
        return nil
    }

    /// TeX records input files as it was given them, often relative to the folder it ran in
    /// (`./chapter1.tex`). That's usually the SyncTeX file's folder, else the PDF's.
    private func resolve(_ name: String) -> String {
        if name.hasPrefix("/") { return URL(fileURLWithPath: name).standardized.path }
        let candidates = [file.url.deletingLastPathComponent(), URL(fileURLWithPath: pdfPath).deletingLastPathComponent()]
            .map { $0.appendingPathComponent(name).standardizedFileURL.path }
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? candidates[0]
    }
}

/// Takes points between SyncTeX space (PDF points from the top-left of the MediaBox, y down) and
/// MuPDF's page space (from the top-left of the CropBox, turned by the page's /Rotate).
public struct SyncTeXPageMapping: Equatable, Sendable {
    public let mediaBox: CGRect
    /// PDF user space (origin bottom-left) to page space.
    public let userToPage: CGAffineTransform

    public init(mediaBox: CGRect, userToPage: CGAffineTransform) {
        self.mediaBox = mediaBox.standardized
        self.userToPage = userToPage
    }

    public func pagePoint(fromSyncTeX point: CGPoint) -> CGPoint {
        CGPoint(x: mediaBox.minX + point.x, y: mediaBox.maxY - point.y).applying(userToPage)
    }

    public func pageRect(fromSyncTeX rect: CGRect) -> CGRect {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY)]
            .map(pagePoint(fromSyncTeX:))
        return CGRect(x: min(corners[0].x, corners[1].x), y: min(corners[0].y, corners[1].y),
                      width: abs(corners[0].x - corners[1].x), height: abs(corners[0].y - corners[1].y))
    }

    public func syncTeXPoint(fromPage point: CGPoint) -> CGPoint {
        let user = point.applying(userToPage.inverted())
        return CGPoint(x: user.x - mediaBox.minX, y: mediaBox.maxY - user.y)
    }
}
