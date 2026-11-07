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

/// Scrolling to something on the canvas (a search result, an anchor, an annotation) without
/// moving the view more than it needs to.
enum ScrollReveal {
    /// The space kept between a target and the view's edges, down and across.
    static let margin = CGSize(width: 32, height: 24)

    /// Where to scroll a view showing `visible` of a canvas `canvasSize` big to show `target`
    /// (in canvas space). If the target is on screen already, the view stays where it is.
    /// Otherwise, in each direction where it shows, the view stays; in each other, the target
    /// is centred, at least `margin` inside the view's edges, or if it's bigger than the view,
    /// its start is put just inside the view's. So moving between results on the same screen
    /// doesn't move the page, and a result below the view scrolls down without the page moving
    /// across.
    static func origin(toShow target: CGRect, in visible: CGRect, canvasSize: CGSize) -> CGPoint {
        func along(_ min: CGFloat, _ max: CGFloat, view lower: CGFloat, _ length: CGFloat, margin: CGFloat, canvas: CGFloat) -> CGFloat {
            let fitsView = max - min <= length
            let shows = fitsView
                ? (min >= lower && max <= lower + length)
                : (min >= lower && min < lower + length)
            guard !shows else { return lower }
            let room = Swift.min(margin, Swift.max(0, (length - (max - min)) / 2))
            let fits = max - min <= length - 2 * room
            var start = fits ? (min + max) / 2 - length / 2 : min - margin
            if fits {
                start = Swift.min(start, min - room)
                start = Swift.max(start, max + room - length)
            }
            return Swift.min(Swift.max(0, start), Swift.max(0, canvas - length))
        }
        return CGPoint(
            x: along(target.minX, target.maxX, view: visible.minX, visible.width, margin: margin.width, canvas: canvasSize.width),
            y: along(target.minY, target.maxY, view: visible.minY, visible.height, margin: margin.height, canvas: canvasSize.height)
        )
    }
}
