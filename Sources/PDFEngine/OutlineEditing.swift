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

/// An outline entry as the file has it, copied for Undo: everything MuPDF keeps of it.
public struct OutlineEntryCopy: Sendable, Equatable {
    /// How far below the entry copied it is (0 for that entry).
    public var level: Int
    public var title: String?
    public var uri: String?
    public var isOpen: Bool
    public var flags: Int32
    public var color: (r: Float, g: Float, b: Float)

    public static func == (a: Self, b: Self) -> Bool {
        a.level == b.level && a.title == b.title && a.uri == b.uri && a.isOpen == b.isOpen && a.flags == b.flags
            && a.color.r == b.color.r && a.color.g == b.color.g && a.color.b == b.color.b
    }
}

/// A change to the outline, which `PDFDocumentCore.applyOutlineEdit` makes and answers with the
/// change that undoes it.
public enum OutlineEdit: Sendable {
    /// Entries as `copyOutlineEntry` gives them, put in at a place (before the entry there).
    case insert(OutlinePath, [OutlineEntryCopy])
    case delete(OutlinePath)
    /// `count` entries in a row from a place, with those under them.
    case deleteSeveral(OutlinePath, count: Int)
    /// A new title or link for an entry; nil keeps it.
    case update(OutlinePath, title: String?, uri: String?)
    /// An entry set back as it was copied (its first copy; those under it are left alone).
    case restore(OutlinePath, OutlineEntryCopy)
    /// An entry moved, with those under it, to a place in the outline as it is without it.
    case move(from: OutlinePath, toPlaceWithout: OutlinePath)
}

extension PDFDocumentCore {
    /// Adds an entry going to `y` (page space, top-down) on `page`, at `path` (before the entry
    /// there, or after the last).
    @discardableResult
    public func addOutlineEntry(title: String, page: Int, y: CGFloat, at path: OutlinePath) throws -> OutlineEdit {
        let entry = OutlineEntryCopy(level: 0, title: title, uri: try outlinePageURI(page: page, y: y), isOpen: false, flags: 0, color: (0, 0, 0))
        return try applyOutlineEdit(.insert(path, [entry]))
    }

    @discardableResult
    public func renameOutlineEntry(at path: OutlinePath, to title: String) throws -> OutlineEdit {
        try applyOutlineEdit(.update(path, title: title, uri: nil))
    }

    /// Points an entry at `y` on `page`.
    @discardableResult
    public func setOutlineEntryDestination(at path: OutlinePath, page: Int, y: CGFloat) throws -> OutlineEdit {
        try applyOutlineEdit(.update(path, title: nil, uri: try outlinePageURI(page: page, y: y)))
    }

    @discardableResult
    public func deleteOutlineEntry(at path: OutlinePath) throws -> OutlineEdit {
        try applyOutlineEdit(.delete(path))
    }

    /// Moves an entry, with those under it, to `destination`: a place in the outline as it is
    /// now (before the entry there, or after the last at its level). A place inside the entry
    /// itself isn't one. Nil when it's where it was.
    @discardableResult
    public func moveOutlineEntry(from source: OutlinePath, to destination: OutlinePath) throws -> OutlineEdit? {
        guard !destination.starts(with: source) else { throw PDFError.operationFailed("An entry can't go inside itself") }
        let target = Self.placeAfterRemoving(source, destination)
        guard target != source else { return nil }
        return try applyOutlineEdit(.move(from: source, toPlaceWithout: target))
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

    /// The entry at `path` and those under it, as the file has them.
    public func copyOutlineEntry(at path: OutlinePath) throws -> [OutlineEntryCopy] {
        try withLockedDocument { ctx, doc in try Self.copyEntry(ctx, doc, path) }
    }

    /// Makes `edit`, reads the outline again, and returns the edit that undoes it.
    @discardableResult
    public func applyOutlineEdit(_ edit: OutlineEdit) throws -> OutlineEdit {
        guard isPDF else { throw PDFError.operationFailed("Only a PDF's outline can be edited") }
        let (inverse, nodes): (OutlineEdit, [PDFOutlineNode]) = try withLockedDocument { ctx, doc in
            var error: UnsafePointer<CChar>?
            let inverse: OutlineEdit
            let status: Int32
            switch edit {
            case let .insert(path, entries):
                let topLevel = entries.filter { $0.level == entries.first?.level }.count
                inverse = topLevel == 1 ? .delete(path) : .deleteSeveral(path, count: topLevel)
                status = Self.withCEntries(entries) { list in
                    Self.withPath(path) { mupdf_outline_insert_entries(ctx, doc, $0, $1, list.baseAddress, Int32(list.count), &error) }
                }
            case let .delete(path):
                inverse = .insert(path, try Self.copyEntry(ctx, doc, path))
                status = Self.withPath(path) { mupdf_outline_delete(ctx, doc, $0, $1, &error) }
            case let .deleteSeveral(path, count):
                var copies: [OutlineEntryCopy] = []
                var result: Int32 = 0
                for _ in 0..<count where result == 0 {
                    copies += try Self.copyEntry(ctx, doc, path)
                    result = Self.withPath(path) { mupdf_outline_delete(ctx, doc, $0, $1, &error) }
                }
                inverse = .insert(path, copies)
                status = result
            case let .update(path, title, uri):
                guard let old = try Self.copyEntry(ctx, doc, path).first else { throw PDFError.operationFailed("No such outline entry") }
                inverse = .restore(path, old)
                status = Self.withPath(path) { mupdf_outline_update(ctx, doc, $0, $1, title, uri, &error) }
            case let .restore(path, entry):
                guard let old = try Self.copyEntry(ctx, doc, path).first else { throw PDFError.operationFailed("No such outline entry") }
                inverse = .restore(path, old)
                status = Self.withCEntries([entry]) { list in
                    Self.withPath(path) { mupdf_outline_set(ctx, doc, $0, $1, list.baseAddress, &error) }
                }
            case let .move(from, to):
                // Back from where it went to where it was: both places in the outline without it.
                inverse = .move(from: to, toPlaceWithout: from)
                status = Self.withPath(from) { fromPath, fromDepth in
                    Self.withPath(to) { mupdf_outline_move(ctx, doc, fromPath, fromDepth, $0, $1, &error) }
                }
            }
            guard status == 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The outline can't be changed")
            }
            var outlinePointer: FZOutline?
            guard mupdf_document_load_outline(ctx, doc, &outlinePointer, nil) == 0, let loaded = outlinePointer else { return (inverse, []) }
            defer { mupdf_outline_drop(ctx, loaded) }
            return (inverse, PDFDocumentCore.parseOutline(loaded))
        }
        outline = nodes
        return inverse
    }

    func outlinePageURI(page: Int, y: CGFloat) throws -> String {
        try withLockedDocument { ctx, doc in
            guard let uri = mupdf_outline_page_uri(ctx, doc, Int32(page), Float(y)) else {
                throw PDFError.operationFailed("There's no page \(page + 1)")
            }
            defer { fz_free(ctx, uri) }
            return String(cString: uri)
        }
    }

    private static func withPath<T>(_ path: OutlinePath, _ body: (UnsafePointer<Int32>?, Int32) -> T) -> T {
        path.map(Int32.init).withUnsafeBufferPointer { body($0.baseAddress, Int32(path.count)) }
    }

    private static func copyEntry(_ ctx: FZContext, _ doc: FZDocument, _ path: OutlinePath) throws -> [OutlineEntryCopy] {
        var list: UnsafeMutablePointer<vp_outline_entry>?
        var count: Int32 = 0
        var error: UnsafePointer<CChar>?
        guard withPath(path, { mupdf_outline_copy(ctx, doc, $0, $1, &list, &count, &error) }) == 0 else {
            throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "No such outline entry")
        }
        defer { mupdf_outline_entries_free(ctx, list, count) }
        return UnsafeBufferPointer(start: list, count: Int(count)).map { e in
            OutlineEntryCopy(level: Int(e.level), title: e.title.map { String(cString: $0) }, uri: e.uri.map { String(cString: $0) },
                             isOpen: e.is_open != 0, flags: e.flags, color: (e.r, e.g, e.b))
        }
    }

    /// Lends `entries` to C, their strings valid inside `body`.
    private static func withCEntries<T>(_ entries: [OutlineEntryCopy], _ body: (UnsafeBufferPointer<vp_outline_entry>) -> T) -> T {
        var owned: [UnsafeMutablePointer<CChar>] = []
        defer { owned.forEach { free($0) } }
        func dup(_ s: String?) -> UnsafeMutablePointer<CChar>? {
            guard let s, let p = strdup(s) else { return nil }
            owned.append(p)
            return p
        }
        let list = entries.map { e in
            vp_outline_entry(level: Int32(e.level), title: dup(e.title), uri: dup(e.uri), is_open: e.isOpen ? 1 : 0,
                             flags: e.flags, r: e.color.r, g: e.color.g, b: e.color.b)
        }
        return list.withUnsafeBufferPointer(body)
    }
}
