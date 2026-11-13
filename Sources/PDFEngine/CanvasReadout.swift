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
import Combine

/// The units the status bar, rulers and Inspector give positions and sizes on the page in.
public enum ReadoutUnit: String, CaseIterable, Sendable {
    case points = "pt", millimeters = "mm", inches = "in"

    public var displayName: String {
        switch self {
        case .points: return "Points"
        case .millimeters: return "Millimeters"
        case .inches: return "Inches"
        }
    }

    /// PDF points (1/72 inch) in one of these units.
    public var pointsPerUnit: Double {
        switch self {
        case .points: return 1
        case .millimeters: return 72 / 25.4
        case .inches: return 72
        }
    }

    public func value(fromPoints points: Double) -> Double { points / pointsPerUnit }
    public func points(fromValue value: Double) -> Double { value * pointsPerUnit }

    /// `points` in this unit, without the unit: to 0.1 pt or mm, or 0.01 in.
    public func format(_ points: Double, decimals: Int? = nil) -> String {
        let value = value(fromPoints: points)
        let places = decimals ?? (self == .inches ? 2 : 1)
        let rounded = (value * pow(10, Double(places))).rounded() / pow(10, Double(places))
        return rounded.formatted(.number.precision(.fractionLength(places)).grouping(.never))
    }

    /// A size, such as `210 × 297 mm`, to whole points or millimetres, or to 0.01 in without
    /// trailing zeros (`8.5 × 11 in`).
    public func formatSize(_ size: CGSize) -> String {
        func one(_ points: CGFloat) -> String {
            let value = value(fromPoints: Double(points))
            switch self {
            case .points, .millimeters:
                return value.rounded().formatted(.number.precision(.fractionLength(0)).grouping(.never))
            case .inches:
                return ((value * 100).rounded() / 100).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            }
        }
        return "\(one(size.width)) × \(one(size.height)) \(rawValue)"
    }
}

/// Paper sizes a page may match: ISO A and B, US, ANSI and architectural.
public enum PaperSize {
    /// Name, width and height in millimetres (portrait).
    static let sizes: [(name: String, width: Double, height: Double)] = {
        let inch = 25.4
        return [
            ("A0", 841, 1189), ("A1", 594, 841), ("A2", 420, 594), ("A3", 297, 420),
            ("A4", 210, 297), ("A5", 148, 210), ("A6", 105, 148),
            ("B3", 353, 500), ("B4", 250, 353), ("B5", 176, 250),
            ("Letter", 8.5 * inch, 11 * inch), ("Legal", 8.5 * inch, 14 * inch),
            ("Tabloid", 11 * inch, 17 * inch),
            ("ANSI C", 17 * inch, 22 * inch), ("ANSI D", 22 * inch, 34 * inch), ("ANSI E", 34 * inch, 44 * inch),
            ("ARCH A", 9 * inch, 12 * inch), ("ARCH B", 12 * inch, 18 * inch), ("ARCH C", 18 * inch, 24 * inch),
            ("ARCH D", 24 * inch, 36 * inch), ("ARCH E1", 30 * inch, 42 * inch), ("ARCH E", 36 * inch, 48 * inch),
        ]
    }()

    /// The name of the paper size a page of `size` (in points) is, either way round, within
    /// 2 mm; nil if it's none of them.
    public static func name(for size: CGSize) -> String? {
        let mm = 25.4 / 72
        let short = Double(min(size.width, size.height)) * mm
        let long = Double(max(size.width, size.height)) * mm
        let tolerance = 2.0
        return sizes.first { abs($0.width - short) <= tolerance && abs($0.height - long) <= tolerance }?.name
    }
}

/// One figure in the status bar's readout, such as `Length` and `4.20 m`.
public struct ReadoutItem: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// Where the pointer is on a page.
public struct PointerLocation: Equatable, Sendable {
    public let pageIndex: Int
    /// In points from the top-left corner of the page as shown (its crop box).
    public let point: CGPoint
}

/// What the status bar shows of the pointer and of a measurement being drawn. Kept apart from
/// the view model, so that moving the pointer only redraws the status bar.
@MainActor
public final class CanvasReadout: ObservableObject {
    @Published public internal(set) var pointer: PointerLocation?
    @Published public internal(set) var measurement: [ReadoutItem] = []
    /// Words and characters in the text selection, while there is one.
    @Published public internal(set) var selectionCounts: (words: Int, characters: Int)?

    nonisolated public init() {}

    func setPointer(_ location: PointerLocation?) {
        if pointer != location { pointer = location }
    }

    func setMeasurement(_ items: [ReadoutItem]) {
        if measurement != items { measurement = items }
    }

    func setSelectionText(_ text: String?) {
        guard let text, !text.isEmpty else {
            if selectionCounts != nil { selectionCounts = nil }
            return
        }
        let counts = Self.counts(of: text)
        if selectionCounts?.words != counts.words || selectionCounts?.characters != counts.characters {
            selectionCounts = counts
        }
    }

    /// Words, as the system's word breaking finds them, and characters, not counting line breaks.
    nonisolated static func counts(of text: String) -> (words: Int, characters: Int) {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        let characters = text.reduce(0) { $1.isNewline ? $0 : $0 + 1 }
        return (words, characters)
    }

    /// The figures for a measurement being drawn: the points placed so far on the page, in page
    /// (top-down) coordinates, and the one under the pointer.
    nonisolated static func measurementItems(mode: CanvasMode, points: [CGPoint], candidate: CGPoint?, scale: PDFScaleConfiguration) -> [ReadoutItem] {
        guard let last = points.last, let candidate else { return [] }
        func length(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(b.x - a.x, b.y - a.y)) }
        func format(_ points: Double) -> String { scale.formatLength(points: points) }
        /// The direction from `a` to `b`, anticlockwise from the right, as on a drawing (y up).
        func direction(_ a: CGPoint, _ b: CGPoint) -> String {
            var degrees = atan2(Double(a.y - b.y), Double(b.x - a.x)) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            return scale.formatAngle(degrees: degrees)
        }
        var path = points + [candidate]
        let pathLength = zip(path, path.dropFirst()).reduce(0) { $0 + length($1.0, $1.1) }
        switch mode {
        case .measureLength, .calibrateScale:
            let start = points[0]
            return [
                ReadoutItem("Length", format(length(start, candidate))),
                ReadoutItem("Angle", direction(start, candidate)),
                ReadoutItem("ΔX", format(Double(abs(candidate.x - start.x)))),
                ReadoutItem("ΔY", format(Double(abs(candidate.y - start.y)))),
            ]
        case .measurePerimeter:
            return [
                ReadoutItem("Perimeter", format(pathLength)),
                ReadoutItem("Segment", format(length(last, candidate))),
                ReadoutItem("Angle", direction(last, candidate)),
            ]
        case .measureArea:
            var items = [ReadoutItem]()
            if path.count >= 3 {
                items.append(ReadoutItem("Area", scale.formatArea(pointsSquared: PDFMeasurementGeometry.shoelaceArea(points: path))))
                path.append(path[0])
                let closed = zip(path, path.dropFirst()).reduce(0) { $0 + length($1.0, $1.1) }
                items.append(ReadoutItem("Perimeter", format(closed)))
            }
            items.append(ReadoutItem("Segment", format(length(last, candidate))))
            return items
        case .measureAngle:
            if points.count >= 2 {
                let apex = points[1], r1 = points[0]
                let a1 = atan2(Double(r1.y - apex.y), Double(r1.x - apex.x))
                let a2 = atan2(Double(candidate.y - apex.y), Double(candidate.x - apex.x))
                var degrees = abs(a1 - a2) * 180 / .pi
                if degrees > 180 { degrees = 360 - degrees }
                return [ReadoutItem("Angle", scale.formatAngle(degrees: degrees)), ReadoutItem("Arm", format(length(apex, candidate)))]
            }
            return [ReadoutItem("Arm", format(length(last, candidate))), ReadoutItem("Direction", direction(last, candidate))]
        default:
            return []
        }
    }
}

extension PDFViewerViewModel {
    /// Counts the selected text's words for the status bar, while it shows.
    func updateSelectionReadout() {
        guard PDFViewerAppCoordinator.shared.showsStatusBar, activeSelection != nil else {
            canvasReadout.setSelectionText(nil)
            return
        }
        canvasReadout.setSelectionText(activeSelectionCombinedText)
    }
}

/// The part of a page in view, in page coordinates.
public struct VisiblePageRect: Equatable, Sendable {
    public let pageIndex: Int
    public let rect: CGRect
}

/// What the navigator shows: the page in the middle of the view and the part of it on screen.
/// Kept apart from the view model, so scrolling only redraws the navigator.
@MainActor
public final class ViewportReadout: ObservableObject {
    @Published public internal(set) var visible: VisiblePageRect?
    /// Set by the scroll view: scrolls so that a page point is in the middle of the view.
    var centerOn: ((_ pageIndex: Int, _ pagePoint: CGPoint) -> Void)?

    nonisolated public init() {}

    func setVisible(_ value: VisiblePageRect?) {
        if visible != value { visible = value }
    }

    public func center(onPage pageIndex: Int, at pagePoint: CGPoint) {
        centerOn?(pageIndex, pagePoint)
    }
}
