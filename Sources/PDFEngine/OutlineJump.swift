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

/// A request to show the heading an outline entry points to. The heading is left where it is
/// if it's already on screen; otherwise it's scrolled to near the top of the view.
public struct OutlineJump: Equatable, Sendable {
    /// Changes with every request, so choosing the same entry twice is acted on twice.
    public let token: Int
    public let pageIndex: Int
    /// The heading, with a little of its section below it, in page space.
    public let rect: CGRect

    /// How much of the section below its heading has to show for the heading to count as shown,
    /// in page points: about two lines of body text.
    static let roomBelow: CGFloat = 28
    /// How far below a destination its heading may start: destinations often point a little
    /// above the heading's text, some into the line before it.
    static let headingSearchDepth: CGFloat = 40
    /// How far above a destination its heading may start: some point at the heading's baseline.
    static let headingSearchHeight: CGFloat = 20

    /// The heading `title` at `y` on a page, and the room below it (see `roomBelow`). It's the
    /// line near `y` reading like the title, or without one, the first line starting below `y`
    /// (see `OutlineSections.headingAllowance`), with any lines beside it in its block. Without
    /// text there, a band across the page.
    static func headingRect(y: CGFloat, title: String = "", pageBounds: CGRect, page: StructuredPage?) -> CGRect {
        // Each line near y, with the lines beside it: a heading's number and its words can be
        // separate lines.
        var rows: [(rect: CGRect, text: String)] = []
        for block in page?.blocks ?? [] where block.type == .text {
            for line in block.lines where line.bbox.maxY > y - headingSearchHeight && line.bbox.minY < y + headingSearchDepth {
                let beside: [TextLine] = block.lines
                    .filter { (other: TextLine) in abs(other.bbox.midY - line.bbox.midY) < line.bbox.height / 2 }
                    .sorted { (a: TextLine, b: TextLine) in a.bbox.minX < b.bbox.minX }
                let rect = beside.reduce(line.bbox) { (union: CGRect, other: TextLine) in union.union(other.bbox) }
                let text = beside.map { (other: TextLine) in other.text }.joined(separator: " ")
                rows.append((rect, text))
            }
        }
        let wanted = comparable(title)
        let titled = rows.filter { row in
            let found = comparable(row.text)
            return found.count >= 3 && !wanted.isEmpty && (wanted.hasPrefix(found) || found.hasPrefix(wanted))
        }
        let heading = titled.map(\.rect).min { abs($0.minY - y) < abs($1.minY - y) }
            ?? rows.map(\.rect).filter { $0.minY >= y - OutlineSections.headingAllowance }.min { $0.minY < $1.minY }
        guard let heading else {
            return CGRect(x: pageBounds.minX, y: y, width: pageBounds.width, height: roomBelow)
        }
        let top = min(y, heading.minY)
        return CGRect(x: heading.minX, y: top, width: heading.width, height: heading.maxY - top + roomBelow)
    }

    /// Text reduced to its letters and digits, lowercased, to tell whether a line reads like a
    /// title whatever its spacing, quotes and punctuation.
    private static func comparable(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Where to scroll a view showing `visible` of a canvas `canvasSize` big, so `target` (in
    /// canvas space) shows; nil when it already does. Along each direction, a target that fits
    /// must show whole, and one that doesn't must show in part. If it doesn't show, the view
    /// moves to put the target's start just inside its own, in each direction where the target
    /// doesn't show or, bigger than the view, its start doesn't: a heading wider than the view
    /// is read from its start.
    static func scrollOrigin(toShow target: CGRect, in visible: CGRect, canvasSize: CGSize) -> CGPoint? {
        func shows(_ min: CGFloat, _ max: CGFloat, within lower: CGFloat, _ upper: CGFloat) -> Bool {
            max - min <= upper - lower ? (min >= lower && max <= upper) : (max > lower && min < upper)
        }
        func startShows(_ min: CGFloat, within lower: CGFloat, _ upper: CGFloat) -> Bool {
            min >= lower && min < upper
        }
        let showsDown = shows(target.minY, target.maxY, within: visible.minY, visible.maxY)
        let showsAcross = shows(target.minX, target.maxX, within: visible.minX, visible.maxX)
        guard !(showsDown && showsAcross) else { return nil }
        let keepsX = showsAcross && (target.width <= visible.width || startShows(target.minX, within: visible.minX, visible.maxX))
        let keepsY = showsDown && (target.height <= visible.height || startShows(target.minY, within: visible.minY, visible.maxY))
        let maxX = max(0, canvasSize.width - visible.width)
        let maxY = max(0, canvasSize.height - visible.height)
        let x = keepsX ? visible.minX : min(max(0, target.minX - 32), maxX)
        let y = keepsY ? visible.minY : min(max(0, target.minY - 24), maxY)
        return CGPoint(x: x, y: y)
    }
}
