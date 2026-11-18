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
import MuPDFBridge

/// Where an outline entry is: its index among its siblings at each level, from the top.
public typealias OutlinePath = [Int]

extension Array where Element == PDFOutlineNode {
    /// The path of the entry with `id`.
    public func path(of id: UUID) -> OutlinePath? {
        for (index, node) in enumerated() {
            if node.id == id { return [index] }
            if let below = node.children.path(of: id) { return [index] + below }
        }
        return nil
    }

    public func node(at path: OutlinePath) -> PDFOutlineNode? {
        guard let first = path.first, first >= 0, first < count else { return nil }
        return path.count == 1 ? self[first] : self[first].children.node(at: OutlinePath(path.dropFirst()))
    }

    /// How many entries are at the level `path` ends in (the siblings of the entry there).
    func siblingCount(at path: OutlinePath) -> Int {
        guard path.count > 1 else { return count }
        return node(at: OutlinePath(path.dropLast()))?.children.count ?? 0
    }
}

extension PDFDocumentCore {
    /// Adds an entry going to `y` (page space, top-down) on `page`, at `path` (before the entry
    /// there, or after the last).
    public func addOutlineEntry(title: String, page: Int, y: CGFloat, at path: OutlinePath) throws {
        try editOutline { ctx, doc, error in
            guard let uri = mupdf_outline_page_uri(ctx, doc, Int32(page), Float(y)) else { return -1 }
            defer { fz_free(ctx, uri) }
            return path.map(Int32.init).withUnsafeBufferPointer {
                mupdf_outline_insert(ctx, doc, $0.baseAddress, Int32(path.count), title, uri, &error)
            }
        }
    }

    public func renameOutlineEntry(at path: OutlinePath, to title: String) throws {
        try editOutline { ctx, doc, error in
            path.map(Int32.init).withUnsafeBufferPointer {
                mupdf_outline_update(ctx, doc, $0.baseAddress, Int32(path.count), title, nil, &error)
            }
        }
    }

    /// Points an entry at `y` on `page`.
    public func setOutlineEntryDestination(at path: OutlinePath, page: Int, y: CGFloat) throws {
        try editOutline { ctx, doc, error in
            guard let uri = mupdf_outline_page_uri(ctx, doc, Int32(page), Float(y)) else { return -1 }
            defer { fz_free(ctx, uri) }
            return path.map(Int32.init).withUnsafeBufferPointer {
                mupdf_outline_update(ctx, doc, $0.baseAddress, Int32(path.count), nil, uri, &error)
            }
        }
    }

    public func deleteOutlineEntry(at path: OutlinePath) throws {
        try editOutline { ctx, doc, error in
            path.map(Int32.init).withUnsafeBufferPointer {
                mupdf_outline_delete(ctx, doc, $0.baseAddress, Int32(path.count), &error)
            }
        }
    }

    /// Moves an entry, with those under it, to `destination`: a place in the outline as it is
    /// now (before the entry there, or after the last at its level). A place inside the entry
    /// itself isn't one.
    public func moveOutlineEntry(from source: OutlinePath, to destination: OutlinePath) throws {
        guard !destination.starts(with: source) else { throw PDFError.operationFailed("An entry can't go inside itself") }
        let target = Self.placeAfterRemoving(source, destination)
        guard target != source else { return }
        try editOutline { ctx, doc, error in
            source.map(Int32.init).withUnsafeBufferPointer { from in
                target.map(Int32.init).withUnsafeBufferPointer { to in
                    mupdf_outline_move(ctx, doc, from.baseAddress, Int32(source.count), to.baseAddress, Int32(target.count), &error)
                }
            }
        }
    }

    /// `destination` once the entry at `source` is gone: the entries after it at its level move
    /// up one, and so do places among or under them.
    static func placeAfterRemoving(_ source: OutlinePath, _ destination: OutlinePath) -> OutlinePath {
        let level = source.count - 1
        guard destination.count > level, Array(destination.prefix(level)) == Array(source.prefix(level)),
              destination[level] > source[level] else { return destination }
        var adjusted = destination
        adjusted[level] -= 1
        return adjusted
    }

    /// Runs an edit, then reads the outline again.
    private func editOutline(_ body: (FZContext, FZDocument, inout UnsafePointer<CChar>?) -> Int32) throws {
        guard isPDF else { throw PDFError.operationFailed("Only a PDF's outline can be edited") }
        let nodes: [PDFOutlineNode] = try withLockedDocument { ctx, doc in
            var error: UnsafePointer<CChar>?
            guard body(ctx, doc, &error) == 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The outline can't be changed")
            }
            var outlinePointer: FZOutline?
            guard mupdf_document_load_outline(ctx, doc, &outlinePointer, nil) == 0, let loaded = outlinePointer else { return [] }
            defer { mupdf_outline_drop(ctx, loaded) }
            return PDFDocumentCore.parseOutline(loaded)
        }
        outline = nodes
    }
}
