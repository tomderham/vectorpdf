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

/// A guide dragged out from a ruler onto a page: a line across the page that measurements snap
/// to. Kept for the window while the document is open, not saved in it.
public struct PageGuide: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// A line of constant x on the page (in the page's own orientation), or else of constant y.
    public let isVertical: Bool
    /// Its x or y in page coordinates.
    public var position: CGFloat

    public init(id: UUID = UUID(), isVertical: Bool, position: CGFloat) {
        self.id = id
        self.isVertical = isVertical
        self.position = position
    }
}

/// Snapping a point to guides and the grid.
public enum GuideSnapping {
    /// The nearest of the lines at `guides`, and of the grid's lines (every `gridSpacing` from
    /// `gridOrigin`, if there's a grid), to `value`, if one is within `threshold`; guides win
    /// over grid lines as near.
    public static func snap(_ value: CGFloat, guides: [CGFloat], gridSpacing: CGFloat?, gridOrigin: CGFloat, threshold: CGFloat) -> CGFloat? {
        var best: (value: CGFloat, distance: CGFloat)?
        for guide in guides {
            let distance = abs(guide - value)
            if distance <= threshold, distance < (best?.distance ?? .infinity) { best = (guide, distance) }
        }
        if let spacing = gridSpacing, spacing > 0 {
            let line = gridOrigin + ((value - gridOrigin) / spacing).rounded() * spacing
            let distance = abs(line - value)
            if distance <= threshold, distance < (best?.distance ?? .infinity) - 0.0001 { best = (line, distance) }
        }
        return best?.value
    }

    /// `point` (page coordinates) snapped in x and y separately to the page's guides, and to the
    /// grid when it shows, drawn from the page's top-left corner `pageOrigin`.
    public static func snap(_ point: CGPoint, guides: [PageGuide], gridSpacing: CGFloat?, pageOrigin: CGPoint, threshold: CGFloat) -> (point: CGPoint, didSnap: Bool) {
        let x = snap(point.x, guides: guides.filter(\.isVertical).map(\.position), gridSpacing: gridSpacing, gridOrigin: pageOrigin.x, threshold: threshold)
        let y = snap(point.y, guides: guides.filter { !$0.isVertical }.map(\.position), gridSpacing: gridSpacing, gridOrigin: pageOrigin.y, threshold: threshold)
        return (CGPoint(x: x ?? point.x, y: y ?? point.y), x != nil || y != nil)
    }
}

/// The marks along a ruler: a major one, with a number, every `major` units, and minor ones
/// between, spaced so neither crowds at the zoom shown.
public struct RulerSteps: Equatable, Sendable {
    public let major: Double
    public let minorCount: Int

    /// For a ruler in `unit` where one unit is `pixelsPerUnit` on screen.
    public static func choose(unit: ReadoutUnit, pixelsPerUnit: Double, minimumMajorSpacing: Double = 60) -> RulerSteps {
        let candidates: [Double]
        switch unit {
        case .inches: candidates = [0.125, 0.25, 0.5, 1, 2, 4, 6, 12, 24, 48, 96, 192]
        case .millimeters, .points: candidates = [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
        }
        let major = candidates.first { $0 * pixelsPerUnit >= minimumMajorSpacing } ?? candidates.last!
        var minor: Int
        switch unit {
        case .inches: minor = major >= 1 && major.truncatingRemainder(dividingBy: 12) == 0 ? 12 : (major >= 1 ? 8 : 4)
        default:
            let leading = major / pow(10, floor(log10(major)))
            minor = leading == 2 ? 4 : (leading == 5 ? 5 : 10)
        }
        // Fewer minor marks when they'd be under 4 pixels apart.
        while minor > 1, major / Double(minor) * pixelsPerUnit < 4 {
            minor = minor % 2 == 0 ? minor / 2 : 1
        }
        return RulerSteps(major: major, minorCount: minor)
    }
}

extension PDFViewerViewModel {
    public func guides(onPage page: Int) -> [PageGuide] { pageGuides[page] ?? [] }

    @discardableResult
    public func addGuide(onPage page: Int, isVertical: Bool, position: CGFloat) -> PageGuide {
        let guide = PageGuide(isVertical: isVertical, position: position)
        pageGuides[page, default: []].append(guide)
        return guide
    }

    public func moveGuide(_ id: UUID, onPage page: Int, to position: CGFloat) {
        guard let index = pageGuides[page]?.firstIndex(where: { $0.id == id }) else { return }
        pageGuides[page]?[index].position = position
    }

    public func removeGuide(_ id: UUID, onPage page: Int) {
        pageGuides[page]?.removeAll { $0.id == id }
        if pageGuides[page]?.isEmpty == true { pageGuides[page] = nil }
    }

    public func clearGuides() {
        pageGuides = [:]
    }

    /// Snaps a page point to the page's guides and, while it shows, the grid; nil when
    /// snapping to them is off or nothing is near.
    func snapToGuidesAndGrid(_ point: CGPoint, onPage page: Int) -> CGPoint? {
        let coordinator = PDFViewerAppCoordinator.shared
        guard coordinator.snapsToGuidesAndGrid, let doc = document, page < doc.pageBounds.count else { return nil }
        let guides = guides(onPage: page)
        let grid = coordinator.showsGrid ? CGFloat(coordinator.gridSpacing) : nil
        guard !guides.isEmpty || grid != nil else { return nil }
        let result = GuideSnapping.snap(point, guides: guides, gridSpacing: grid, pageOrigin: doc.pageBounds[page].origin, threshold: 6 / max(effectiveZoom, 0.01))
        return result.didSnap ? result.point : nil
    }
}

/// The grid spacings offered in the View menu, in the chosen units.
public struct GridSpacingChoice: Sendable {
    public let title: String
    public let points: Double

    public static func choices(for unit: ReadoutUnit) -> [GridSpacingChoice] {
        let values: [Double]
        switch unit {
        case .millimeters: values = [1, 2, 5, 10, 20, 50]
        case .inches: values = [0.0625, 0.125, 0.25, 0.5, 1]
        case .points: values = [6, 12, 18, 36, 72]
        }
        return values.map { value in
            let title: String
            switch unit {
            case .inches:
                let fractions: [Double: String] = [0.0625: "1/16", 0.125: "1/8", 0.25: "1/4", 0.5: "1/2", 1: "1"]
                title = "\(fractions[value] ?? PageRulerView.label(value)) in"
            default:
                title = "\(PageRulerView.label(value)) \(unit.rawValue)"
            }
            return GridSpacingChoice(title: title, points: unit.points(fromValue: value))
        }
    }
}
