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

import AppKit
import SwiftUI

/// Assigns per-segment tooltips to an AppKit-backed segmented control.
public struct SegmentedControlTooltipModifier: ViewModifier {
    let tooltips: [String]

    public init(tooltips: [String]) {
        self.tooltips = tooltips
    }

    public func body(content: Content) -> some View {
        content
            .background(SegmentedControlTooltipAccessor(tooltips: tooltips))
    }
}

public extension View {
    /// Applies individual hover tooltips to each segment of an AppKit-backed segmented picker.
    func segmentedControlTooltips(_ tooltips: [String]) -> some View {
        modifier(SegmentedControlTooltipModifier(tooltips: tooltips))
    }
}

public struct SegmentedControlTooltipAccessor: NSViewRepresentable {
    let tooltips: [String]

    public init(tooltips: [String]) {
        self.tooltips = tooltips
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            Self.applyTooltips(tooltips, from: view)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            Self.applyTooltips(tooltips, from: nsView)
        }
    }

    public static func applyTooltips(_ tooltips: [String], to seg: NSSegmentedControl) {
        seg.toolTip = nil // Remove blanket control tooltip so segment tooltips take precedence
        for (index, tip) in tooltips.enumerated() {
            if index < seg.segmentCount {
                seg.setToolTip(tip, forSegment: index)
                if let cell = seg.cell as? NSSegmentedCell {
                    cell.setToolTip(tip, forSegment: index)
                }
            }
        }
    }

    private static func applyTooltips(_ tooltips: [String], from view: NSView) {
        guard let seg = findSegmentedControl(from: view) else { return }
        applyTooltips(tooltips, to: seg)
    }

    private static func findSegmentedControl(from view: NSView) -> NSSegmentedControl? {
        var current: NSView? = view
        for _ in 0..<4 {
            guard let parent = current?.superview else { break }
            if let direct = parent.subviews.compactMap({ $0 as? NSSegmentedControl }).first {
                return direct
            }
            for sub in parent.subviews {
                if let seg = sub as? NSSegmentedControl ?? sub.subviews.compactMap({ $0 as? NSSegmentedControl }).first {
                    return seg
                }
            }
            current = parent
        }
        return nil
    }
}

