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

/// Where each outline entry starts, so a place on a page can be told which section it's in:
/// the last entry starting at or before it. Entries are taken by where they point, not their
/// order in the outline, so outlines listing sections out of page order still work.
public struct OutlineSections: Sendable {
    public struct Section: Sendable, Hashable {
        /// Identifies the section among the document's entries.
        public let index: Int
        /// Titles from the top-level entry down to this one.
        public let path: [String]
        public var title: String { path.last ?? "" }
    }

    private struct Start: Sendable {
        let page: Int
        /// -infinity for an entry naming only its page, which then starts at the top.
        let y: CGFloat
        let path: [String]
    }

    /// How far below a place an entry may point and still count as starting before it. An entry
    /// can point at its heading's baseline rather than its top, which puts the heading's own text
    /// above it; the last line of the section before is always further up than this.
    static let headingAllowance: CGFloat = 6

    private let starts: [Start]

    public init(outline: [PDFOutlineNode]) {
        var collected: [(order: Int, start: Start)] = []
        func visit(_ nodes: [PDFOutlineNode], parents: [String]) {
            for node in nodes {
                let path = parents + [node.title]
                if let page = node.targetPage {
                    collected.append((collected.count, Start(page: page, y: node.targetY ?? -.infinity, path: path)))
                }
                visit(node.children, parents: path)
            }
        }
        visit(outline, parents: [])
        // Entries pointing at the same place keep outline order, so a chapter and its first
        // section starting together give the section, which comes later.
        collected.sort { a, b in
            if a.start.page != b.start.page { return a.start.page < b.start.page }
            if a.start.y != b.start.y { return a.start.y < b.start.y }
            return a.order < b.order
        }
        starts = collected.map(\.start)
    }

    public var isEmpty: Bool { starts.isEmpty }

    /// The section holding the place `y` (page space, y down) on `page`, or nil if it comes
    /// before every entry. A nil `y` means the top of the page.
    public func section(page: Int, y: CGFloat?) -> Section? {
        let limit = y.map { $0 + Self.headingAllowance } ?? -.infinity
        // The first start after the place; the one before it holds it.
        var low = 0
        var high = starts.count
        while low < high {
            let mid = (low + high) / 2
            let start = starts[mid]
            if start.page < page || (start.page == page && start.y <= limit) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low > 0 else { return nil }
        return Section(index: low - 1, path: starts[low - 1].path)
    }
}
